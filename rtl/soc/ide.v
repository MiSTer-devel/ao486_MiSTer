/*
 * Copyright (c) 2020, Alexey Melnikov
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

module ide
(
	input             clk,
	input             rst_n,

	output reg        irq,
	output            drq,
	
	input             use_fast, // 1 - supports fast read mode
	output            no_data,  // pause for system when no data is available in fast mode

	output      [1:0] drive_en,

	input       [3:0] io_address,
	input             io_read,
	output reg [31:0] io_readdata,
	input             io_write,
	input      [31:0] io_writedata,
	input             io_32,

	output reg        io_wait,

	output reg  [2:0] request,

	input       [3:0] mgmt_address,
	input             mgmt_write,
	input      [15:0] mgmt_writedata,
	input             mgmt_read,
	output reg [15:0] mgmt_readdata
);

assign drq      = status[3];
assign drive_en = present;

//------------------------------------------------------------------------------

wire io_wr = io_write & |present;

//------------------------------------------------------------------------------

always @(posedge clk) if(io_read) begin
	if(!present) io_readdata <= 32'hFFFFFFFF;
	else begin
		case(io_address)
				   0: io_readdata <= status[3] ? {buf_q[31:16], (~io_32 & io_cnt[0]) ? buf_q[31:16] : buf_q[15:0]} : 32'd0;
				   1: io_readdata <= error;
				   2: io_readdata <= (hob ? sector_count[15:8] : sector_count[7:0] );
				   3: io_readdata <= (hob ? sector[15:8]       : sector[7:0]       );
				   4: io_readdata <= (hob ? cylinder[23:16]    : cylinder[7:0]     );
				   5: io_readdata <= (hob ? cylinder[31:24]    : cylinder[15:8]    );
				   6: io_readdata <= drv_addr;
				   7: io_readdata <= status;
				  14: io_readdata <= status;
				  15: io_readdata <= { 2'b10, ~drv_addr[3:0], ~drv_addr[4], drv_addr[4]};
			default: io_readdata <= 0;
		endcase
	end
end

//------------------------------------------------------------------------------

reg [7:0] features;
always @(posedge clk) begin
	if(~rst_n)                               features <= 8'h00;
	else if(io_wr && io_address == 1)        features <= io_writedata[7:0];
end

reg [15:0] blk_size;
always @(posedge clk) begin
	if(~rst_n)                                               blk_size <= 16'h0000;
	else if(mgmt_write && mgmt_address == 0)                 blk_size <= {mgmt_writedata[7:0], 8'h00};
	else if(mgmt_write && mgmt_address == 4 && blk_size[15]) blk_size <= mgmt_writedata[15:0];
end

reg [7:0] error;
always @(posedge clk) begin
	if(~rst_n)                               error <= 8'h00;
	else if(mgmt_write && mgmt_address == 0) error <= mgmt_writedata[15:8];
end

reg [15:0] sector_count;
always @(posedge clk) begin
	if(~rst_n)                               sector_count       <= 16'd1;
	else if(mgmt_write && mgmt_address == 1) sector_count[7:0]  <= mgmt_writedata[7:0];
	else if(mgmt_write && mgmt_address == 3) sector_count[15:8] <= mgmt_writedata[7:0];
	else if(io_wr && io_address == 2)        sector_count       <= {sector_count[7:0], io_writedata[7:0]};
end

reg [15:0] sector;
always @(posedge clk) begin
	if(~rst_n)                               sector       <= 16'd1;
	else if(mgmt_write && mgmt_address == 1) sector[7:0]  <= mgmt_writedata[15:8];
	else if(mgmt_write && mgmt_address == 3) sector[15:8] <= mgmt_writedata[15:8];
	else if(io_wr && io_address == 3)        sector       <= {sector[7:0],io_writedata[7:0]};
end

reg [31:0] cylinder;
always @(posedge clk) begin
	if(~rst_n)                               cylinder                          <= 32'hFFFFFFFF;
	else if(mgmt_write && mgmt_address == 2) cylinder[15:0]                    <= mgmt_writedata[15:0];
	else if(mgmt_write && mgmt_address == 4) cylinder[31:16]                   <= mgmt_writedata[15:0];
	else if(io_wr && io_address == 4)        {cylinder[23:16], cylinder[7:0] } <= {cylinder[7:0],  io_writedata[7:0]};
	else if(io_wr && io_address == 5)        {cylinder[31:24], cylinder[15:8]} <= {cylinder[15:8], io_writedata[7:0]};
end

reg [7:0] drv_addr;
always @(posedge clk) begin
	if(~rst_n)                               drv_addr <= 8'd0;
	else if(mgmt_write && mgmt_address == 5) drv_addr <= mgmt_writedata[7:0];
	else if(io_wr && io_address == 6)        drv_addr <= io_writedata[7:0];
end

reg [7:0] cmd;
always @(posedge clk) begin
	if(~rst_n)                               cmd <= 8'd0;
	else if(io_wr && io_address == 7)        cmd <= io_writedata[7:0];
end

reg [7:0] status = 0;
always @(posedge clk) begin
	if(reset)                                status <= 8'h80;
	else if(mgmt_write && mgmt_address == 5) status <= {mgmt_writedata[15:14],1'b0,mgmt_writedata[12:11],2'b00,mgmt_writedata[8]};
	else if(io_wr && io_address == 7)        status <= 8'h80;
	else if(io_done & drq & last_read)       status <= 8'h40;
	else if(io_done & drq)                   status <= 8'h80;
end

reg last_read = 0;
always @(posedge clk) begin
	if(reset)                                last_read <= 0;
	else if(mgmt_write && mgmt_address == 5) last_read <= mgmt_writedata[9];
	else if(io_done & drq)                   last_read <= 0;
end

reg fast_read = 0;
always @(posedge clk) begin
	if(reset)                                fast_read <= 0;
	else if(mgmt_write && mgmt_address == 5) fast_read <= mgmt_writedata[13];
	else if(io_done & drq)                   fast_read <= 0;
end

always @(posedge clk) begin
	if(~rst_n)                               io_wait <= 1'd0;
	else if(sw_reset)                        io_wait <= use_wait;
	else if(mgmt_write && mgmt_address == 5) io_wait <= 1'd0;
	else if(io_wr && io_address == 7)        io_wait <= use_wait;
	else if(io_done & drq)                   io_wait <= use_wait;
end

always @(posedge clk) begin
	if(reset)                                request <= 3'b110; // reset
	else if(mgmt_write && mgmt_address == 5) request <= 3'b000;
	else if(io_wr && io_address == 7)        request <= 3'b100; // new command 
	else if(io_done & drq & ~last_read)      request <= 3'b101; // data send/recv
end

always @(posedge clk) begin
	if(reset)                                                                      irq <= 1'b0;
	else if(mgmt_write && mgmt_address == 5 && mgmt_writedata[10] && ~disable_irq) irq <= 1'b1;
	else if((io_read | io_wr) && io_address == 7)                                  irq <= 1'b0;
end

always @(posedge clk) begin
	case(mgmt_address)
			0: mgmt_readdata <= {features, 6'd0, use_fast, io_done};
			1: mgmt_readdata <= {sector[7:0], sector_count[7:0]};
			2: mgmt_readdata <= {cylinder[15:0]};
			3: mgmt_readdata <= {sector[15:8], sector_count[15:8]};
			4: mgmt_readdata <= {cylinder[31:16]};
			5: mgmt_readdata <= {cmd, drv_addr};
	default: mgmt_readdata <= (mgmt_cnt[0]) ? buf_readdata[31:16] : buf_readdata[15:0];
	endcase
end

//------------------------------------------------------------------------------

reg [1:0] hob_ena = 0;
reg [1:0] present = 0;
always @(posedge clk) begin
	if(mgmt_write && mgmt_address == 6 && mgmt_writedata[3]) {hob_ena[0], present[0]} <= mgmt_writedata[1:0];
	if(mgmt_write && mgmt_address == 6 && mgmt_writedata[7]) {hob_ena[1], present[1]} <= mgmt_writedata[5:4];
end

reg use_wait = 0;
always @(posedge clk) begin
	if(mgmt_write && mgmt_address == 6 && mgmt_writedata[9]) use_wait <= mgmt_writedata[8];
end

//------------------------------------------------------------------------------

wire reset = ~rst_n | sw_reset;

reg disable_irq;
always @(posedge clk) begin
	if(reset)                          disable_irq <= 1'b0;
	else if(io_wr && io_address == 14) disable_irq <= io_writedata[1];
end

reg sw_reset;
always @(posedge clk) begin
	if(~rst_n)                         sw_reset <= 1'b0;
	else if(io_wr && io_address == 14) sw_reset <= io_writedata[2];
end

reg hob_pre;
always @(posedge clk) begin
	if(reset)                          hob_pre <= 1'b0;
	else if(io_wr && io_address == 14) hob_pre <= io_writedata[7];
end

reg hob;
always @(posedge clk) hob <= hob_pre & hob_ena[drv_addr[4]];

//------------------------------------------------------------------------------

wire write_data_io = io_wr   && io_address == 0 && drq;
wire read_data_io  = io_read && io_address == 0 && drq;

wire       io_done = (blk_size && io_cnt >= blk_size);
reg [13:0] io_cnt;
wire       io_stb = read_data_io | write_data_io;

always @(posedge clk) begin
	reg old_stb, r_32;
	old_stb <= io_stb;

	if(io_stb) r_32 <= io_32;

	if(reset)                                io_cnt <= 0;
	else if(mgmt_write && mgmt_address == 5) io_cnt <= 0;
	else if(old_stb & ~io_stb)               io_cnt <= io_cnt + 1'd1 + r_32;
end

reg [13:0] mgmt_cnt;
always @(posedge clk) begin
	reg old_wr, old_rd;
	
	old_wr <= mgmt_write;
	old_rd <= mgmt_read;
	if((old_wr & ~mgmt_write) | (old_rd & ~mgmt_read)) begin
		if(&mgmt_address) mgmt_cnt <= mgmt_cnt + 1'd1;
		else mgmt_cnt <= 0;
	end
	
	if(~rst_n) mgmt_cnt <= 0;
end

wire       n_data = (mgmt_cnt[13:1] <= io_cnt[13:1]) && drq && fast_read;
reg  [1:0] n_data_r;
assign     no_data = n_data || n_data_r;
always @(posedge clk) n_data_r <= {n_data_r[0], n_data};

wire [31:0] buf_readdata;
wire [31:0] buf_q;

dpram #(12,16) io_buf0
(
	.clock(clk),

	.address_a(mgmt_cnt[12:1]),
	.data_a(mgmt_writedata),
	.wren_a(mgmt_write & &mgmt_address & ~mgmt_cnt[0]),
	.q_a(buf_readdata[15:0]),

	.address_b(io_cnt[12:1]),
	.data_b(io_writedata[15:0]),
	.wren_b(write_data_io & (io_32 | ~io_cnt[0])),
	.q_b(buf_q[15:0])
);

dpram #(12,16) io_buf1
(
	.clock(clk),

	.address_a(mgmt_cnt[12:1]),
	.data_a(mgmt_writedata),
	.wren_a(mgmt_write & &mgmt_address & mgmt_cnt[0]),
	.q_a(buf_readdata[31:16]),

	.address_b(io_cnt[12:1]),
	.data_b(io_32 ? io_writedata[31:16] : io_writedata[15:0]),
	.wren_b(write_data_io & (io_32 | io_cnt[0])),
	.q_b(buf_q[31:16])
);

//------------------------------------------------------------------------------

endmodule
