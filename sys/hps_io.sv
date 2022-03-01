//
// hps_io.v
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
// Copyright (c) 2017-2020 Alexey Melnikov
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
//
///////////////////////////////////////////////////////////////////////
// altera message_off 10665

//
// Use buffer to access SD card. It's time-critical part.
//
// WIDE=1 for 16 bit file I/O
// VDNUM 1..10
// BLKSZ 0..7: 0 = 128, 1 = 256, 2 = 512(default), .. 7 = 16384
//
module hps_io #(parameter CONF_STR, CONF_STR_BRAM=1, PS2DIV=0, WIDE=0, VDNUM=1, BLKSZ=2, PS2WE=0)
(
	input             clk_sys,
	inout      [48:0] HPS_BUS,

	// buttons up to 32
	output reg [31:0] joystick_0,
	output reg [31:0] joystick_1,
	output reg [31:0] joystick_2,
	output reg [31:0] joystick_3,
	output reg [31:0] joystick_4,
	output reg [31:0] joystick_5,
	
	// analog -127..+127, Y: [15:8], X: [7:0]
	output reg [15:0] joystick_l_analog_0,
	output reg [15:0] joystick_l_analog_1,
	output reg [15:0] joystick_l_analog_2,
	output reg [15:0] joystick_l_analog_3,
	output reg [15:0] joystick_l_analog_4,
	output reg [15:0] joystick_l_analog_5,

	output reg [15:0] joystick_r_analog_0,
	output reg [15:0] joystick_r_analog_1,
	output reg [15:0] joystick_r_analog_2,
	output reg [15:0] joystick_r_analog_3,
	output reg [15:0] joystick_r_analog_4,
	output reg [15:0] joystick_r_analog_5,

	// paddle 0..255
	output reg  [7:0] paddle_0,
	output reg  [7:0] paddle_1,
	output reg  [7:0] paddle_2,
	output reg  [7:0] paddle_3,
	output reg  [7:0] paddle_4,
	output reg  [7:0] paddle_5,

	// spinner [7:0] -128..+127, [8] - toggle with every update
	output reg  [8:0] spinner_0,
	output reg  [8:0] spinner_1,
	output reg  [8:0] spinner_2,
	output reg  [8:0] spinner_3,
	output reg  [8:0] spinner_4,
	output reg  [8:0] spinner_5,

	output      [1:0] buttons,
	output            forced_scandoubler,
	output            direct_video,
	input             video_rotated,

	//toggle to force notify of video mode change
	input             new_vmode,

	output reg [63:0] status,
	input      [63:0] status_in,
	input             status_set,
	input      [15:0] status_menumask,

	input             info_req,
	input       [7:0] info,

	// SD config
	output reg [VD:0] img_mounted,  // signaling that new image has been mounted
	output reg        img_readonly, // mounted as read only. valid only for active bit in img_mounted
	output reg [63:0] img_size,     // size of image in bytes. valid only for active bit in img_mounted

	// SD block level access
	input      [31:0] sd_lba[VDNUM],
	input       [5:0] sd_blk_cnt[VDNUM], // number of blocks-1, total size ((sd_blk_cnt+1)*(1<<(BLKSZ+7))) must be <= 16384!
	input      [VD:0] sd_rd,
	input      [VD:0] sd_wr,
	output reg [VD:0] sd_ack,

	// SD byte level access. Signals for 2-PORT altsyncram.
	output reg [AW:0] sd_buff_addr,
	output reg [DW:0] sd_buff_dout,
	input      [DW:0] sd_buff_din[VDNUM],
	output reg        sd_buff_wr,

	// ARM -> FPGA download
	output reg        ioctl_download = 0, // signal indicating an active download
	output reg [15:0] ioctl_index,        // menu index used to upload the file
	output reg        ioctl_wr,
	output reg [26:0] ioctl_addr,         // in WIDE mode address will be incremented by 2
	output reg [DW:0] ioctl_dout,
	output reg        ioctl_upload = 0,   // signal indicating an active upload
	input             ioctl_upload_req,   // request to save (must be supported on HPS side for specific core)
	input       [7:0] ioctl_upload_index,
	input      [DW:0] ioctl_din,
	output reg        ioctl_rd,
	output reg [31:0] ioctl_file_ext,
	input             ioctl_wait,

	// [15]: 0 - unset, 1 - set. [1:0]: 0 - none, 1 - 32MB, 2 - 64MB, 3 - 128MB
	// [14]: debug mode: [8]: 1 - phase up, 0 - phase down. [7:0]: amount of shift.
	output reg [15:0] sdram_sz,

	// RTC MSM6242B layout
	output reg [64:0] RTC,

	// Seconds since 1970-01-01 00:00:00
	output reg [32:0] TIMESTAMP,

	// UART flags
	output reg  [7:0] uart_mode,
	output reg [31:0] uart_speed,

	// ps2 keyboard emulation
	output            ps2_kbd_clk_out,
	output            ps2_kbd_data_out,
	input             ps2_kbd_clk_in,
	input             ps2_kbd_data_in,

	input       [2:0] ps2_kbd_led_status,
	input       [2:0] ps2_kbd_led_use,

	output            ps2_mouse_clk_out,
	output            ps2_mouse_data_out,
	input             ps2_mouse_clk_in,
	input             ps2_mouse_data_in,

	// ps2 alternative interface.

	// [8] - extended, [9] - pressed, [10] - toggles with every press/release
	output reg [10:0] ps2_key = 0,

	// [24] - toggles with every event
	output reg [24:0] ps2_mouse = 0,
	output reg [15:0] ps2_mouse_ext = 0, // 15:8 - reserved(additional buttons), 7:0 - wheel movements

	inout      [21:0] gamma_bus,

	// for core-specific extensions
	inout      [35:0] EXT_BUS
);

assign EXT_BUS[31:16] = HPS_BUS[31:16];
assign EXT_BUS[35:33] = HPS_BUS[35:33];

localparam DW = (WIDE) ? 15 : 7;
localparam AW = (WIDE) ? 12 : 13;
localparam VD = VDNUM-1;

wire        io_strobe= HPS_BUS[33];
wire        io_enable= HPS_BUS[34];
wire        fp_enable= HPS_BUS[35];
wire        io_wide  = (WIDE) ? 1'b1 : 1'b0;
wire [15:0] io_din   = HPS_BUS[31:16];
reg  [15:0] io_dout;

assign HPS_BUS[37]   = ioctl_wait;
assign HPS_BUS[36]   = clk_sys;
assign HPS_BUS[32]   = io_wide;
assign HPS_BUS[15:0] = EXT_BUS[32] ? EXT_BUS[15:0] : fp_enable ? fp_dout : io_dout;

reg [15:0] cfg;
assign buttons = cfg[1:0];
//cfg[2] - vga_scaler handled in sys_top
//cfg[3] - csync handled in sys_top
assign forced_scandoubler = cfg[4];
//cfg[5] - ypbpr handled in sys_top
assign direct_video = cfg[10];

reg [3:0] sdn;
reg [3:0] sd_rrb = 0;
always_comb begin
	int n, i;

	sdn = 0;
   for(i = VDNUM - 1; i >= 0; i = i - 1) begin
		n = i + sd_rrb;
		if(n >= VDNUM) n = n - VDNUM;
		if(sd_wr[n] | sd_rd[n]) sdn = n[3:0];
   end
end

/////////////////////////////////////////////////////////

wire [15:0] vc_dout;
video_calc video_calc
(
	.clk_100(HPS_BUS[43]),
	.clk_vid(HPS_BUS[42]),
	.clk_sys(clk_sys),
	.ce_pix(HPS_BUS[41]),
	.de(HPS_BUS[40]),
	.hs(HPS_BUS[39]),
	.vs(HPS_BUS[38]),
	.vs_hdmi(HPS_BUS[44]),
	.f1(HPS_BUS[45]),
	.new_vmode(new_vmode),
	.video_rotated(video_rotated),

	.par_num(byte_cnt[3:0]),
	.dout(vc_dout)
);

/////////////////////////////////////////////////////////

localparam STRLEN = $size(CONF_STR)>>3;
localparam MAX_W = $clog2((32 > (STRLEN+2)) ? 32 : (STRLEN+2))-1;

wire [7:0] conf_byte;
generate
	if(CONF_STR_BRAM) begin
		confstr_rom #(CONF_STR, STRLEN) confstr_rom(.*, .conf_addr(byte_cnt - 1'd1));
	end
	else begin
		assign conf_byte = CONF_STR[{(STRLEN - byte_cnt),3'b000} +:8];
	end
endgenerate

assign     gamma_bus[20:0] = {clk_sys, gamma_en, gamma_wr, gamma_wr_addr, gamma_value};
reg        gamma_en;
reg        gamma_wr;
reg  [9:0] gamma_wr_addr;
reg  [7:0] gamma_value;

reg [31:0] ps2_key_raw = 0;
wire       pressed  = (ps2_key_raw[15:8] != 8'hf0);
wire       extended = (~pressed ? (ps2_key_raw[23:16] == 8'he0) : (ps2_key_raw[15:8] == 8'he0));

reg [MAX_W:0] byte_cnt;
reg   [3:0] sdn_ack;
wire [15:0] disk = 16'd1 << io_din[11:8];

always@(posedge clk_sys) begin : uio_block
	reg [15:0] cmd;
	reg  [2:0] b_wr;
	reg  [3:0] stick_idx;
	reg  [3:0] pdsp_idx;
	reg        ps2skip = 0;
	reg  [3:0] stflg = 0;
	reg [63:0] status_req;
	reg        old_status_set = 0;
	reg        old_upload_req = 0;
	reg        upload_req = 0;
	reg        old_info = 0;
	reg  [7:0] info_n = 0;
	reg [15:0] tmp1;
	reg  [7:0] tmp2;
	reg  [3:0] sdn_r;

	old_status_set <= status_set;
	if(~old_status_set & status_set) begin
		stflg <= stflg + 1'd1;
		status_req <= status_in;
	end
	
	old_upload_req <= ioctl_upload_req;
	if(~old_upload_req & ioctl_upload_req) upload_req <= 1;

	old_info <= info_req;
	if(~old_info & info_req) info_n <= info;

	sd_buff_wr <= b_wr[0];
	if(b_wr[2] && (~&sd_buff_addr)) sd_buff_addr <= sd_buff_addr + 1'b1;
	b_wr <= (b_wr<<1);

	if(PS2DIV) {kbd_rd,kbd_we,mouse_rd,mouse_we} <= 0;

	gamma_wr <= 0;

	if(~io_enable) begin
		if(cmd == 4 && !ps2skip) ps2_mouse[24] <= ~ps2_mouse[24];
		if(cmd == 5 && !ps2skip) begin
			ps2_key <= {~ps2_key[10], pressed, extended, ps2_key_raw[7:0]};
			if(ps2_key_raw == 'hE012E07C) ps2_key[9:0] <= 'h37C; // prnscr pressed
			if(ps2_key_raw == 'h7CE0F012) ps2_key[9:0] <= 'h17C; // prnscr released
			if(ps2_key_raw == 'hF014F077) ps2_key[9:0] <= 'h377; // pause  pressed
		end
		if(cmd == 'h22) RTC[64] <= ~RTC[64];
		if(cmd == 'h24) TIMESTAMP[32] <= ~TIMESTAMP[32];
		cmd <= 0;
		byte_cnt <= 0;
		sd_ack <= 0;
		io_dout <= 0;
		ps2skip <= 0;
		img_mounted <= 0;
	end
	else if(io_strobe) begin

		io_dout <= 0;
		if(~&byte_cnt) byte_cnt <= byte_cnt + 1'd1;

		if(byte_cnt == 0) begin
			cmd <= io_din;

			casex(io_din)
				  'h16: begin io_dout <= {1'b1, sd_blk_cnt[sdn], BLKSZ[2:0], sdn, sd_wr[sdn], sd_rd[sdn]}; sdn_r <= sdn; end
				'h0X17,
				'h0X18: begin sd_ack <= disk[VD:0]; sdn_ack <= io_din[11:8]; end
				  'h29: io_dout <= {4'hA, stflg};
`ifdef MISTER_DISABLE_ADAPTIVE
				  'h2B: io_dout <= {HPS_BUS[48:46],4'b0110};
`else
				  'h2B: io_dout <= {HPS_BUS[48:46],4'b0111};
`endif
				  'h2F: io_dout <= 1;
				  'h32: io_dout <= gamma_bus[21];
				  'h36: begin io_dout <= info_n; info_n <= 0; end
				  'h39: io_dout <= 1;
				  'h3C: if(upload_req) begin io_dout <= {ioctl_upload_index, 8'd1}; upload_req <= 0; end
				  'h3E: io_dout <= 1; // shadow mask
			endcase

			sd_buff_addr <= 0;
			if(io_din == 5) ps2_key_raw <= 0;
		end else begin

			casex(cmd)
				// buttons and switches
				'h01: cfg <= io_din;
				'h02: if(byte_cnt==1) joystick_0[15:0] <= io_din; else joystick_0[31:16] <= io_din;
				'h03: if(byte_cnt==1) joystick_1[15:0] <= io_din; else joystick_1[31:16] <= io_din;
				'h10: if(byte_cnt==1) joystick_2[15:0] <= io_din; else joystick_2[31:16] <= io_din;
				'h11: if(byte_cnt==1) joystick_3[15:0] <= io_din; else joystick_3[31:16] <= io_din;
				'h12: if(byte_cnt==1) joystick_4[15:0] <= io_din; else joystick_4[31:16] <= io_din;
				'h13: if(byte_cnt==1) joystick_5[15:0] <= io_din; else joystick_5[31:16] <= io_din;

				// store incoming ps2 mouse bytes
				'h04: begin
							if(PS2DIV) begin
								mouse_data <= io_din[7:0];
								mouse_we   <= 1;
							end
							if(&io_din[15:8]) ps2skip <= 1;
							if(~&io_din[15:8] && ~ps2skip && !byte_cnt[MAX_W:2]) begin
								case(byte_cnt[1:0])
									1: ps2_mouse[7:0]   <= io_din[7:0];
									2: ps2_mouse[15:8]  <= io_din[7:0];
									3: ps2_mouse[23:16] <= io_din[7:0];
								endcase
								case(byte_cnt[1:0])
									1: ps2_mouse_ext[7:0]  <= {io_din[14], io_din[14:8]};
									2: ps2_mouse_ext[11:8] <= io_din[11:8];
									3: ps2_mouse_ext[15:12]<= io_din[11:8];
								endcase
							end
						end

				// store incoming ps2 keyboard bytes
				'h05: begin
							if(&io_din[15:8]) ps2skip <= 1;
							if(~&io_din[15:8] & ~ps2skip) ps2_key_raw[31:0] <= {ps2_key_raw[23:0], io_din[7:0]};
							if(PS2DIV) begin
								kbd_data <= io_din[7:0];
								kbd_we <= 1;
							end
						end

				// reading config string, returning a byte from string
				'h14: if(byte_cnt <= STRLEN) io_dout[7:0] <= conf_byte;

				// reading sd card status
				'h16: if(!byte_cnt[MAX_W:2]) begin
							case(byte_cnt[1:0])
								1: sd_rrb  <= (sd_rrb == VD) ? 4'd0 : (sd_rrb + 1'd1);
								2: io_dout <= sd_lba[sdn_r][15:0];
								3: io_dout <= sd_lba[sdn_r][31:16];
							endcase
						end

				// send sector IO -> FPGA
				// flag that download begins
				'h0X17: begin
							sd_buff_dout <= io_din[DW:0];
							b_wr <= 1;
						end

				// reading sd card write data
				'h0X18: begin
							if(~&sd_buff_addr) sd_buff_addr <= sd_buff_addr + 1'b1;
							io_dout <= sd_buff_din[sdn_ack];
						end

				// joystick left analog
				'h1a: if(!byte_cnt[MAX_W:2]) begin
							case(byte_cnt[1:0])
								1: {pdsp_idx,stick_idx} <= io_din[7:0]; // first byte is joystick index
								2: case(stick_idx)
										 0: joystick_l_analog_0 <= io_din;
										 1: joystick_l_analog_1 <= io_din;
										 2: joystick_l_analog_2 <= io_din;
										 3: joystick_l_analog_3 <= io_din;
										 4: joystick_l_analog_4 <= io_din;
										 5: joystick_l_analog_5 <= io_din;
										15: case(pdsp_idx)
												 0: paddle_0 <= io_din[7:0];
												 1: paddle_1 <= io_din[7:0];
												 2: paddle_2 <= io_din[7:0];
												 3: paddle_3 <= io_din[7:0];
												 4: paddle_4 <= io_din[7:0];
												 5: paddle_5 <= io_din[7:0];
												 8: spinner_0 <= {~spinner_0[8],io_din[7:0]};
												 9: spinner_1 <= {~spinner_1[8],io_din[7:0]};
												10: spinner_2 <= {~spinner_2[8],io_din[7:0]};
												11: spinner_3 <= {~spinner_3[8],io_din[7:0]};
												12: spinner_4 <= {~spinner_4[8],io_din[7:0]};
												13: spinner_5 <= {~spinner_5[8],io_din[7:0]};
											endcase
									endcase
							endcase
						end

				// joystick right analog
				'h3d: if(!byte_cnt[MAX_W:2]) begin
							case(byte_cnt[1:0])
								1: stick_idx <= io_din[3:0]; // first byte is joystick index
								2: case(stick_idx)
										 0: joystick_r_analog_0 <= io_din;
										 1: joystick_r_analog_1 <= io_din;
										 2: joystick_r_analog_2 <= io_din;
										 3: joystick_r_analog_3 <= io_din;
										 4: joystick_r_analog_4 <= io_din;
										 5: joystick_r_analog_5 <= io_din;
									endcase
							endcase
						end

				// notify image selection
				'h1c: begin
							img_mounted  <= io_din[VD:0] ? io_din[VD:0] : 1'b1;
							img_readonly <= io_din[7];
						end

				// send image info
				'h1d: if(byte_cnt<5) img_size[{byte_cnt-1'b1, 4'b0000} +:16] <= io_din;

				// status, 64bit version
				'h1e: if(!byte_cnt[MAX_W:3]) begin
							case(byte_cnt[2:0])
								1: status[15:00] <= io_din;
								2: status[31:16] <= io_din;
								3: status[47:32] <= io_din;
								4: status[63:48] <= io_din;
							endcase
						end

				// reading keyboard LED status
				'h1f: io_dout <= {|PS2WE, 2'b01, ps2_kbd_led_status[2], ps2_kbd_led_use[2], ps2_kbd_led_status[1], ps2_kbd_led_use[1], ps2_kbd_led_status[0], ps2_kbd_led_use[0]};

				// reading ps2 keyboard/mouse control
				'h21: if(PS2DIV) begin
							if(byte_cnt == 1) begin
								io_dout <= kbd_data_host;
								kbd_rd <= 1;
							end
							else
							if(byte_cnt == 2) begin
								io_dout <= mouse_data_host;
								mouse_rd <= 1;
							end
						end

				//RTC
				'h22: RTC[(byte_cnt-6'd1)<<4 +:16] <= io_din;

				//Video res.
				'h23: if(!byte_cnt[MAX_W:4]) io_dout <= vc_dout;

				//RTC
				'h24: TIMESTAMP[(byte_cnt-6'd1)<<4 +:16] <= io_din;

				//status set
				'h29: if(!byte_cnt[MAX_W:3]) begin
							case(byte_cnt[2:0])
								1: io_dout <= status_req[15:00];
								2: io_dout <= status_req[31:16];
								3: io_dout <= status_req[47:32];
								4: io_dout <= status_req[63:48];
							endcase
						end

				//menu mask
				'h2E: if(byte_cnt == 1) io_dout <= status_menumask;
				
				//sdram size set
				'h31: if(byte_cnt == 1) sdram_sz <= io_din;

				// Gamma
				'h32: gamma_en <= io_din[0];
				'h33: begin
							gamma_wr_addr <= {(byte_cnt[1:0]-1'b1),io_din[15:8]};
							{gamma_wr, gamma_value} <= {1'b1,io_din[7:0]};
							if (byte_cnt[1:0] == 3) byte_cnt <= 1;
						end

				// UART
				'h3b: if(!byte_cnt[MAX_W:2]) begin
							case(byte_cnt[1:0])
								1: tmp2 <= io_din[7:0];
								2: tmp1 <= io_din;
								3: {uart_speed, uart_mode} <= {io_din, tmp1, tmp2};
							endcase
						end
			endcase
		end
	end
end


///////////////////////////////   PS2   ///////////////////////////////
generate
	if(PS2DIV) begin
		reg clk_ps2;
		always @(posedge clk_sys) begin
			integer cnt;
			cnt <= cnt + 1'd1;
			if(cnt == PS2DIV) begin
				clk_ps2 <= ~clk_ps2;
				cnt <= 0;
			end
		end

		reg  [7:0] kbd_data;
		reg        kbd_we;
		wire [8:0] kbd_data_host;
		reg        kbd_rd;

		ps2_device keyboard
		(
			.clk_sys(clk_sys),

			.wdata(kbd_data),
			.we(kbd_we),

			.ps2_clk(clk_ps2),
			.ps2_clk_out(ps2_kbd_clk_out),
			.ps2_dat_out(ps2_kbd_data_out),

			.ps2_clk_in(ps2_kbd_clk_in  || !PS2WE),
			.ps2_dat_in(ps2_kbd_data_in || !PS2WE),

			.rdata(kbd_data_host),
			.rd(kbd_rd)
		);

		reg  [7:0] mouse_data;
		reg        mouse_we;
		wire [8:0] mouse_data_host;
		reg        mouse_rd;

		ps2_device mouse
		(
			.clk_sys(clk_sys),

			.wdata(mouse_data),
			.we(mouse_we),

			.ps2_clk(clk_ps2),
			.ps2_clk_out(ps2_mouse_clk_out),
			.ps2_dat_out(ps2_mouse_data_out),

			.ps2_clk_in(ps2_mouse_clk_in  || !PS2WE),
			.ps2_dat_in(ps2_mouse_data_in || !PS2WE),

			.rdata(mouse_data_host),
			.rd(mouse_rd)
		);
	end
	else begin
		assign ps2_kbd_clk_out = 0;
		assign ps2_kbd_data_out = 0;
		assign ps2_mouse_clk_out = 0;
		assign ps2_mouse_data_out = 0;
	end
endgenerate

///////////////////////////////   DOWNLOADING   ///////////////////////////////

localparam FIO_FILE_TX      = 8'h53;
localparam FIO_FILE_TX_DAT  = 8'h54;
localparam FIO_FILE_INDEX   = 8'h55;
localparam FIO_FILE_INFO    = 8'h56;

reg [15:0] fp_dout;
always@(posedge clk_sys) begin : fio_block
	reg [15:0] cmd;
	reg  [2:0] cnt;
	reg        has_cmd;
	reg [26:0] addr;
	reg        wr;
	
	ioctl_rd <= 0;
	ioctl_wr <= wr;
	wr <= 0;

	if(~fp_enable) has_cmd <= 0;
	else begin
		if(io_strobe) begin

			if(!has_cmd) begin
				cmd <= io_din;
				has_cmd <= 1;
				cnt <= 0;
			end else begin

				case(cmd)
					FIO_FILE_INFO:
						if(~cnt[1]) begin
							case(cnt)
								0: ioctl_file_ext[31:16] <= io_din;
								1: ioctl_file_ext[15:00] <= io_din;
							endcase
							cnt <= cnt + 1'd1;
						end

					FIO_FILE_INDEX:
						begin
							ioctl_index <= io_din[15:0];
						end

					FIO_FILE_TX:
						begin
							cnt <= cnt + 1'd1;
							case(cnt) 
								0:	if(io_din[7:0] == 8'hAA) begin
										ioctl_addr <= 0;
										ioctl_upload <= 1;
										ioctl_rd <= 1;
									end
									else if(io_din[7:0]) begin
										addr <= 0;
										ioctl_download <= 1;
									end
									else begin
										if(ioctl_download) ioctl_addr <= addr;
										ioctl_download <= 0;
										ioctl_upload <= 0;
									end

								1: begin
										ioctl_addr[15:0] <= io_din;
										addr[15:0] <= io_din;
									end

								2: begin
										ioctl_addr[26:16] <= io_din[10:0];
										addr[26:16] <= io_din[10:0];
									end
							endcase
						end

					FIO_FILE_TX_DAT:
						if(ioctl_download) begin
							ioctl_addr <= addr;
							ioctl_dout <= io_din[DW:0];
							wr   <= 1;
							addr <= addr + (WIDE ? 2'd2 : 2'd1);
						end
						else begin
							ioctl_addr <= ioctl_addr + (WIDE ? 2'd2 : 2'd1);
							fp_dout <= ioctl_din;
							ioctl_rd <= 1;
						end
				endcase
			end
		end
	end
end

endmodule

//////////////////////////////////////////////////////////////////////////////////


module ps2_device #(parameter PS2_FIFO_BITS=5)
(
	input        clk_sys,

	input  [7:0] wdata,
	input        we,

	input        ps2_clk,
	output reg   ps2_clk_out,
	output reg   ps2_dat_out,
	output reg   tx_empty,

	input        ps2_clk_in,
	input        ps2_dat_in,

	output [8:0] rdata,
	input        rd
);


(* ramstyle = "logic" *) reg [7:0] fifo[1<<PS2_FIFO_BITS];

reg [PS2_FIFO_BITS-1:0] wptr;
reg [PS2_FIFO_BITS-1:0] rptr;

reg [2:0] rx_state = 0;
reg [3:0] tx_state = 0;

reg       has_data;
reg [7:0] data;
assign    rdata = {has_data, data};

always@(posedge clk_sys) begin
	reg [7:0] tx_byte;
	reg parity;
	reg r_inc;
	reg old_clk;
	reg [1:0] timeout;

	reg [3:0] rx_cnt;

	reg c1,c2,d1;

	tx_empty <= ((wptr == rptr) && (tx_state == 0));

	if(we && !has_data) begin
		fifo[wptr] <= wdata;
		wptr <= wptr + 1'd1;
	end

	if(rd) has_data <= 0;

	c1 <= ps2_clk_in;
	c2 <= c1;
	d1 <= ps2_dat_in;
	if(!rx_state && !tx_state && ~c2 && c1 && ~d1) begin
		rx_state <= rx_state + 1'b1;
		ps2_dat_out <= 1;
	end

	old_clk <= ps2_clk;
	if(~old_clk & ps2_clk) begin

		if(rx_state) begin
			case(rx_state)
				1: begin
						rx_state <= rx_state + 1'b1;
						rx_cnt <= 0;
					end

				2: begin
						if(rx_cnt <= 7) data <= {d1, data[7:1]};
						else rx_state <= rx_state + 1'b1;
						rx_cnt <= rx_cnt + 1'b1;
					end

				3: if(d1) begin
						rx_state <= rx_state + 1'b1;
						ps2_dat_out <= 0;
					end

				4: begin
						ps2_dat_out <= 1;
						has_data <= 1;
						rx_state <= 0;
						rptr     <= 0;
						wptr     <= 0;
					end
			endcase
		end else begin

			// transmitter is idle?
			if(tx_state == 0) begin
				// data in fifo present?
				if(c2 && c1 && d1 && wptr != rptr) begin

					timeout <= timeout - 1'd1;
					if(!timeout) begin
						tx_byte <= fifo[rptr];
						rptr <= rptr + 1'd1;

						// reset parity
						parity <= 1;

						// start transmitter
						tx_state <= 1;

						// put start bit on data line
						ps2_dat_out <= 0;			// start bit is 0
					end
				end
			end else begin

				// transmission of 8 data bits
				if((tx_state >= 1)&&(tx_state < 9)) begin
					ps2_dat_out <= tx_byte[0];	          // data bits
					tx_byte[6:0] <= tx_byte[7:1]; // shift down
					if(tx_byte[0])
						parity <= !parity;
				end

				// transmission of parity
				if(tx_state == 9) ps2_dat_out <= parity;

				// transmission of stop bit
				if(tx_state == 10) ps2_dat_out <= 1;    // stop bit is 1

				// advance state machine
				if(tx_state < 11) tx_state <= tx_state + 1'd1;
					else tx_state <= 0;
			end
		end
	end

	if(~old_clk & ps2_clk) ps2_clk_out <= 1;
	if(old_clk & ~ps2_clk) ps2_clk_out <= ((tx_state == 0) && (rx_state<2));

end

endmodule


///////////////// calc video parameters //////////////////
module video_calc
(
	input clk_100,
	input clk_vid,
	input clk_sys,

	input ce_pix,
	input de,
	input hs,
	input vs,
	input vs_hdmi,
	input f1,
	input new_vmode,
	input video_rotated,

	input       [3:0] par_num,
	output reg [15:0] dout
);

always @(posedge clk_sys) begin
	case(par_num)
		1: dout <= {video_rotated, |vid_int, vid_nres};
		2: dout <= vid_hcnt[15:0];
		3: dout <= vid_hcnt[31:16];
		4: dout <= vid_vcnt[15:0];
		5: dout <= vid_vcnt[31:16];
		6: dout <= vid_htime[15:0];
		7: dout <= vid_htime[31:16];
		8: dout <= vid_vtime[15:0];
		9: dout <= vid_vtime[31:16];
	  10: dout <= vid_pix[15:0];
	  11: dout <= vid_pix[31:16];
	  12: dout <= vid_vtime_hdmi[15:0];
	  13: dout <= vid_vtime_hdmi[31:16];
	  default dout <= 0;
	endcase
end

reg [31:0] vid_hcnt = 0;
reg [31:0] vid_vcnt = 0;
reg  [7:0] vid_nres = 0;
reg  [1:0] vid_int  = 0;

always @(posedge clk_vid) begin
	integer hcnt;
	integer vcnt;
	reg old_vs= 0, old_de = 0, old_vmode = 0;
	reg [3:0] resto = 0;
	reg calch = 0;

	if(ce_pix) begin
		old_vs <= vs;
		old_de <= de;

		if(~vs & ~old_de & de) vcnt <= vcnt + 1;
		if(calch & de) hcnt <= hcnt + 1;
		if(old_de & ~de) calch <= 0;

		if(old_vs & ~vs) begin
			vid_int <= {vid_int[0],f1};
			if(~f1) begin
				if(hcnt && vcnt) begin
					old_vmode <= new_vmode;

					//report new resolution after timeout
					if(resto) resto <= resto + 1'd1;
					if(vid_hcnt != hcnt || vid_vcnt != vcnt || old_vmode != new_vmode) resto <= 1;
					if(&resto) vid_nres <= vid_nres + 1'd1;
					vid_hcnt <= hcnt;
					vid_vcnt <= vcnt;
				end
				vcnt <= 0;
				hcnt <= 0;
				calch <= 1;
			end
		end
	end
end

reg [31:0] vid_htime = 0;
reg [31:0] vid_vtime = 0;
reg [31:0] vid_pix = 0;

always @(posedge clk_100) begin
	integer vtime, htime, hcnt;
	reg old_vs, old_hs, old_vs2, old_hs2, old_de, old_de2;
	reg calch = 0;

	old_vs <= vs;
	old_hs <= hs;

	old_vs2 <= old_vs;
	old_hs2 <= old_hs;

	vtime <= vtime + 1'd1;
	htime <= htime + 1'd1;

	if(~old_vs2 & old_vs) begin
		vid_pix <= hcnt;
		vid_vtime <= vtime;
		vtime <= 0;
		hcnt <= 0;
	end

	if(old_vs2 & ~old_vs) calch <= 1;

	if(~old_hs2 & old_hs) begin
		vid_htime <= htime;
		htime <= 0;
	end

	old_de   <= de;
	old_de2  <= old_de;

	if(calch & old_de) hcnt <= hcnt + 1;
	if(old_de2 & ~old_de) calch <= 0;
end

reg [31:0] vid_vtime_hdmi;
always @(posedge clk_100) begin
	integer vtime;
	reg old_vs, old_vs2;

	old_vs <= vs_hdmi;
	old_vs2 <= old_vs;

	vtime <= vtime + 1'd1;

	if(~old_vs2 & old_vs) begin
		vid_vtime_hdmi <= vtime;
		vtime <= 0;
	end
end

endmodule

module confstr_rom #(parameter CONF_STR, STRLEN)
(
	input      clk_sys,
	input      [$clog2(STRLEN+1)-1:0] conf_addr,
	output reg [7:0] conf_byte
);

wire [7:0] rom[STRLEN];
initial for(int i = 0; i < STRLEN; i++) rom[i] = CONF_STR[((STRLEN-i)*8)-1 -:8];
always @ (posedge clk_sys) conf_byte <= rom[conf_addr];

endmodule
