//============================================================================
//
//  MiSTer hardware abstraction module
//  (c)2017,2018 Sorgelig
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
	inout         VGA_HS,  // VGA_HS is secondary SD card detect when VGA_EN = 1 (inactive)
	output		  VGA_VS,
	input         VGA_EN,  // active low

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
	
	input         HDMI_TX_INT,

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

	//////////// SDIO ///////////
	inout   [3:0] SDIO_DAT,
	inout         SDIO_CMD,
	output        SDIO_CLK,
	input         SDIO_CD,

	////////// MB KEY ///////////
	input   [1:0] KEY,

	////////// MB SWITCH ////////
	input   [3:0] SW,

	////////// MB LED ///////////
	output  [7:0] LED
);


assign SDIO_DAT[2:1] = 2'bZZ;


//////////////////////////  LEDs  ///////////////////////////////////////

reg [7:0] led_overtake = 0;
reg [7:0] led_state    = 0;

wire led_p =  led_power[1] ? ~led_power[0] : 1'b0;
wire led_d =  led_disk[1]  ? ~led_disk[0]  : ~(led_disk[0] | gp_out[29]);
wire led_u = ~led_user;

assign LED_POWER = led_p ? 1'bZ : 1'b0;
assign LED_HDD   = led_d ? 1'bZ : 1'b0;
assign LED_USER  = led_u ? 1'bZ : 1'b0;

//LEDs on main board
assign LED = (led_overtake & led_state) | (~led_overtake & {3'b000, ~led_p, 1'b0, ~led_d, 1'b0, ~led_u});


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

reg  cfg_got   = 0;
reg  cfg_set   = 0;
//wire [2:0] hdmi_res  = cfg[10:8];
wire dvi_mode  = cfg[7];
wire audio_96k = cfg[6];
wire ypbpr_en  = cfg[5];
wire csync     = cfg[3];
wire vga_scaler= 1; //cfg[2];

reg        cfg_custom_t = 0;
reg  [5:0] cfg_custom_p1;
reg [31:0] cfg_custom_p2;

reg  [4:0] vol_att = 0;

reg  [6:0] coef_addr;
reg  [8:0] coef_data;
reg        coef_wr = 0;

wire  [7:0] ARX, ARY;
reg  [11:0] VSET = 0;
reg   [2:0] scaler_flt;
reg         lowlat = 0;

always@(posedge clk_sys) begin
	reg  [7:0] cmd;
	reg        has_cmd;
	reg        old_strobe;
	reg  [7:0] cnt = 0;

	old_strobe <= io_strobe;
	coef_wr <= 0;

	if(~io_uio) begin
		has_cmd <= 0;
	end
	else
	if(~old_strobe & io_strobe) begin
		if(!has_cmd) begin
			has_cmd <= 1;
			cmd <= io_din[7:0];
			cnt <= 0;
		end
		else begin
			if(cmd == 1) begin
				cfg <= io_din;
				cfg_set <= 1;
			end
			if(cmd == 'h20) begin
				cfg_set <= 0;
				cnt <= cnt + 1'd1;
				if(cnt<8) begin
					case(cnt)
						0: if(WIDTH  != io_din[11:0]) begin WIDTH  <= io_din[11:0]; end
						1: if(HFP    != io_din[11:0]) begin HFP    <= io_din[11:0]; end
						2: if(HS     != io_din[11:0]) begin HS     <= io_din[11:0]; end
						3: if(HBP    != io_din[11:0]) begin HBP    <= io_din[11:0]; end
						4: if(HEIGHT != io_din[11:0]) begin HEIGHT <= io_din[11:0]; end
						5: if(VFP    != io_din[11:0]) begin VFP    <= io_din[11:0]; end
						6: if(VS     != io_din[11:0]) begin VS     <= io_din[11:0]; end
						7: if(VBP    != io_din[11:0]) begin VBP    <= io_din[11:0]; end
					endcase
					if(cnt == 1) begin
						cfg_custom_p1 <= 0;
						cfg_custom_p2 <= 0;
						cfg_custom_t <= ~cfg_custom_t;
					end
				end
				else begin
					if(cnt[1:0]==0) cfg_custom_p1 <= io_din[5:0];
					if(cnt[1:0]==1) cfg_custom_p2[15:0]  <= io_din;
					if(cnt[1:0]==2) begin
						cfg_custom_p2[31:16] <= io_din;
						cfg_custom_t <= ~cfg_custom_t;
						cnt[2:0] <= 3'b100;
					end
					if(cnt == 8) lowlat <= io_din[15];
				end
			end
			if(cmd == 'h25) {led_overtake, led_state} <= io_din;
			if(cmd == 'h26) vol_att <= io_din[4:0];
			if(cmd == 'h27) VSET    <= io_din[11:0];
			if(cmd == 'h2A) {coef_wr,coef_addr,coef_data} <= {1'b1,io_din};
			if(cmd == 'h2B) scaler_flt <= io_din[2:0];
		end
	end
end

always @(posedge clk_sys) begin
	reg vsd, vsd2;
	if(~cfg_ready || ~cfg_set) cfg_got <= cfg_set;
	else begin
		vsd  <= HDMI_TX_VS;
		vsd2 <= vsd;
		if(~vsd2 & vsd) cfg_got <= cfg_set;
	end
end

cyclonev_hps_interface_peripheral_uart uart
(
	.ri(0),
	.dsr(uart_dsr),
	.dcd(uart_dsr),
	.dtr(uart_dtr),

	.cts(uart_cts),
	.rts(uart_rts),
	.rxd(uart_rxd),
	.txd(uart_txd)
);

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

wire clk_100m;
wire clk_hdmi  = ~HDMI_TX_CLK;  // Internal HDMI clock, inverted in relation to external clock
wire clk_audio = FPGA_CLK3_50;

/////////////////////////  SYSTEM MODULE  ////////////////////////////////

wire reset;
sysmem_lite sysmem
(
	//Reset/Clock
	.reset_reset_req(reset_req),
	.reset_reset(reset),
	.ctl_clock(clk_100m),

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
	.ram2_write(0),

	// HDMI frame buffer
	.vbuf_clk(clk_100m),
	.vbuf_address(vbuf_address),
	.vbuf_burstcount(vbuf_burstcount),
	.vbuf_waitrequest(vbuf_waitrequest),
	.vbuf_writedata(vbuf_writedata),
	.vbuf_byteenable(vbuf_byteenable),
	.vbuf_write(vbuf_write),
	.vbuf_readdata(vbuf_readdata),
	.vbuf_readdatavalid(vbuf_readdatavalid),
	.vbuf_read(vbuf_read)
	
);

wire  [27:0] vbuf_address;
wire   [7:0] vbuf_burstcount;
wire         vbuf_waitrequest;
wire [127:0] vbuf_readdata;
wire         vbuf_readdatavalid;
wire         vbuf_read;
wire [127:0] vbuf_writedata;
wire  [15:0] vbuf_byteenable;
wire         vbuf_write;

ascal 
#(
	.RAMBASE(32'h20000000),
	.N_DW(128),
	.N_AW(28)
)
ascal
(
	.reset_na (~reset_req),
	.run      (1),
	.freeze   (0),

	.i_clk  (clk_vid),
	.i_ce   (ce_pix),
	.i_r    (r_out),
	.i_g    (g_out),
	.i_b    (b_out),
	.i_hs   (hs),
	.i_vs   (vs),
	.i_fl   (f1),
	.i_de   (de),
	.iauto  (1),
	.himin  (0),
	.himax  (0),
	.vimin  (0),
	.vimax  (0),

	.o_clk  (clk_hdmi),
	.o_ce   (1),
	.o_r    (hdmi_data[23:16]),
	.o_g    (hdmi_data[15:8]),
	.o_b    (hdmi_data[7:0]),
	.o_hs   (HDMI_TX_HS),
	.o_vs   (HDMI_TX_VS),
	.o_de   (hdmi_de),
	.htotal (WIDTH+HFP+HBP+HS),
	.hsstart(WIDTH + HFP),
	.hsend  (WIDTH + HFP + HS),
	.hdisp  (WIDTH),
	.hmin   (hmin),
	.hmax   (hmax),
	.vtotal (HEIGHT+VFP+VBP+VS),
	.vsstart(HEIGHT + VFP),
	.vsend  (HEIGHT + VFP + VS),
	.vdisp  (HEIGHT),
	.vmin   (vmin),
	.vmax   (vmax),

	.mode     ({~lowlat,|scaler_flt,2'b00}),
	.poly_clk (clk_sys),
	.poly_a   (coef_addr),
	.poly_dw  (coef_data),
	.poly_wr  (coef_wr),

	.avl_clk          (clk_100m),
	.avl_waitrequest  (vbuf_waitrequest),
	.avl_readdata     (vbuf_readdata),
	.avl_readdatavalid(vbuf_readdatavalid),
	.avl_burstcount   (vbuf_burstcount),
	.avl_writedata    (vbuf_writedata),
	.avl_address      (vbuf_address),
	.avl_write        (vbuf_write),
	.avl_read         (vbuf_read),
	.avl_byteenable   (vbuf_byteenable)
);

reg [11:0] hmin;
reg [11:0] hmax;
reg [11:0] vmin;
reg [11:0] vmax;

always @(posedge clk_vid) begin
	reg [31:0] wcalc;
	reg [31:0] hcalc;
	reg  [2:0] state;
	reg [11:0] videow;
	reg [11:0] videoh;

	state <= state + 1'd1;
	case(state)
		0: begin
				wcalc <= VSET ? (VSET*ARX)/ARY : (HEIGHT*ARX)/ARY;
				hcalc <= (WIDTH*ARY)/ARX;
			end
		6: begin
				videow <= (!VSET && (wcalc > WIDTH))     ? WIDTH  : wcalc[11:0];
				videoh <= VSET ? VSET : (hcalc > HEIGHT) ? HEIGHT : hcalc[11:0];
			end
		7: begin
				hmin <= ((WIDTH  - videow)>>1);
				hmax <= ((WIDTH  - videow)>>1) + videow - 1'd1;
				vmin <= ((HEIGHT - videoh)>>1);
				vmax <= ((HEIGHT - videoh)>>1) + videoh - 1'd1;
			end
	endcase
end

pll_hdmi_adj pll_hdmi_adj
(
   .clk(FPGA_CLK1_50),
	.reset_na(~reset_req),

	.llena(lowlat),
	.lltune(lltune),
	.i_waitrequest(adj_waitrequest),
	.i_write(adj_write),
	.i_address(adj_address),
	.i_writedata(adj_data),
	.o_waitrequest(cfg_waitrequest),
	.o_write(cfg_write),
	.o_address(cfg_address),
	.o_writedata(cfg_data)
);


/////////////////////////  HDMI output  /////////////////////////////////

pll_hdmi pll_hdmi
(
	.refclk(FPGA_CLK1_50),
	.rst(reset_req),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.outclk_0(HDMI_TX_CLK)
);

//1920x1080@60 PCLK=148.5MHz CEA
reg  [11:0] WIDTH  = 1920;
reg  [11:0] HFP    = 88;
reg  [11:0] HS     = 48;
reg  [11:0] HBP    = 148;
reg  [11:0] HEIGHT = 1080;
reg  [11:0] VFP    = 4;
reg  [11:0] VS     = 5;
reg  [11:0] VBP    = 36;

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest,adj_waitrequest;
reg         cfg_write,adj_write;
reg   [5:0] cfg_address,adj_address;
reg  [31:0] cfg_data,adj_data;

pll_hdmi_cfg pll_hdmi_cfg
(
	.mgmt_clk(FPGA_CLK1_50),
	.mgmt_reset(reset_req),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

reg cfg_ready = 0;

always @(posedge FPGA_CLK1_50) begin
	reg gotd = 0, gotd2 = 0;
	reg custd = 0, custd2 = 0;
	reg old_wait = 0;

	gotd  <= cfg_got;
	gotd2 <= gotd;
	
	adj_write <= 0;
	
	custd <= cfg_custom_t;
	custd2 <= custd;
	if(custd2 != custd & ~gotd) begin
		adj_address <= cfg_custom_p1;
		adj_data <= cfg_custom_p2;
		adj_write <= 1;
	end

	if(~gotd2 & gotd) begin
		adj_address <= 2;
		adj_data <= 0;
		adj_write <= 1;
	end

	old_wait <= adj_waitrequest;
	if(old_wait & ~adj_waitrequest & gotd) cfg_ready <= 1;
end

hdmi_config hdmi_config
(
	.iCLK(FPGA_CLK1_50),
	.iRST_N(cfg_ready & ~HDMI_TX_INT),

	.I2C_SCL(HDMI_I2C_SCL),
	.I2C_SDA(HDMI_I2C_SDA),

	.dvi_mode(dvi_mode),
	.audio_96k(audio_96k)
);

wire [23:0] hdmi_data;
wire [23:0] hdmi_data_sl;
wire        hdmi_de;

scanlines #(1) HDMI_scanlines
(
	.clk(clk_hdmi),

	.scanlines(scanlines),
	.din(hdmi_data),
	.dout(hdmi_data_sl),
	.hs(HDMI_TX_HS),
	.vs(HDMI_TX_VS)
);

osd hdmi_osd
(
	.clk_sys(clk_sys),

	.io_osd(io_osd),
	.io_strobe(io_strobe),
	.io_din(io_din),

	.clk_video(clk_hdmi),
	.din(hdmi_data_sl),
	.dout(HDMI_TX_D),
	.de_in(hdmi_de),
	.de_out(HDMI_TX_DE)
);

assign HDMI_MCLK = 0;
i2s i2s
(
	.reset(~cfg_ready),
	.clk_sys(clk_audio),
	.half_rate(~audio_96k),

	.sclk(HDMI_SCLK),
	.lrclk(HDMI_LRCLK),
	.sdata(HDMI_I2S),

	//Could inverse the MSB but it will shift 0 level to -MAX level
	.left_chan (audio_l >> !audio_s),
	.right_chan(audio_r >> !audio_s)
);


/////////////////////////  VGA output  //////////////////////////////////

wire [23:0] vga_data_sl;

scanlines #(0) VGA_scanlines
(
	.clk(clk_vid),

	.scanlines(scanlines),
	.din(de ? {r_out, g_out, b_out} : 24'd0),
	.dout(vga_data_sl),
	.hs(hs1),
	.vs(vs1)
);

osd vga_osd
(
	.clk_sys(clk_sys),

	.io_osd(io_osd),
	.io_strobe(io_strobe),
	.io_din(io_din),

	.clk_video(clk_vid),
	.din(vga_data_sl),
	.dout(vga_q),
	.de_in(de)
);

wire [23:0] vga_q;
wire [23:0] vga_o;

vga_out vga_out
(
	.ypbpr_full(1),
	.ypbpr_en(ypbpr_en),
	.dout(vga_o),
	.din(vga_scaler ? {24{HDMI_TX_DE}} & HDMI_TX_D : vga_q)
);

wire vs1 = vga_scaler ? HDMI_TX_VS : vs;
wire hs1 = vga_scaler ? HDMI_TX_HS : hs;

assign VGA_VS = VGA_EN ? 1'bZ      : csync ?     1'b1     : ~vs1;
assign VGA_HS = VGA_EN ? 1'bZ      : csync ? ~(vs1 ^ hs1) : ~hs1;
assign VGA_R  = VGA_EN ? 6'bZZZZZZ : vga_o[23:18];
assign VGA_G  = VGA_EN ? 6'bZZZZZZ : vga_o[15:10];
assign VGA_B  = VGA_EN ? 6'bZZZZZZ : vga_o[7:2];


/////////////////////////  Audio output  ////////////////////////////////

wire al, ar, aspdif;

sigma_delta_dac #(15) dac_l
(
	.CLK(clk_audio),
	.RESET(reset),
	.DACin({audio_l[15] ^ audio_s, audio_l[14:0]}),
	.DACout(al)
);

sigma_delta_dac #(15) dac_r
(
	.CLK(clk_audio),
	.RESET(reset),
	.DACin({audio_r[15] ^ audio_s, audio_r[14:0]}),
	.DACout(ar)
);

spdif toslink
(
	.clk_i(clk_audio),

	.rst_i(reset),
	.half_rate(0),

	.audio_l(audio_l >> !audio_s),
	.audio_r(audio_r >> !audio_s),

	.spdif_o(aspdif)
);

assign AUDIO_SPDIF = SW[0] ? HDMI_LRCLK : aspdif;
assign AUDIO_R     = SW[0] ? HDMI_I2S   : ar;
assign AUDIO_L     = SW[0] ? HDMI_SCLK  : al;

reg [15:0] audio_l; 
reg [15:0] audio_r;

always @(posedge clk_audio) begin
	reg signed [15:0] al;
	reg signed [15:0] ar;

	case({audio_s,audio_mix})
		'b000: al <= audio_ls;
		'b001: al <= audio_ls - (audio_ls >> 3) + (audio_rs >> 3);
		'b010: al <= audio_ls - (audio_ls >> 2) + (audio_rs >> 2);
		'b011: al <= (audio_ls >> 1) + (audio_rs >> 1);
		'b100: al <= audio_ls;
		'b101: al <= audio_ls - (audio_ls >>> 3) + (audio_rs >>> 3);
		'b110: al <= audio_ls - (audio_ls >>> 2) + (audio_rs >>> 2);
		'b111: al <= (audio_ls >>> 1) + (audio_rs >>> 1);
	endcase

	case({audio_s,audio_mix})
		'b000: ar <= audio_rs;
		'b001: ar <= audio_rs - (audio_rs >> 3) + (audio_ls >> 3);
		'b010: ar <= audio_rs - (audio_rs >> 2) + (audio_ls >> 2);
		'b011: ar <= (audio_rs >> 1) + (audio_ls >> 1);
		'b100: ar <= audio_rs;
		'b101: ar <= audio_rs - (audio_rs >>> 3) + (audio_ls >>> 3);
		'b110: ar <= audio_rs - (audio_rs >>> 2) + (audio_ls >>> 2);
		'b111: ar <= (audio_rs >>> 1) + (audio_ls >>> 1);
	endcase
	
	if(vol_att[4]) begin
		audio_l <= 0;
		audio_r <= 0;
	end
	else
	if(audio_s) begin
		audio_l <= al >>> vol_att[3:0];
		audio_r <= ar >>> vol_att[3:0];
	end
	else
	begin
		audio_l <= al >> vol_att[3:0];
		audio_r <= ar >> vol_att[3:0];
	end
end

///////////////////  User module connection ////////////////////////////

wire signed [15:0] audio_ls, audio_rs;
wire        audio_s;
wire  [1:0] audio_mix;
wire  [7:0] r_out, g_out, b_out;
wire        vs, hs, de, f1;
wire  [1:0] scanlines;
wire [15:0] lltune;
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

wire vs_emu, hs_emu;
sync_fix sync_v(clk_vid, vs_emu, vs);
sync_fix sync_h(clk_vid, hs_emu, hs);

wire        uart_dtr;
wire        uart_dsr;
wire        uart_cts;
wire        uart_rts;
wire        uart_rxd;
wire        uart_txd;

emu emu
(
	.CLK_50M(FPGA_CLK3_50),
	.RESET(reset),
	.HPS_BUS({HDMI_TX_VS, clk_100m, clk_vid, ce_pix, de, hs, vs, io_wait, clk_sys, io_fpga, io_uio, io_strobe, io_wide, io_din, io_dout}),

	.CLK_VIDEO(clk_vid),
	.CE_PIXEL(ce_pix),

	.VGA_R(r_out),
	.VGA_G(g_out),
	.VGA_B(b_out),
	.VGA_HS(hs_emu),
	.VGA_VS(vs_emu),
	.VGA_DE(de),
	.VGA_F1(f1),
	.VGA_SL(scanlines),

	.LED_USER(led_user),
	.LED_POWER(led_power),
	.LED_DISK(led_disk),

	.VIDEO_ARX(ARX),
	.VIDEO_ARY(ARY),

	.AUDIO_L(audio_ls),
	.AUDIO_R(audio_rs),
	.AUDIO_S(audio_s),
	.AUDIO_MIX(audio_mix),
	.TAPE_IN(0),

	// SCK  -> CLK
	// MOSI -> CMD
	// MISO <- DAT0
	//    Z -> DAT1
	//    Z -> DAT2
	// CS   -> DAT3
	.SD_SCK(SDIO_CLK),
	.SD_MOSI(SDIO_CMD),
	.SD_MISO(SDIO_DAT[0]),
	.SD_CS(SDIO_DAT[3]),
	.SD_CD(VGA_EN ? VGA_HS : SDIO_CD),

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
	.SDRAM_CKE(SDRAM_CKE),

	.UART_CTS(uart_rts),
	.UART_RTS(uart_cts),
	.UART_RXD(uart_txd),
	.UART_TXD(uart_rxd),
	.UART_DTR(uart_dsr),
	.UART_DSR(uart_dtr)
);

endmodule

module sync_fix
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
