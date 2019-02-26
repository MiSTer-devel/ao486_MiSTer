// A simple OSD implementation. Can be hooked up between a cores
// VGA output and the physical VGA pins

module osd
(
	input         clk_sys,

	input         io_osd,
	input         io_strobe,
	input  [15:0] io_din,

	input         clk_video,
	input  [23:0] din,
	output [23:0] dout,
	input         de_in,
	output reg    de_out,
	output reg    osd_status
);

parameter  OSD_COLOR    =  3'd4;
parameter  OSD_X_OFFSET = 12'd0;
parameter  OSD_Y_OFFSET = 12'd0;

localparam OSD_WIDTH    = 12'd256;
localparam OSD_HEIGHT   = 12'd64;

reg        osd_enable;
reg  [7:0] osd_buffer[4096];

reg        info = 0;
reg  [8:0] infoh;
reg  [8:0] infow;
reg [11:0] infox;
reg [21:0] infoy;
reg [21:0] hrheight;

always@(posedge clk_sys) begin
	reg [11:0] bcnt;
	reg  [7:0] cmd;
	reg        has_cmd;
	reg        old_strobe;
	reg        highres = 0;

	hrheight <= info ? infoh : (OSD_HEIGHT<<highres);

	old_strobe <= io_strobe;

	if(~io_osd) begin
		bcnt <= 0;
		has_cmd <= 0;
		cmd <= 0;
		if(cmd[7:4] == 4) osd_enable <= cmd[0];
	end else begin
		if(~old_strobe & io_strobe) begin
			if(!has_cmd) begin
				has_cmd <= 1;
				cmd <= io_din[7:0];
				// command 0x40: OSDCMDENABLE, OSDCMDDISABLE
				if(io_din[7:4] == 4) begin
					if(!io_din[0]) {osd_status,highres} <= 0;
					else {osd_status,info} <= {~io_din[2],io_din[2]};
					bcnt <= 0;
				end
				// command 0x20: OSDCMDWRITE
				if(io_din[7:4] == 2) begin
					if(io_din[3]) highres <= 1;
					bcnt <= {io_din[3:0], 8'h00};
				end
			end else begin
				// command 0x40: OSDCMDENABLE, OSDCMDDISABLE
				if(cmd[7:4] == 4) begin
					if(bcnt == 0) infox <= io_din[11:0];
					if(bcnt == 1) infoy <= io_din[11:0];
					if(bcnt == 2) infow <= {io_din[5:0], 3'b000};
					if(bcnt == 3) infoh <= {io_din[5:0], 3'b000};
				end

				// command 0x20: OSDCMDWRITE
				if(cmd[7:4] == 2) osd_buffer[bcnt] <= io_din[7:0];

				bcnt <= bcnt + 1'd1;
			end
		end
	end
end

reg ce_pix;
always @(negedge clk_video) begin
	integer cnt = 0;
	integer pixsz, pixcnt;
	reg deD;

	cnt <= cnt + 1;
	deD <= de_in;

	pixcnt <= pixcnt + 1;
	if(pixcnt == pixsz) pixcnt <= 0;
	ce_pix <= !pixcnt;

	if(~deD && de_in) cnt <= 0;

	if(deD && ~de_in) begin
		pixsz  <= (((cnt+1'b1) >> 9) > 1) ? (((cnt+1'b1) >> 9) - 1) : 0;
		pixcnt <= 0;
	end
end

reg [2:0] osd_de;
reg       osd_pixel;

always @(posedge clk_video) begin
	reg        deD;
	reg  [1:0] osd_div;
	reg  [1:0] multiscan;
	reg  [7:0] osd_byte; 
	reg [23:0] h_cnt;
	reg [21:0] v_cnt;
	reg [21:0] dsp_width;
	reg [21:0] osd_vcnt;
	reg [21:0] h_osd_start;
	reg [21:0] v_osd_start;
	reg [21:0] osd_hcnt;
	reg        osd_de1,osd_de2;
	reg  [1:0] osd_en;

	if(ce_pix) begin

		deD <= de_in;
		if(~&h_cnt) h_cnt <= h_cnt + 1'd1;

		if(~&osd_hcnt) osd_hcnt <= osd_hcnt + 1'd1;
		if (h_cnt == h_osd_start) begin
			osd_de[0] <= osd_en[1] && hrheight && (osd_vcnt < hrheight);
			osd_hcnt <= 0;
		end
		if (osd_hcnt+1 == (info ? infow : OSD_WIDTH)) osd_de[0] <= 0;

		// falling edge of de
		if(!de_in && deD) dsp_width <= h_cnt[21:0];

		// rising edge of de
		if(de_in && !deD) begin
			h_cnt <= 0;
			v_cnt <= v_cnt + 1'd1;
			h_osd_start <= info ? infox : (((dsp_width - OSD_WIDTH)>>1) + OSD_X_OFFSET - 2'd2);

			if(h_cnt > {dsp_width, 2'b00}) begin
				v_cnt <= 0;

				osd_en <= (osd_en << 1) | osd_enable;
				if(~osd_enable) osd_en <= 0;

				if(v_cnt<320) begin
					multiscan <= 0;
					v_osd_start <= info ? infoy : (((v_cnt-hrheight)>>1) + OSD_Y_OFFSET);
				end
				else if(v_cnt<640) begin
					multiscan <= 1;
					v_osd_start <= info ? (infoy<<1) : (((v_cnt-(hrheight<<1))>>1) + OSD_Y_OFFSET);
				end
				else if(v_cnt<960) begin
					multiscan <= 2;
					v_osd_start <= info ? (infoy + (infoy << 1)) : (((v_cnt-(hrheight + (hrheight<<1)))>>1) + OSD_Y_OFFSET);
				end
				else begin
					multiscan <= 3;
					v_osd_start <= info ? (infoy<<2) : (((v_cnt-(hrheight<<2))>>1) + OSD_Y_OFFSET);
				end
			end

			osd_div <= osd_div + 1'd1;
			if(osd_div == multiscan) begin
				osd_div <= 0;
				if(~&osd_vcnt) osd_vcnt <= osd_vcnt + 1'd1;
			end
			if(v_osd_start == (v_cnt+1'b1)) {osd_div, osd_vcnt} <= 0;
		end

		osd_byte  <= osd_buffer[{osd_vcnt[6:3], osd_hcnt[7:0]}];
		osd_pixel <= osd_byte[osd_vcnt[2:0]];
		osd_de[2:1] <= osd_de[1:0];
	end
end

reg [23:0] rdout;
assign dout = rdout;

always @(posedge clk_video) begin
	rdout <= ~osd_de[2] ? din : {{osd_pixel, osd_pixel, OSD_COLOR[2], din[23:19]},
	                             {osd_pixel, osd_pixel, OSD_COLOR[1], din[15:11]},
	                             {osd_pixel, osd_pixel, OSD_COLOR[0], din[7:3]}};
	de_out <= de_in;
end

endmodule
