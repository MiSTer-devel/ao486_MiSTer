/*
 * Copyright (c) 2014, Aleksander Osman
 * Copyright (C) 2017-2020 Alexey Melnikov
 * All rights reserved.
 * 
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

module dma
(
	input               clk,
	input               rst_n,


	input       [4:0]   io_address,
	input               io_read,
	output      [7:0]   io_readdata,
	input               io_write,
	input       [7:0]   io_writedata,

	input               io_master_cs, //0C0h - 0DFh for master DMA 
	input               io_slave_cs,  //000h - 00Fh for slave DMA
	input               io_page_cs,   //080h - 08Fh for DMA page    

	//master
	output reg  [23:0]  mem_address,
	output reg          mem_16bit,
	input               mem_waitrequest,
	output reg          mem_read,
	input               mem_readdatavalid,
	input      [15:0]   mem_readdata,
	output reg          mem_write,
	output reg [15:0]   mem_writedata,

	/// 8 bit channels
	
	input               dma_0_req,
	output              dma_0_ack,
	output              dma_0_tc,
	output      [7:0]   dma_0_readdata,
	input       [7:0]   dma_0_writedata,

	input               dma_1_req,
	output              dma_1_ack,
	output              dma_1_tc,
	output      [7:0]   dma_1_readdata,
	input       [7:0]   dma_1_writedata,

	input               dma_2_req,
	output              dma_2_ack,
	output              dma_2_tc,
	output      [7:0]   dma_2_readdata,
	input       [7:0]   dma_2_writedata,

	input               dma_3_req,
	output              dma_3_ack,
	output              dma_3_tc,
	output      [7:0]   dma_3_readdata,
	input       [7:0]   dma_3_writedata,

	/// 16 bit channels

	input               dma_5_req,
	output              dma_5_ack,
	output              dma_5_tc,
	output     [15:0]   dma_5_readdata,
	input      [15:0]   dma_5_writedata,

	input               dma_6_req,
	output              dma_6_ack,
	output              dma_6_tc,
	output     [15:0]   dma_6_readdata,
	input      [15:0]   dma_6_writedata,

	input               dma_7_req,
	output              dma_7_ack,
	output              dma_7_tc,
	output     [15:0]   dma_7_readdata,
	input      [15:0]   dma_7_writedata
);

wire master_read  = io_read  & io_master_cs;
wire master_write = io_write & io_master_cs;
wire slave_read   = io_read  & io_slave_cs;
wire slave_write  = io_write & io_slave_cs;
wire page_write   = io_write & io_page_cs;

assign io_readdata = io_master_cs ? mas_readdata : io_slave_cs ? sla_readdata : pag_readdata;

//------------------------------------------------------------------------------

reg [7:0] pag_readdata;
always @(posedge clk) begin
	case(io_address[3:0])
			4'h1: pag_readdata <= sla_page[2];
			4'h2: pag_readdata <= sla_page[3];
			4'h3: pag_readdata <= sla_page[1];
			4'h7: pag_readdata <= sla_page[0];
			4'h9: pag_readdata <= mas_page[2];
			4'hA: pag_readdata <= mas_page[3];
			4'hB: pag_readdata <= mas_page[1];
			4'hF: pag_readdata <= mas_page[0];
		default: pag_readdata <= pag_extra;
	endcase
end

reg [7:0] sla_page[4];
reg [7:0] mas_page[4];
reg [7:0] pag_extra;

always @(posedge clk) begin
	if(~rst_n) begin
		sla_page[0] <= 0; sla_page[1] <= 0; sla_page[2] <= 0; sla_page[3] <= 0;
		mas_page[0] <= 0; mas_page[1] <= 0; mas_page[2] <= 0; mas_page[3] <= 0;
		pag_extra   <= 0;
	end
	else if(page_write) begin
		case(io_address[3:0])
				4'h1: sla_page[2] <= io_writedata;
				4'h2: sla_page[3] <= io_writedata;
				4'h3: sla_page[1] <= io_writedata;
				4'h7: sla_page[0] <= io_writedata;
				4'h9: mas_page[2] <= io_writedata;
				4'hA: mas_page[3] <= io_writedata;
				4'hB: mas_page[1] <= io_writedata;
				4'hF: mas_page[0] <= io_writedata;
			default: pag_extra   <= io_writedata;
		endcase
	end
end

//------------------------------------------------------------------------------

wire [15:0] dma_sla_address;
wire        dma_sla_write;
wire [15:0] dma_sla_writedata;
wire        dma_sla_read;
wire  [3:0] sla_req;
wire  [3:0] sla_busy;
wire        sla_disabled;
wire  [7:0] sla_readdata;

i8237 dma_sla
(
	.clk(clk),
	.rst_n(rst_n),

	.address(io_address[3:0]),
	.write(slave_write),
	.writedata(io_writedata),
	.read(slave_read),
	.readdata(sla_readdata),

	.dma_address(dma_sla_address),
	.dma_write(dma_sla_write),
	.dma_writedata(dma_sla_writedata),
	.dma_read(dma_sla_read),
	.dma_readdata(mem_readdata),
	.dma_readdatavalid(mem_readdatavalid),
	.dma_waitrequest(mem_waitrequest),

	.ch0_req(dma_0_req),
	.ch0_ack(dma_0_ack),
	.ch0_writedata(dma_0_writedata),
	.ch0_readdata(dma_0_readdata),
	.ch0_tc(dma_0_tc),

	.ch1_req(dma_1_req),
	.ch1_ack(dma_1_ack),
	.ch1_writedata(dma_1_writedata),
	.ch1_readdata(dma_1_readdata),
	.ch1_tc(dma_1_tc),

	.ch2_req(dma_2_req),
	.ch2_ack(dma_2_ack),
	.ch2_writedata(dma_2_writedata),
	.ch2_readdata(dma_2_readdata),
	.ch2_tc(dma_2_tc),

	.ch3_req(dma_3_req),
	.ch3_ack(dma_3_ack),
	.ch3_writedata(dma_3_writedata),
	.ch3_readdata(dma_3_readdata),
	.ch3_tc(dma_3_tc),

	.req(sla_req),
	.ch_req(ch_req[3:0]),
	.busy(sla_busy),
	.disabled(sla_disabled)
);

wire [15:0] dma_mas_address;
wire        dma_mas_write;
wire [15:0] dma_mas_writedata;
wire        dma_mas_read;
wire  [3:0] mas_req;
wire  [3:0] mas_busy;
wire        mas_disabled;
wire  [3:0] mas_mask;
wire  [7:0] mas_readdata;

i8237 dma_mas
(
	.clk(clk),
	.rst_n(rst_n),

	.address(io_address[4:1]),
	.write(master_write),
	.writedata(io_writedata),
	.read(master_read),
	.readdata(mas_readdata),

	.dma_address(dma_mas_address),
	.dma_write(dma_mas_write),
	.dma_writedata(dma_mas_writedata),
	.dma_read(dma_mas_read),
	.dma_readdata(mem_readdata),
	.dma_readdatavalid(mem_readdatavalid),
	.dma_waitrequest(mem_waitrequest),

	.ch1_req(dma_5_req),
	.ch1_ack(dma_5_ack),
	.ch1_writedata(dma_5_writedata),
	.ch1_readdata(dma_5_readdata),
	.ch1_tc(dma_5_tc),

	.ch2_req(dma_6_req),
	.ch2_ack(dma_6_ack),
	.ch2_writedata(dma_6_writedata),
	.ch2_readdata(dma_6_readdata),
	.ch2_tc(dma_6_tc),

	.ch3_req(dma_7_req),
	.ch3_ack(dma_7_ack),
	.ch3_writedata(dma_7_writedata),
	.ch3_readdata(dma_7_readdata),
	.ch3_tc(dma_7_tc),

	.req(mas_req),
	.ch_req(ch_req[7:4]),
	.busy(mas_busy),
	.disabled(mas_disabled),
	.mask(mas_mask)
);

always @(posedge clk) begin
	if(mas_busy) begin
		mem_address[16:0] <= {dma_mas_address, 1'b0};
		if(mas_busy[3]) mem_address[23:17] <= mas_page[3][7:1];
		if(mas_busy[2]) mem_address[23:17] <= mas_page[2][7:1];
		if(mas_busy[1]) mem_address[23:17] <= mas_page[1][7:1];
		mem_16bit     <= 1;
		mem_write     <= dma_mas_write;
		mem_read      <= dma_mas_read;
		mem_writedata <= dma_mas_writedata;
	end
	else if(sla_busy) begin
		mem_address[15:0] <= dma_sla_address;
		if(sla_busy[3]) mem_address[23:16] <= sla_page[3];
		if(sla_busy[2]) mem_address[23:16] <= sla_page[2];
		if(sla_busy[1]) mem_address[23:16] <= sla_page[1];
		if(sla_busy[0]) mem_address[23:16] <= sla_page[0];
		mem_16bit     <= 0;
		mem_write     <= dma_sla_write;
		mem_read      <= dma_sla_read;
		mem_writedata <= dma_sla_writedata;
	end
	else begin
		mem_write <= 0;
		mem_read  <= 0;
	end
end

wire sla_mute = sla_disabled | mas_disabled | mas_mask[0];
wire mas_mute = mas_disabled;

wire [7:0] ch_req =
	sla_busy || mas_busy   ? 8'b00000000 :
	sla_req[0] & ~sla_mute ? 8'b00000001 :
	sla_req[1] & ~sla_mute ? 8'b00000010 :
	sla_req[2] & ~sla_mute ? 8'b00000100 :
	sla_req[3] & ~sla_mute ? 8'b00001000 :
   mas_req[1] & ~mas_mute ? 8'b00100000 :
   mas_req[2] & ~mas_mute ? 8'b01000000 :
   mas_req[3] & ~mas_mute ? 8'b10000000 :
				                8'b00000000;

endmodule

/////////////////////////////////////////////////////////////////////////////////////////////////////////

module i8237
(
	input             clk,
	input             rst_n,

	input       [3:0] address,
	input             write,
	input       [7:0] writedata,
	input             read,
	output reg  [7:0] readdata,

	output     [15:0] dma_address,
	output            dma_write,
	output     [15:0] dma_writedata,
	output            dma_read,
	input      [15:0] dma_readdata,
	input             dma_readdatavalid,
	input             dma_waitrequest,

	input             ch0_req,
	output            ch0_ack,
	input      [15:0] ch0_writedata,
	output     [15:0] ch0_readdata,
	output reg        ch0_tc,

	input             ch1_req,
	output            ch1_ack,
	input      [15:0] ch1_writedata,
	output     [15:0] ch1_readdata,
	output reg        ch1_tc,

	input             ch2_req,
	output            ch2_ack,
	input      [15:0] ch2_writedata,
	output     [15:0] ch2_readdata,
	output reg        ch2_tc,

	input             ch3_req,
	output            ch3_ack,
	input      [15:0] ch3_writedata,
	output     [15:0] ch3_readdata,
	output reg        ch3_tc,

	output      [3:0] req,
	input       [3:0] ch_req,
	output      [3:0] busy,
	output reg        disabled,
	output reg  [3:0] mask
);

wire  [7:0] ch_readdata[4];
wire  [3:0] tc;
wire  [3:0] auto;
wire  [3:0] ack;

wire [15:0] req_data[4];
assign req_data[0] = ch0_writedata;
assign req_data[1] = ch1_writedata;
assign req_data[2] = ch2_writedata;
assign req_data[3] = ch3_writedata;

wire [15:0] ack_data[4];
assign ch0_readdata = ack_data[0];
assign ch1_readdata = ack_data[1];
assign ch2_readdata = ack_data[2];
assign ch3_readdata = ack_data[3];

assign {ch3_ack, ch2_ack, ch1_ack, ch0_ack} = ack;
always @(posedge clk) {ch3_tc, ch2_tc, ch1_tc, ch0_tc} <= tc;

wire [15:0] dma_ch_address[4];
wire  [3:0] dma_ch_write;
wire [15:0] dma_ch_writedata[4];
wire  [3:0] dma_ch_read;

assign dma_read      = |dma_ch_read;
assign dma_write     = |dma_ch_write;
assign dma_address   = dma_ch_address[0] | dma_ch_address[1] | dma_ch_address[2] | dma_ch_address[3];
assign dma_writedata = dma_ch_writedata[0] | dma_ch_writedata[1] | dma_ch_writedata[2] | dma_ch_writedata[3];

generate
	genvar i;
	for( i = 0; i < 4; i = i + 1) begin : chan
		i8237_chan #(i) dma_chan
		(
			.clk(clk),
			.rst_n(rst_n),
			.ch_reset(reset),

			.address(address),
			.writedata(writedata),
			.readdata(ch_readdata[i]),
			.write(write),
			.flip_flop(flip_flop),

			.req(ch_req[i]),
			.req_data(req_data[i]),
			.ack(ack[i]),
			.ack_data(ack_data[i]),

			.dma_address(dma_ch_address[i]),
			.dma_write(dma_ch_write[i]),
			.dma_writedata(dma_ch_writedata[i]),
			.dma_read(dma_ch_read[i]),
			.dma_readdata(dma_readdata),
			.dma_readdatavalid(dma_readdatavalid),
			.dma_waitrequest(dma_waitrequest),

			.busy(busy[i]),
			.auto(auto[i]),
			.tc(tc[i])
		);
	end
endgenerate

reg read_last;
always @(posedge clk) begin
	if(~rst_n)         read_last <= 0;
	else if(read_last) read_last <= 0;
	else               read_last <= read;
end
wire read_valid = read && ~read_last;

always @(posedge clk) begin
	if(read_valid) readdata <=
							(~address[3])     ? (ch_readdata[0]|ch_readdata[1]|ch_readdata[2]|ch_readdata[3]) :
							(address == 4'h8) ? {pending, terminated} :
							(address == 4'hF) ? {4'hF, mask} :
														8'd0; //temp reg
end

wire reset = write && address == 4'hD;

reg flip_flop;
always @(posedge clk) begin
	if(~rst_n | reset)                            flip_flop <= 0;
	else if(write && address == 12)               flip_flop <= 0;
	else if((read_valid || write) && ~address[3]) flip_flop <= ~flip_flop;
end

always @(posedge clk) begin
	if(~rst_n | reset)                disabled <= 0;
	else if(write && address == 4'h8) disabled <= writedata[2];
end

wire [3:0] writedata_bits = (4'b0001 << writedata[1:0]);
wire [3:0] pending_next   = {ch3_req, ch2_req, ch1_req, ch0_req };

reg [3:0] pending;
always @(posedge clk) begin
	if(~rst_n | reset)                              pending <= 0;
	else if(write && address == 9 &&  writedata[2]) pending <= pending | writedata_bits;
	else if(write && address == 9 && ~writedata[2]) pending <= pending & ~(writedata_bits);
	else                                            pending <= pending_next;
end

always @(posedge clk) begin
	if(~rst_n | reset)                                 mask <= 4'hF;
	else if(write && address == 4'hE)                  mask <= 4'h0;
	else if(write && address == 4'hF)                  mask <= writedata[3:0];
	else if(write && address == 4'hA &&  writedata[2]) mask <= mask | writedata_bits;
	else if(write && address == 4'hA && ~writedata[2]) mask <= mask & ~(writedata_bits);
	else                                               mask <= mask | (tc & ~auto);
end

reg [3:0] terminated;
always @(posedge clk) begin
	if(~rst_n | reset)                     terminated <= 4'h0;
	else if(read_valid && address == 4'h8) terminated <= 4'd0;
	else                                   terminated <= terminated | tc;
end

assign req = pending & ~mask;

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////


module i8237_chan #(parameter num) 
(
	input             clk,
	input             rst_n,
	input             ch_reset,

	input       [3:0] address,
	input       [7:0] writedata,
	input             write,
	output      [7:0] readdata,
	input             flip_flop,

	input             req,
	input      [15:0] req_data,
	output reg        ack,
	output reg [15:0] ack_data,

	output reg [15:0] dma_address,
	output reg        dma_write,
	output reg [15:0] dma_writedata,
	output reg        dma_read,
	input      [15:0] dma_readdata,
	input             dma_readdatavalid,
	input             dma_waitrequest,

	output            busy,
	output reg        auto,
	output            tc
);

wire sel_addr = address == (num*2);
wire sel_cnt  = address == ((num*2)+1);

assign readdata = sel_addr ? current_address[(flip_flop*8) +:8] : sel_cnt  ? current_counter[(flip_flop*8) +:8] : 8'd0;

reg [15:0] base_address;
always @(posedge clk) begin
	if(~rst_n)                base_address <= 0;
	else if(write & sel_addr) base_address[(flip_flop*8) +:8] <= writedata;
end

reg [15:0] current_address;
always @(posedge clk) begin
	if(~rst_n)                current_address <= 0;
	else if(write & sel_addr) current_address[(flip_flop*8) +:8] <= writedata;
	else if(tc && auto)       current_address <= base_address;     
	else if(update && ~dec)   current_address <= current_address + 1'd1;
	else if(update &&  dec)   current_address <= current_address - 1'd1;
end

reg [15:0] base_counter;
always @(posedge clk) begin
	if(~rst_n)                base_counter <= 0;
	else if(write & sel_cnt)  base_counter[(flip_flop*8) +:8] <= writedata;
end

reg [15:0] current_counter;
always @(posedge clk) begin
	if(~rst_n)                current_counter <= 0;
	else if(write & sel_cnt)  current_counter[(flip_flop*8) +:8] <= writedata;
	else if(tc && auto)       current_counter <= base_counter;
	else if(update)           current_counter <= current_counter - 1'd1;    
end

wire sel_mode = address == 11 && writedata[1:0] == num;

reg dec;
always @(posedge clk) begin
	if(~rst_n)                 dec <= 0;
	else if(write && sel_mode) dec <= writedata[5];
end

always @(posedge clk) begin
	if(~rst_n)                 auto <= 0;
	else if(write && sel_mode) auto <= writedata[4];
end

reg [1:0] transfer;
always @(posedge clk) begin
	if(~rst_n)                 transfer <= 0;
	else if(write && sel_mode) transfer <= writedata[3:2];
end

wire update = state == 4;
assign tc   = update && !current_counter;
assign busy = |state;

reg [2:0] state;
always @(posedge clk) begin
	if(~rst_n | ch_reset)                    state <= 0;

	else if(state == 0 && req)               state <= 1;

	else if(state == 1 && transfer == 2)     state <= 2;
	else if(state == 2 && ~dma_waitrequest)  state <= 3;
	else if(state == 3 && dma_readdatavalid) state <= 4;

	else if(state == 4)                      state <= 5;
	else if(state == 5)                      state <= 0;

	else if(state == 1 && transfer == 1)     state <= 6;
	else if(state == 6 && ~dma_waitrequest)  state <= 4;

	else if(state == 1)                      state <= 7;
	else if(state == 7)                      state <= 4;
end

always @(posedge clk) begin
	if(~rst_n)                               ack <= 0;
	else if(state == 3 && dma_readdatavalid) ack <= 1;
	else if(state == 6 && ~dma_waitrequest)  ack <= 1;
	else if(state == 7)                      ack <= 1;
	else                                     ack <= 0;
end

always @(posedge clk) begin
	if(!state)                               dma_address <= 0;
	else if(state == 1)                      dma_address <= current_address;
end

always @(posedge clk) begin
	if(!state)                               dma_read <= 0;
	else if(state == 1 && transfer == 2)     dma_read <= 1;
	else if(state == 2 && ~dma_waitrequest)  dma_read <= 0;
end

always @(posedge clk) begin
	if(!state)                               dma_write <= 0;
	else if(state == 1 && transfer == 1)     dma_write <= 1;
	else if(state == 6 && ~dma_waitrequest)  dma_write <= 0;
end

always @(posedge clk) begin
	if(!state)                               dma_writedata <= 0;
	else if(state == 1 && transfer == 1)     dma_writedata <= req_data;
end

always @(posedge clk) begin
	if(state == 3 && dma_readdatavalid)      ack_data <= dma_readdata;
end

endmodule
