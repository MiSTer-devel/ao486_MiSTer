//============================================================================
//
//  DE10-nano HAL top module
//  (c)2017 Sorgelig
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

module sys_top
(
	/////////// CLOCK //////////
	input         FPGA_CLK1_50,
	input         FPGA_CLK2_50,
	input         FPGA_CLK3_50,

	//////////// VGA ///////////
	output  [5:0] VGA_R,
	output  [5:0] VGA_G,
	output  [5:0] VGA_B,
	output		  VGA_HS,
	output		  VGA_VS,
	input         VGA_EN,

	/////////// AUDIO //////////
	output		  AUDIO_L,
	output		  AUDIO_R,
	output		  AUDIO_SPDIF,

	//////////// HDMI //////////
	output        HDMI_I2C_SCL,
	inout         HDMI_I2C_SDA,

	output        HDMI_MCLK,
	output        HDMI_SCLK,
	output        HDMI_LRCLK,
	output        HDMI_I2S,

	output        HDMI_TX_CLK,
	output        HDMI_TX_DE,
	output [23:0] HDMI_TX_D,
	output        HDMI_TX_HS,
	output        HDMI_TX_VS,

	//////////// SDR ///////////
	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,

	//////////// I/O ///////////
	output        LED_USER,
	output        LED_HDD,
	output        LED_POWER,
	input         BTN_USER,
	input         BTN_OSD,
	input         BTN_RESET,

	////////// MB KEY ///////////
	input   [1:0] KEY,

	////////// MB LED ///////////
	output  [7:0] LED
);


//////////////////////////  LEDs  ///////////////////////////////////////

wire led_p =  led_power[1] ? ~led_power[0] : 1'b0;
wire led_d =  led_disk[1]  ? ~led_disk[0]  : ~(led_disk[0] | gp_out[29]);
wire led_u = ~led_user;

assign LED_POWER = led_p ? 1'bZ : 1'b0;
assign LED_HDD   = led_d ? 1'bZ : 1'b0;
assign LED_USER  = led_u ? 1'bZ : 1'b0;

//LEDs on main board
assign LED = {3'b000, ~led_p, 1'b0, ~led_d, 1'b0, ~led_u};


//////////////////////////  Buttons  ///////////////////////////////////
reg btn_user, btn_osd;
always @(posedge FPGA_CLK2_50) begin
	integer div;
	reg [7:0] deb_user;
	reg [7:0] deb_osd;

	div <= div + 1'b1;
	if(div > 100000) div <= 0;
	
	if(!div) begin
		deb_user <= {deb_user[6:0], ~(BTN_USER & KEY[1])};
		if(&deb_user) btn_user <= 1;
		if(!deb_user) btn_user <= 0;

		deb_osd <= {deb_osd[6:0], ~(BTN_OSD & KEY[0])};
		if(&deb_osd) btn_osd <= 1;
		if(!deb_osd) btn_osd <= 0;
	end
end

reg btn_reset = 1;
always @(posedge FPGA_CLK2_50) btn_reset <= BTN_RESET;


/////////////////////////  HPS I/O  /////////////////////////////////////

// gp_in[31] = 0 - quick flag that FPGA is initialized (HPS reads 1 when FPGA is not in user mode)
//                 used to avoid lockups while JTAG loading
wire [31:0] gp_in = {1'b0, btn_user, btn_osd, 9'd0, io_ver, io_ack, io_wide, io_dout};
wire [31:0] gp_out;

wire  [1:0] io_ver    = 1; // 0 - standard MiST I/O (for quick porting of complex MiST cores). 1 - optimized HPS I/O. 2,3 - reserved for future.
wire        io_wait;
wire        io_wide;
wire [15:0] io_dout;                  
wire [15:0] io_din    = gp_outr[15:0];
wire        io_clk    = gp_outr[17];
wire        io_fpga   = gp_outr[18];
wire        io_osd    = gp_outr[19];
wire        io_uio    = gp_outr[20];
//wire        io_sdd    = gp_outr[21]; // used only in ST core

reg  io_ack;
reg  rack;
wire io_strobe = ~rack & io_clk;

always @(posedge clk_sys) begin
	if(~io_wait | io_strobe) begin
		rack <= io_clk;
		io_ack <= rack;
	end
end

reg [31:0] gp_outr;
always @(posedge clk_sys) begin
	reg [31:0] gp_outd;
	gp_outr <= gp_outd;
	gp_outd <= gp_out;
end

wire  [7:0] core_type  = 'hA4; // A4 - generic core.

// HPS will not communicate to core if magic is different
wire [31:0] core_magic = {24'h5CA623, core_type};

cyclonev_hps_interface_mpu_general_purpose h2f_gp
(
	.gp_in({~gp_out[31] ? core_magic : gp_in}),
	.gp_out(gp_out)
);


reg [15:0] cfg;

reg  cfg_ready = 0;
wire audio_96k = cfg[6];
wire ypbpr_en  = cfg[5];
wire csync     = cfg[3];
`ifndef LITE
wire vga_scaler= cfg[2];
`endif

always@(posedge clk_sys) begin
	reg  [7:0] cmd;
	reg        has_cmd;
	reg        old_strobe;

	old_strobe <= io_strobe;

	if(~io_uio) has_cmd <= 0;
	else
	if(~old_strobe & io_strobe) begin
		if(!has_cmd) begin
			has_cmd <= 1;
			cmd <= io_din[7:0];
		end
		else
		if(cmd == 1) begin
			cfg <= io_din;
			cfg_ready <= 1;
		end
	end
end


///////////////////////////  RESET  ///////////////////////////////////

reg reset_req = 0;
always @(posedge FPGA_CLK2_50) begin
	reg [1:0] resetd, resetd2;
	reg       old_reset;

	//latch the reset
	old_reset <= reset;
	if(~old_reset & reset) reset_req <= 1;

	//special combination to set/clear the reset
	//preventing of accidental reset control
	if(resetd==1) reset_req <= 1;
	if(resetd==2 && resetd2==0) reset_req <= 0;

	resetd  <= gp_out[31:30];
	resetd2 <= resetd;
end


///////////////////////// VIP version  ///////////////////////////////

`ifndef LITE

wire reset;
vip vip
(
	//Reset/Clock
	.reset_reset_req(reset_req),
	.reset_reset(reset),

	//DE10-nano has no reset signal on GPIO, so core has to emulate cold reset button.
	.reset_cold_req(~btn_reset),
	.reset_warm_req(0),

	//control
	.ctl_address(ctl_address),
	.ctl_write(ctl_write),
	.ctl_writedata(ctl_writedata),
	.ctl_waitrequest(ctl_waitrequest),
	.ctl_clock(ctl_clk),
	.ctl_reset(ctl_reset),

	//64-bit DDR3 RAM access
	.ramclk1_clk(ram_clk),
	.ram1_address(ram_address),
	.ram1_burstcount(ram_burstcount),
	.ram1_waitrequest(ram_waitrequest),
	.ram1_readdata(ram_readdata),
	.ram1_readdatavalid(ram_readdatavalid),
	.ram1_read(ram_read),
	.ram1_writedata(ram_writedata),
	.ram1_byteenable(ram_byteenable),
	.ram1_write(ram_write),

	//Spare 64-bit DDR3 RAM access
	//currently unused
	//can combine with ram1 to make a wider RAM bus (although will increase the latency)
	.ramclk2_clk(0),
	.ram2_address(0),
	.ram2_burstcount(0),
	.ram2_waitrequest(),
	.ram2_readdata(),
	.ram2_readdatavalid(),
	.ram2_read(0),
	.ram2_writedata(0),
	.ram2_byteenable(0),
	.ram2_write(0),

	//Video input
	.in_vid_clk(clk_vid),
	.in_vid_data({r_out, g_out, b_out}),
	.in_vid_de(de),
	.in_vid_v_sync(vs),
	.in_vid_h_sync(hs),
	.in_vid_datavalid(ce_pix),
	.in_vid_locked(1),
	.in_vid_f(0),
	.in_vid_color_encoding(0),
	.in_vid_bit_width(0),

	//HDMI output
	.hdmi_vid_clk(~HDMI_TX_CLK),
	.hdmi_vid_data(hdmi_data),
	.hdmi_vid_datavalid(HDMI_TX_DE),
	.hdmi_vid_v_sync(HDMI_TX_VS),
	.hdmi_vid_h_sync(HDMI_TX_HS)
);

wire  [8:0] ctl_address;
wire        ctl_write;
wire [31:0] ctl_writedata;
wire        ctl_waitrequest;
wire        ctl_reset;
wire        ctl_clk;
wire  [7:0] ARX, ARY;

vip_config vip_config
(
	.clk(ctl_clk),
	.reset(ctl_reset),

	.ARX(ARX),
	.ARY(ARY),

	.address(ctl_address),
	.write(ctl_write),
	.writedata(ctl_writedata),
	.waitrequest(ctl_waitrequest)
);
`endif


/////////////////////////  Lite version  ////////////////////////////////

`ifdef LITE

wire        INTERLACED = 0;
wire [11:0] V_TOTAL_0 = 750;
wire [11:0] V_FP_0 = 5;
wire [11:0] V_BP_0 = 20;
wire [11:0] V_SYNC_0 = 5;
wire [11:0] V_TOTAL_1 = 0;
wire [11:0] V_FP_1 = 0;
wire [11:0] V_BP_1 = 0;
wire [11:0] V_SYNC_1 = 0;
wire [11:0] H_TOTAL = 1650;
wire [11:0] H_FP = 110;
wire [11:0] H_BP = 220;
wire [11:0] H_SYNC = 40;
wire [11:0] HV_OFFSET_0 = 0;
wire [11:0] HV_OFFSET_1 = 0;

wire [11:0] x;
wire [12:0] y;

sync_vg #(.X_BITS(12), .Y_BITS(12)) sync_vg
(
	.clk(HDMI_TX_CLK),
	.reset(reset),
	.interlaced(INTERLACED),
	.clk_out(), // inverted output clock - unconnected
	.v_total_0(V_TOTAL_0),
	.v_fp_0(V_FP_0),
	.v_bp_0(V_BP_0),
	.v_sync_0(V_SYNC_0),
	.v_total_1(V_TOTAL_1),
	.v_fp_1(V_FP_1),
	.v_bp_1(V_BP_1),
	.v_sync_1(V_SYNC_1),
	.h_total(H_TOTAL),
	.h_fp(H_FP),
	.h_bp(H_BP),
	.h_sync(H_SYNC),
	.hv_offset_0(HV_OFFSET_0),
	.hv_offset_1(HV_OFFSET_1),
	.vde_out(vde),
	.hde_out(hde),
	.vs_out(vs_hdmi),
	.v_count_out(),
	.h_count_out(),
	.x_out(x),
	.y_out(y),
	.hs_out(hs_hdmi),
	.field_out(field)
);

wire vde, hde;
wire vs_hdmi;
wire hs_hdmi;
wire field;

pattern_vg
#(
	.B(8), // Bits per channel
	.X_BITS(12),
	.Y_BITS(12),
	.FRACTIONAL_BITS(12) // Number of fractional bits for ramp pattern
)
pattern_vg
(
	.reset(reset),
	.clk_in(HDMI_TX_CLK),
	.x(x),
	.y(y[11:0]),
	.vn_in(vs_hdmi),
	.hn_in(hs_hdmi),
	.dn_in(vde & hde),
	.r_in(0),
	.g_in(0),
	.b_in(0),
	.vn_out(HDMI_TX_VS),
	.hn_out(HDMI_TX_HS),
	.den_out(HDMI_TX_DE),
	.r_out(hdmi_data[23:16]),
	.g_out(hdmi_data[15:8]),
	.b_out(hdmi_data[7:0]),
	.total_active_pix(H_TOTAL - (H_FP + H_BP + H_SYNC)),
	.total_active_lines(INTERLACED ? (V_TOTAL_0 - (V_FP_0 + V_BP_0 + V_SYNC_0)) + (V_TOTAL_1 - (V_FP_1 + V_BP_1 + V_SYNC_1)) : (V_TOTAL_0 - (V_FP_0 + V_BP_0 + V_SYNC_0))), // originally: 13'd480
	.pattern(4),
	.ramp_step(20'h0333)
);

wire reset;
sysmem_lite sysmem
(
	//Reset/Clock
	.reset_reset_req(reset_req),
	.reset_reset(reset),

	//DE10-nano has no reset signal on GPIO, so core has to emulate cold reset button.
	.reset_cold_req(~btn_reset),
	.reset_warm_req(0),

	//64-bit DDR3 RAM access
	.ramclk1_clk(ram_clk),
	.ram1_address(ram_address),
	.ram1_burstcount(ram_burstcount),
	.ram1_waitrequest(ram_waitrequest),
	.ram1_readdata(ram_readdata),
	.ram1_readdatavalid(ram_readdatavalid),
	.ram1_read(ram_read),
	.ram1_writedata(ram_writedata),
	.ram1_byteenable(ram_byteenable),
	.ram1_write(ram_write),

	//Spare 64-bit DDR3 RAM access
	//currently unused
	//can combine with ram1 to make a wider RAM bus (although will increase the latency)
	.ramclk2_clk(0),
	.ram2_address(0),
	.ram2_burstcount(0),
	.ram2_waitrequest(),
	.ram2_readdata(),
	.ram2_readdatavalid(),
	.ram2_read(0),
	.ram2_writedata(0),
	.ram2_byteenable(0),
	.ram2_write(0)
);

`endif


/////////////////////////  HDMI output  /////////////////////////////////

pll_hdmi pll_hdmi
(
	.refclk(FPGA_CLK1_50),
	.rst(reset),
	.outclk_0(HDMI_TX_CLK)
);

hdmi_config hdmi_config
(
	.iCLK(FPGA_CLK1_50),
	.iRST_N(cfg_ready),
	.I2C_SCL(HDMI_I2C_SCL),
	.I2C_SDA(HDMI_I2C_SDA),

	.audio_48k(~audio_96k),
	.iRES(4), // 720p
	.iAR(1)   // Aspect Ratio
);

wire [23:0] hdmi_data;
osd hdmi_osd
(
	.clk_sys(clk_sys),

	.io_osd(io_osd),
	.io_strobe(io_strobe),
	.io_din(io_din[7:0]),

	.clk_video(HDMI_TX_CLK),
	.din(hdmi_data),
	.dout(HDMI_TX_D),
	.de(HDMI_TX_DE)
);

assign HDMI_MCLK = 0;
i2s i2s
(
	.reset(~cfg_ready),
	.clk_sys(FPGA_CLK1_50),
	.half_rate(~audio_96k),

	.sclk(HDMI_SCLK),
	.lrclk(HDMI_LRCLK),
	.sdata(HDMI_I2S),

	//Could inverse the MSB but it will shift 0 level to -MAX level
	.left_chan (audio_l >> !audio_s),
	.right_chan(audio_r >> !audio_s)
);


/////////////////////////  VGA output  //////////////////////////////////

wire [23:0] vga_q;
osd vga_osd
(
	.clk_sys(clk_sys),

	.io_osd(io_osd),
	.io_strobe(io_strobe),
	.io_din(io_din[7:0]),

	.clk_video(clk_vid),
	.din(de ? {r_out, g_out, b_out} : 24'd0),
	.dout(vga_q),
	.de(de)
);

wire [23:0] vga_o;

vga_out vga_out
(
	.ypbpr_full(1),
	.ypbpr_en(ypbpr_en),
	.dout(vga_o),
`ifdef LITE
	.din(vga_q)
`else
	.din(vga_scaler ? HDMI_TX_D : vga_q)
`endif
);

`ifdef LITE
	wire vs1 = vs;
	wire hs1 = hs;
`else
	wire vs1 = vga_scaler ? HDMI_TX_VS : vs;
	wire hs1 = vga_scaler ? HDMI_TX_HS : hs;
`endif

assign VGA_VS = VGA_EN ? 1'bZ      : csync ?     1'b1     : ~vs1;
assign VGA_HS = VGA_EN ? 1'bZ      : csync ? ~(vs1 ^ hs1) : ~hs1;
assign VGA_R  = VGA_EN ? 6'bZZZZZZ : vga_o[23:18];
assign VGA_G  = VGA_EN ? 6'bZZZZZZ : vga_o[15:10];
assign VGA_B  = VGA_EN ? 6'bZZZZZZ : vga_o[7:2];


/////////////////////////  Audio output  ////////////////////////////////

sigma_delta_dac #(15) dac_l
(
	.CLK(FPGA_CLK3_50),
	.RESET(reset),
	.DACin({audio_l[15] ^ audio_s, audio_l[14:0]}),
	.DACout(AUDIO_L)
);

sigma_delta_dac #(15) dac_r
(
	.CLK(FPGA_CLK3_50),
	.RESET(reset),
	.DACin({audio_r[15] ^ audio_s, audio_r[14:0]}),
	.DACout(AUDIO_R)
);

spdif toslink
(
	.clk_i(FPGA_CLK3_50),

	.rst_i(reset),
	.half_rate(0),

	.audio_l(audio_l >> !audio_s),
	.audio_r(audio_r >> !audio_s),

	.spdif_o(AUDIO_SPDIF)
);


///////////////////  User module connection ////////////////////////////

wire [15:0] audio_l, audio_r;
wire        audio_s;
wire  [7:0] r_out, g_out, b_out;
wire        vs, hs, de;
wire        clk_sys, clk_vid, ce_pix;

wire        ram_clk;
wire [28:0] ram_address;
wire [7:0]  ram_burstcount;
wire        ram_waitrequest;
wire [63:0] ram_readdata;
wire        ram_readdatavalid;
wire        ram_read;
wire [63:0] ram_writedata;
wire [7:0]  ram_byteenable;
wire        ram_write;

wire        led_user;
wire  [1:0] led_power;
wire  [1:0] led_disk;

emu emu
(
	.CLK_50M(FPGA_CLK3_50),
	.RESET(reset),
	.HPS_BUS({io_wait, clk_sys, io_fpga, io_uio, io_strobe, io_wide, io_din, io_dout}),

	.CLK_VIDEO(clk_vid),
	.CE_PIXEL(ce_pix),

	.VGA_R(r_out),
	.VGA_G(g_out),
	.VGA_B(b_out),
	.VGA_HS(hs),
	.VGA_VS(vs),
	.VGA_DE(de),

	.LED_USER(led_user),
	.LED_POWER(led_power),
	.LED_DISK(led_disk),

`ifndef LITE
	.VIDEO_ARX(ARX),
	.VIDEO_ARY(ARY),
`endif

	.AUDIO_L(audio_l),
	.AUDIO_R(audio_r),
	.AUDIO_S(audio_s),
	.TAPE_IN(0),

	.DDRAM_CLK(ram_clk),
	.DDRAM_ADDR(ram_address),
	.DDRAM_BURSTCNT(ram_burstcount),
	.DDRAM_BUSY(ram_waitrequest),
	.DDRAM_DOUT(ram_readdata),
	.DDRAM_DOUT_READY(ram_readdatavalid),
	.DDRAM_RD(ram_read),
	.DDRAM_DIN(ram_writedata),
	.DDRAM_BE(ram_byteenable),
	.DDRAM_WE(ram_write),

	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE)
);

endmodule
