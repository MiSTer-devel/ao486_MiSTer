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
	input             clk_audio,
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

	input             fm_mode, // 0 = OPL2, 1 = OPL3
	input             cms_en,

	output reg        sbp,

	output reg  [4:0] vol_master_l,
	output reg  [4:0] vol_master_r,
	output reg  [4:0] vol_voice_l,
	output reg  [4:0] vol_voice_r,
	output reg  [4:0] vol_midi_l,
	output reg  [4:0] vol_midi_r,
	output reg  [4:0] vol_cd_l,
	output reg  [4:0] vol_cd_r,
	output reg  [4:0] vol_line_l,
	output reg  [4:0] vol_line_r,
	output reg  [1:0] vol_spk,
	output reg  [4:0] vol_en,

	//dma
	output            dma_req8,
	output            dma_req16,
	input             dma_ack,
	input      [15:0] dma_readdata,
	output     [15:0] dma_writedata,

	//sound output
	output      [8:0] sample_cms_l,
	output      [8:0] sample_cms_r,
	output     [15:0] sample_sb_l,
	output     [15:0] sample_sb_r,
	output     [15:0] sample_opl_l,
	output     [15:0] sample_opl_r,

	input      [27:0] clock_rate
);

wire sb_read  = read  & sb_cs;
wire sb_write = write & sb_cs;

always @(posedge clk) readdata <= mixer_rd ? mixer_val : 
                                  cms_rd   ? data_from_cms : 
                                  opl_cs   ? (opl_dout | (fm_mode ? 8'h00 : 8'h06)) : 
                                             data_from_dsp;

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
	.clk               (clk),
	.rst_n             (rst_n),

	.clock_rate        (clk_rate),

	.ce_1us            (ce_1us),

	.irq8              (irq8),
	.irq16             (irq16),

	//io slave 220h-22Fh
	.io_address        (address),
	.io_read           (sb_read),
	.io_readdata       (data_from_dsp),
	.io_write          (sb_write),
	.io_writedata      (writedata),

	//dma
	.dma_req8          (dma_req8),
	.dma_req16         (dma_req16),
	.dma_ack           (dma_ack),
	.dma_readdata      (dma_readdata),
	.dma_writedata     (dma_writedata),

	.dma_16_en         (dma_16_en),
	.sbp               (sbp),
	.sbp_stereo        (sbp_stereo),
	.sbp_stereo_ff_rst (sbp_stereo_ff_rst),

	//sample
	.sample_value_l    (dsp_value_l),
	.sample_value_r    (dsp_value_r)
);

wire   irq    = irq8 | irq16;
assign irq_5  = irq & irq_5_en;
assign irq_7  = irq & irq_7_en;
assign irq_10 = irq & irq_10_en;

//------------------------------------------------------------------------------ opl

wire  [7:0] opl_dout;

wire opl_cs = (           address[2:1] == 0 && sb_cs)  //220-221,228-229
           || (fm_mode && address[3:1] == 1 && sb_cs)  //222-223
           || (             address[1] == 0 && fm_cs)  //388-389
           || (fm_mode &&   address[1] == 1 && fm_cs); //38A-38B

wire opl_wr = write && !cms_wr;
wire opl_rd = read;

opl3 opl
(
	.clk(clk_audio),
	.clk_host(clk),
	.clk_dac(),
	.ic_n(rst_n),
	.cs_n(!opl_cs),
	.rd_n(!opl_rd),
	.wr_n(!opl_wr),
	.address(address[1:0]),
	.din(writedata),
	.dout(opl_dout),
	.sample_valid(),
	.sample_l(sample_opl_l),
	.sample_r(sample_opl_r),
	.led(),
	.irq_n()
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

reg irq_7_en, irq_10_en;
always @(posedge clk) begin
	if(~rst_n)                                                      {sbp,irq_10_en,irq_7_en} <= 0;
	else if(write && sb_cs && address == 4'h5 && mixer_reg == 'h80) begin
		if(writedata == 'hAD)      sbp <= 1; // Select SBPro
		else if(writedata == 'hAE) sbp <= 0; // Select SB16
		else                       {irq_10_en,irq_7_en} <= {writedata[3:2] == 2'b10, writedata[3:2] == 2'b01};
	end
end

wire irq_5_en = ~irq_7_en & ~irq_10_en;

// Mixer Chip:
// SBPro 2.0 = CT1345
// SB16      = CT1745

// This resets the stereo interleaving flip-flop in the Sound Blaster Pro mixer.
wire sbp_stereo_ff_rst = write && sb_cs && address == 4'h5 && mixer_reg == 8'h0E; // SBPro mixer reg 0Eh write

reg       sbp_stereo;
reg       sbp_output_lpf_bypass;
reg       sbp_input_lpf_bypass;
reg       sbp_input_lpf_freq;
reg [1:0] sbp_input_source;

// SBPro Volume (3-bit -> 5-bit): From -28 dB to 0 dB in 4 dB steps
//                                vol_5bit = 5'd17 + (vol_3bit * 2) = {1'b1, vol_3bit, 1'b1}
// SB16  Volume (4-bit -> 5-bit): From -60 dB to 0 dB in 4 dB steps
//                                vol_5bit = 5'd01 + (vol_4bit * 2) = {      vol_4bit, 1'b1}
wire [9:0] vol_mapped = sbp ? {1'b1, writedata[7:5], 1'b1,   1'b1, writedata[3:1], 1'b1}
                            : {      writedata[7:4], 1'b1,         writedata[3:0], 1'b1};

// Note: SBPDIG.ADV performs a read-modify-write check on the mixer's mic volume register 0Ah
//       as part of the Sound Blaster Pro detection routine (e.g. Ultima Underworld, Dune II, others...).
reg [4:0] vol_mic; // SBPro: Mic volume does not affect recording

reg [6:0] rec_en[2];

reg [1:0] input_gain_l;
reg [1:0] input_gain_r;
reg [1:0] output_gain_l;
reg [1:0] output_gain_r;
reg       input_agc;
reg [3:0] treble_l;
reg [3:0] treble_r;
reg [3:0] bass_l;
reg [3:0] bass_r;

always @(posedge clk) begin
	if(~rst_n || (write && sb_cs && address == 4'h5 && mixer_reg == 8'h00)) begin
		sbp_stereo                   <= 1'b0;           // SBPro: Mixer Stereo Switch: 0=mono output, 1=stereo output (interleaved stereo)
		sbp_output_lpf_bypass        <= 1'b0;           // SBPro: Output Low-Pass Filter: 0=output through lpf, 1=bypass output lpf
		sbp_input_lpf_bypass         <= 1'b0;           // SBPro: Input Low-Pass Filter: 0=input through lpf, 1=bypass input lpf
		sbp_input_lpf_freq           <= 1'b0;           // SBPro: Input Low-Pass Filter Frequency: 0=3.2kHz lpf, 1=8.8kHz lpf
		sbp_input_source             <= 2'h0;           // SBPro: Input Source: 0,2=mic, 1=cd, 3=line
		vol_mic                      <= 5'h0;           // SBPro: Mic volume control at 4 levels (2 bits) from -46dB to 0dB in approximate 7dB steps
		                                                // SB16:  Mic volume control at 8 levels (3 bits) from -42dB to 0dB in 6dB steps
		// Original default volume:
		// - Master/Voice/MIDI (volume_5bit = 25): -11 dB SBPro, -12 dB SB16
		// - CD/Line           (volume_5bit = 00): -46 dB SBPro, -62 dB SB16
		// Note: After each channel volume the master volume will be applied to the whole mix.
		// The original default volume levels seem to be too low.
		// Reasonable volume settings with enough headroom?...
		{vol_master_l, vol_master_r} <= {5'd29, 5'd29}; // SB16:  Master volume control L/R at 32 levels (5 bits) in 2dB steps (SBPro: 8 levels (3 bits) in approximate 4dB steps)
		{vol_voice_l,  vol_voice_r}  <= {5'd29, 5'd29}; // SB16:  Voice  volume control L/R at 32 levels (5 bits) in 2dB steps (SBPro: 8 levels (3 bits) in approximate 4dB steps)
		{vol_midi_l,   vol_midi_r}   <= {5'd29, 5'd29}; // SB16:  MIDI   volume control L/R at 32 levels (5 bits) in 2dB steps (SBPro: 8 levels (3 bits) in approximate 4dB steps)
		{vol_cd_l,     vol_cd_r}     <= {5'd29, 5'd29}; // SB16:  CD     volume control L/R at 32 levels (5 bits) in 2dB steps (SBPro: 8 levels (3 bits) in approximate 4dB steps)
		{vol_line_l,   vol_line_r}   <= {5'd29, 5'd29}; // SB16:  Line   volume control L/R at 32 levels (5 bits) in 2dB steps (SBPro: 8 levels (3 bits) in approximate 4dB steps)
		vol_spk                      <= 2'h3;           // SB16:  PC Speaker volume control at 4 levels from -18dB to 0dB in 6dB steps
		vol_en                       <= 5'b11111;       // SB16:  Output mixer switches:                  line_l, line_r, cd_l, cd_r, mic
		rec_en[0]                    <= 7'b0010101;     // SB16:  Input mixer l switches: midi_l, midi_r, line_l, line_r, cd_l, cd_r, mic
		rec_en[1]                    <= 7'b0001011;     // SB16:  Input mixer r switches: midi_l, midi_r, line_l, line_r, cd_l, cd_r, mic
		input_gain_l                 <= 2'h0;           // SB16:  Input gain control left
		input_gain_r                 <= 2'h0;           // SB16:  Input gain control right
		output_gain_l                <= 2'h0;           // SB16:  Output gain control left
		output_gain_r                <= 2'h0;           // SB16:  Output gain control right
		input_agc                    <= 1'b0;           // SB16:  Automatic Gain Control (AGC): 0=disabled, 1=enabled
		treble_l                     <= 4'h8;           // SB16:  Treble left  control: 15 levels from -14dB to 14dB in 2dB steps
		treble_r                     <= 4'h8;           // SB16:  Treble right control: 15 levels from -14dB to 14dB in 2dB steps
		bass_l                       <= 4'h8;           // SB16:  Bass left    control: 15 levels from -14dB to 14dB in 2dB steps
		bass_r                       <= 4'h8;           // SB16:  Bass right   control: 15 levels from -14dB to 14dB in 2dB steps
	end
	else if(write && sb_cs && address == 4'h5) begin
		case (mixer_reg)
			// Common registers (SBPro & SB16)
			8'h04: {vol_voice_l,  vol_voice_r}  <= vol_mapped;
			8'h22: {vol_master_l, vol_master_r} <= vol_mapped;
			8'h26: {vol_midi_l,   vol_midi_r}   <= vol_mapped;
			8'h28: {vol_cd_l,     vol_cd_r}     <= vol_mapped;
			8'h2E: {vol_line_l,   vol_line_r}   <= vol_mapped;
			// SBPro Mic (2-bit -> 5-bit): from -24 dB to 0 dB in 8 dB steps
			//                             vol_5bit = 5'd19 + (vol_2bit * 4) = {1'b1, vol_2bit, 2'b11}
			// SB16  Mic (3-bit -> 5-bit): from -42 dB to 0 dB in 6 dB steps
			//                             vol_5bit = 5'd10 + (vol_3bit * 3) = 5'd10 + (vol_3bit << 1) + vol_3bit
			8'h0A: vol_mic <= sbp ? {1'b1, writedata[2:1], 2'b11}
			                      : 5'd10 + {writedata[2:0], 1'b0} + writedata[2:0];

			// SBPro only registers
			8'h0C: if (sbp) {sbp_input_lpf_bypass, sbp_input_lpf_freq, sbp_input_source} <= {writedata[5], writedata[3], writedata[2:1]};
			8'h0E: if (sbp) {sbp_output_lpf_bypass, sbp_stereo} <= {writedata[5], writedata[1]};

			// SB16 only registers
			8'h30: if (!sbp) vol_master_l  <= writedata[7:3];
			8'h31: if (!sbp) vol_master_r  <= writedata[7:3];
			8'h32: if (!sbp) vol_voice_l   <= writedata[7:3];
			8'h33: if (!sbp) vol_voice_r   <= writedata[7:3];
			8'h34: if (!sbp) vol_midi_l    <= writedata[7:3];
			8'h35: if (!sbp) vol_midi_r    <= writedata[7:3];
			8'h36: if (!sbp) vol_cd_l      <= writedata[7:3];
			8'h37: if (!sbp) vol_cd_r      <= writedata[7:3];
			8'h38: if (!sbp) vol_line_l    <= writedata[7:3];
			8'h39: if (!sbp) vol_line_r    <= writedata[7:3];
			8'h3A: if (!sbp) vol_mic       <= writedata[7:3];
			8'h3B: if (!sbp) vol_spk       <= writedata[7:6];
			8'h3C: if (!sbp) vol_en        <= writedata[4:0];
			8'h3D: if (!sbp) rec_en[0]     <= writedata[6:0];
			8'h3E: if (!sbp) rec_en[1]     <= writedata[6:0];
			8'h3F: if (!sbp) input_gain_l  <= writedata[7:6];
			8'h40: if (!sbp) input_gain_r  <= writedata[7:6];
			8'h41: if (!sbp) output_gain_l <= writedata[7:6];
			8'h42: if (!sbp) output_gain_r <= writedata[7:6];
			8'h43: if (!sbp) input_agc     <= writedata[0];
			8'h44: if (!sbp) treble_l      <= writedata[7:4];
			8'h45: if (!sbp) treble_r      <= writedata[7:4];
			8'h46: if (!sbp) bass_l        <= writedata[7:4];
			8'h47: if (!sbp) bass_r        <= writedata[7:4];

			default: ; // no change
		endcase
	end
end

wire [7:0] vol_mic_sum  = {(vol_mic - 5'd10), 3'd0} + {(vol_mic - 5'd10), 1'd0} + (vol_mic - 5'd10);
wire [2:0] vol_mic_3bit = vol_mic_sum[7:5];

reg [7:0] mixer_val;
always @(posedge clk) begin
	mixer_val <= 8'h00;

	case (mixer_reg)
		// Common registers (SBPro & SB16)
		// Note: The Sound Blaster Series 16-bit MASI Driver v2.90 used in games like Epic Pinball (MDRV004R.MUS) and
		//       Jazz Jackrabbit (MDRV004D.MUS) writes the value F3h to the mixer's master volume register (22h),
		//       then reads it back to verify. Stereo playback is enabled only if the returned value matches what was written.
		//       Hence, the reserved bits 0 and 4 in the volume registers 04h, 22h, 26h, 28h, 2Eh must be output
		//       like the original Sound Blaster Pro does (value 1) to ensure correct stereo detection with this driver.
		8'h04: mixer_val <= sbp ? { vol_voice_l < 5'd17 ? 3'd0 :  vol_voice_l[3:1], 1'b1,  vol_voice_r < 5'd17 ? 3'd0 :  vol_voice_r[3:1], 1'b1} : { vol_voice_l[4:1],  vol_voice_r[4:1]};
		8'h22: mixer_val <= sbp ? {vol_master_l < 5'd17 ? 3'd0 : vol_master_l[3:1], 1'b1, vol_master_r < 5'd17 ? 3'd0 : vol_master_r[3:1], 1'b1} : {vol_master_l[4:1], vol_master_r[4:1]};
		8'h26: mixer_val <= sbp ? {  vol_midi_l < 5'd17 ? 3'd0 :   vol_midi_l[3:1], 1'b1,   vol_midi_r < 5'd17 ? 3'd0 :   vol_midi_r[3:1], 1'b1} : {  vol_midi_l[4:1],   vol_midi_r[4:1]};
		8'h28: mixer_val <= sbp ? {    vol_cd_l < 5'd17 ? 3'd0 :     vol_cd_l[3:1], 1'b1,     vol_cd_r < 5'd17 ? 3'd0 :     vol_cd_r[3:1], 1'b1} : {    vol_cd_l[4:1],     vol_cd_r[4:1]};
		8'h2E: mixer_val <= sbp ? {  vol_line_l < 5'd17 ? 3'd0 :   vol_line_l[3:1], 1'b1,   vol_line_r < 5'd17 ? 3'd0 :   vol_line_r[3:1], 1'b1} : {  vol_line_l[4:1],   vol_line_r[4:1]};
		// SBPro Mic (5-bit -> 2-bit): vol_2bit = (vol_5bit - 5'd19) / 4
		// SB16  Mic (5-bit -> 3-bit): vol_3bit = (vol_5bit - 5'd10) / 3 = (vol_5bit - 5'd10) * 11/32
		8'h0A: mixer_val <= sbp ? {5'b00000, (vol_mic < 5'd19 ? 2'd0 : vol_mic[3:2]), 1'b0}
		                        : {5'b00000, (vol_mic < 5'd10 ? 3'd0 : vol_mic_3bit)};

		// SBPro only registers
		8'h0C: if (sbp) mixer_val <= {2'b00, sbp_input_lpf_bypass, 1'b0, sbp_input_lpf_freq, sbp_input_source, 1'b1};
		8'h0E: if (sbp) mixer_val <= {2'b00, sbp_output_lpf_bypass, 1'b1, 2'b00, sbp_stereo, 1'b1};

		// SB16 only registers
		8'h30: if (!sbp) mixer_val <= {vol_master_l, 3'b000};
		8'h31: if (!sbp) mixer_val <= {vol_master_r, 3'b000};
		8'h32: if (!sbp) mixer_val <= {vol_voice_l,  3'b000};
		8'h33: if (!sbp) mixer_val <= {vol_voice_r,  3'b000};
		8'h34: if (!sbp) mixer_val <= {vol_midi_l,   3'b000};
		8'h35: if (!sbp) mixer_val <= {vol_midi_r,   3'b000};
		8'h36: if (!sbp) mixer_val <= {vol_cd_l,     3'b000};
		8'h37: if (!sbp) mixer_val <= {vol_cd_r,     3'b000};
		8'h38: if (!sbp) mixer_val <= {vol_line_l,   3'b000};
		8'h39: if (!sbp) mixer_val <= {vol_line_r,   3'b000};
		8'h3A: if (!sbp) mixer_val <= {vol_mic,      3'b000};
		8'h3B: if (!sbp) mixer_val <= {vol_spk,   6'b000000};
		8'h3C: if (!sbp) mixer_val <= {3'b000, vol_en};
		8'h3D: if (!sbp) mixer_val <= {1'b0, rec_en[0]};
		8'h3E: if (!sbp) mixer_val <= {1'b0, rec_en[1]};
		8'h3F: if (!sbp) mixer_val <= {input_gain_l,  6'b000000};
		8'h40: if (!sbp) mixer_val <= {input_gain_r,  6'b000000};
		8'h41: if (!sbp) mixer_val <= {output_gain_l, 6'b000000};
		8'h42: if (!sbp) mixer_val <= {output_gain_r, 6'b000000};
		8'h43: if (!sbp) mixer_val <= {7'b0000000, input_agc};
		8'h44: if (!sbp) mixer_val <= {treble_l, 4'b0000};
		8'h45: if (!sbp) mixer_val <= {treble_r, 4'b0000};
		8'h46: if (!sbp) mixer_val <= {bass_l,   4'b0000};
		8'h47: if (!sbp) mixer_val <= {bass_r,   4'b0000};
		8'h80: if (!sbp) mixer_val <= {4'b1111, irq_10_en, irq_7_en, irq_5_en, 1'b0}; // IRQ 10, 7, 5
		8'h81: if (!sbp) mixer_val <= {1'b0, 1'b0, dma_16_en, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0}; // DMA 5 (16-bit), DMA 1 (8-bit)
		8'h82: if (!sbp) mixer_val <= {4'b0010, 1'b0, 1'b0, irq16, irq8}; // bits [7:4] = 1h (v4.04), 2h (v4.05), 8h (v4.12)
	endcase
end

cdc_vector_handshake_continuous #(
	.DATA_WIDTH(16*2 + 9*2)
) audio_cdc (
	.clk_in(clk),
	.clk_out(clk_audio),
	.data_in({dsp_value_l, dsp_value_r, cms_l, cms_r}),
	.data_out({sample_sb_l, sample_sb_r, sample_cms_l, sample_cms_r})
);

endmodule

//------------------------------------------------------------------------------ SB Volume

module sb_volume
#(
	parameter integer NUM_CH       = 10, // number of channels
	parameter integer SAMPLE_WIDTH = 16  // number of bits per sample
)(
	input                                clk,
	input                                sbp,         // SBPro: sbp=1, SB16: sbp=0
	input                 [NUM_CH*5-1:0] volumes_in,  // input volumes (5 bits per channel volume control)
	input      [NUM_CH*SAMPLE_WIDTH-1:0] samples_in,  // input samples (SAMPLE_WIDTH bits per channel sample)
	output reg [NUM_CH*SAMPLE_WIDTH-1:0] samples_out, // output samples (attenuated)
	output reg                           valid        // samples_out valid flag
);

// SBPro gain table (unsigned, 16-bit gain values)
// volume = 0 to 7 (3-bit) => -46 dB to 0 dB, in approximate 4 dB steps
// 8 x 16 = 128 bits packed into one vector
localparam [127:0] sbp_gain_lut = {
	16'hFFFF, //   0 dB (17'h10000 will be used for unity gain)
	16'hB53C, //  -3 dB
	16'h725A, //  -7 dB
	16'h4827, // -11 dB
	16'h2893, // -16 dB
	16'h1456, // -22 dB
	16'h0A31, // -28 dB
	16'h0148  // -46 dB
};

// SB16 gain table (unsigned, 16-bit gain values)
// volume = 0 to 31 (5-bit) => -62 dB to 0 dB, in 2 dB steps
// 32 x 16 = 512 bits packed into one vector
localparam [511:0] sb16_gain_lut = {
	16'hFFFF, //   0 dB (17'h10000 will be used for unity gain)
	16'hCB59, //  –2 dB
	16'hA186, //  –4 dB
	16'h804E, //  –6 dB
	16'h65EA, //  –8 dB
	16'h50F4, // –10 dB
	16'h404E, // –12 dB
	16'h3314, // –14 dB
	16'h2893, // –16 dB
	16'h203A, // –18 dB
	16'h199A, // –20 dB
	16'h1456, // –22 dB
	16'h1027, // –24 dB
	16'h0CD5, // –26 dB
	16'h0A31, // –28 dB
	16'h0818, // –30 dB
	16'h066E, // –32 dB
	16'h051C, // –34 dB
	16'h040F, // –36 dB
	16'h0339, // –38 dB
	16'h028F, // –40 dB
	16'h0209, // –42 dB
	16'h019E, // –44 dB
	16'h0148, // –46 dB
	16'h0105, // –48 dB
	16'h00CF, // –50 dB
	16'h00A5, // –52 dB
	16'h0083, // –54 dB
	16'h0068, // –56 dB
	16'h0053, // –58 dB
	16'h0042, // –60 dB
	16'h0034  // –62 dB
};

reg [$clog2(NUM_CH)-1:0] ch;

wire [4:0] volume_5bit = volumes_in[5*ch +: 5];
wire [2:0] volume_3bit = volume_5bit[3:1];

reg                    [16:0] gain;
reg signed [SAMPLE_WIDTH-1:0] sample;
always @(posedge clk) begin
	gain   <= (volume_5bit == 5'd31) ? 17'h10000 : 
	                             sbp ?  sbp_gain_lut[volume_3bit*16 +: 16] : 
	                                   sb16_gain_lut[volume_5bit*16 +: 16];
	sample <= samples_in[SAMPLE_WIDTH*ch +: SAMPLE_WIDTH];
end

// DSP-targeted multiply (1 x DSP block shared across all channels)
wire signed [33:0] gain_product = $signed({1'b0, gain}) * sample;

always @(posedge clk) begin
	samples_out       <= {gain_product[31:16], samples_out[NUM_CH*SAMPLE_WIDTH-1:SAMPLE_WIDTH]};
	valid             <= (ch == 0);
	ch                <= (ch == NUM_CH-1) ? 1'b0 : ch + 1'b1;
end

endmodule
