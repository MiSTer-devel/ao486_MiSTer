//
//
// Video crop 
// Copyright (c) 2020 Grabulosaure, (c) 2021 Alexey Melnikov
// 
// Integer scaling
// Copyright (c) 2021 Alexey Melnikov
//
// This program is GPL Licensed. See COPYING for the full license.
//
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module video_freak
(
	input             CLK_VIDEO,
	input             CE_PIXEL,
	input             VGA_VS,
	input      [11:0] HDMI_WIDTH,
	input      [11:0] HDMI_HEIGHT,
	output            VGA_DE,
	output reg [12:0] VIDEO_ARX,
	output reg [12:0] VIDEO_ARY,

	input             VGA_DE_IN,
	input      [11:0] ARX,
	input      [11:0] ARY,
	input      [11:0] CROP_SIZE,
	input       [4:0] CROP_OFF, // -16...+15
	input       [2:0] SCALE     //0 - normal, 1 - V-integer, 2 - HV-Integer-, 3 - HV-Integer+, 4 - HV-Integer
);

reg         mul_start;
wire        mul_run;
reg  [11:0] mul_arg1, mul_arg2;
wire [23:0] mul_res;
sys_umul #(12,12) mul(CLK_VIDEO,mul_start,mul_run, mul_arg1,mul_arg2,mul_res);

reg        vde;
reg [11:0] arxo,aryo;
reg [11:0] vsize;
reg [11:0] hsize;

always @(posedge CLK_VIDEO) begin
	reg        old_de, old_vs,ovde;
	reg [11:0] vtot,vcpt,vcrop,voff;
	reg [11:0] hcpt;
	reg [11:0] vadj;
	reg [23:0] ARXG,ARYG;
	reg [11:0] arx,ary;
	reg  [1:0] vcalc;

	if (CE_PIXEL) begin
		old_de <= VGA_DE_IN;
		old_vs <= VGA_VS;
		if (VGA_VS & ~old_vs) begin
			vcpt  <= 0;
			vtot  <= vcpt;
			vcalc <= 1;
			vcrop <= (CROP_SIZE >= vcpt) ? 12'd0 : CROP_SIZE;
		end
		
		if (VGA_DE_IN) hcpt <= hcpt + 1'd1;
		if (~VGA_DE_IN & old_de) begin
			vcpt <= vcpt + 1'd1;
			if(!vcpt) hsize <= hcpt;
			hcpt <= 0;
		end
	end

	arx <= ARX;
	ary <= ARY;

	vsize <= vcrop ? vcrop : vtot;
	
	mul_start <= 0;

	if(!vcrop || !ary || !arx) begin
		arxo  <= arx;
		aryo  <= ary;
	end
	else if (vcalc) begin
		if(~mul_start & ~mul_run) begin
			vcalc <= vcalc + 1'd1;
			case(vcalc)
				1: begin
						mul_arg1  <= arx;
						mul_arg2  <= vtot;
						mul_start <= 1;
					end

				2: begin
						ARXG      <= mul_res;
						mul_arg1  <= ary;
						mul_arg2  <= vcrop;
						mul_start <= 1;
					end

				3: begin
						ARYG      <= mul_res;
					end
			endcase
		end
	end
	else if (ARXG[23] | ARYG[23]) begin
		arxo <= ARXG[23:12];
		aryo <= ARYG[23:12];
	end
	else begin
		ARXG <= ARXG << 1;
		ARYG <= ARYG << 1;
	end

	vadj <= (vtot-vcrop) + {{6{CROP_OFF[4]}},CROP_OFF,1'b0};
	voff <= vadj[11] ? 12'd0 : ((vadj[11:1] + vcrop) > vtot) ? vtot-vcrop : vadj[11:1];
	ovde <= ((vcpt >= voff) && (vcpt < (vcrop + voff))) || !vcrop;
	vde  <= ovde;
end

assign VGA_DE = vde & VGA_DE_IN;

video_scale_int scale
(
	.CLK_VIDEO(CLK_VIDEO),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.SCALE(SCALE),
	.hsize(hsize),
	.vsize(vsize),
	.arx_i(arxo),
	.ary_i(aryo),
	.arx_o(VIDEO_ARX),
	.ary_o(VIDEO_ARY)
);

endmodule


module video_scale_int
(
	input             CLK_VIDEO,

	input      [11:0] HDMI_WIDTH,
	input      [11:0] HDMI_HEIGHT,

	input       [2:0] SCALE,

	input      [11:0] hsize,
	input      [11:0] vsize,

	input      [11:0] arx_i,
	input      [11:0] ary_i,

	output reg [12:0] arx_o,
	output reg [12:0] ary_o
);

reg         div_start;
wire        div_run;
reg  [23:0] div_num;
reg  [11:0] div_den;
wire [23:0] div_res;
sys_udiv #(24,12) div(CLK_VIDEO,div_start,div_run, div_num,div_den,div_res);

reg         mul_start;
wire        mul_run;
reg  [11:0] mul_arg1, mul_arg2;
wire [23:0] mul_res;
sys_umul #(12,12) mul(CLK_VIDEO,mul_start,mul_run, mul_arg1,mul_arg2,mul_res);

always @(posedge CLK_VIDEO) begin
	reg [11:0] oheight,htarget,wres,hinteger,wideres;
	reg [12:0] arxf,aryf;
	reg  [3:0] cnt;
	reg        narrow;

	div_start <= 0;
	mul_start <= 0;

	if (!SCALE || (!ary_i && arx_i)) begin
		arxf <= arx_i;
		aryf <= ary_i;
	end
	else if(~div_start & ~div_run & ~mul_start & ~mul_run) begin
		cnt <= cnt + 1'd1;
		case(cnt)
			// example ideal and non-ideal cases:
			// [1] 720x400 4:3 VGA 80x25 text-mode (non-square pixels)
			// [2] 640x480 4:3 VGA graphics mode (square pixels)
			// [3] 512x512 4:3 X68000 graphics mode (non-square pixels)
			0: begin
					div_num   <= HDMI_HEIGHT;
					div_den   <= vsize;
					div_start <= 1;
				end
				// [1] 1080 / 400 -> 2
				// [2] 1080 / 480 -> 2
				// [3] 1080 / 512 -> 2

			1: if(!div_res[11:0]) begin
					// screen resolution is lower than video resolution.
					// Integer scaling is impossible.
					arxf      <= arx_i;
					aryf      <= ary_i;
					cnt       <= 0;
				end
				else begin
					mul_arg1  <= vsize;
					mul_arg2  <= div_res[11:0];
					mul_start <= 1;
				end
				// [1] 1080 / 400 * 400 -> 800
				// [2] 1080 / 480 * 480 -> 960
				// [3] 1080 / 512 * 512 -> 1024

			2: begin
					oheight   <= mul_res[11:0];
					if(!ary_i) begin
						cnt    <= 8;
					end
				end
				
			3: begin
					mul_arg1  <= mul_res[11:0];
					mul_arg2  <= arx_i;
					mul_start <= 1;
				end
				// [1] 1080 / 400 * 400 * 4 -> 3200
				// [2] 1080 / 480 * 480 * 4 -> 3840
				// [3] 1080 / 512 * 512 * 4 -> 4096

			4: begin
					div_num   <= mul_res;
					div_den   <= ary_i;
					div_start <= 1;
				end
				// [1] 1080 / 480 * 480 * 4 / 3 -> 1066
				// [2] 1080 / 480 * 480 * 4 / 3 -> 1280
				// [3] 1080 / 512 * 512 * 4 / 3 -> 1365
				// saved as htarget

			5: begin
					htarget   <= div_res[11:0];
					div_num   <= div_res;
					div_den   <= hsize;
					div_start <= 1;
				end
				// computes wide scaling factor as a ceiling division
				// [1] 1080 / 400 * 400 * 4 / 3 / 720 -> 1
				// [2] 1080 / 480 * 480 * 4 / 3 / 640 -> 2
				// [3] 1080 / 512 * 512 * 4 / 3 / 512 -> 2

			6: begin
					mul_arg1  <= hsize;
					mul_arg2  <= div_res[11:0] ? div_res[11:0] : 12'd1;
					mul_start <= 1;
				end
				// [1] 1080 / 400 * 400 * 4 / 3 / 720 * 720 -> 720
				// [2] 1080 / 480 * 480 * 4 / 3 / 640 * 640 -> 1280
				// [3] 1080 / 512 * 512 * 4 / 3 / 512 * 512 -> 1024

			7: if(mul_res <= HDMI_WIDTH) begin
					hinteger = mul_res[11:0];
                    cnt       <= 12;
				end

			8:	begin
					div_num   <= HDMI_WIDTH;
					div_den   <= hsize;
					div_start <= 1;
				end
				// [1] 1920 / 720 -> 2
				// [2] 1920 / 640 -> 3
				// [3] 1920 / 512 -> 3

			9: begin
					mul_arg1  <= hsize;
					mul_arg2  <= div_res[11:0] ? div_res[11:0] : 12'd1;
					mul_start <= 1;
				end
				// [1] 1920 / 720 * 720 -> 1440
				// [2] 1920 / 640 * 640 -> 1920
				// [3] 1920 / 512 * 512 -> 1536

            10: begin
                    hinteger  <= mul_res[11:0];
                    mul_arg1  <= vsize;
                    mul_arg2  <= div_res[11:0] ? div_res[11:0] : 12'd1;
                    mul_start <= 1;
                end
                
            11: begin
                    oheight <= mul_res[11:0];
                end
            
			12: begin
                    wideres <= hinteger + hsize;
					narrow    <= ((htarget - hinteger) <= (wideres - htarget)) || (wideres > HDMI_WIDTH);
					wres      <= hinteger == htarget ? hinteger : wideres;
				end
				// [1] 1066 - 720  = 346 <= 1440 - 1066 = 374 || 1440 > 1920 -> true
				// [2] 1280 - 1280 = 0   <= 1920 - 1280 = 640 || 1920 > 1920 -> true
				// [3] 1365 - 1024 = 341 <= 1536 - 1365 = 171 || 1536 > 1920 -> false
				// 1. narrow flag is true when mul_res[11:0] narrow width is closer to
				//    htarget aspect ratio target width or when wideres wider width
				//    does not fit to the screen.
				// 2. wres becomes wideres only when mul_res[11:0] narrow width not equal
				//    to target width, meaning it is not optimal for source aspect ratio.
				//    otherwise it is set to narrow width that is optimal.

			13: begin
					case(SCALE)
							2: arxf <= {1'b1, hinteger};
							3: arxf <= {1'b1, (wres > HDMI_WIDTH) ? hinteger : wres};
							4: arxf <= {1'b1,              narrow ? hinteger : wres};
					default: arxf <= {1'b1, div_num[11:0]};
					endcase
					aryf <= {1'b1, oheight};
				end
		endcase
	end

	arx_o <= arxf;
	ary_o <= aryf;
end

endmodule
