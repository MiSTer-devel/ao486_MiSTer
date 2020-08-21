/*
 * Copyright (c) 2014, Aleksander Osman
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

module sound(
	input               clk,
	input               clk_opl,
	input               rst_n,

	output              irq,

	
	input       [3:0]   address,
	input               read,
	output reg  [7:0]   readdata,
	input               write,
	input       [7:0]   writedata,

	input               sb_cs,   //220h-22Fh
	input               fm_cs,   //388h-38Bh (228h-229h)

	input               fm_mode,
	input               cms_en,

	//dma
	output              dma_req,
	input               dma_ack,
	input               dma_terminal,
	input       [7:0]   dma_readdata,
	output      [7:0]   dma_writedata,

	//sound output
	output     [15:0]   sample_l,
	output     [15:0]   sample_r,

	input      [27:0]   clock_rate
);

wire sb_read  = read  & sb_cs;
wire sb_write = write & sb_cs;
wire fm_read  = read  & fm_cs;
wire fm_write = write & fm_cs;

always @(posedge clk) readdata <= cms_rd ? data_from_cms : (!address[2:0]) ? (opl_dout | (fm_mode ? 8'h00 : 8'h06)) : data_from_dsp;

//------------------------------------------------------------------------------

reg [27:0] clk_rate;
always @(posedge clk) clk_rate <= clock_rate;

reg ce_1us;
always @(posedge clk) begin
	reg [27:0] sum = 0;

	ce_1us = 0;
	sum = sum + 28'd1000000;
	if(sum >= clk_rate) begin
		sum = sum - clk_rate;
		ce_1us = 1;
	end
end

//------------------------------------------------------------------------------ dsp

wire [7:0] data_from_dsp;

wire       dsp_disabled;
wire       dsp_do;
wire [7:0] dsp_value;

sound_dsp sound_dsp_inst(
	.clk             (clk),
	.rst_n           (rst_n),

	.ce_1us          (ce_1us),

	.irq             (irq),           //output

	//io slave 220h-22Fh
	.io_address      (address),       //input [3:0]
	.io_read         (sb_read),       //input
	.io_readdata     (data_from_dsp), //output [7:0]
	.io_write        (sb_write),      //input
	.io_writedata    (writedata),     //input [7:0]

	//dma
	.dma_req         (dma_req),       //output
	.dma_ack         (dma_ack),       //input
	.dma_terminal    (dma_terminal),  //input
	.dma_readdata    (dma_readdata),  //input [7:0]
	.dma_writedata   (dma_writedata), //output [7:0]

	//sample
	.sample_disabled (dsp_disabled),  //output
	.sample_do       (dsp_do),        //output
	.sample_value    (dsp_value)      //output [7:0] unsigned
);

//------------------------------------------------------------------------------ opl

wire [15:0] sample_from_opl_l;
wire [15:0] sample_from_opl_r;
wire  [7:0] opl_dout;

wire opl_we = (           address[2:1] == 0 && sb_write)  //220-221,228-229
           || (fm_mode && address[3:1] == 1 && sb_write)  //222-223
           || (             address[1] == 0 && fm_write)  //388-389
           || (fm_mode &&   address[1] == 1 && fm_write); //38A-38B

opl3 #(50000000) opl
(
	.clk(clk),
	.clk_opl(clk_opl),
	.rst_n(rst_n),

	.ce_1us(ce_1us),

	.addr(address[1:0]),
	.din(writedata),
	.dout(opl_dout),
	.we(opl_we & ~cms_wr),
	.rd((sb_read || fm_read) && (address == 8)),

	.sample_l(sample_from_opl_l),
	.sample_r(sample_from_opl_r)
);

//------------------------------------------------------------------------------ c/ms

wire cms_rd = (address == 4'h4 || address == 4'hB) && sb_cs && cms_en;
wire [7:0] data_from_cms = address[3] ? cms_det : 8'h7F;

wire cms_wr = ~address[3] & sb_cs & cms_en;

reg [7:0] cms_det;
always @(posedge clk) if(write && cms_wr && &address[2:1]) cms_det <= writedata;

reg ce_saa;
always @(posedge clk) begin
	reg [27:0] sum = 0;

	ce_saa = 0;
	sum = sum + 28'd7159090;
	if(sum >= clk_rate) begin
		sum = sum - clk_rate;
		ce_saa = 1;
	end
end

wire [7:0] saa1_l,saa1_r;
saa1099 ssa1
(
	.clk_sys(clk),
	.ce(ce_saa),
	.rst_n(rst_n & cms_en),
	.cs_n(~(cms_wr && (address[2:1] == 0))),
	.a0(address[0]),
	.wr_n(~write),
	.din(writedata),
	.out_l(saa1_l),
	.out_r(saa1_r)
);

wire [7:0] saa2_l,saa2_r;
saa1099 ssa2
(
	.clk_sys(clk),
	.ce(ce_saa),
	.rst_n(rst_n & cms_en),
	.cs_n(~(cms_wr && (address[2:1] == 1))),
	.a0(address[0]),
	.wr_n(~write),
	.din(writedata),
	.out_l(saa2_l),
	.out_r(saa2_r)
);

wire [8:0] cms_l = {1'b0, saa1_l} + {1'b0, saa2_l};
wire [8:0] cms_r = {1'b0, saa1_r} + {1'b0, saa2_r};

//------------------------------------------------------------------------------

reg [15:0] sample_dsp;
always @(posedge clk) begin
	if(dsp_disabled) sample_dsp <= 0;
	else if(dsp_do)  sample_dsp <= {~dsp_value[7], dsp_value[6:0], dsp_value};  //unsigned to signed
end

assign sample_l = {{2{sample_dsp[15]}}, sample_dsp[15:2]} + {sample_from_opl_l[15], sample_from_opl_l[15:1]} + {2'b00, cms_l, cms_l[8:4]};
assign sample_r = {{2{sample_dsp[15]}}, sample_dsp[15:2]} + {sample_from_opl_r[15], sample_from_opl_r[15:1]} + {2'b00, cms_r, cms_r[8:4]};

endmodule
