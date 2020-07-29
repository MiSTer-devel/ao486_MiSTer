//============================================================================
//  ao486
// 
//  Port to MiSTer.
//  Copyright (C) 2017-2019 Alexey Melnikov
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
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,

	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,
	
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,

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
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
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
assign USER_OUT = '1;
assign {SDRAM_A, SDRAM_BA, SDRAM_DQ, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3;

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;
assign AUDIO_L   = sb_out_l + {2'b00, {14{speaker_ena & speaker_out}}};
assign AUDIO_R   = sb_out_r + {2'b00, {14{speaker_ena & speaker_out}}};

assign LED_DISK[1] = 1;
assign LED_POWER   = 0;
assign BUTTONS   = 0;

led hdd_led(clk_sys,  device & ioctl_wait, LED_DISK[0]);
led fdd_led(clk_sys, ~device & ioctl_wait, LED_USER);


`include "build_id.v"
localparam CONF_STR =
{
	"AO486;;",
	"-;",
	"S0,IMG,Mount Floppy;",
	"-;",
	"S2,VHD,Mount Primary HDD;",
	"S3,VHD,Mount Secondary HDD;",
	"-;",
	"OX2,Boot order,FDD/HDD,HDD/FDD;",
	"-;",
	"O1,Aspect ratio,4:3,16:9;",
	"O4,VSync,60Hz,Variable;",
	"O8,16/24bit mode,BGR,RGB;",
	"O9,16bit format,1555,565;",
	"-;",
	"O3,FM mode,OPL2,OPL3;",
	"-;",
	"OCD,Joystick type,2 Buttons,4 Buttons,Gravis Pro;",
	"-;",
	"OB,RAM Size,256MB,16MB;",
`ifndef DEBUG
	"O57,Speed,90MHz,100MHz,15MHz,30MHz,56MHz;",
	"OA,UART Speed,Normal,10x;",
`endif
	"-;",
	"R0,Reset and apply HDD;",
	"J,Button 1,Button 2,Button 3,Button 4,Start,Select,R1,L1,R2,L2;",
	"jn,A,B,X,Y,Start,Select,R,L;",
	"V,v",`BUILD_DATE
};


//////////////////   MIST ARM I/O   ///////////////////
wire        ps2_kbd_clk_out;
wire        ps2_kbd_data_out;
wire        ps2_kbd_clk_in;
wire        ps2_kbd_data_in;

wire        ps2_mouse_clk_out;
wire        ps2_mouse_data_out;
wire        ps2_mouse_clk_in;
wire        ps2_mouse_data_in;

wire  [1:0] buttons;
wire [31:0] status;

reg         ioctl_wait = 0;

wire [13:0] joystick_0;
wire [13:0] joystick_1;
wire [15:0] joystick_analog_0;
wire [15:0] joystick_analog_1;

wire [21:0] gamma_bus;

hps_io #(.STRLEN(($size(CONF_STR))>>3), .PS2DIV(4000), .PS2WE(1), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.conf_str(CONF_STR),
	
	.HPS_BUS(HPS_BUS),

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
	.new_vmode(status[4]),
	.gamma_bus(gamma_bus),

	.ioctl_wait(ioctl_wait),

	.uart_mode(16'b000_11111_000_11111),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_analog_0(joystick_analog_0),
	.joystick_analog_1(joystick_analog_1),

	.EXT_BUS(EXT_BUS)
);

wire        mgmt_wait;
wire        mgmt_valid;
wire [31:0] mgmt_data;
reg         mgmt_we = 0;
reg         mgmt_rd = 0;
wire [31:0] mgmt_din;
wire [31:0] mgmt_dout;
wire [31:0] mgmt_addr;
wire        mgmt_hrd;
wire        mgmt_hwr;
wire  [1:0] mgmt_status;
wire  [1:0] mgmt_req;

wire [35:0] EXT_BUS;
hps_ext hps_ext
(
	.clk_sys(clk_sys),
	.EXT_BUS(EXT_BUS),

	.io_wait(ioctl_wait),
	
	.clk_rate(
`ifdef DEBUG
	30000000
`else
	clk_rate[status[7:5]]
`endif
	),

	.ext_din(mgmt_din),
	.ext_dout(mgmt_dout),
	.ext_addr(mgmt_addr),
	.ext_rd(mgmt_hrd),
	.ext_wr(mgmt_hwr),
	.ext_req(mgmt_req),
	.ext_status(mgmt_status)
);

//------------------------------------------------------------------------------

wire clk_sys, clk_uart, clk_opl;

`ifdef DEBUG

pll2 pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_sys)
	.outclk_1(clk_uart),
	.outclk_2(clk_opl)
);

`else

wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_uart),
	.outclk_2(clk_opl),
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

reg [2:0] speed;
always @(posedge CLK_50M) begin
	reg [2:0] sp1, sp2;
	
	sp1 <= status[7:5];
	sp2 <= sp1;
	
	if(sp2 == sp1) speed <= sp2;
end

reg uspeed;
always @(posedge CLK_50M) begin
	reg sp1, sp2;
	
	sp1 <= ~status[10];
	sp2 <= sp1;
	
	if(sp2 == sp1) uspeed <= sp2;
end

(* romstyle = "logic" *) wire [31:0] clk_rate[5]  = '{90000000, 100000000, 15000000, 30000000, 56250000};
(* romstyle = "logic" *) wire [17:0] speed_div[5] = '{  'h0505,   'h20504,   'h1e1e,   'h0f0f,   'h0808};

always @(posedge CLK_50M) begin
	reg [2:0] old_speed = 0;
	reg [2:0] state = 0;
	reg       old_uspeed = 0;

	if(!cfg_waitrequest) begin
		
		cfg_write <= 0;
		
		if(pll_locked) begin
			if(state) state<=state+1'd1;
			case(state)
				0: begin
						old_speed <= speed;
						old_uspeed <= uspeed;
						if(old_speed != speed || old_uspeed != uspeed) state <= 1;
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
						cfg_data <= uspeed ? 32'h4F4F4 : 32'h61716;
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

`endif

wire        ps2_reset_n;

wire        speaker_ena, speaker_out;
wire [15:0] sb_out_l, sb_out_r;

wire        device;

wire        de;
reg  [15:0] ded;
always @(posedge CLK_VIDEO) if(CE_PIXEL) ded <= (ded<<1) | de;

assign VGA_F1 = 0;
assign VGA_SL = 0;
assign CLK_VIDEO = clk_sys;

wire [7:0] r,g,b;
wire       HSync,VSync;

video_cleaner video_cleaner
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(CE_PIXEL),

	.R(r),
	.G(g),
	.B(b),

	.HSync(HSync),
	.VSync(VSync),
	.DE_in(de & ded[15]),

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
	.RGB_in({R,G,B}),

	.HSync_out(VGA_HS),
	.VSync_out(VGA_VS),
	.DE_out(VGA_DE),
	.RGB_out({VGA_R,VGA_G,VGA_B})
);

wire  [7:0] vga_pal_a;
wire [17:0] vga_pal_d;
wire        vga_pal_we;

wire [19:0] vga_start_addr;
wire  [5:0] vga_wr_seg;
wire  [5:0] vga_rd_seg;
wire  [8:0] vga_width;
wire  [8:0] vga_stride;
wire [10:0] vga_height;
wire  [3:0] vga_flags;
wire        vga_off;

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

system u0
(
	.clk_sys_clk          (clk_sys),
	.clk_uart_clk         (clk_uart),
	.clk_opl_clk          (clk_opl),

	.qsys_reset_reset     (sys_reset),

	.video_ce             (CE_PIXEL),
	.video_mode           (status[4]),
	.video_blank_n        (de),
	.video_hsync          (HSync),
	.video_vsync          (VSync),
	.video_r              (r),
	.video_g              (g),
	.video_b              (b),
	.video_memmode        (vga_mode),

	.video_pal_a          (vga_pal_a),
	.video_pal_d          (vga_pal_d),
	.video_pal_we         (vga_pal_we),
	.video_start_addr     (vga_start_addr),
	.video_wr_seg         (vga_wr_seg),
	.video_rd_seg         (vga_rd_seg),
	.video_width          (vga_width),
	.video_stride         (vga_stride),
	.video_height         (vga_height),
	.video_flags          (vga_flags),
	.video_off            (vga_off),

	.sound_sample_l       (sb_out_l),
	.sound_sample_r       (sb_out_r),
	.sound_fm_mode        (status[3]),
	
	.speaker_enable       (speaker_ena),
	.speaker_out          (speaker_out),


	.ps2_misc_a20_enable  (),
	.ps2_misc_reset_n     (ps2_reset_n),

	.ps2_kbclk_in         (ps2_kbd_clk_out),
	.ps2_kbdat_in         (ps2_kbd_data_out),
	.ps2_kbclk_out        (ps2_kbd_clk_in),
	.ps2_kbdat_out        (ps2_kbd_data_in),

	.ps2_mouseclk_in      (ps2_mouse_clk_out),
	.ps2_mousedat_in      (ps2_mouse_data_out),
	.ps2_mouseclk_out     (ps2_mouse_clk_in),
	.ps2_mousedat_out     (ps2_mouse_data_in),

	.joystick_dig_1       (joystick_0),
	.joystick_dig_2       (joystick_1),
	.joystick_ana_1       (joystick_analog_0),
	.joystick_ana_2       (joystick_analog_1),
	.joystick_mode        (status[13:12]),

	.cpu_reset_reset      (cpu_reset),

	.mem_address          (mem_address),
	.mem_read             (mem_read),
	.mem_waitrequest      (mem_waitrequest),
	.mem_readdata         (mem_readdata),
	.mem_write            (mem_write),
	.mem_writedata        (mem_writedata),
	.mem_readdatavalid    (mem_readdatavalid),
	.mem_byteenable       (mem_byteenable),
	.mem_burstcount       (mem_burstcount),

	.vga_address          (vga_address),
	.vga_read             (vga_read),
	.vga_readdata         (vga_readdata),
	.vga_write            (vga_write),
	.vga_writedata        (vga_writedata),

	.rtc_memcfg           (memcfg),

	.mgmt_waitrequest     (mgmt_wait),
	.mgmt_readdata        (mgmt_data),
	.mgmt_readdatavalid   (mgmt_valid),
	.mgmt_burstcount      (1),
	.mgmt_writedata       (mgmt_dout),
	.mgmt_address         (mgmt_addr),
	.mgmt_write           (mgmt_we),
	.mgmt_read            (mgmt_rd),
	.mgmt_byteenable      (4'b1111),
	.mgmt_debugaccess     (0),
	
	.disk_op_read         (mgmt_req[0]),
	.disk_op_write        (mgmt_req[1]),
	.disk_op_device       (device),
	.disk_result_ok       (mgmt_status[0]),
	.disk_result_error    (mgmt_status[1]),
	
	.uart_h_cts_n         (UART_CTS),
	.uart_h_rts_n         (UART_RTS),
	.uart_s_sin           (UART_RXD),
	.uart_s_sout          (UART_TXD),
	.uart_h_dsr_n         (UART_DSR),
	.uart_h_dtr_n         (UART_DTR),
	.uart_h_dcd_n         (UART_DSR),
	.uart_h_ri_n          (1),
	.uart_s_sout_oe       (),
	.uart_h_out1_n        (),
	.uart_h_out2_n        ()
);


wire [29:0] mem_address;
wire [31:0] mem_writedata;
wire [31:0] mem_readdata;
wire [3:0]  mem_byteenable;
wire [3:0]  mem_burstcount;
wire        mem_write;
wire        mem_read;
wire        mem_waitrequest;
wire        mem_readdatavalid;

wire [16:0] vga_address;
wire  [7:0] vga_readdata;
wire  [7:0] vga_writedata;
wire        vga_read;
wire        vga_write;
wire  [2:0] vga_mode;

assign      DDRAM_ADDR[28:25] = 4'h3;
assign      DDRAM_CLK = clk_sys;

l2_cache cache
(
	.CLK              (clk_sys            ),
	.RESET            (cpu_reset          ),

	.CPU_ADDR         (mem_address        ),
	.CPU_DIN          (mem_writedata      ),
	.CPU_DOUT         (mem_readdata       ),
	.CPU_DOUT_READY   (mem_readdatavalid  ),
	.CPU_BE           (mem_byteenable     ),
	.CPU_BURSTCNT     (mem_burstcount     ),
	.CPU_BUSY         (mem_waitrequest    ),
	.CPU_RD           (mem_read           ),
	.CPU_WE           (mem_write          ),

	.DDRAM_ADDR       (DDRAM_ADDR[24:0]   ),
	.DDRAM_DIN        (DDRAM_DIN          ),
	.DDRAM_DOUT       (DDRAM_DOUT         ),
	.DDRAM_DOUT_READY (DDRAM_DOUT_READY   ),
	.DDRAM_BE         (DDRAM_BE           ),
	.DDRAM_BURSTCNT   (DDRAM_BURSTCNT     ),
	.DDRAM_BUSY       (DDRAM_BUSY         ),
	.DDRAM_RD         (DDRAM_RD           ),
	.DDRAM_WE         (DDRAM_WE           ),

	.VGA_ADDR         (vga_address        ),
	.VGA_DIN          (vga_readdata       ),
	.VGA_DOUT         (vga_writedata      ),
	.VGA_RD           (vga_read           ),
	.VGA_WE           (vga_write          ),
	.VGA_MODE         (vga_mode           ),

	.VGA_WR_SEG       (vga_wr_seg         ),
	.VGA_RD_SEG       (vga_rd_seg         ),
	.VGA_FB_EN        (fb_en              )
);

reg memcfg = 0;
always @(posedge clk_sys) if(cpu_reset) memcfg <= status[11];

wire       sys_reset = rst_q[7] | ~init_reset_n | RESET;
wire       cpu_reset = cpu_rst1 | sys_reset;

reg  [7:0] rst_q;
reg        old_rst1 = 0;
reg        old_rst2 = 0;
reg        cpu_rst1 = 0;
reg        init_reset_n = 0;

always @(posedge clk_sys) begin
	old_rst1 <= status[0];
	old_rst2 <= old_rst1;

	cpu_rst1 <= buttons[1] | status[0] | ~ps2_reset_n;

	rst_q <= rst_q << 1;
	if(~old_rst2 & old_rst1) begin
		rst_q <= '1;
		init_reset_n <= 1;
	end
end

always @(posedge clk_sys) begin
	reg old_reset;
	reg [2:0] state = 0;

	old_reset <= RESET;

	if(~mgmt_wait) begin
		{mgmt_rd, mgmt_we} <= 0;
		case(state)
			1: begin
					mgmt_rd <= 1;
					state <= state + 1'd1;
				end
			2: if(mgmt_valid) begin
					mgmt_din <= mgmt_data;
					ioctl_wait <= 0;
					state <= 0;
				end
			3: begin
					mgmt_we <= 1;
					state <= state + 1'd1;
				end
			4: begin
					ioctl_wait <= 0;
					state <= 0;
				end
		endcase
	end

	if(mgmt_hrd) begin
		ioctl_wait <= 1;
		state <= 1;
	end
	if(mgmt_hwr) begin
		ioctl_wait <= 1;
		state <= 3;
	end
	
	if(~old_reset && RESET) {state,ioctl_wait} <= 0;
end

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
