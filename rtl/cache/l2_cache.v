
module l2_cache #(parameter ADDRBITS = 24)
(
   input         CLK,
   input         RESET,
	
   input         DISABLE,
   
   // CPU bus, master, 32bit
   input  [29:0] CPU_ADDR,
   input  [31:0] CPU_DIN,
   output [31:0] CPU_DOUT,
   output        CPU_DOUT_READY,
   input   [3:0] CPU_BE,
   input   [3:0] CPU_BURSTCNT,
   output        CPU_BUSY,
   input         CPU_RD,
   input         CPU_WE,
   
   // DDR3 RAM, slave, 64bit
   output [ADDRBITS:0] DDRAM_ADDR,
   output [63:0] DDRAM_DIN,
   input  [63:0] DDRAM_DOUT,
   input         DDRAM_DOUT_READY,
   output  [7:0] DDRAM_BE,
   output  [7:0] DDRAM_BURSTCNT,
   input         DDRAM_BUSY,
   output        DDRAM_RD,
   output        DDRAM_WE,
   
   // VGA bus, slave, 8bit
   output [16:0] VGA_ADDR,
   input   [7:0] VGA_DIN,
   output  [7:0] VGA_DOUT,
   input   [2:0] VGA_MODE,
   output        VGA_RD,
   output        VGA_WE,

	input   [5:0] VGA_WR_SEG,
	input   [5:0] VGA_RD_SEG,
	input         VGA_FB_EN
);
   

// cache settings
localparam LINES         = 128;
localparam LINESIZE      = 8;
localparam ASSOCIATIVITY = 4;	

// cache control
localparam ASSO_BITS     = $clog2(ASSOCIATIVITY);
localparam LINESIZE_BITS = $clog2(LINESIZE);
localparam LINE_BITS     = $clog2(LINES);
localparam RAMSIZEBITS   = $clog2(LINESIZE * LINES);

localparam LINEMASKLSB   = $clog2(LINESIZE);
localparam LINEMASKMSB   = LINEMASKLSB + $clog2(LINES) - 1;

reg    [ASSOCIATIVITY-1:0]      tags_dirty_in;
reg    [ASSOCIATIVITY-1:0]      tags_dirty_out;
wire   [ADDRBITS-RAMSIZEBITS:0] tags_read[0:ASSOCIATIVITY-1];
reg                             update_tag_we;
reg    [LINE_BITS-1:0]          update_tag_addr;

reg    [ASSO_BITS-1:0] LRU_in [0:ASSOCIATIVITY-1];
reg    [ASSO_BITS-1:0] LRU_out[0:ASSOCIATIVITY-1];
reg                             LRU_we;
reg    [LINE_BITS-1:0]          LRU_addr;

localparam [3:0]
   START         = 0,
	IDLE          = 1,
	WRITEONE      = 2,
	READONE       = 3,
	FILLCACHE     = 4,
	READCACHE_OUT = 5,
	VGAREAD       = 6,
	VGAWAIT       = 7,
	VGABYTECHECK  = 8,
	VGAWRITE      = 9;

// memory
wire              [31:0] readdata_cache[0:ASSOCIATIVITY-1];
reg      [ASSO_BITS-1:0] cache_mux;

reg    [RAMSIZEBITS-1:0] memory_addr_b;
reg               [63:0] memory_datain;
reg  [0:ASSOCIATIVITY-1] memory_we;
reg                [7:0] memory_be;
reg  [LINESIZE_BITS-1:0] fillcount;

reg   [3:0] state;

reg  [ADDRBITS:0] read_addr;
reg         [3:0] burst_left;

reg         force_fetch;
reg         force_next;

reg         data64_high;

// internal mux
reg         ram_dout_ready;
reg   [7:0] ram_burstcnt;
reg [ADDRBITS:0] ram_addr;
reg         ram_rd;
reg  [63:0] ram_din;
reg   [7:0] ram_be;
reg         ram_we;

reg         shr_rgn_en;
reg         read_behind;

reg         vga_ram;
reg  [31:0] vga_data;
reg  [31:0] vga_data_r;
reg   [3:0] vga_be;
reg   [2:0] vga_bcnt;
reg   [1:0] vga_ba;
reg         vga_wr;
reg         vga_re;
reg  [14:0] vga_wa;
reg   [1:0] vga_mask;
reg   [1:0] vga_cmp;
reg  [31:0] vga_next_data;
reg   [3:0] vga_next_be;
reg         vgabusy;

reg  [29:0] CPU_ADDR_1;
reg  [31:0] CPU_DIN_1;
reg         CPU_WE_1;

reg         RESET_1;
reg         RESET_2;

assign DDRAM_BURSTCNT = ram_burstcnt;
assign DDRAM_ADDR     = ram_addr;
assign DDRAM_RD       = ram_rd;
assign DDRAM_DIN      = ram_din;
assign DDRAM_BE       = ram_be;
assign DDRAM_WE       = ram_we;

assign CPU_BUSY       = (state == IDLE) ? DDRAM_BUSY : (vgabusy | ram_we);
assign CPU_DOUT       = vga_ram ? vga_data_r : readdata_cache[cache_mux];
assign CPU_DOUT_READY = ram_dout_ready;

assign VGA_DOUT       = vga_data[7:0];
assign VGA_WE         = vga_wr & vga_be[0];
assign VGA_RD         = vga_re & vga_be[0];
assign VGA_ADDR       = {vga_wa, vga_ba};

always @(posedge CLK) begin
	case (VGA_MODE)
		3'b100:		// 128K
			begin
				vga_mask <= 2'b00;
				vga_cmp  <= 2'b00;
			end
		
		3'b101:		// lower 64K
			begin
				vga_mask <= 2'b10;
				vga_cmp  <= 2'b00;
			end
		
		3'b110:		// 3rd 32K
			begin
				vga_mask <= 2'b11;
				vga_cmp  <= 2'b10;
			end
		
		3'b111:		// top 32K
			begin
				vga_mask <= 2'b11;
				vga_cmp  <= 2'b11;
			end
		
		default :	// disable VGA RAM
			begin
				vga_mask <= 2'b00;
				vga_cmp  <= 2'b11;
			end
	endcase
end
   
wire ram_rgn = !CPU_ADDR[29:ADDRBITS+2];
wire rom_rgn = (CPU_ADDR[ADDRBITS+1:14] == 'hC)  || (CPU_ADDR[ADDRBITS+1:14] == 'hF);
wire vga_rgn = (CPU_ADDR[ADDRBITS+1:15] == 'h5)  && ((CPU_ADDR[14:13] & vga_mask) == vga_cmp);
wire shr_rgn = (CPU_ADDR[ADDRBITS+1:11] == 'h67) && shr_rgn_en;

wire [7:0] be64 = CPU_ADDR[0] ? {CPU_BE, 4'h0} : {4'h0, CPU_BE};

always @(posedge CLK) begin
	reg [ASSO_BITS:0] i;
	reg [ASSO_BITS-1:0] match;
	
	ram_dout_ready <= 1'b0;
	memory_we      <= {ASSOCIATIVITY{1'b0}};
	
	RESET_1 <= RESET;
	RESET_2 <= RESET_1;

	if (RESET_1 && ~RESET_2) begin
		state           <= START;
		update_tag_addr <= {LINE_BITS{1'b0}};
		update_tag_we   <= 1'b1;
		tags_dirty_in   <= {ASSOCIATIVITY{1'b1}};
		shr_rgn_en      <= 1'b0;
		vgabusy         <= 1'b0;
	end
	else begin
		
		if (~DDRAM_BUSY) begin
			ram_rd <= 1'b0;
			ram_we <= 1'b0;
		end

		// LRU update after read
		LRU_we <= ram_dout_ready && ~LRU_we;
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

		if (CPU_WE_1 && (CPU_ADDR_1 == 'h33800) && (CPU_DIN_1[15:0] == 'hA345)) shr_rgn_en <= 1'b1;
		
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
					vga_wr <= 1'b0;
					vga_re <= 1'b0;
					if (!DDRAM_BUSY) begin
						
						// for timing purposes, most registers are assigned without region checks
						CPU_ADDR_1    <= CPU_ADDR;
						CPU_DIN_1     <= CPU_DIN;
						CPU_WE_1      <= CPU_WE;

						ram_addr      <= CPU_ADDR[ADDRBITS+1:1];
						ram_burstcnt  <= 8'h01;
						read_addr     <= CPU_ADDR[ADDRBITS+1:1];
						burst_left    <= CPU_BURSTCNT;
						data64_high   <= CPU_ADDR[0];

						vga_wa        <= CPU_ADDR[14:0];
						vga_bcnt      <= 3;
						vga_next_data <= CPU_DIN;
						vga_next_be   <= CPU_BE;
						vga_ba        <= 2'b00;
						vga_be        <= CPU_BE;

						ram_din       <= {CPU_DIN, CPU_DIN};
						ram_be        <= be64;

						memory_datain <= {CPU_DIN, CPU_DIN};
						memory_be     <= be64;
						memory_addr_b <= CPU_ADDR[RAMSIZEBITS:1];

						read_behind   <= ~ram_rgn;
						force_fetch   <= shr_rgn | DISABLE;
						force_next    <= shr_rgn | DISABLE;

						if (CPU_RD) begin
							state     <= READONE;
							if (vga_rgn) begin
								if(VGA_FB_EN) begin
									ram_addr[24:13]  <= {6'b111110, VGA_RD_SEG};
									read_addr[24:13] <= {6'b111110, VGA_RD_SEG};
								end
								else begin
									vga_re  <= 1'b1;
									state   <= VGAWAIT;
								end
							end
						end
						else if (CPU_WE & (~rom_rgn | shr_rgn) & ram_rgn) begin
							if (vga_rgn) begin
								if(VGA_FB_EN) begin
									ram_addr[24:13]  <= {6'b111110, VGA_WR_SEG};
									read_addr[24:13] <= {6'b111110, VGA_WR_SEG};
									ram_we  <= 1'b1;
									state   <= WRITEONE;
								end
								else begin
									vgabusy <= 1'b1;
									state   <= VGABYTECHECK;
								end
							end
							else begin
								ram_we  <= 1'b1;
								state   <= WRITEONE;
							end
						end
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
					vga_ram         <= read_behind;		// use fake vga response for reading behind available ram
					vga_data_r      <= 32'd0;
					state           <= FILLCACHE;
					ram_rd          <= 1'b1;
					ram_addr        <= {read_addr[ADDRBITS:LINESIZE_BITS], {LINESIZE_BITS{1'b0}}};
					ram_be          <= 8'h00;
					ram_burstcnt    <= LINESIZE[7:0];
					fillcount       <= 0;
					memory_addr_b   <= {read_addr[RAMSIZEBITS - 1:LINESIZE_BITS], {LINESIZE_BITS{1'b0}}};
					tags_dirty_in   <= tags_dirty_out;
					update_tag_addr <= read_addr[LINEMASKMSB:LINEMASKLSB];
					update_tag_we   <= 1'b0;
					LRU_addr        <= read_addr[LINEMASKMSB:LINEMASKLSB];

					if (force_fetch) force_next <= ~force_next;

					if (~force_next) begin
						for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
							if (~tags_dirty_out[i]) begin
								if (tags_read[i] == read_addr[ADDRBITS:RAMSIZEBITS]) begin
									ram_rd         <= 1'b0;
									cache_mux      <= i[ASSO_BITS-1:0];
									ram_dout_ready <= 1'b1;
									if (burst_left > 1) begin
										state       <= READONE;
										burst_left  <= burst_left - 1'd1;
										data64_high <= ~data64_high;
										if (data64_high) read_addr <= read_addr + 1'd1;
									end
									else begin
										state <= IDLE;
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
			
			FILLCACHE:
				begin
					for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
						if (LRU_out[i] == {ASSO_BITS{1'b1}} ) cache_mux <= i[ASSO_BITS-1:0]; 
					end

					if (DDRAM_DOUT_READY) begin
						memory_datain        <= DDRAM_DOUT;
						memory_we[cache_mux] <= 1'b1;
						memory_be            <= 8'hFF;

						tags_dirty_in[cache_mux] <= 1'b0;

						if (fillcount > 0) memory_addr_b <= memory_addr_b + 1'd1;
						if (fillcount < LINESIZE - 1) fillcount <= fillcount + 1'd1;
						else begin 
							state         <= READCACHE_OUT;
							update_tag_we <= 1'b1;
						end
					end
				end
			
			VGAWAIT:
				state <= VGAREAD;
			
			VGAREAD:
				begin
					vga_ram  <= 1'b1;
					vga_bcnt <= vga_bcnt - 1'd1;
					vga_be   <= {1'b0, vga_be[3:1]};
					vga_ba   <= vga_ba + 1'd1;
					vga_data <= {VGA_DIN, vga_data[31:8]};
					state    <= VGAWAIT;

					if (!vga_bcnt) begin
						ram_dout_ready <= 1'b1;
						vga_data_r     <= {VGA_DIN, vga_data[31:8]};
						if (burst_left > 1) begin
							vga_wa      <= vga_wa + 1'd1;
							vga_ba      <= 2'b00;
							vga_bcnt    <= 3;
							vga_be      <= 4'b1111;
							burst_left  <= burst_left - 1'd1;
						end
						else begin
							state <= IDLE;
						end
					end
				end
			
			VGABYTECHECK:
				begin
					state  <= VGAWRITE;
					vga_wr <= 1'b1;
					if (!vga_next_be[2:0]) begin
						vga_data <= {24'h000000, vga_next_data[31:24]};
						vga_be   <= {3'b000, vga_next_be[3]};
						vga_ba   <= 2'b11;
					end
					else if (!vga_next_be[1:0]) begin
						vga_data <= {16'h0000, vga_next_data[31:16]};
						vga_be   <= {2'b00, vga_next_be[3:2]};
						vga_ba   <= 2'b10;
					end
					else if (!vga_next_be[0]) begin
						vga_data <= {8'h00, vga_next_data[31:8]};
						vga_be   <= {1'b0, vga_next_be[3:1]};
						vga_ba   <= 2'b01;
					end
					else begin
						vga_data <= vga_next_data;
						vga_be   <= vga_next_be;
						vga_ba   <= 2'b00;
					end
				end

			VGAWRITE:
				begin
					vga_bcnt   <= vga_bcnt - 1'd1;
					vga_be     <= {1'b0, vga_be[3:1]};
					vga_ba     <= vga_ba + 1'd1;
					vga_data   <= {8'h00, vga_data[31:8]};
					if (!vga_be[3:1]) begin
						state   <= IDLE;
						vgabusy <= 1'b0;
					end
				end

			READCACHE_OUT:
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
			.numwords_b(2**(RAMSIZEBITS+1)),
			.operation_mode("DUAL_PORT"),
			.outdata_aclr_b("NONE"),
			.outdata_reg_b("UNREGISTERED"),
			.power_up_uninitialized("FALSE"),
			.read_during_write_mode_mixed_ports("DONT_CARE"),
			.widthad_a(RAMSIZEBITS),
			.widthad_b(RAMSIZEBITS+1),
			.width_a(64),
			.width_b(32),
			.width_byteena_a(8)
		)
		ram (
			.clock0 (CLK),

			.address_a(memory_addr_b),
			.byteena_a(memory_be),
			.data_a(memory_datain),
			.wren_a(memory_we[i]),

			.address_b({read_addr[RAMSIZEBITS - 1:0], data64_high}),
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
