//
//
// Copyright (c) 2012-2013 Ludvig Strigeus
// Copyright (c) 2017 Sorgelig
//
// This program is GPL Licensed. See COPYING for the full license.
//
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on

`define BITS_TO_FIT(N) ( \
     N <=    2 ? 0 : \
     N <=    4 ? 1 : \
     N <=    8 ? 2 : \
     N <=   16 ? 3 : \
     N <=   32 ? 4 : \
     N <=   64 ? 5 : \
     N <=  128 ? 6 : \
     N <=  256 ? 7 : \
     N <=  512 ? 8 : \
     N <= 1024 ? 9 : \
     N <= 2048 ?10 : 11 )

module Hq2x #(parameter LENGTH, parameter HALF_DEPTH)
(
	input               clk,
	input               ce_x4,
	input    [DWIDTH:0] inputpixel,
	input               mono,
	input               disable_hq2x,
	input               reset_frame,
	input               reset_line,
	input         [1:0] read_y,
	input  [AWIDTH+1:0] read_x,
	output   [DWIDTH:0] outpixel
);


localparam AWIDTH = `BITS_TO_FIT(LENGTH);
localparam DWIDTH = HALF_DEPTH ? 11 : 23;

wire [5:0] hqTable[256] = '{
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 47, 35, 23, 15, 55, 39,
	19, 19, 26, 58, 19, 19, 26, 58, 23, 15, 35, 35, 23, 15, 7,  35,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 55, 39, 23, 15, 51, 43,
	19, 19, 26, 58, 19, 19, 26, 58, 23, 15, 51, 35, 23, 15, 7,  43,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 61, 35, 35, 23, 61, 51, 35,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 51, 35, 23, 15, 51, 35,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 61, 7,  35, 23, 61, 7,  43,
	19, 19, 26, 11, 19, 19, 26, 58, 23, 15, 51, 35, 23, 61, 7,  43,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 47, 35, 23, 15, 55, 39,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 51, 35, 23, 15, 51, 35,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 55, 39, 23, 15, 51, 43,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 51, 39, 23, 15, 7,  43,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 51, 35, 23, 15, 51, 39,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 51, 35, 23, 15, 7,  35,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 51, 35, 23, 15, 7,  43,
	19, 19, 26, 11, 19, 19, 26, 11, 23, 15, 7,  35, 23, 15, 7,  43
};

reg [23:0] Prev0, Prev1, Prev2, Curr0, Curr1, Next0, Next1, Next2;
reg [23:0] A, B, D, F, G, H;
reg  [7:0] pattern, nextpatt;
reg  [1:0] i;
reg  [7:0] y;

wire curbuf = y[0];
reg  prevbuf = 0;
wire iobuf = !curbuf;

wire diff0, diff1;
DiffCheck diffcheck0(Curr1, (i == 0) ? Prev0 : (i == 1) ? Curr0 : (i == 2) ? Prev2 : Next1, diff0);
DiffCheck diffcheck1(Curr1, (i == 0) ? Prev1 : (i == 1) ? Next0 : (i == 2) ? Curr2 : Next2, diff1);

wire [7:0] new_pattern = {diff1, diff0, pattern[7:2]};

wire [23:0] X = (i == 0) ? A : (i == 1) ? Prev1 : (i == 2) ? Next1 : G;
wire [23:0] blend_result;
Blend blender(hqTable[nextpatt], disable_hq2x, Curr0, X, B, D, F, H, blend_result);

reg             Curr2_addr1;
reg  [AWIDTH:0] Curr2_addr2;
wire     [23:0] Curr2 = HALF_DEPTH ? h2rgb(Curr2tmp) : Curr2tmp;
wire [DWIDTH:0] Curr2tmp;

reg  [AWIDTH:0] wrin_addr2;
reg  [DWIDTH:0] wrpix;
reg             wrin_en;

function [23:0] h2rgb;
	input [11:0] v;
begin
	h2rgb = mono ? {v[7:0], v[7:0], v[7:0]} : {v[11:8],v[11:8],v[7:4],v[7:4],v[3:0],v[3:0]};
end
endfunction

function [11:0] rgb2h;
	input [23:0] v;
begin
	rgb2h = mono ? {4'b0000, v[23:20], v[19:16]} : {v[23:20], v[15:12], v[7:4]};
end
endfunction

hq2x_in #(.LENGTH(LENGTH), .DWIDTH(DWIDTH)) hq2x_in
(
	.clk(clk),

	.rdaddr(Curr2_addr2),
	.rdbuf(Curr2_addr1),
	.q(Curr2tmp),

	.wraddr(wrin_addr2),
	.wrbuf(iobuf),
	.data(wrpix),
	.wren(wrin_en)
);

reg         [1:0] wrout_addr1;
reg  [AWIDTH+1:0] wrout_addr2;
reg               wrout_en;
reg    [DWIDTH:0] wrdata;

hq2x_out #(.LENGTH(LENGTH), .DWIDTH(DWIDTH)) hq2x_out
(
	.clk(clk),

	.rdaddr(read_x),
	.rdbuf(read_y),
	.q(outpixel),

	.wraddr(wrout_addr2),
	.wrbuf(wrout_addr1),
	.data(wrdata),
	.wren(wrout_en)
);

always @(posedge clk) begin
	reg [AWIDTH:0] offs;
	reg old_reset_line;
	reg old_reset_frame;

	wrout_en <= 0;
	wrin_en  <= 0;

	if(ce_x4) begin

		pattern <= new_pattern;

		if(~&offs) begin
			if (i == 0) begin
				Curr2_addr1 <= prevbuf;
				Curr2_addr2 <= offs;
			end
			if (i == 1) begin
				Prev2 <= Curr2;
				Curr2_addr1 <= curbuf;
				Curr2_addr2 <= offs;
			end
			if (i == 2) begin
				Next2 <= HALF_DEPTH ? h2rgb(inputpixel) : inputpixel;
				wrpix <= inputpixel;
				wrin_addr2 <= offs;
				wrin_en <= 1;
			end
			if (i == 3) begin
				offs <= offs + 1'd1;
			end

			if(HALF_DEPTH) wrdata <= rgb2h(blend_result);
			else           wrdata <= blend_result;

			wrout_addr1 <= {curbuf, i[1]};
			wrout_addr2 <= {offs, i[1]^i[0]};
			wrout_en    <= 1;
		end

		if(i==3) begin
			nextpatt <= {new_pattern[7:6], new_pattern[3], new_pattern[5], new_pattern[2], new_pattern[4], new_pattern[1:0]};
			{A, G} <= {Prev0, Next0};
			{B, F, H, D} <= {Prev1, Curr2, Next1, Curr0};
			{Prev0, Prev1} <= {Prev1, Prev2};
			{Curr0, Curr1} <= {Curr1, Curr2};
			{Next0, Next1} <= {Next1, Next2};
		end else begin
			nextpatt <= {nextpatt[5], nextpatt[3], nextpatt[0], nextpatt[6], nextpatt[1], nextpatt[7], nextpatt[4], nextpatt[2]};
			{B, F, H, D} <= {F, H, D, B};
		end

		i <= i + 1'b1;
		if(old_reset_line && ~reset_line) begin
			old_reset_frame <= reset_frame;
			offs <= 0;
			i <= 0;
			y <= y + 1'd1;
			prevbuf <= curbuf;
			if(old_reset_frame & ~reset_frame) begin
				y <= 0;
				prevbuf <= 0;
			end
		end

		old_reset_line  <= reset_line;
	end
end

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////

module hq2x_in #(parameter LENGTH, parameter DWIDTH)
(
	input            clk,

	input [AWIDTH:0] rdaddr,
	input            rdbuf,
	output[DWIDTH:0] q,

	input [AWIDTH:0] wraddr,
	input            wrbuf,
	input [DWIDTH:0] data,
	input            wren
);

	localparam AWIDTH = `BITS_TO_FIT(LENGTH);
	wire [DWIDTH:0] out[2];
	assign q = out[rdbuf];

	hq2x_buf #(.NUMWORDS(LENGTH), .AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) buf0(clk,data,rdaddr,wraddr,wren && (wrbuf == 0),out[0]);
	hq2x_buf #(.NUMWORDS(LENGTH), .AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) buf1(clk,data,rdaddr,wraddr,wren && (wrbuf == 1),out[1]);
endmodule


module hq2x_out #(parameter LENGTH, parameter DWIDTH)
(
	input            clk,

	input [AWIDTH:0] rdaddr,
	input      [1:0] rdbuf,
	output[DWIDTH:0] q,

	input [AWIDTH:0] wraddr,
	input      [1:0] wrbuf,
	input [DWIDTH:0] data,
	input            wren
);

	localparam AWIDTH = `BITS_TO_FIT(LENGTH*2);
	wire  [DWIDTH:0] out[4];
	assign q = out[rdbuf];

	hq2x_buf #(.NUMWORDS(LENGTH*2), .AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) buf0(clk,data,rdaddr,wraddr,wren && (wrbuf == 0),out[0]);
	hq2x_buf #(.NUMWORDS(LENGTH*2), .AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) buf1(clk,data,rdaddr,wraddr,wren && (wrbuf == 1),out[1]);
	hq2x_buf #(.NUMWORDS(LENGTH*2), .AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) buf2(clk,data,rdaddr,wraddr,wren && (wrbuf == 2),out[2]);
	hq2x_buf #(.NUMWORDS(LENGTH*2), .AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) buf3(clk,data,rdaddr,wraddr,wren && (wrbuf == 3),out[3]);
endmodule


module hq2x_buf #(parameter NUMWORDS, parameter AWIDTH, parameter DWIDTH)
(
	input                   clock,
	input        [DWIDTH:0] data,
	input        [AWIDTH:0] rdaddress,
	input        [AWIDTH:0] wraddress,
	input                   wren,
	output logic [DWIDTH:0] q
);

logic [DWIDTH:0] ram[0:NUMWORDS-1];

always_ff@(posedge clock) begin
	if(wren) ram[wraddress] <= data;
	q <= ram[rdaddress];
end

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////

module DiffCheck
(
	input [23:0] rgb1,
	input [23:0] rgb2,
	output result
);

	wire [7:0] r = rgb1[7:1]   - rgb2[7:1];
	wire [7:0] g = rgb1[15:9]  - rgb2[15:9];
	wire [7:0] b = rgb1[23:17] - rgb2[23:17];
	wire [8:0] t = $signed(r) + $signed(b);
	wire [8:0] gx = {g[7], g};
	wire [9:0] y = $signed(t) + $signed(gx);
	wire [8:0] u = $signed(r) - $signed(b);
	wire [9:0] v = $signed({g, 1'b0}) - $signed(t);

	// if y is inside (-96..96)
	wire y_inside = (y < 10'h60 || y >= 10'h3a0);

	// if u is inside (-16, 16)
	wire u_inside = (u < 9'h10 || u >= 9'h1f0);

	// if v is inside (-24, 24)
	wire v_inside = (v < 10'h18 || v >= 10'h3e8);
	assign result = !(y_inside && u_inside && v_inside);
endmodule

module InnerBlend
(
	input  [8:0] Op,
	input  [7:0] A,
	input  [7:0] B,
	input  [7:0] C,
	output [7:0] O
);

	function  [10:0] mul8x3;
		input   [7:0] op1;
		input   [2:0] op2;
	begin
		mul8x3 = 11'd0;
		if(op2[0]) mul8x3 = mul8x3 + op1;
		if(op2[1]) mul8x3 = mul8x3 + {op1, 1'b0};
		if(op2[2]) mul8x3 = mul8x3 + {op1, 2'b00};
	end
	endfunction

	wire OpOnes = Op[4];
	wire [10:0] Amul = mul8x3(A, Op[7:5]);
	wire [10:0] Bmul = mul8x3(B, {Op[3:2], 1'b0});
	wire [10:0] Cmul = mul8x3(C, {Op[1:0], 1'b0});
	wire [10:0] At =  Amul;
	wire [10:0] Bt = (OpOnes == 0) ? Bmul : {3'b0, B};
	wire [10:0] Ct = (OpOnes == 0) ? Cmul : {3'b0, C};
	wire [11:0] Res = {At, 1'b0} + Bt + Ct;
	assign O = Op[8] ? A : Res[11:4];
endmodule

module Blend
(
	input   [5:0] rule,
	input         disable_hq2x,
	input  [23:0] E,
	input  [23:0] A,
	input  [23:0] B,
	input  [23:0] D,
	input  [23:0] F,
	input  [23:0] H,
	output [23:0] Result
);

	reg [1:0] input_ctrl;
	reg [8:0] op;
	localparam BLEND0 = 9'b1_xxx_x_xx_xx; // 0: A
	localparam BLEND1 = 9'b0_110_0_10_00; // 1: (A * 12 + B * 4) >> 4
	localparam BLEND2 = 9'b0_100_0_10_10; // 2: (A * 8 + B * 4 + C * 4) >> 4
	localparam BLEND3 = 9'b0_101_0_10_01; // 3: (A * 10 + B * 4 + C * 2) >> 4
	localparam BLEND4 = 9'b0_110_0_01_01; // 4: (A * 12 + B * 2 + C * 2) >> 4
	localparam BLEND5 = 9'b0_010_0_11_11; // 5: (A * 4 + (B + C) * 6) >> 4
	localparam BLEND6 = 9'b0_111_1_xx_xx; // 6: (A * 14 + B + C) >> 4
	localparam AB = 2'b00;
	localparam AD = 2'b01;
	localparam DB = 2'b10;
	localparam BD = 2'b11;
	wire is_diff;
	DiffCheck diff_checker(rule[1] ? B : H, rule[0] ? D : F, is_diff);

	always @* begin
		case({!is_diff, rule[5:2]})
			1,17:  {op, input_ctrl} = {BLEND1, AB};
			2,18:  {op, input_ctrl} = {BLEND1, DB};
			3,19:  {op, input_ctrl} = {BLEND1, BD};
			4,20:  {op, input_ctrl} = {BLEND2, DB};
			5,21:  {op, input_ctrl} = {BLEND2, AB};
			6,22:  {op, input_ctrl} = {BLEND2, AD};

			 8: {op, input_ctrl} = {BLEND0, 2'bxx};
			 9: {op, input_ctrl} = {BLEND0, 2'bxx};
			10: {op, input_ctrl} = {BLEND0, 2'bxx};
			11: {op, input_ctrl} = {BLEND1, AB};
			12: {op, input_ctrl} = {BLEND1, AB};
			13: {op, input_ctrl} = {BLEND1, AB};
			14: {op, input_ctrl} = {BLEND1, DB};
			15: {op, input_ctrl} = {BLEND1, BD};

			24: {op, input_ctrl} = {BLEND2, DB};
			25: {op, input_ctrl} = {BLEND5, DB};
			26: {op, input_ctrl} = {BLEND6, DB};
			27: {op, input_ctrl} = {BLEND2, DB};
			28: {op, input_ctrl} = {BLEND4, DB};
			29: {op, input_ctrl} = {BLEND5, DB};
			30: {op, input_ctrl} = {BLEND3, BD};
			31: {op, input_ctrl} = {BLEND3, DB};
			default: {op, input_ctrl} = {11{1'bx}};
		endcase

		// Setting op[8] effectively disables HQ2X because blend will always return E.
		if (disable_hq2x) op[8] = 1;
	end

	// Generate inputs to the inner blender. Valid combinations.
	// 00: E A B
	// 01: E A D 
	// 10: E D B
	// 11: E B D
	wire [23:0] Input1 = E;
	wire [23:0] Input2 = !input_ctrl[1] ? A :
                        !input_ctrl[0] ? D : B;

	wire [23:0] Input3 = !input_ctrl[0] ? B : D;
	InnerBlend inner_blend1(op, Input1[7:0],   Input2[7:0],   Input3[7:0],   Result[7:0]);
	InnerBlend inner_blend2(op, Input1[15:8],  Input2[15:8],  Input3[15:8],  Result[15:8]);
	InnerBlend inner_blend3(op, Input1[23:16], Input2[23:16], Input3[23:16], Result[23:16]);
endmodule
