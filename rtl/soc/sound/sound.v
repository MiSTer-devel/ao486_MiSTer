/*
 * Copyright (c) 2014, Aleksander Osman
 * Copyright (C) 2017-2020 Alexey Melnikov
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

module sound
(
	input             clk,
	input             clk_opl,
	input             rst_n,

	output            irq_5,
	output            irq_7,
	output            irq_10,

	input       [3:0] address,
	input             read,
	output reg  [7:0] readdata,
	input             write,
	input       [7:0] writedata,

	input             sb_cs,   //220h-22Fh
	input             fm_cs,   //388h-38Bh

	input             fm_mode,
	input             cms_en,

	//dma
	output            dma_req8,
	output            dma_req16,
	input             dma_ack,
	input      [15:0] dma_readdata,
	output     [15:0] dma_writedata,

	//sound output
	output reg [15:0] sample_l,
	output reg [15:0] sample_r,

	input      [27:0] clock_rate
);

wire sb_read  = read  & sb_cs;
wire sb_write = write & sb_cs;
wire fm_read  = read  & fm_cs;
wire fm_write = write & fm_cs;

always @(posedge clk) readdata <= mixer_rd ? mixer_val : cms_rd ? data_from_cms : (!address[2:0]) ? (opl_dout | (fm_mode ? 8'h00 : 8'h06)) : data_from_dsp;

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

wire  [7:0] data_from_dsp;
wire [15:0] dsp_value_l, dsp_value_r;
wire        irq8, irq16;

sound_dsp sound_dsp_inst
(
	.clk             (clk),
	.rst_n           (rst_n),

	.clock_rate      (clk_rate),

	.ce_1us          (ce_1us),

	.irq8            (irq8),
	.irq16           (irq16),

	//io slave 220h-22Fh
	.io_address      (address),
	.io_read         (sb_read),
	.io_readdata     (data_from_dsp),
	.io_write        (sb_write),
	.io_writedata    (writedata),

	//dma
	.dma_req8        (dma_req8),
	.dma_req16       (dma_req16),
	.dma_ack         (dma_ack),
	.dma_readdata    (dma_readdata),
	.dma_writedata   (dma_writedata),

	.dma_16_en       (dma_16_en),
	.sbp             (sbp),
	.sbp_stereo      (sbp_stereo),

	//sample
	.sample_value_l  (dsp_value_l),
	.sample_value_r  (dsp_value_r)
);

wire   irq    = irq8 | irq16;
assign irq_5  = irq & irq_5_en;
assign irq_7  = irq & irq_7_en;
assign irq_10 = irq & irq_10_en;

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

//------------------------------------------------------------------------------ output mixer

wire mixer_rd = (address == 4'h5) && sb_cs;

reg [7:0] mixer_reg;
always @(posedge clk) begin
	if(~rst_n)                                 mixer_reg <= 0;
	else if(write && sb_cs && address == 4'h4) mixer_reg <= writedata;
end

reg dma_16_en;
always @(posedge clk) begin
	if(~rst_n)                                                      dma_16_en <= 1;
	else if(write && sb_cs && address == 4'h5 && mixer_reg == 'h81) dma_16_en <= writedata[5];
end

reg irq_7_en, irq_10_en, sbp;
always @(posedge clk) begin
	if(~rst_n)                                                      {sbp,irq_10_en,irq_7_en} <= 0;
	else if(write && sb_cs && address == 4'h5 && mixer_reg == 'h80) begin
		if(writedata == 'hAD)      sbp <= 1;
		else if(writedata == 'hAE) sbp <= 0;
		else                       {irq_10_en,irq_7_en} <= {writedata[3:2] == 2'b10, writedata[3:2] == 2'b01};
	end
end

wire irq_5_en = ~irq_7_en & ~irq_10_en;

reg       sbp_stereo;
reg [4:0] vol_l, vol_r;
always @(posedge clk) begin
	if(~rst_n) begin
		{vol_l, vol_r} <= 10'h3FF;
		sbp_stereo <= 0;
	end
	else if(write && sb_cs && address == 4'h5) begin
		if(mixer_reg == 8'h00) begin {vol_l, vol_r} <= 10'h3FF; sbp_stereo <= 0; end
		if(mixer_reg == 8'h0E) sbp_stereo <= writedata[1];
		if(mixer_reg == 8'h22) {vol_l, vol_r} <= {writedata[7:4], writedata[7], writedata[3:0], writedata[3]};
		if(mixer_reg == 8'h30 && ~sbp) vol_l <= writedata[7:3];
		if(mixer_reg == 8'h31 && ~sbp) vol_r <= writedata[7:3];
	end
end

reg [7:0] mixer_val;
always @(posedge clk) begin
	case(mixer_reg)
		'h04: mixer_val <= 8'hFF;
		'h0E: mixer_val <= {6'd0, sbp_stereo, 1'b0};
		'h22: mixer_val <= {vol_l[4:1],vol_r[4:1]};
	default: mixer_val <= 8'h00;
	endcase

	if(~sbp) begin
		case(mixer_reg)
			'h30: mixer_val <= {vol_l, 3'd0};
			'h31: mixer_val <= {vol_r, 3'd0};
			'h32: mixer_val <= 8'hFF;
			'h33: mixer_val <= 8'hFF;
			'h80: mixer_val <= {4'h0, irq_10_en, irq_7_en, irq_5_en, 1'b0}; //IRQ 7 or 5
			'h81: mixer_val <= {2'b00,dma_16_en,1'b0,4'h2}; //DMA 5/1
			'h82: mixer_val <= {6'd0, irq16, irq8};
		endcase;
	end
end

reg [15:0] sample_pre_l, sample_pre_r;
always @(posedge clk) begin
	sample_pre_l <= {{2{dsp_value_l[15]}}, dsp_value_l[15:2]} + {sample_from_opl_l[15], sample_from_opl_l[15:1]} + {2'b00, cms_l, cms_l[8:4]};
	sample_pre_r <= {{2{dsp_value_r[15]}}, dsp_value_r[15:2]} + {sample_from_opl_r[15], sample_from_opl_r[15:1]} + {2'b00, cms_r, cms_r[8:4]};
end

always @(posedge clk) begin
	sample_l <= $signed(sample_pre_l) >>> ~vol_l[4:1];
	sample_r <= $signed(sample_pre_r) >>> ~vol_l[4:1];
end

endmodule
