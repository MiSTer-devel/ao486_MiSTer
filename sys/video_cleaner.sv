//
//
// Copyright (c) 2018 Sorgelig
//
// This program is GPL Licensed. See COPYING for the full license.
//
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module video_cleaner
(
	input            clk_vid,
	input            ce_pix,
	input      [1:0] mix,

	input      [7:0] R,
	input      [7:0] G,
	input      [7:0] B,

	input            HSync,
	input            VSync,
	input            HBlank,
	input            VBlank,

	//optional de
	input            DE_in,

	// video output signals
	output reg [7:0] VGA_R,
	output reg [7:0] VGA_G,
	output reg [7:0] VGA_B,
	output reg       VGA_VS,
	output reg       VGA_HS,
	output           VGA_DE,
	
	// optional aligned blank
	output reg       HBlank_out,
	output reg       VBlank_out,
	
	// optional aligned de
	output reg       DE_out
);

wire hs, vs;
wire [15:0] px = R * 16'd054 + G * 16'd183 + B * 16'd018;
s_fix sync_v(clk_vid, HSync, hs);
s_fix sync_h(clk_vid, VSync, vs);

wire hbl = hs | HBlank;
wire vbl = vs | VBlank;

assign VGA_DE = ~(HBlank_out | VBlank_out);

always @(posedge clk_vid) begin
	if(ce_pix) begin
		HBlank_out <= hbl;

		VGA_HS <= hs;
		if(~VGA_HS & hs) VGA_VS <= vs;

		{VGA_R, VGA_G, VGA_B} <= 0;
		case(mix)			
			0: {VGA_R, VGA_G, VGA_B} <= {R, G, B};                        // color
			1: {       VGA_G       } <= {          px[15:8]            }; // green
			2: {VGA_R, VGA_G       } <= {px[15:8], px[15:8] - px[15:10]}; // amber			
			3: {VGA_R, VGA_G, VGA_B} <= {px[15:8], px[15:8], px[15:8]  }; // gray
		endcase
				
		DE_out <= DE_in;

		if(HBlank_out & ~hbl) VBlank_out <= vbl;
	end
end

endmodule

module s_fix
(
	input clk,
	
	input sync_in,
	output sync_out
);

assign sync_out = sync_in ^ pol;

reg pol;
always @(posedge clk) begin
	integer pos = 0, neg = 0, cnt = 0;
	reg s1,s2;

	s1 <= sync_in;
	s2 <= s1;

	if(~s2 & s1) neg <= cnt;
	if(s2 & ~s1) pos <= cnt;

	cnt <= cnt + 1;
	if(s2 != s1) cnt <= 0;

	pol <= pos > neg;
end

endmodule
