//============================================================================
// 	YC - Luma / Chroma Generation 
//  Copyright (C) 2022 Mike Simone
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================
/* 
Colorspace
Y	0.299R' + 0.587G' + 0.114B'
U	0.492(B' - Y) = 504 (X 1024)
V	0.877(R' - Y) = 898 (X 1024)
*/
//////////////////////////////////////////////////////////

module yc_out
(
	input         clk,
	input  [39:0] PHASE_INC,
	input         PAL_EN,
	input         CVBS,
	input  [16:0] COLORBURST_RANGE,

	input	        hsync,
	input	        vsync,
	input	        csync,
	input	        de,

	input	 [23:0] din,
	output [23:0] dout,

	output reg	  hsync_o,
	output reg	  vsync_o,
	output reg	  csync_o,
	output reg	  de_o
);

wire [7:0] red = din[23:16];
wire [7:0] green = din[15:8];
wire [7:0] blue = din[7:0];

logic [9:0] red_1, blue_1, green_1, red_2, blue_2, green_2;

logic signed [20:0] yr = 0, yb = 0, yg = 0;

typedef struct {
	logic signed [20:0] y;
	logic signed [20:0] c;
	logic signed [20:0] u;
	logic signed [20:0] v;
	logic        hsync;
	logic        vsync;
	logic        csync;
	logic        de;
} phase_t;

localparam MAX_PHASES = 7'd8;

phase_t phase[MAX_PHASES];
reg unsigned [7:0] Y, C, c, U, V;


reg [10:0]  cburst_phase;     // colorburst counter
reg unsigned [7:0] vref = 'd128; // Voltage reference point (Used for Chroma)
logic [7:0]  chroma_LUT_COS; // Chroma cos LUT reference
logic [7:0]  chroma_LUT_SIN; // Chroma sin LUT reference
logic [7:0]  chroma_LUT_BURST; // Chroma colorburst LUT reference
logic [7:0]  chroma_LUT = 8'd0;

/*
THe following LUT table was calculated by Sin(2*pi*t/2^8) where t: 0 - 255
*/

/*************************************
		8 bit Sine look up Table
**************************************/
wire signed [10:0] chroma_SIN_LUT[256] = '{
	11'h000, 11'h006, 11'h00C, 11'h012, 11'h018, 11'h01F, 11'h025, 11'h02B, 11'h031, 11'h037, 11'h03D, 11'h044, 11'h04A, 11'h04F, 
	11'h055, 11'h05B, 11'h061, 11'h067, 11'h06D, 11'h072, 11'h078, 11'h07D, 11'h083, 11'h088, 11'h08D, 11'h092, 11'h097, 11'h09C, 
	11'h0A1, 11'h0A6, 11'h0AB, 11'h0AF, 11'h0B4, 11'h0B8, 11'h0BC, 11'h0C1, 11'h0C5, 11'h0C9, 11'h0CC, 11'h0D0, 11'h0D4, 11'h0D7, 
	11'h0DA, 11'h0DD, 11'h0E0, 11'h0E3, 11'h0E6, 11'h0E9, 11'h0EB, 11'h0ED, 11'h0F0, 11'h0F2, 11'h0F4, 11'h0F5, 11'h0F7, 11'h0F8, 
	11'h0FA, 11'h0FB, 11'h0FC, 11'h0FD, 11'h0FD, 11'h0FE, 11'h0FE, 11'h0FE, 11'h0FF, 11'h0FE, 11'h0FE, 11'h0FE, 11'h0FD, 11'h0FD, 
	11'h0FC, 11'h0FB, 11'h0FA, 11'h0F8, 11'h0F7, 11'h0F5, 11'h0F4, 11'h0F2, 11'h0F0, 11'h0ED, 11'h0EB, 11'h0E9, 11'h0E6, 11'h0E3, 
	11'h0E0, 11'h0DD, 11'h0DA, 11'h0D7, 11'h0D4, 11'h0D0, 11'h0CC, 11'h0C9, 11'h0C5, 11'h0C1, 11'h0BC, 11'h0B8, 11'h0B4, 11'h0AF, 
	11'h0AB, 11'h0A6, 11'h0A1, 11'h09C, 11'h097, 11'h092, 11'h08D, 11'h088, 11'h083, 11'h07D, 11'h078, 11'h072, 11'h06D, 11'h067, 
	11'h061, 11'h05B, 11'h055, 11'h04F, 11'h04A, 11'h044, 11'h03D, 11'h037, 11'h031, 11'h02B, 11'h025, 11'h01F, 11'h018, 11'h012, 
	11'h00C, 11'h006, 11'h000, 11'h7F9, 11'h7F3, 11'h7ED, 11'h7E7, 11'h7E0, 11'h7DA, 11'h7D4, 11'h7CE, 11'h7C8, 11'h7C2, 11'h7BB, 
	11'h7B5, 11'h7B0, 11'h7AA, 11'h7A4, 11'h79E, 11'h798, 11'h792, 11'h78D, 11'h787, 11'h782, 11'h77C, 11'h777, 11'h772, 11'h76D, 
	11'h768, 11'h763, 11'h75E, 11'h759, 11'h754, 11'h750, 11'h74B, 11'h747, 11'h743, 11'h73E, 11'h73A, 11'h736, 11'h733, 11'h72F, 
	11'h72B, 11'h728, 11'h725, 11'h722, 11'h71F, 11'h71C, 11'h719, 11'h716, 11'h714, 11'h712, 11'h70F, 11'h70D, 11'h70B, 11'h70A, 
	11'h708, 11'h707, 11'h705, 11'h704, 11'h703, 11'h702, 11'h702, 11'h701, 11'h701, 11'h701, 11'h701, 11'h701, 11'h701, 11'h701, 
	11'h702, 11'h702, 11'h703, 11'h704, 11'h705, 11'h707, 11'h708, 11'h70A, 11'h70B, 11'h70D, 11'h70F, 11'h712, 11'h714, 11'h716, 
	11'h719, 11'h71C, 11'h71F, 11'h722, 11'h725, 11'h728, 11'h72B, 11'h72F, 11'h733, 11'h736, 11'h73A, 11'h73E, 11'h743, 11'h747, 
	11'h74B, 11'h750, 11'h754, 11'h759, 11'h75E, 11'h763, 11'h768, 11'h76D, 11'h772, 11'h777, 11'h77C, 11'h782, 11'h787, 11'h78D, 
	11'h792, 11'h798, 11'h79E, 11'h7A4, 11'h7AA, 11'h7B0, 11'h7B5, 11'h7BB, 11'h7C2, 11'h7C8, 11'h7CE, 11'h7D4, 11'h7DA, 11'h7E0, 
	11'h7E7, 11'h7ED, 11'h7F3, 11'h7F9
};

logic [39:0] phase_accum;
logic PAL_FLIP = 1'd0;
logic PAL_line_count = 1'd0;

/**************************************
	Generate Luma and Chroma Signals
***************************************/

always_ff @(posedge clk) begin
	for (logic [3:0] x = 0; x < (MAX_PHASES - 1'd1); x = x + 1'd1) begin
		phase[x + 1] <= phase[x];
	end

	// delay red / blue signals to align luma with U/V calculation (Fixes colorbleeding)
	red_1 <= red;
	blue_1 <= blue;
	red_2 <= red_1;
	blue_2 <= blue_1;

	// Calculate Luma signal
	yr <= {red, 8'd0} + {red, 5'd0}+ {red, 4'd0} + {red, 1'd0};
	yg <= {green, 9'd0} + {green, 6'd0} + {green, 4'd0} + {green, 3'd0} + green;
	yb <= {blue, 6'd0} + {blue, 5'd0} + {blue, 4'd0} + {blue, 2'd0} + blue;
	phase[0].y <= yr + yg + yb;

	// Generate the LUT values using the phase accumulator reference.
	phase_accum <= phase_accum + PHASE_INC;
	chroma_LUT <= phase_accum[39:32];

	// Adjust SINE carrier reference for PAL (Also adjust for PAL Switch)
	if (PAL_EN) begin
		if (PAL_FLIP)
			chroma_LUT_BURST <= chroma_LUT + 8'd160;
		else
			chroma_LUT_BURST <= chroma_LUT + 8'd96;
	end else  // Adjust SINE carrier reference for NTSC
		chroma_LUT_BURST <= chroma_LUT + 8'd128;

	// Prepare LUT values for sin / cos (+90 degress)
	chroma_LUT_SIN <= chroma_LUT;
	chroma_LUT_COS <= chroma_LUT + 8'd64;

	// Calculate for U, V - Bit Shift Multiple by u = by * 1024 x 0.492 = 504, v = ry * 1024 x 0.877 = 898
	phase[0].u <= $signed({2'b0 ,(blue_2)}) - $signed({2'b0 ,phase[0].y[17:10]});
	phase[0].v <= $signed({2'b0 , (red_2)}) - $signed({2'b0 ,phase[0].y[17:10]});
	phase[1].u <= 21'($signed({phase[0].u, 8'd0}) + $signed({phase[0].u, 7'd0}) + $signed({phase[0].u, 6'd0}) + $signed({phase[0].u, 5'd0}) + $signed({phase[0].u, 4'd0}) + $signed({phase[0].u, 3'd0}));
	phase[1].v <= 21'($signed({phase[0].v, 9'd0}) + $signed({phase[0].v, 8'd0}) + $signed({phase[0].v, 7'd0}) + $signed({phase[0].v, 1'd0}));

	phase[0].c <= vref;
	phase[1].c <= phase[0].c;
	phase[2].c <= phase[1].c;
	phase[3].c <= phase[2].c;

	if (hsync) begin // Reset colorburst counter, as well as the calculated cos / sin values.
		cburst_phase <= 'd0;
		phase[2].u <= 21'b0;
		phase[2].v <= 21'b0;
		phase[4].c <= phase[3].c;

		if (PAL_line_count) begin
			PAL_FLIP <= ~PAL_FLIP;
			PAL_line_count <= ~PAL_line_count;
		end
	end
	else begin // Generate Colorburst for 9 cycles
		if (cburst_phase >= COLORBURST_RANGE[16:10] && cburst_phase <= COLORBURST_RANGE[9:0]) begin // Start the color burst signal at 40 samples or 0.9 us
			// COLORBURST SIGNAL GENERATION (9 CYCLES ONLY or between count 40 - 240)
			phase[2].u <= $signed({chroma_SIN_LUT[chroma_LUT_BURST],5'd0});
			phase[2].v <= 21'b0;

			// Division to scale down the results to fit 8 bit.
			if (PAL_EN)
				phase[3].u <= $signed(phase[2].u[20:8]) + $signed(phase[2].u[20:10]) + $signed(phase[2].u[20:14]);
			else
				phase[3].u <= $signed(phase[2].u[20:8]) + $signed(phase[2].u[20:11]) + $signed(phase[2].u[20:12]) + $signed(phase[2].u[20:13]);

			phase[3].v <= phase[2].v;
		end	else begin  // MODULATE U, V for chroma
			/*
			U,V are both multiplied by 1024 earlier to scale for the decimals in the YUV colorspace conversion.
			U and V are both divided by 2^10 which introduce chroma subsampling of 4:1:1 (25% or from 8 bit to 6 bit)
			*/
			phase[2].u <= $signed((phase[1].u)>>>10) * $signed(chroma_SIN_LUT[chroma_LUT_SIN]);
			phase[2].v <= $signed((phase[1].v)>>>10) * $signed(chroma_SIN_LUT[chroma_LUT_COS]);

			// Divide U*sin(wt) and V*cos(wt) to fit results to 8 bit
			phase[3].u <= $signed(phase[2].u[20:9]) + $signed(phase[2].u[20:10]) + $signed(phase[2].u[20:14]);
			phase[3].v <= $signed(phase[2].v[20:9]) + $signed(phase[2].v[20:10]) + $signed(phase[2].u[20:14]);
		end

		// Stop the colorburst timer as its only needed for the initial pulse
		if (cburst_phase <= COLORBURST_RANGE[9:0])
			cburst_phase <= cburst_phase + 9'd1;

			// Calculate for chroma (Note: "PAL SWITCH" routine flips V * COS(Wt) every other line)
		if (PAL_EN) begin
			if (PAL_FLIP)
				phase[4].c <= vref + phase[3].u - phase[3].v;
			else 
				phase[4].c <= vref + phase[3].u + phase[3].v;
				PAL_line_count <= 1'd1;
		end else
				phase[4].c <= vref + phase[3].u + phase[3].v;
	end

	// Adjust sync timing correctly
	phase[1].hsync <= hsync; phase[1].vsync <= vsync; phase[1].csync <= csync; phase[1].de <= de;
	phase[2].hsync <= phase[1].hsync; phase[2].vsync <= phase[1].vsync; phase[2].csync <= phase[1].csync; phase[2].de <= phase[1].de;
	phase[3].hsync <= phase[2].hsync; phase[3].vsync <= phase[2].vsync; phase[3].csync <= phase[2].csync; phase[3].de <= phase[2].de;
	phase[4].hsync <= phase[3].hsync; phase[4].vsync <= phase[3].vsync; phase[4].csync <= phase[3].csync; phase[4].de <= phase[3].de;
	hsync_o <= phase[4].hsync;        vsync_o <= phase[4].vsync;        csync_o <= phase[4].csync;        de_o <= phase[4].de;

	phase[1].y <= phase[0].y; phase[2].y <= phase[1].y; phase[3].y <= phase[2].y; phase[4].y <= phase[3].y; phase[5].y <= phase[4].y;

	// Set Chroma / Luma output
	C <= CVBS ? 8'd0 : phase[4].c[7:0];
	Y <= CVBS ? ({1'b0, phase[5].y[17:11]} + {1'b0, phase[4].c[7:1]}) : phase[5].y[17:10];
end

assign dout = {C, Y, 8'd0};

endmodule

