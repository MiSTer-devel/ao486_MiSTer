//
// scandoubler.v
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// Copyright (c) 2017-2019 Sorgelig
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 

// TODO: Delay vsync one line

module scandoubler #(parameter LENGTH, parameter HALF_DEPTH)
(
	// system interface
	input             clk_sys,
	input             ce_pix,
	output            ce_pix_out,

	input             hq2x,

	// shifter video interface
	input             hs_in,
	input             vs_in,
	input             hb_in,
	input             vb_in,

	input  [DWIDTH:0] r_in,
	input  [DWIDTH:0] g_in,
	input  [DWIDTH:0] b_in,
	input             mono,

	// output interface
	output reg        hs_out,
	output            vs_out,
	output            hb_out,
	output            vb_out,
	output [DWIDTH:0] r_out,
	output [DWIDTH:0] g_out,
	output [DWIDTH:0] b_out
);


localparam DWIDTH = HALF_DEPTH ? 3 : 7;

assign vs_out = vso[3];
assign ce_pix_out = hq2x ? ce_x4 : ce_x2;

//Compensate picture shift after HQ2x
assign vb_out = vbo[3];
assign hb_out = hbo[6];

reg  [7:0] pix_len = 0;
reg  [7:0] pix_cnt = 0;
wire [7:0] pl = pix_len + 1'b1;
wire [7:0] pc = pix_cnt + 1'b1;

reg ce_x4, ce_x2, ce_x1;
always @(negedge clk_sys) begin
	reg old_ce, valid, hs;
	reg [2:0] ce_cnt;

	reg [7:0] pixsz, pixsz2, pixsz4 = 0;

	if(~&pix_len) pix_len <= pl;
	if(~&pix_cnt) pix_cnt <= pc;

	ce_x4 <= 0;
	ce_x2 <= 0;
	ce_x1 <= 0;

	// use such odd comparison to place ce_x4 evenly if master clock isn't multiple of 4.
	if((pc == pixsz4) || (pc == pixsz2) || (pc == (pixsz2+pixsz4))) ce_x4 <= 1;
	if( pc == pixsz2) ce_x2 <= 1;

	old_ce <= ce_pix;
	if(~old_ce & ce_pix) begin
		if(valid & ~hb_in & ~vb_in) begin
			pixsz  <= pl;
			pixsz2 <= {1'b0,  pl[7:1]};
			pixsz4 <= {2'b00, pl[7:2]};
		end
		pix_len <= 0;
		valid <= 1;
	end

	if(hb_in | vb_in) valid <= 0;

	hs <= hs_out;
	if((~hs & hs_out) || (pc >= pixsz)) begin
		ce_x2 <= 1;
		ce_x4 <= 1;
		ce_x1 <= 1;
		pix_cnt <= 0;
	end
end

Hq2x #(.LENGTH(LENGTH), .HALF_DEPTH(HALF_DEPTH)) Hq2x
(
	.clk(clk_sys),
	.ce_x4(ce_x4),
	.inputpixel({b_d,g_d,r_d}),
	.mono(mono),
	.disable_hq2x(~hq2x),
	.reset_frame(vb_in),
	.reset_line(req_line_reset),
	.read_y(sd_line),
	.hblank(hbo[0]&hbo[8]),
	.outpixel({b_out,g_out,r_out})
);

reg [DWIDTH:0] r_d;
reg [DWIDTH:0] g_d;
reg [DWIDTH:0] b_d;

reg [1:0] sd_line;
reg [3:0] vbo;
reg [3:0] vso;
reg [8:0] hbo;

reg req_line_reset;
always @(posedge clk_sys) begin

	reg [31:0] hcnt;
	reg [30:0] sd_hcnt;
	reg [30:0] hs_start, hs_end;
	reg [30:0] hde_start, hde_end;

	reg hs, hb;

	if(ce_x4) begin
		hbo[8:1] <= hbo[7:0];
	end

	// output counter synchronous to input and at twice the rate
	sd_hcnt <= sd_hcnt + 1'd1;
	if(sd_hcnt == hde_start) begin
		sd_hcnt <= 0;
		vbo[3:1] <= vbo[2:0];
	end

	if(sd_hcnt == hs_end) begin
		sd_line <= sd_line + 1'd1;
		if(&vbo[3:2]) sd_line <= 1;
		vso[3:1] <= vso[2:0];
	end

	if(sd_hcnt == hde_start)hbo[0] <= 0;
	if(sd_hcnt == hde_end)  hbo[0] <= 1;

	// replicate horizontal sync at twice the speed
	if(sd_hcnt == hs_end)   hs_out <= 0;
	if(sd_hcnt == hs_start) hs_out <= 1;

	hs <= hs_in;
	hb <= hb_in;

	if(ce_x1) begin
		req_line_reset <= hb_in;
		r_d <= r_in;
		g_d <= g_in;
		b_d <= b_in;
	end

	hcnt <= hcnt + 1'd1;
	if(hb && !hb_in) begin
		hde_start <= hcnt[31:1];
		hbo[0] <= 0;
		hcnt <= 0;
		sd_hcnt <= 0;
		vbo <= {vbo[2:0],vb_in};
	end

	if(!hb && hb_in) hde_end <= hcnt[31:1];

	// falling edge of hsync indicates start of line
	if(hs && !hs_in) begin
		hs_end <= hcnt[31:1];
		vso[0] <= vs_in;
	end

	// save position of rising edge
	if(!hs && hs_in) hs_start <= hcnt[31:1];
end

endmodule
