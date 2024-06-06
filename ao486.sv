//============================================================================
//  ao486
//
//  Port to MiSTer.
//  Copyright (C) 2017-2020 Alexey Melnikov
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
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

//`define DEBUG

assign ADC_BUS  = 'Z;
assign {SDRAM_A, SDRAM_BA, SDRAM_DQ, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign LED_DISK[1] = 0;
assign LED_POWER   = 0;
assign BUTTONS     = {~ps2_reset_n, 1'b0};
assign HDMI_FREEZE = 0;
assign VGA_DISABLE = 0;

led hdd_led(clk_sys, |mgmt_req[5:0], LED_DISK[0]);
led fdd_led(clk_sys, |mgmt_req[7:6], LED_USER);

// Status Bit Map:
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX XXXXXXXXXXXXXXXXXXXXXXX

`include "build_id.v"
localparam CONF_STR =
{
	"AO486;UART115200:4000000(Turbo 115200),MIDI;",
	"S0,IMGIMAVFD,Floppy A:;",
	"S1,IMGIMAVFD,Floppy B:;",
	"O12,Write Protect,None,A:,B:,A: & B:;",
	"-;",
	"S2,VHD,IDE 0-0;",
	"S3,VHD,IDE 0-1;",
	"-;",
	"S4,VHDISOCUECHD,IDE 1-0;",
	"S5,VHDISOCUECHD,IDE 1-1;",
	"-;",
	"oJM,CPU Preset,User Defined,~PC XT-7MHz,~PC AT-8MHz,~PC AT-10MHz,~PC AT-20MHz,~PS/2-20MHz,~386SX-25MHz,~386DX-33Mhz,~386DX-40Mhz,~486SX-33Mhz,~486DX-33Mhz,MAX (unstable);",
	"-;",
	"P1,Audio & Video;",
	"P1-;",
	"P1OMN,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O4,VSync,60Hz,Variable;",
	"P1O8,16/24bit mode,BGR,RGB;",
	"P1O9,16bit format,1555,565;",
	"P1OE,Low-Res,Native,4x;",
	"P1oDE,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"P1O3,FM mode,OPL2,OPL3;",
	"P1OH,C/MS,Disable,Enable;",
	"P1OIJ,Speaker Volume,1,2,3,4;",
	"P1OKL,Audio Boost,No,2x,4x;",
	"P1oBC,Stereo Mix,none,25%,50%,100%;",
	"P1OP,MT32 Volume Ctl,MIDI,Line-In;",

	"P2,Hardware;",
	"P2o01,Boot 1st,Floppy/Hard Disk,Floppy,Hard Disk,CD-ROM;",
	"P2o23,Boot 2nd,NONE,Floppy,Hard Disk,CD-ROM;",
	"P2o45,Boot 3rd,NONE,Floppy,Hard Disk,CD-ROM;",
	"P2-;",
	"P2o6,IDE 1-0 CD Hot-Swap,Yes,No;",
	"P2o7,IDE 1-1 CD Hot-Swap,No,Yes;",
	"P2-;",
	"P2OB,RAM Size,256MB,16MB;",
`ifndef DEBUG
	"H5P2-;",
	"H5D2D1P2O56,CPU Clock,90MHz,15MHz,30MHz,56MHz;",
	"H5h0P2O7,Overclock,Off,100Mhz;",
	"H5D2P2OF,L1 Cache,On,Off;",
	"H5D2P2OG,L2 Cache,On,Off;",
`endif
	"P2-;",
	"P2OA,USER I/O,MIDI,COM2;",
	"P2-;",
	"P2OCD,Joystick type,2 Buttons,4 Buttons,Gravis Pro,None;",
	"P2oFG,Joystick Mode,2 Joysticks,2 Sticks,2 Wheels,4-axes Wheel;",
	"P2oH,Joystick 1,Enabled,Disabled;",
	"P2oI,Joystick 2,Enabled,Disabled;",

	"h3P3,MT32-pi;",
	"h3P3-;",
	"h3P3OO,Use MT32-pi,Yes,No;",
	"h3P3o9A,Show Info,No,Yes,LCD-On(non-FB),LCD-Auto(non-FB);",
	"h3P3-;",
	"h3P3-,Default Config:;",
	"h3P3OQ,Synth,Munt,FluidSynth;",
	"h3P3ORS,Munt ROM,MT-32 v1,MT-32 v2,CM-32L;",
	"h3P3OTV,SoundFont,0,1,2,3,4,5,6,7;",
	"h3P3-;",
	"h3P3r8,Reset Hanging Notes;",
	"-;",
	"R0,Reset and apply HDD;",
	"J,Button 1,Button 2,Button 3,Button 4,Start,Select,R1,L1,R2,L2;",
	"jn,A,B,X,Y,Start,Select,R,L;",
	"I,",
	"MT32-pi: SoundFont #0,",
	"MT32-pi: SoundFont #1,",
	"MT32-pi: SoundFont #2,",
	"MT32-pi: SoundFont #3,",
	"MT32-pi: SoundFont #4,",
	"MT32-pi: SoundFont #5,",
	"MT32-pi: SoundFont #6,",
	"MT32-pi: SoundFont #7,",
	"MT32-pi: MT-32 v1,",
	"MT32-pi: MT-32 v2,",
	"MT32-pi: CM-32L,",
	"MT32-pi: Unknown mode;",
	"V,v",`BUILD_DATE
};

////////////////////////////////////////////////////////////////////////

wire        ps2_kbd_clk_out;
wire        ps2_kbd_data_out;
wire        ps2_kbd_clk_in;
wire        ps2_kbd_data_in;
wire [10:0] ps2_key;

wire        ps2_mouse_clk_out;
wire        ps2_mouse_data_out;
wire        ps2_mouse_clk_in;
wire        ps2_mouse_data_in;

wire  [1:0] buttons;
wire [63:0] status;

wire [13:0] joystick_0;
wire [13:0] joystick_1;
wire [15:0] joystick_l_analog_0;
wire [15:0] joystick_l_analog_1;
wire [15:0] joystick_r_analog_0;
wire [15:0] joystick_r_analog_1;

wire [21:0] gamma_bus;
wire  [7:0] uart1_mode;
wire [31:0] uart1_speed;

hps_io #(.CONF_STR(CONF_STR), .CONF_STR_BRAM(0), .PS2DIV(2000), .PS2WE(1), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.ps2_key(ps2_key),
	.ps2_kbd_clk_out(ps2_kbd_clk_out),
	.ps2_kbd_data_out(ps2_kbd_data_out),
	.ps2_kbd_clk_in(ps2_kbd_clk_in),
	.ps2_kbd_data_in(ps2_kbd_data_in),

	.ps2_mouse_clk_out(ps2_mouse_clk_out),
	.ps2_mouse_data_out(ps2_mouse_data_out),
	.ps2_mouse_clk_in(ps2_mouse_clk_in),
	.ps2_mouse_data_in(ps2_mouse_data_in),

	.buttons(buttons),
	.status(status),
	.status_menumask({|status[54:51],mt32_newmode,mt32_available,syscfg[7],status[7],dbg_menu}),
	.info_req(mt32_info_req),
	.info(mt32_info_disp),

	.new_vmode(status[4]),
	.gamma_bus(gamma_bus),

	.uart_mode(uart1_mode),
	.uart_speed(uart1_speed),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_l_analog_0(joystick_l_analog_0),
	.joystick_l_analog_1(joystick_l_analog_1),
	.joystick_r_analog_0(joystick_r_analog_0),
	.joystick_r_analog_1(joystick_r_analog_1),

	.EXT_BUS(EXT_BUS)
);

wire [15:0] mgmt_din;
wire [15:0] mgmt_dout;
wire [15:0] mgmt_addr;
wire        mgmt_rd;
wire        mgmt_wr;
wire  [7:0] mgmt_req;

wire [35:0] EXT_BUS;
hps_ext hps_ext
(
	.clk_sys(clk_sys),
	.EXT_BUS(EXT_BUS),

	.ext_din(mgmt_din),
	.ext_dout(mgmt_dout),
	.ext_addr(mgmt_addr),
	.ext_rd(mgmt_rd),
	.ext_wr(mgmt_wr),

	.cdda_req(cdda_req),
	.cdda_wr(cdda_wr),
	.cdda_dout(cdda_dout),

	.ext_req(mgmt_req),
	.ext_hotswap(status[39:38])
);

/////////////////////////////  PLL  ////////////////////////////////////

wire clk_sys, clk_uart1, clk_uart2, clk_mpu, clk_vga;
reg [27:0] cur_rate;

`ifdef DEBUG

pll2 pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_vga),
	.outclk_1(clk_uart1),
	.outclk_2(clk_mpu),
	.outclk_3(),
	.outclk_4(clk_sys),
	.outclk_5(clk_uart2)
);

always @(posedge clk_sys) cur_rate <= 30000000;

`else


wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_uart1),
	.outclk_2(clk_mpu),
	.outclk_3(), // 14.285714 instead of 14.318181 which is within tolerance of typical resonator
	.outclk_4(clk_vga),
	.outclk_5(clk_uart2),
	.locked(pll_locked),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

reg [2:0] clk_req;
reg l1, l2;
always @(posedge clk_sys) begin
	case(status[54:51])
		'd1: begin clk_req <= 'd3; l1 <= 1'b1; l2 <= 1'b1; end  // ao486 XT 7
		'd2: begin clk_req <= 'd1; l1 <= 1'b1; l2 <= 1'b0; end  // ao486 AT 8
		'd3: begin clk_req <= 'd2; l1 <= 1'b0; l2 <= 1'b1; end  // ao486 AT 10
		'd4: begin clk_req <= 'd2; l1 <= 1'b1; l2 <= 1'b0; end  // ao486 AT 20
		'd5: begin clk_req <= 'd1; l1 <= 1'b0; l2 <= 1'b0; end  // ao486 PS/2 20
		'd6: begin clk_req <= 'd3; l1 <= 1'b1; l2 <= 1'b0; end  // ao486 3SX 25
		'd7: begin clk_req <= 'd2; l1 <= 1'b0; l2 <= 1'b0; end  // ao486 3DX 33
		'd8: begin clk_req <= 'd0; l1 <= 1'b1; l2 <= 1'b0; end  // ao486 3DX 40
		'd9: begin clk_req <= 'd3; l1 <= 1'b0; l2 <= 1'b0; end  // ao486 4SX 33
		'd10: begin clk_req <= 'd0; l1 <= 1'b0; l2 <= 1'b0; end // ao486 MAX (stable)
		'd11: begin clk_req <= 'd4; l1 <= 1'b0; l2 <= 1'b0; end // ao486 MAX+ (unstable)
		default: begin
		// CPU & Cache config
		clk_req <= {status[7], syscfg[7] ? syscfg[1:0] : status[6:5]};
		l1 <= syscfg[7] ? syscfg[4] : status[15];
		l2 <= syscfg[7] ? syscfg[5] : status[16];
		end
	endcase
end

reg [2:0] speed;
always @(posedge CLK_50M) begin
	reg [2:0] sp1, sp2;

	sp1 <= clk_req;
	sp2 <= sp1;

	if(sp2 == sp1) speed <= sp2;
end

reg uspeed_sys;
always @(posedge clk_sys) uspeed_sys <= (uart1_speed <= 115200);

reg uspeed;
always @(posedge CLK_50M) begin
	reg sp1, sp2;

	sp1 <= uspeed_sys;
	sp2 <= sp1;

	if(sp2 == sp1) uspeed <= sp2;
end

(* romstyle = "logic" *) wire [27:0] clk_rate[8]  = '{90000000, 15000000, 30000000, 56250000, 100000000, 100000000, 100000000, 100000000 };
(* romstyle = "logic" *) wire [17:0] speed_div[8] = '{  'h0505,   'h1e1e,   'h0f0f,   'h0808,   'h20504,   'h20504,   'h20504,   'h20504 };

always @(posedge CLK_50M) begin
	reg [2:0] old_speed = 0;
	reg [2:0] state = 0;
	reg       old_uspeed = 0;
	reg       old_rst = 0;

	if(!cfg_waitrequest) begin

		cfg_write <= 0;

		if(pll_locked) begin
			if(state) state<=state+1'd1;
			case(state)
				0: begin
						old_rst <= reset;
						old_speed <= speed;
						old_uspeed <= uspeed;
						if((old_speed != speed) || (old_uspeed != uspeed) || (old_rst & ~reset)) state <= 1;
					end
				1: begin
						cfg_address <= 0;
						cfg_data <= 0;
						cfg_write <= 1;
					end
				3: begin
						cfg_address <= 5;
						cfg_data <= speed_div[speed];
						cfg_write <= 1;
					end
				5: begin
						cfg_address <= 5;
						cfg_data <= uspeed ? 32'h4F4F4 : 32'h40909;
						cfg_write <= 1;
					end
				7: begin
						cfg_address <= 2;
						cfg_data <= 0;
						cfg_write <= 1;
					end
			endcase
		end
	end
end

always @(posedge clk_sys) cur_rate <= clk_rate[clk_req];

`endif

////////////////////////////  UART  ////////////////////////////////////

/// UART1

wire uart1_cts, uart1_dcd, uart1_dsr, uart1_rts, uart1_dtr;
wire uart1_tx, uart1_rx;
wire mpu_tx, mpu_rx;

wire hps_mpu = (uart1_mode >= 3);

assign UART_RTS  = ~hps_mpu & uart1_rts;
assign UART_DTR  = ~hps_mpu & uart1_dtr;
assign uart1_cts = ~hps_mpu & UART_CTS;
assign uart1_dcd = ~hps_mpu & UART_DSR;
assign uart1_dsr = ~hps_mpu & UART_DSR;
assign uart1_rx  = ~hps_mpu & UART_RXD;
assign mpu_rx    = ~hps_mpu ? midi_rx : UART_RXD;
assign UART_TXD  = ~hps_mpu ? uart1_tx : (mpu_tx & ~mt32_use);

/// UART2

wire user_io_mode = status[10];

assign USER_OUT = user_io_mode ? {1'b1, 1'b1, uart2_dtr, 1'b1, uart2_rts, uart2_tx, 1'b1} : mt32_out;

//
// Pin | USB Name |   |Signal
// ----+----------+---+-------------
// 0   | D+       | I |RX
// 1   | D-       | O |TX
// 2   | TX-      | O |RTS
// 3   | GND_d    | I |CTS
// 4   | RX+      | O |DTR
// 5   | RX-      | I |DSR
// 6   | TX+      | I |DCD
//

wire uart2_tx, uart2_rts, uart2_dtr;

wire uart2_rx  = ~user_io_mode | USER_IN[0];
wire uart2_cts = ~user_io_mode | USER_IN[3];
wire uart2_dsr = ~user_io_mode | USER_IN[5];
wire uart2_dcd = ~user_io_mode | USER_IN[6];

////////////////////////////  VIDEO  ///////////////////////////////////

assign VGA_F1 = 0;
assign VGA_SL = 0;
assign VGA_SCALER = 1;
assign CLK_VIDEO = clk_vga;
assign CE_PIXEL = vga_ce & vga_out_en;

wire [7:0] r,g,b;
wire       HSync,VSync;
wire       ce_pix;

video_cleaner video_cleaner
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(vga_ce),

	.R(r),
	.G(g),
	.B(b),

	.HSync(HSync),
	.VSync(VSync),
	.DE_in(vga_de),

	.VGA_R(R),
	.VGA_G(G),
	.VGA_B(B),
	.VGA_VS(vs),
	.VGA_HS(hs),
	.DE_out(de1)
);

wire hs,vs,de1;
wire [7:0] R,G,B;

gamma_fast gamma
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(CE_PIXEL),

	.gamma_bus(gamma_bus),

	.HSync(hs),
	.VSync(vs),
	.DE(de1),
	.RGB_in(mt32_lcd ? {{2{mt32_lcd_pix}},R[7:2], {2{mt32_lcd_pix}},G[7:2], {2{mt32_lcd_pix}},B[7:2]} : {R,G,B}),

	.HSync_out(VGA_HS),
	.VSync_out(VGA_VS),
	.DE_out(VGA_DE),
	.RGB_out({VGA_R,VGA_G,VGA_B})
);

wire  [7:0] vga_pal_a;
wire [17:0] vga_pal_d;
wire        vga_pal_we;

wire [19:0] vga_start_addr;
wire  [8:0] vga_width;
wire  [8:0] vga_stride;
wire [10:0] vga_height;
wire  [3:0] vga_flags;
wire        vga_off;
wire        vga_ce;
wire        vga_de;
wire        vga_lores = ~status[14];

reg vga_out_en;
always @(posedge clk_vga) begin
	reg old_hs, old_vs;

	if(vga_flags[3] & vga_lores) begin
		old_hs <= HSync;
		if(~old_hs & HSync) begin
			old_vs <= VSync;
			vga_out_en <= ~vga_out_en;
			if(~old_vs & VSync) vga_out_en <= 0;
		end
	end
	else begin
		vga_out_en <= 1;
	end
end

reg         fb_en;
reg  [31:0] fb_base;
reg  [11:0] fb_height;
reg  [11:0] fb_width;
reg  [13:0] fb_stride;
reg   [4:0] fb_fmt;
reg         fb_off;

always @(posedge clk_sys) begin
	fb_en       <= ~vga_flags[2] && |vga_flags[1:0];
	fb_base     <= {4'h3, 6'b111110, vga_start_addr, 2'b00};
	fb_width    <= (vga_flags[1:0] == 3) ? 12'd640 /*({vga_width, 3'b000}/3)*/ : vga_flags[2] ? {1'b0, vga_width, 2'b00} : {vga_width, 3'b000};
	fb_stride   <= {vga_stride, 3'b000};
	fb_height   <= vga_flags[3] ? vga_height[10:1] : vga_height;
	fb_fmt[2:0] <= (vga_flags[1:0] == 3) ? 3'b101 : (vga_flags[1:0] == 2) ? 3'b100 : 3'b011;
	fb_fmt[4:3] <= {~status[8],~status[9]};
	fb_off      <= vga_off;
end

assign FB_PAL_CLK     = clk_sys;
assign FB_PAL_ADDR    = vga_pal_a;
assign FB_PAL_DOUT    = {vga_pal_d[17:12], vga_pal_d[17:16], vga_pal_d[11:6], vga_pal_d[11:10], vga_pal_d[5:0], vga_pal_d[5:4]};
assign FB_PAL_WR      = vga_pal_we;
assign FB_EN          = fb_en;
assign FB_BASE        = fb_base;
assign FB_FORMAT      = fb_fmt;
assign FB_WIDTH       = fb_width;
assign FB_HEIGHT      = fb_height;
assign FB_STRIDE      = fb_stride;
assign FB_FORCE_BLANK = fb_off;

reg f60;
always @(posedge clk_sys) f60 <= fb_en || (fb_width > 760);

reg  [2:0] ar,SCALE;
reg [11:0] arx_i,ary_i;
always @(posedge CLK_VIDEO) begin
	ar    <= status[23:22];
	SCALE <= status[46:45];
	arx_i <= (!ar) ? 8'd4 : (ar - 1'd1);
	ary_i <= (!ar) ? 8'd3 : 8'd0;
end

wire [12:0] fb_arx, arx, fb_ary, ary;

video_scale_int fb_scale
(
	.*,
	.hsize(fb_width),
	.vsize(fb_height),
	.arx_o(fb_arx),
	.ary_o(fb_ary)
);

video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),
	.ARX(arx_i),
	.ARY(ary_i),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.VIDEO_ARX(arx),
	.VIDEO_ARY(ary)
);

assign VIDEO_ARX = fb_en ? fb_arx : arx;
assign VIDEO_ARY = fb_en ? fb_ary : ary;

////////////////////////////////////////////////////////////////////////

assign DDRAM_ADDR[28:25] = 4'h3;

wire [4:0] vol_l, vol_r, vol_cd_l, vol_cd_r, vol_midi_l, vol_midi_r, vol_line_l, vol_line_r;
wire [1:0] vol_spk;
wire [4:0] vol_en;

system system
(
	.clk_sys              (clk_sys),
	.clk_audio            (CLK_AUDIO),
	.clk_uart1            (clk_uart1),
	.clk_uart2            (clk_uart2),
	.clk_mpu              (clk_mpu),
	.clk_vga              (clk_vga),

	.reset                (reset),

	.clock_rate           (cur_rate),

	.syscfg               (syscfg),
	.l1_disable           (l1),
	.l2_disable           (l2),

	.video_ce             (vga_ce),
	.video_f60            (~status[4] | f60),
	.video_blank_n        (vga_de),
	.video_hsync          (HSync),
	.video_vsync          (VSync),
	.video_r              (r),
	.video_g              (g),
	.video_b              (b),

	.clock_rate_vga       (90000000),
	.video_pal_a          (vga_pal_a),
	.video_pal_d          (vga_pal_d),
	.video_pal_we         (vga_pal_we),
	.video_start_addr     (vga_start_addr),
	.video_width          (vga_width),
	.video_stride         (vga_stride),
	.video_height         (vga_height),
	.video_flags          (vga_flags),
	.video_off            (vga_off),
	.video_fb_en          (fb_en),
	.video_lores          (vga_lores),

	.sample_sb_l          (sb_out_l),
	.sample_sb_r          (sb_out_r),
	.sample_opl_l         (opl_out_l),
	.sample_opl_r         (opl_out_r),
	.sound_fm_mode        (status[3]),
	.sound_cms_en         (status[17]),
	.vol_l                (vol_l),
	.vol_r                (vol_r),
	.vol_cd_l             (vol_cd_l),
	.vol_cd_r             (vol_cd_r),
	.vol_midi_l           (vol_midi_l),
	.vol_midi_r           (vol_midi_r),
	.vol_line_l           (vol_line_l),
	.vol_line_r           (vol_line_r),
	.vol_spk              (vol_spk),
	.vol_en               (vol_en),
	.speaker_out          (speaker_out),

	.ps2_reset_n          (ps2_reset_n),

	.ps2_kbclk_in         (ps2_kbd_clk_out),
	.ps2_kbdat_in         (ps2_kbd_data_out),
	.ps2_kbclk_out        (ps2_kbd_clk_in),
	.ps2_kbdat_out        (ps2_kbd_data_in),

	.ps2_mouseclk_in      (ps2_mouse_clk_out),
	.ps2_mousedat_in      (ps2_mouse_data_out),
	.ps2_mouseclk_out     (ps2_mouse_clk_in),
	.ps2_mousedat_out     (ps2_mouse_data_in),

	.joystick_dis         (joystick_dis),
	.joystick_dig_1       (joystick_0 & dig_mask),
	.joystick_dig_2       (status[47] ? 14'd0 : (joystick_1 & dig_mask)),
	.joystick_ana_1       ({ja_1y,ja_1x}),
	.joystick_ana_2       ({ja_2y,ja_2x}),
	.joystick_mode        (status[13:12]),

	.mgmt_readdata        (mgmt_din),
	.mgmt_writedata       (mgmt_dout),
	.mgmt_address         (mgmt_addr),
	.mgmt_write           (mgmt_wr),
	.mgmt_read            (mgmt_rd),

	.ide0_request         (mgmt_req[2:0]),
	.ide1_request         (mgmt_req[5:3]),
	.fdd_request          (mgmt_req[7:6]),
	.floppy_wp            (status[2:1]),

	.uart1_rx             (uart1_rx),
	.uart1_tx             (uart1_tx),
	.uart1_cts_n          (uart1_cts),
	.uart1_dcd_n          (uart1_dcd),
	.uart1_dsr_n          (uart1_dsr),
	.uart1_rts_n          (uart1_rts),
	.uart1_dtr_n          (uart1_dtr),

	.uart2_rx             (uart2_rx),
	.uart2_tx             (uart2_tx),
	.uart2_cts_n          (uart2_cts),
	.uart2_dcd_n          (uart2_dcd),
	.uart2_dsr_n          (uart2_dsr),
	.uart2_rts_n          (uart2_rts),
	.uart2_dtr_n          (uart2_dtr),

	.mpu_rx               (mpu_rx),
	.mpu_tx               (mpu_tx),

	.memcfg               (memcfg),
	.bootcfg              (status[37:32]),

	.DDRAM_CLK            (DDRAM_CLK),
	.DDRAM_ADDR           (DDRAM_ADDR[24:0]),
	.DDRAM_DIN            (DDRAM_DIN),
	.DDRAM_DOUT           (DDRAM_DOUT),
	.DDRAM_DOUT_READY     (DDRAM_DOUT_READY),
	.DDRAM_BE             (DDRAM_BE),
	.DDRAM_BURSTCNT       (DDRAM_BURSTCNT),
	.DDRAM_BUSY           (DDRAM_BUSY),
	.DDRAM_RD             (DDRAM_RD),
	.DDRAM_WE             (DDRAM_WE)
);

wire [7:0] syscfg;
wire       ps2_reset_n;

reg memcfg = 0;
always @(posedge clk_sys) if(reset) memcfg <= status[11];

reg reset;
always @(posedge clk_sys) begin
	reg init_reset_n = 0;
	reg old_rst = 0;

	reset <= buttons[1] | status[0] | RESET | ~init_reset_n;

	old_rst <= status[0];
	if(old_rst & ~status[0]) init_reset_n <= 1;
end

reg dbg_menu = 0;
always @(posedge clk_sys) begin
	reg old_stb;
	reg enter = 0;
	reg esc = 0;

	old_stb <= ps2_key[10];
	if(old_stb ^ ps2_key[10]) begin
		if(ps2_key[7:0] == 'h5A) enter <= ps2_key[9];
		if(ps2_key[7:0] == 'h76) esc   <= ps2_key[9];
	end

	if(enter & esc) begin
		dbg_menu <= ~dbg_menu;
		enter <= 0;
		esc <= 0;
	end

	if(status[7]) dbg_menu <= 1;
end


wire  [7:0] ja_1x,ja_1y,ja_2x,ja_2y;
wire [15:0] dig_mask;
wire  [1:0] joystick_dis;

wire [7:0] pedal_combo;
always_comb begin
	ja_1x = joystick_l_analog_0[7:0];
	ja_1y = joystick_l_analog_0[15:8];
	ja_2x = joystick_l_analog_1[7:0];
	ja_2y = joystick_l_analog_1[15:8];
	dig_mask = '1;
	joystick_dis = status[50:49];

	case(status[48:47])
		1: begin
				ja_2x = joystick_r_analog_0[7:0];
				ja_2y = joystick_r_analog_0[15:8];
				joystick_dis[1] = status[49];
			end
		2: begin
				ja_1y = 0;
				if(joystick_l_analog_0[15]) ja_1y = joystick_l_analog_0[15:8];
				if(joystick_r_analog_0[15]) ja_1y = ja_1y - joystick_r_analog_0[15:8];
				ja_2y = 0;
				if(joystick_l_analog_1[15]) ja_2y = joystick_l_analog_1[15:8];
				if(joystick_r_analog_1[15]) ja_2y = ja_2y - joystick_r_analog_1[15:8];
				dig_mask[3:0] = 0;
			end
		3: begin
				ja_1y = joystick_l_analog_0[15] ? {joystick_l_analog_0[14:8] + 7'd63, 1'b0} : 8'd127;
				ja_2y = joystick_r_analog_0[15] ? {joystick_r_analog_0[14:8] + 7'd63, 1'b0} : 8'd127;
				ja_2x = joystick_r_analog_0[7]  ? {joystick_r_analog_0[6:0]  + 7'd63, 1'b0} : 8'd127;
				dig_mask[3:0] = 0;
				joystick_dis[1] = status[49];
			end
		default:;
	endcase
end

////////////////////////////  MT32pi  //////////////////////////////////

wire        mt32_reset    = status[40] | reset;
wire        mt32_disable  = status[24];
wire        mt32_mode_req = status[26];
wire  [1:0] mt32_rom_req  = status[28:27];
wire  [7:0] mt32_sf_req   = status[31:29];
wire  [1:0] mt32_info     = status[42:41];

wire [15:0] mt32_i2s_r, mt32_i2s_l;
wire  [7:0] mt32_mode, mt32_rom, mt32_sf;
wire        mt32_lcd_en, mt32_lcd_pix, mt32_lcd_update;
wire        midi_rx;

wire mt32_newmode;
wire mt32_available;
wire mt32_use  = mt32_available & ~mt32_disable;
wire mt32_mute = mt32_available &  mt32_disable;

wire [6:0] mt32_out;
mt32pi mt32pi
(
	.*,
	.reset(mt32_reset),
	.USER_IN(user_io_mode ? 7'h7F : USER_IN),
	.USER_OUT(mt32_out),
	.midi_tx(mpu_tx | mt32_mute)
);

reg mt32_info_req;
reg [3:0] mt32_info_disp;
always @(posedge clk_sys) begin
	reg old_mode;

	old_mode <= mt32_newmode;
	mt32_info_req <= (old_mode ^ mt32_newmode) && (mt32_info == 1);

	mt32_info_disp <= (mt32_mode == 'hA2) ? (4'd1 + mt32_sf[2:0]) :
                     (mt32_mode == 'hA1 && mt32_rom == 0) ?  4'd9 :
                     (mt32_mode == 'hA1 && mt32_rom == 1) ?  4'd10 :
                     (mt32_mode == 'hA1 && mt32_rom == 2) ?  4'd11 : 4'd12;
end

reg mt32_lcd_on;
always @(posedge CLK_VIDEO) begin
	int to;
	reg old_update;

	old_update <= mt32_lcd_update;
	if(to) to <= to - 1;

	if(mt32_info == 2) mt32_lcd_on <= 1;
	else if(mt32_info != 3) mt32_lcd_on <= 0;
	else begin
		if(!to) mt32_lcd_on <= 0;
		if(old_update ^ mt32_lcd_update) begin
			mt32_lcd_on <= 1;
			to <= 90000000 * 2;
		end
	end
end

wire mt32_lcd = mt32_lcd_on & mt32_lcd_en;

////////////////////////////  AUDIO  ///////////////////////////////////

wire        speaker_out;
reg  [16:0] spk_out;
always @(posedge CLK_AUDIO) begin
	reg [16:0] spk;
	spk <= {2'b00, {3'b000,speaker_out} << status[19:18], 11'd0};
	spk_out <= spk >> ~vol_spk;
end

// cross clk_host->clk_audio domains using single bit synchronized handshaking signal
// 100e6/24.576e6 * 2 + 1 = hold signals stable for 9 cycles to pass through synchronizer
wire [15:0] sb_out_l, sb_out_r;
reg [15:0] sb_out_l_p1, sb_out_r_p1, sb_out_l_hold, sb_out_r_hold;
reg new_sample_l_clk_sys, new_sample_r_clk_sys;
reg [8:0] new_sample_l_hold_sr, new_sample_r_hold_sr;
reg new_sample_l_clk_audio_p0, new_sample_r_clk_audio_p0, new_sample_l_clk_audio_p1, new_sample_r_clk_audio_p1;
wire [16:0] sb_l, sb_r;

always @(posedge clk_sys) begin
	sb_out_l_p1 <= sb_out_l;
	sb_out_r_p1 <= sb_out_r;

	new_sample_l_hold_sr <= new_sample_l_hold_sr << 1;
	new_sample_r_hold_sr <= new_sample_r_hold_sr << 1;

	if (new_sample_l_hold_sr == 0)
		new_sample_l_clk_sys <= 0;

	if (new_sample_r_hold_sr == 0)
		new_sample_r_clk_sys <= 0;

	if (sb_out_l != sb_out_l_p1 && new_sample_l_hold_sr == 0) begin
		new_sample_l_clk_sys <= 1;
		new_sample_l_hold_sr[0] <= 1;
		sb_out_l_hold <= sb_out_l;
	end

	if (sb_out_r != sb_out_r_p1 && new_sample_r_hold_sr == 0) begin
		new_sample_r_clk_sys <= 1;
		new_sample_r_hold_sr[0] <= 1;
		sb_out_r_hold <= sb_out_r;
	end
end

always @(posedge CLK_AUDIO) begin
	new_sample_l_clk_audio_p0 <= new_sample_l_clk_sys;
	new_sample_l_clk_audio_p1 <= new_sample_l_clk_audio_p0;

	new_sample_r_clk_audio_p0 <= new_sample_r_clk_sys;
	new_sample_r_clk_audio_p1 <= new_sample_r_clk_audio_p0;

	if (new_sample_l_clk_audio_p1)
		sb_l <= {sb_out_l_hold[15],sb_out_l_hold};

	if (new_sample_r_clk_audio_p1)
		sb_r <= {sb_out_r_hold[15],sb_out_r_hold};
end

wire [15:0] opl_out_l, opl_out_r; // already synced to CLK_AUDIO

wire [15:0] cdda_l;
wire [15:0] cdda_r;
wire [31:0] cdda_dout;
wire        cdda_req;
wire        cdda_wr;

cdda #(24576000) cdda
(
	.CLK(clk_sys),
	.CDDA_REQ(cdda_req),
	.CDDA_WR(cdda_wr),
	.CDDA_DATA(cdda_dout),

	.VOLUME_L(vol_cd_l[4:1]),
	.VOLUME_R(vol_cd_r[4:1]),

	.CLK_AUDIO(CLK_AUDIO),
	.AUDIO_L(cdda_l),
	.AUDIO_R(cdda_r)
);

function signed [15:0] volume(input [15:0] inp, input [4:0] vol);
	begin
		volume = vol ? $signed($signed(inp) >>> ~vol[4:1]) : 16'd0;
	end
endfunction

reg [15:0] out_l, out_r;
always @(posedge CLK_AUDIO) begin
	reg [16:0] tmp_l, tmp_r;
	reg [15:0] mt32_l, mt32_r;

	mt32_l <= volume(mt32_i2s_l, ~status[25] ? vol_midi_l : vol_en[4] ? vol_line_l : 5'd0);
	mt32_r <= volume(mt32_i2s_r, ~status[25] ? vol_midi_r : vol_en[3] ? vol_line_r : 5'd0);

	tmp_l <= {opl_out_l[15],opl_out_l} + sb_l + spk_out + (mt32_mute ? 17'd0 : {mt32_l[15],mt32_l}) + (vol_en[2] ? {cdda_l[15],cdda_l} : 17'd0);
	tmp_r <= {opl_out_r[15],opl_out_r} + sb_r + spk_out + (mt32_mute ? 17'd0 : {mt32_r[15],mt32_r}) + (vol_en[1] ? {cdda_r[15],cdda_r} : 17'd0);

	// clamp the output
	out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];
	out_r <= (^tmp_r[16:15]) ? {tmp_r[16], {15{tmp_r[15]}}} : tmp_r[15:0];
end

wire [15:0] cmp_l, cmp_r;
acompr acompr_l(CLK_AUDIO, status[21], out_l, cmp_l);
acompr acompr_r(CLK_AUDIO, status[21], out_r, cmp_r);

reg [15:0] audio_l, audio_r;
always @(posedge CLK_AUDIO) begin
	audio_l <= volume(status[21:20] ? cmp_l : out_l, vol_l);
	audio_r <= volume(status[21:20] ? cmp_r : out_r, vol_r);
end

assign AUDIO_L   = audio_l;
assign AUDIO_R   = audio_r;
assign AUDIO_S   = 1;
assign AUDIO_MIX = status[44:43];

////////////////////////////////////////////////////////////////////////

endmodule

module led
(
	input      clk,
	input      in,
	output reg out
);

integer counter = 0;
always @(posedge clk) begin
	if(!counter) out <= 0;
	else begin
		counter <= counter - 1'b1;
		out <= 1;
	end

	if(in) counter <= 4500000;
end

endmodule

module acompr
(
	input             clk,
	input             mode,
	input      [15:0] inp,
	output reg [15:0] out
);

localparam [3:0] comp_f1 = 4;
localparam [3:0] comp_a1 = 2;
localparam       comp_x1 = ((32767 * (comp_f1 - 1)) / ((comp_f1 * comp_a1) - 1)) + 1; // +1 to make sure it won't overflow
localparam       comp_b1 = comp_x1 * comp_a1;

localparam [3:0] comp_f2 = 8;
localparam [3:0] comp_a2 = 4;
localparam       comp_x2 = ((32767 * (comp_f2 - 1)) / ((comp_f2 * comp_a2) - 1)) + 1; // +1 to make sure it won't overflow
localparam       comp_b2 = comp_x2 * comp_a2;

always @(posedge clk) begin
	reg [15:0] v, v1, v2, v3;
	reg vs, vs1, vs3;

	v   <= inp[15] ? -inp : inp;
	vs  <= inp[15];

	v1  <= (v < comp_x1[15:0]) ? (v * comp_a1) : (((v - comp_x1[15:0])/comp_f1) + comp_b1[15:0]);
	v2  <= (v < comp_x2[15:0]) ? (v * comp_a2) : (((v - comp_x2[15:0])/comp_f2) + comp_b2[15:0]);
	vs1 <= vs;

	v3  <= mode ? v2 : v1;
	vs3 <= vs1;

	out <= vs3 ? -v3 : v3;
end

endmodule
