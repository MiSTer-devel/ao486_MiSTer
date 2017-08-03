// A simple OSD implementation. Can be hooked up between a cores
// VGA output and the physical VGA pins

module osd
(
	input         clk_sys,

	input         io_osd,
	input         io_strobe,
	input   [7:0] io_din,

	input         clk_video,
	input  [23:0] din,
	output [23:0] dout,
	input         de
);

parameter  OSD_COLOR    =  3'd4;
parameter  OSD_X_OFFSET = 12'd0;
parameter  OSD_Y_OFFSET = 12'd0;

localparam OSD_WIDTH    = 12'd256;
localparam OSD_HEIGHT   = 12'd64;

// this core supports only the display related OSD commands
// of the minimig v1
reg osd_enable;
(* ramstyle = "no_rw_check" *) reg  [7:0] osd_buffer[4096];  // the OSD buffer itself

reg highres = 0;

// the OSD has its own SPI interface to the io controller
always@(posedge clk_sys) begin
	reg [11:0] bcnt;
	reg  [7:0] cmd;
	reg        has_cmd;
	reg        old_strobe;

	old_strobe <= io_strobe;

	if(~io_osd) begin
		bcnt <= 0;
		has_cmd <= 0;
	end else begin
		if(~old_strobe & io_strobe) begin
			if(!has_cmd) begin
				has_cmd <= 1;
				cmd <= io_din;
				// command 0x40: OSDCMDENABLE, OSDCMDDISABLE
				if(io_din[7:4] == 4'b0100) begin
					osd_enable <= io_din[0];
					if(!io_din[0]) highres <= 0;
				end
				bcnt <= {io_din[3:0], 8'h00};
				if(io_din[7:3] == 5'b00101) highres <= 1;
			end else begin
				// command 0x20: OSDCMDWRITE
				if(cmd[7:4] == 4'b0010) begin
					osd_buffer[bcnt] <= io_din;
					bcnt <= bcnt + 1'd1;
				end
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
	deD <= de;

	pixcnt <= pixcnt + 1;
	if(pixcnt == pixsz) pixcnt <= 0;
	ce_pix <= !pixcnt;

	if(~deD && de) cnt <= 0;

	if(deD && ~de) begin
		pixsz  <= (((cnt+1'b1) >> 9) > 1) ? (((cnt+1'b1) >> 9) - 1) : 0;
		pixcnt <= 0;
	end
end

reg  [23:0] h_cnt;
reg  [21:0] v_cnt;
reg  [21:0] dsp_width;
reg  [21:0] dsp_height;
reg   [7:0] osd_byte; 
reg  [21:0] osd_vcnt;
reg  [21:0] fheight;

wire [21:0] hrheight = (OSD_HEIGHT<<highres);

always @(posedge clk_video) begin
	reg       deD;
	reg [1:0] osd_div;
	reg [1:0] multiscan;
	
	if(ce_pix) begin

		deD <= de;
		if(~&h_cnt) h_cnt <= h_cnt + 1'd1;

		// falling edge of de
		if(!de && deD) dsp_width <= h_cnt[21:0];

		// rising edge of de
		if(de && !deD) begin
			v_cnt <= v_cnt + 1'd1;
			if(h_cnt > {dsp_width, 2'b00}) begin
				v_cnt <= 0;
				dsp_height <= v_cnt;
				
				if(v_cnt<320) begin
					multiscan <= 0;
					fheight <= hrheight;
				end
				else if(v_cnt<640) begin
					multiscan <= 1;
					fheight <= hrheight << 1;
				end
				else if(v_cnt<960) begin
					multiscan <= 2;
					fheight <= hrheight + (hrheight<<1);
				end
				else begin
					multiscan <= 3;
					fheight <= hrheight << 2;
				end
			end
			h_cnt <= 0;
			
			osd_div <= osd_div + 1'd1;
			if(osd_div == multiscan) begin
				osd_div <= 0;
				osd_vcnt <= osd_vcnt + 1'd1;
			end
			if(v_osd_start == (v_cnt+1'b1)) {osd_div, osd_vcnt} <= 0;
		end
		
		osd_byte <= osd_buffer[{osd_vcnt[6:3], osd_hcnt[7:0]}];
	end
end

// area in which OSD is being displayed
wire [21:0] h_osd_start = ((dsp_width - OSD_WIDTH)>>1) + OSD_X_OFFSET;
wire [21:0] h_osd_end   = h_osd_start + OSD_WIDTH;
wire [21:0] v_osd_start = ((dsp_height- fheight)>>1) + OSD_Y_OFFSET;
wire [21:0] v_osd_end   = v_osd_start + fheight;

wire [21:0] osd_hcnt    = h_cnt[21:0] - h_osd_start + 1'd1;

wire osd_de = osd_enable &&
              (h_cnt >= h_osd_start) && (h_cnt < h_osd_end) &&
              (v_cnt >= v_osd_start) && (v_cnt < v_osd_end);

wire osd_pixel = osd_byte[osd_vcnt[2:0]];


assign dout = !osd_de ? din : {{osd_pixel, osd_pixel, OSD_COLOR[2], din[23:19]},
                               {osd_pixel, osd_pixel, OSD_COLOR[1], din[15:11]},
                               {osd_pixel, osd_pixel, OSD_COLOR[0], din[7:3]}};

endmodule
