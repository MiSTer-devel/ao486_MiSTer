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

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 6'b111111;
assign SDRAM_DQ  ='Z;
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
	"O1,Aspect ratio,4:3,16:9;",
	"O4,VSync,60Hz,Variable;",
	"O3,FM mode,OPL2,OPL3;",
	"-;",
	"OX2,Boot order,FDD/HDD,HDD/FDD;",
	"R0,Reset and apply HDD;",
	"J,Button 1,Button 2;",
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

wire [31:0] dma_din;
wire [31:0] dma_dout;
wire [31:0] dma_addr;
wire        dma_rd;
wire        dma_wr;
wire  [1:0] dma_status;
wire  [1:0] dma_req;

wire  [5:0] joystick_0;
wire  [5:0] joystick_1;
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

wire [35:0] EXT_BUS;
hps_ext hps_ext
(
	.clk_sys(clk_sys),
	.EXT_BUS(EXT_BUS),

	.io_wait(ioctl_wait),

	.dma_din(dma_din),
	.dma_dout(dma_dout),
	.dma_addr(dma_addr),
	.dma_rd(dma_rd),
	.dma_wr(dma_wr),
	.dma_req(dma_req),
	.dma_status(dma_status)
);

//------------------------------------------------------------------------------

wire clk_sys, clk_uart;
pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_sys),
	.outclk_1(clk_uart)
);

wire        mem_wait;
wire        mem_valid;
wire [31:0] mem_data;
reg         mem_we = 0;
reg         mem_rd = 0;

wire [31:0] dram_addr;
assign      DDRAM_ADDR = dram_addr[31:3];
assign      DDRAM_CLK = clk_sys;

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

system u0
(
	.clk_opl_clk          (CLK_50M),
	.clk_sys_clk          (clk_sys),
	.clk_uart_clk         (clk_uart),

	.qsys_reset_reset     (sys_reset),

	.vga_ce               (CE_PIXEL),
	.vga_mode             (status[4]),
	.vga_blank_n          (de),
	.vga_hsync            (HSync),
	.vga_vsync            (VSync),
	.vga_r                (r),
	.vga_g                (g),
	.vga_b                (b),

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

	.cpu_reset_reset      (cpu_reset),

	.ddram_address        (DDRAM_IN_ADDR),
	.ddram_read           (DDRAM_IN_RD),
	.ddram_waitrequest    (DDRAM_IN_BUSY),
	.ddram_readdata       (DDRAM_IN_DOUT),
	.ddram_write          (DDRAM_IN_WE),
	.ddram_writedata      (DDRAM_IN_DIN),
	.ddram_readdatavalid  (DDRAM_IN_DOUT_READY),
	.ddram_byteenable     (DDRAM_IN_BE),
	.ddram_burstcount     (DDRAM_IN_BURSTCNT),

	.mem_waitrequest      (mem_wait),
	.mem_readdata         (mem_data),
	.mem_readdatavalid    (mem_valid),
	.mem_burstcount       (1),
	.mem_writedata        (dma_dout),
	.mem_address          (dma_addr),
	.mem_write            (mem_we),
	.mem_read             (mem_rd),
	.mem_byteenable       (4'b1111),
	.mem_debugaccess      (0),
	
	.disk_op_read         (dma_req[0]),
	.disk_op_write        (dma_req[1]),
	.disk_op_device       (device),
	.disk_result_ok       (dma_status[0]),
	.disk_result_error    (dma_status[1]),
	
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

wire        DDRAM_IN_BUSY;      
wire [63:0] DDRAM_IN_DOUT;      
wire        DDRAM_IN_DOUT_READY;
wire  [7:0] DDRAM_IN_BURSTCNT;  
wire [31:0] DDRAM_IN_ADDR;      
wire        DDRAM_IN_RD;        
wire [63:0] DDRAM_IN_DIN;       
wire  [7:0] DDRAM_IN_BE;        
wire        DDRAM_IN_WE;        

ddrram_cache cache_0
   (
      .DDRAM_CLK            (DDRAM_CLK),
      .RESET                (sys_reset),
                            
      .DDRAM_OUT_BUSY       (DDRAM_BUSY      ),
      .DDRAM_OUT_DOUT       (DDRAM_DOUT      ),
      .DDRAM_OUT_DOUT_READY (DDRAM_DOUT_READY),
      .DDRAM_OUT_BURSTCNT   (DDRAM_BURSTCNT  ),
      .DDRAM_OUT_ADDR       (dram_addr       ),
      .DDRAM_OUT_RD         (DDRAM_RD        ),
      .DDRAM_OUT_DIN        (DDRAM_DIN       ),
      .DDRAM_OUT_BE         (DDRAM_BE        ),
      .DDRAM_OUT_WE         (DDRAM_WE        ),

      .DDRAM_IN_BUSY        (DDRAM_IN_BUSY      ),
      .DDRAM_IN_DOUT        (DDRAM_IN_DOUT      ),
      .DDRAM_IN_DOUT_READY  (DDRAM_IN_DOUT_READY),
      .DDRAM_IN_BURSTCNT    (DDRAM_IN_BURSTCNT  ),
      .DDRAM_IN_ADDR        (DDRAM_IN_ADDR      ),
      .DDRAM_IN_RD          (DDRAM_IN_RD        ),
      .DDRAM_IN_DIN         (DDRAM_IN_DIN       ),
      .DDRAM_IN_BE          (DDRAM_IN_BE        ),
      .DDRAM_IN_WE          (DDRAM_IN_WE        )
);

wire       uart_h_dtr_n;

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

	if(~mem_wait) begin
		{mem_rd, mem_we} <= 0;
		case(state)
			1: begin
					mem_rd <= 1;
					state <= state + 1'd1;
				end
			2: if(mem_valid) begin
					dma_din <= mem_data;
					ioctl_wait <= 0;
					state <= 0;
				end
			3: begin
					mem_we <= 1;
					state <= state + 1'd1;
				end
			4: begin
					ioctl_wait <= 0;
					state <= 0;
				end
		endcase
	end

	if(dma_rd) begin
		ioctl_wait <= 1;
		state <= 1;
	end
	if(dma_wr) begin
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
