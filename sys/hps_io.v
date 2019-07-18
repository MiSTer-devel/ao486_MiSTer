//
// hps_io.v (ao486 only!)
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
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
//
///////////////////////////////////////////////////////////////////////

//
//
// for synchronous projects default value for PS2DIV is fine for any frequency of system clock.
// clk_ps2 = CLK_SYS/(PS2DIV*2)
//

module hps_io #(parameter STRLEN=0, PS2DIV=2000)
(
	input             clk_sys,
	inout      [45:0] HPS_BUS,

	// parameter STRLEN and the actual length of conf_str have to match
	input [(8*STRLEN)-1:0] conf_str,

	output reg [15:0] joystick_0,
	output reg [15:0] joystick_1,
	output reg [15:0] joystick_analog_0,
	output reg [15:0] joystick_analog_1,

	output      [1:0] buttons,

	output reg [31:0] status,
	input      [31:0] status_in,
	input             status_set,
	input      [15:0] status_menumask,

	//toggle to force notify of video mode change
	input             new_vmode,

	input             ioctl_wait,
	
	input      [31:0] dma_din,
	output reg [31:0] dma_dout,
	output reg [31:0] dma_addr,
	output reg        dma_rd,
	output reg        dma_wr,
	output reg  [1:0] dma_status,
	input       [1:0] dma_req,
	
	input      [15:0] uart_mode,

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
	input             ps2_mouse_data_in
);

wire        io_wait  = ioctl_wait;
wire        io_enable= |HPS_BUS[35:34];
wire        io_strobe= HPS_BUS[33];
wire        io_wide  = 1;
wire [15:0] io_din   = HPS_BUS[31:16];
reg  [15:0] io_dout;

assign HPS_BUS[37]   = io_wait;
assign HPS_BUS[36]   = clk_sys;
assign HPS_BUS[32]   = io_wide;
assign HPS_BUS[15:0] = io_dout;

reg [7:0] cfg;
assign buttons = cfg[1:0];
//cfg[2] - vga_scaler handled in sys_top
//cfg[3] - csync handled in sys_top
//assign forced_scandoubler = cfg[4];
//cfg[5] - ypbpr handled in sys_top


///////////////// calc video parameters //////////////////

wire clk_100 = HPS_BUS[43];
wire clk_vid = HPS_BUS[42];
wire ce_pix  = HPS_BUS[41];
wire de      = HPS_BUS[40];
wire hs      = HPS_BUS[39];
wire vs      = HPS_BUS[38];
wire vs_hdmi = HPS_BUS[44];
wire f1      = HPS_BUS[45];

reg [31:0] vid_hcnt = 0;
reg [31:0] vid_vcnt = 0;
reg  [7:0] vid_nres = 0;
reg  [1:0] vid_int  = 0;
integer hcnt;

always @(posedge clk_vid) begin
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


/////////////////////////////////////////////////////////

always@(posedge clk_sys) begin
	reg [15:0] cmd;
	reg  [9:0] byte_cnt;   // counts bytes
	reg  [2:0] b_wr;
	reg  [2:0] stick_idx;
	reg        dma_hilo;
	reg        old_wait;
	reg        pending;
	reg  [3:0] stflg = 0;
	reg [31:0] status_req;
	reg        old_status_set = 0;

	old_status_set <= status_set;
	if(~old_status_set & status_set) begin
		stflg <= stflg + 1'd1;
		status_req <= status_in;
	end

	{kbd_rd,kbd_we,mouse_rd,mouse_we} <= 0;
	
	{dma_rd, dma_wr} <= 0;
	dma_status <= 0;

	old_wait <= io_wait;

	if(~io_enable) begin
		byte_cnt <= 0;
		io_dout <= 0;
		dma_hilo <= 0;
		old_wait <= 0;
		pending <= 0;
	end else begin
		if(io_strobe) begin

			io_dout <= 0;
			if(~&byte_cnt) byte_cnt <= byte_cnt + 1'd1;

			if(byte_cnt == 0) begin
				cmd <= io_din;
				if(io_din == 'h29) io_dout <= {4'hA, stflg};
				if(io_din == 'h2B) io_dout <= 1;
				if(io_din == 'h2F) io_dout <= 1;
				dma_hilo <= 0;
			end else begin

				case(cmd)
					// buttons and switches
					'h01: cfg        <= io_din[7:0]; 
					'h02: joystick_0 <= io_din;
					'h03: joystick_1 <= io_din;

					// store incoming ps2 mouse bytes 
					'h04: begin
								mouse_data <= io_din[7:0];
								mouse_we   <= 1;
							end

					// store incoming ps2 keyboard bytes 
					'h05: begin
								kbd_data <= io_din[7:0];
								kbd_we   <= 1;
							end

					// reading config string
					'h14: begin
								// returning a byte from string
								if(byte_cnt < STRLEN + 1) io_dout[7:0] <= conf_str[(STRLEN - byte_cnt)<<3 +:8];
							end

					// joystick analog
					'h1a: case(byte_cnt)
								1: stick_idx <= io_din[2:0]; // first byte is joystick index
								2: case(stick_idx)
										0: joystick_analog_0 <= io_din;
										1: joystick_analog_1 <= io_din;
									endcase
							endcase

					// reading sd card status
					'h16: io_dout <= 0;

					// status, 32bit version
					'h1e: if(byte_cnt==1) status[15:0] <= io_din;
							else
							if(byte_cnt==2) status[31:16] <= io_din;

					// reading keyboard LED status
					'h1f: io_dout <= 16'h0100;

					// reading ps2 keyboard/mouse control
					'h21: if(byte_cnt == 1) begin
								io_dout <= kbd_data_host;
								kbd_rd <= 1;
							end
							else 
							if(byte_cnt == 2) begin
								io_dout <= mouse_data_host;
								mouse_rd <= 1;
							end

					//Video res.
					'h23: case(byte_cnt)
								1: io_dout <= {|vid_int, vid_nres};
								2: io_dout <= vid_hcnt[15:0];
								3: io_dout <= vid_hcnt[31:16];
								4: io_dout <= vid_vcnt[15:0];
								5: io_dout <= vid_vcnt[31:16];
								6: io_dout <= vid_htime[15:0];
								7: io_dout <= vid_htime[31:16];
								8: io_dout <= vid_vtime[15:0];
								9: io_dout <= vid_vtime[31:16];
							  10: io_dout <= vid_pix[15:0];
							  11: io_dout <= vid_pix[31:16];
							  12: io_dout <= vid_vtime_hdmi[15:0];
							  13: io_dout <= vid_vtime_hdmi[31:16];
							endcase

					//UART flags
					'h28: io_dout <= uart_mode;

					//status set
					'h29: case(byte_cnt)
								1: io_dout <= status_req[15:0];
								2: io_dout <= status_req[31:16];
							endcase
					
					//menu mask
					'h2E: if(byte_cnt == 1) io_dout <= status_menumask;

					'h61: if(byte_cnt == 1) begin
								dma_addr[15:0] <= io_din;
							end
							else
							if(byte_cnt == 2) begin
								dma_addr[31:16] <= io_din;
							end
							else
							begin
								if(~dma_hilo) begin
									if(byte_cnt>4) dma_addr <= dma_addr + 3'd4;
									dma_dout[15:0] <= io_din;
								end
								else
								begin
									dma_dout[31:16] <= io_din;
									dma_wr <= 1;
								end
								dma_hilo <= ~dma_hilo;
							end

					'h62: if(byte_cnt == 1) begin
								dma_addr[15:0] <= io_din;
							end
							else
							if(byte_cnt == 2) begin
								dma_addr[31:16] <= io_din;
							end
							else
							begin
								if(~dma_hilo) begin
									dma_rd <= 1;
									pending <= 1;
								end
								else
								begin
									io_dout <= dma_din[31:16];
									dma_addr <= dma_addr + 3'd4;
								end
								dma_hilo <= ~dma_hilo;
							end

					'h63: begin
								io_dout <= dma_req;
								dma_status <= io_din[1:0];
							end
					default: ;
				endcase
			end
		end

		//some pending read functions
		if(old_wait & ~io_wait & pending) begin
			pending <= 0;
			case(cmd)
				'h62: io_dout <= dma_din[15:0];
			endcase
		end
	end
end


///////////////////////////////   PS2   ///////////////////////////////
reg clk_ps2;
always @(negedge clk_sys) begin
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
	
	.ps2_clk_in(ps2_kbd_clk_in),
	.ps2_dat_in(ps2_kbd_data_in),

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

	.ps2_clk_in(ps2_mouse_clk_in),
	.ps2_dat_in(ps2_mouse_data_in),

	.rdata(mouse_data_host),
	.rd(mouse_rd)
);

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

	if(we) begin
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
