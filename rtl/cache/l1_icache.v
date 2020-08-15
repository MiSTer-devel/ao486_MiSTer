
module l1_icache
(
	input             CLK,
	input             RESET,
	input             pr_reset,
	
	input             DISABLE,

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
localparam LINES         = 128;
localparam LINESIZE      = 8;
localparam ASSOCIATIVITY = 4;
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

reg    [ASSOCIATIVITY-1:0]      tags_dirty_in;
reg    [ASSOCIATIVITY-1:0]      tags_dirty_out;
wire   [ADDRBITS-RAMSIZEBITS:0] tags_read[0:ASSOCIATIVITY-1];
reg                             update_tag_we;
reg    [LINE_BITS-1:0]          update_tag_addr;

reg    [ASSO_BITS-1:0] LRU_in [0:ASSOCIATIVITY-1];
reg    [ASSO_BITS-1:0] LRU_out[0:ASSOCIATIVITY-1];
reg                             LRU_we;
reg    [LINE_BITS-1:0]          LRU_addr;

localparam [2:0]
	START         = 0,
	IDLE          = 1,
	WRITEONE      = 2,
	READONE       = 3,
	FILLCACHE     = 4,
	READCACHE_OUT = 5;
	
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

reg force_fetch;
reg force_next;

always @(posedge CLK) begin : mainfsm
	reg [ASSO_BITS:0]   i;
	reg [ASSO_BITS-1:0] match;
	
	memory_we <= {ASSOCIATIVITY{1'b0}};
	CPU_DONE  <= 1'b0;
	CPU_VALID <= 1'b0;
	
	if (RESET) begin
		state           <= START;
		update_tag_addr <= {LINE_BITS{1'b0}};
		update_tag_we   <= 1'b1;
		tags_dirty_in   <= {ASSOCIATIVITY{1'b1}};

		MEM_REQ         <= 1'b0;
		CPU_REQ_hold    <= 1'b0;
	end
	else begin
		if (CPU_REQ) CPU_REQ_hold <= 1'b1;

		// LRU update after read
		LRU_we <= CPU_VALID && ~LRU_we;
		for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
			LRU_in[i] <= LRU_out[i];
			if (cache_mux == i[ASSO_BITS-1:0]) begin
				match     = LRU_out[i];
				LRU_in[i] <= {ASSO_BITS{1'b0}};
			end
		end
		for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
			if (LRU_out[i] < match) begin
				LRU_in[i] <= LRU_out[i] + 1'd1;
			end
		end

		case (state)
			START:
			begin
				update_tag_addr <= update_tag_addr + 1'd1;
				
				for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
					LRU_in[i]    <= i[ASSO_BITS-1:0]; 
				end
				LRU_addr        <= update_tag_addr;
				LRU_we          <= 1'b1; 
				
				if (update_tag_addr == {LINE_BITS{1'b1}}) begin
					state         <= IDLE;
					update_tag_we <= 1'b0;
				end
			end
		
			IDLE:
				begin
					if (!Fifo_empty) begin
						state         <= WRITEONE;
						read_addr     <= Fifo_dout[25:0];
						memory_addr_a <= Fifo_dout[RAMSIZEBITS - 1:0];
						memory_datain <= Fifo_dout[57:26];
						memory_be     <= Fifo_dout[61:58];
					end
					else if (CPU_REQ || CPU_REQ_hold) begin
						force_fetch   <= DISABLE;
						force_next    <= DISABLE;
						state         <= READONE;
						read_addr     <= CPU_ADDR[31:2];
						CPU_REQ_hold  <= 1'b0;
						burstleft     <= CACHEBURST[CACHEBURST_BITS-1:0] - 1'd1;
					end
				end
			
			WRITEONE:
				begin
					state <= IDLE;
					for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
						if (~tags_dirty_out[i]) begin
							if (tags_read[i] == read_addr[ADDRBITS:RAMSIZEBITS]) memory_we[i] <= 1'b1;
						end
					end
				end

			READONE:
				begin
					if (pr_reset) begin
						state     <= IDLE;
						CPU_DONE  <= 1'b1;
					end else begin
						state           <= FILLCACHE;
						MEM_REQ         <= 1'b1;
						MEM_ADDR        <= {read_addr[ADDRBITS:LINESIZE_BITS], {LINESIZE_BITS{1'b0}}, 2'b00};
						fillcount       <= 0;
						memory_addr_a   <= {read_addr[RAMSIZEBITS - 1:LINESIZE_BITS], {LINESIZE_BITS{1'b0}}};
						tags_dirty_in   <= tags_dirty_out;
						update_tag_addr <= read_addr[LINEMASKMSB:LINEMASKLSB];
						LRU_addr        <= read_addr[LINEMASKMSB:LINEMASKLSB];

						if (force_fetch) force_next <= ~force_next;

						if (~force_next) begin
							for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
								if (~tags_dirty_out[i]) begin
									if (tags_read[i] == read_addr[ADDRBITS:RAMSIZEBITS]) begin
										MEM_REQ   <= 1'b0;
										cache_mux <= i[ASSO_BITS-1:0];
										CPU_VALID <= 1'b1;
										if (!burstleft) begin
											state    <= IDLE;
											CPU_DONE <= 1'b1;
										end else begin
											state     <= READONE;
											burstleft <= burstleft - 1'd1;
											read_addr <= read_addr + 1'd1;
										end
									end
								end
							end
						end
						else begin
							tags_dirty_in <= {ASSOCIATIVITY{1'b1}};
							update_tag_we <= 1'b1;
						end
					end
				end
			
			FILLCACHE:
				begin
					for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
						if (LRU_out[i] == {ASSO_BITS{1'b1}} ) cache_mux <= i[ASSO_BITS-1:0]; 
					end

					if (MEM_DONE) begin
						MEM_REQ              <= 1'b0;
						memory_datain        <= MEM_DATA;
						memory_we[cache_mux] <= 1'b1;
						memory_be            <= 4'hF;
						
						tags_dirty_in[cache_mux] <= 1'b0;

						if (fillcount > 0) memory_addr_a <= memory_addr_a + 1'd1;
						if (fillcount < LINESIZE - 1) fillcount <= fillcount + 1'd1;
						else begin 
						   state         <= READCACHE_OUT;
						   update_tag_we <= 1'b1;
						end
					end
				end
			
			READCACHE_OUT :
				begin
					state         <= READONE;
					update_tag_we <= 1'b0;
				end
		endcase
	end
end

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
	.width(ASSOCIATIVITY),
	.widthad(LINE_BITS),
	.width_byteena(1),
	.wraddress_aclr("OFF"),
	.wraddress_reg("INCLOCK"),
	.wrcontrol_aclr("OFF"),
	.wrcontrol_reg("INCLOCK")
)
dirtyram (
	.inclock(CLK),
	.outclock(CLK),
	
	.data(tags_dirty_in),
	.rdaddress(read_addr[LINEMASKMSB:LINEMASKLSB]),
	.wraddress(update_tag_addr),
	.wren(update_tag_we),
	.q(tags_dirty_out)
);

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
			.width(ASSO_BITS),
			.widthad(LINE_BITS),
			.width_byteena(1),
			.wraddress_aclr("OFF"),
			.wraddress_reg("INCLOCK"),
			.wrcontrol_aclr("OFF"),
			.wrcontrol_reg("INCLOCK")
		)
		LRUram (
			.inclock(CLK),
			.outclock(CLK),
			
			.data(LRU_in[i]),
			.rdaddress(LRU_addr),
			.wraddress(LRU_addr),
			.wren(LRU_we),
			.q(LRU_out[i])
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
