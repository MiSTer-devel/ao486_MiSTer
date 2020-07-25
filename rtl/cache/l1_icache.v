
module l1_icache
(
   input             CLK,
   input             RESET,
   
   input             CPU_REQ,
   input      [31:0] CPU_ADDR,
   output reg        CPU_VALID,
   output reg        CPU_DONE,
   output     [31:0] CPU_DATA,
   
   output reg        MEM_REQ,
   output reg [31:0] MEM_ADDR,
   input             MEM_DONE,
   input      [31:0] MEM_DATA,
   
   input      [27:2] snoop_addr,
   input      [31:0] snoop_data,
   input       [3:0] snoop_be,
   input             snoop_we
);

// cache settings
localparam LINES         = 64;
localparam LINESIZE      = 8;
localparam ASSOCIATIVITY = 2;
localparam ADDRBITS      = 29;
localparam CACHEBURST    = 4;

// cache control
localparam ASSO_BITS       = $clog2(ASSOCIATIVITY);
localparam LINESIZE_BITS   = $clog2(LINESIZE);
localparam LINE_BITS       = $clog2(LINES);
localparam CACHEBURST_BITS = $clog2(CACHEBURST);
localparam RAMSIZEBITS     = $clog2(LINESIZE * LINES);
localparam LINEMASKLSB     = $clog2(LINESIZE);
localparam LINEMASKMSB     = LINEMASKLSB + $clog2(LINES) - 1;

reg             [ASSO_BITS-1:0] rrb[0:LINES-1];
reg [(LINES*ASSOCIATIVITY)-1:0] tag_dirty;
wire   [ADDRBITS-RAMSIZEBITS:0] tags_read[0:ASSOCIATIVITY-1];

localparam [2:0]
	IDLE          = 0,
	WRITEONE      = 1,
	READONE       = 2,
	FILLCACHE     = 3,
	READCACHE_OUT = 4;
	
// memory
wire             [31:0] readdata_cache[0:ASSOCIATIVITY-1];
reg     [ASSO_BITS-1:0] cache_mux;

reg        [ADDRBITS:0] read_addr;

reg   [RAMSIZEBITS-1:0] memory_addr_a;
reg              [31:0] memory_datain;
reg [0:ASSOCIATIVITY-1] memory_we;
reg               [3:0] memory_be;

reg   [LINESIZE_BITS-1:0] fillcount;
reg [CACHEBURST_BITS-1:0] burstleft;

reg   [2:0] state;
reg         CPU_REQ_hold;

// fifo for snoop
wire [61:0] Fifo_dout;
wire        Fifo_empty;

simple_fifo_mlab #(
	.widthu(4),
	.width(62)
)
isimple_fifo (
	.clk(CLK),
	.rst_n(1'b1),
	.sclr(RESET),

	.data({snoop_be, snoop_data, snoop_addr}),
	.wrreq(snoop_we),

	.q(Fifo_dout),
	.rdreq((state == IDLE) && !Fifo_empty),
	.empty(Fifo_empty)
);
   
assign CPU_DATA = readdata_cache[cache_mux];
   
always @(posedge CLK) begin : mainfsm
	reg [ASSO_BITS:0] i;
	
	memory_we <= {ASSOCIATIVITY{1'b0}};
	CPU_DONE  <= 1'b0;
	CPU_VALID <= 1'b0;
	
	if (RESET) begin
		tag_dirty    <= {(LINES*ASSOCIATIVITY){1'b1}};
		state        <= IDLE;
		MEM_REQ      <= 1'b0;
		CPU_REQ_hold <= 1'b0;
		// synthesis translate_off
		rrb[0:LINES-1] <= '{default:'0};
		// synthesis translate_on
	end
	else begin
		if (CPU_REQ) CPU_REQ_hold <= 1'b1;

		case (state)
			IDLE:
				if (!Fifo_empty) begin
					state         <= WRITEONE;
					read_addr     <= Fifo_dout[25:0];
					memory_addr_a <= Fifo_dout[RAMSIZEBITS - 1:0];
					memory_datain <= Fifo_dout[57:26];
					memory_be     <= Fifo_dout[61:58];
				end
				else if (CPU_REQ || CPU_REQ_hold) begin
					state         <= READONE;
					read_addr     <= CPU_ADDR[31:2];
					CPU_REQ_hold  <= 1'b0;
					burstleft     <= CACHEBURST[CACHEBURST_BITS-1:0] - 1'd1;
				end
			
			WRITEONE:
				begin
					state <= IDLE;
					for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
						if (~tag_dirty[read_addr[LINEMASKMSB:LINEMASKLSB] * ASSOCIATIVITY + i]) begin
							if (tags_read[i] == read_addr[ADDRBITS:RAMSIZEBITS]) memory_we[i] <= 1'b1;
						end
					end
				end

			READONE:
				begin
					state         <= FILLCACHE;
					MEM_REQ       <= 1'b1;
					MEM_ADDR      <= {read_addr[ADDRBITS:LINESIZE_BITS], {LINESIZE_BITS{1'b0}}, 2'b00};
					fillcount     <= 0;
					memory_addr_a <= {read_addr[RAMSIZEBITS - 1:LINESIZE_BITS], {LINESIZE_BITS{1'b0}}};
					cache_mux     <= rrb[read_addr[LINEMASKMSB:LINEMASKLSB]];
					for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
						if (~tag_dirty[read_addr[LINEMASKMSB:LINEMASKLSB] * ASSOCIATIVITY + i]) begin
							if (tags_read[i] == read_addr[ADDRBITS:RAMSIZEBITS]) begin
								MEM_REQ   <= 1'b0;
								cache_mux <= i[ASSO_BITS-1:0];
								CPU_VALID <= 1'b1;
								if (!burstleft) begin
									state    <= IDLE;
									CPU_DONE <= 1'b1;
								end
								else begin
									state     <= READONE;
									burstleft <= burstleft - 1'd1;
									read_addr <= read_addr + 1'd1;
								end
							end
						end
					end
				end
			
			FILLCACHE:
				if (MEM_DONE) begin
					MEM_REQ              <= 1'b0;
					memory_datain        <= MEM_DATA;
					memory_we[cache_mux] <= 1'b1;
					memory_be            <= 4'hF;

					if (fillcount > 0) memory_addr_a <= memory_addr_a + 1'd1;
					if (fillcount < LINESIZE - 1) fillcount <= fillcount + 1'd1;
					else state <= READCACHE_OUT;
				end
			
			READCACHE_OUT :
				begin
					state <= READONE;
					tag_dirty[read_addr[LINEMASKMSB:LINEMASKLSB] * ASSOCIATIVITY + cache_mux] <= 1'b0;
					rrb[read_addr[LINEMASKMSB:LINEMASKLSB]] <= rrb[read_addr[LINEMASKMSB:LINEMASKLSB]] + 1'd1;
				end
		endcase
	end
end

generate
	genvar i;
	for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin : gcache
		altdpram #(
			.indata_aclr("OFF"),
			.indata_reg("INCLOCK"),
			.intended_device_family("Cyclone V"),
			.lpm_type("altdpram"),
			.outdata_aclr("OFF"),
			.outdata_reg("UNREGISTERED"),
			.ram_block_type("MLAB"),
			.rdaddress_aclr("OFF"),
			.rdaddress_reg("UNREGISTERED"),
			.rdcontrol_aclr("OFF"),
			.rdcontrol_reg("UNREGISTERED"),
			.read_during_write_mode_mixed_ports("CONSTRAINED_DONT_CARE"),
			.width(ADDRBITS - RAMSIZEBITS + 1),
			.widthad(LINE_BITS),
			.width_byteena(1),
			.wraddress_aclr("OFF"),
			.wraddress_reg("INCLOCK"),
			.wrcontrol_aclr("OFF"),
			.wrcontrol_reg("INCLOCK")
		)
		tagram (
			.inclock(CLK),
			.outclock(CLK),
			
			.data(read_addr[ADDRBITS:RAMSIZEBITS]),
			.rdaddress(read_addr[LINEMASKMSB:LINEMASKLSB]),
			.wraddress(read_addr[LINEMASKMSB:LINEMASKLSB]),
			.wren((state == READCACHE_OUT) && (cache_mux == i)),
			.q(tags_read[i])
		);
		
		altsyncram #(
			.address_aclr_b("NONE"),
			.address_reg_b("CLOCK0"),
			.byte_size(8),
			.clock_enable_input_a("BYPASS"),
			.clock_enable_input_b("BYPASS"),
			.clock_enable_output_b("BYPASS"),
			.intended_device_family("Cyclone V"),
			.lpm_type("altsyncram"),
			.numwords_a(2**RAMSIZEBITS),
			.numwords_b(2**RAMSIZEBITS),
			.operation_mode("DUAL_PORT"),
			.outdata_aclr_b("NONE"),
			.outdata_reg_b("UNREGISTERED"),
			.power_up_uninitialized("FALSE"),
			.read_during_write_mode_mixed_ports("DONT_CARE"),
			.widthad_a(RAMSIZEBITS),
			.widthad_b(RAMSIZEBITS),
			.width_a(32),
			.width_b(32),
			.width_byteena_a(4)
		)
		ram (
			.clock0 (CLK),

			.address_a(memory_addr_a),
			.byteena_a(memory_be),
			.data_a(memory_datain),
			.wren_a(memory_we[i]),

			.address_b(read_addr[RAMSIZEBITS - 1:0]),
			.q_b(readdata_cache[i]),

			.aclr0(1'b0),
			.aclr1(1'b0),
			.addressstall_a(1'b0),
			.addressstall_b(1'b0),
			.byteena_b(1'b1),
			.clock1(1'b1),
			.clocken0(1'b1),
			.clocken1(1'b1),
			.clocken2(1'b1),
			.clocken3(1'b1),
			.data_b(32'b0),
			.eccstatus(),
			.q_a(),
			.rden_a(1'b1),
			.rden_b(1'b1),
			.wren_b(1'b0)
		);
	end
endgenerate
   
endmodule
