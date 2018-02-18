//============================================================================
//
//  HDMI Lite output module
//  Copyright (C) 2017 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//============================================================================


module hdmi_lite
(
	input          reset,

	input          clk_video,
	input          ce_pixel,
	input          video_vs,
	input          video_de,
	input   [23:0] video_d,

	input          clk_hdmi,
	input          hdmi_hde,
	input          hdmi_vde,
	output reg     hdmi_de,
	output  [23:0] hdmi_d,

	input   [11:0] screen_w,
	input   [11:0] screen_h,
	input          quadbuf,

	// 0-3 => scale 1-4
	input    [1:0] scale_x,
	input    [1:0] scale_y,
	input          scale_auto,

	input          clk_vbuf,
	output  [27:0] vbuf_address,
	input  [127:0] vbuf_readdata,
	output [127:0] vbuf_writedata,
	output   [7:0] vbuf_burstcount,
	output  [15:0] vbuf_byteenable,
	input          vbuf_waitrequest,
	input          vbuf_readdatavalid,
	output reg     vbuf_read,
	output reg     vbuf_write
);

localparam  [7:0] burstsz  = 64;

reg   [1:0] nbuf = 0;
wire [27:0] read_buf  = {4'd2, 3'b000, (quadbuf ? nbuf-2'd1 : 2'b00), 19'd0};
wire [27:0] write_buf = {4'd2, 3'b000, (quadbuf ? nbuf+2'd1 : 2'b00), 19'd0};

assign vbuf_address    = vbuf_write ? vbuf_waddress    : vbuf_raddress;
assign vbuf_burstcount = vbuf_write ? vbuf_wburstcount : vbuf_rburstcount;

wire [95:0] hf_out;
wire  [7:0] hf_usedw;
reg         hf_reset = 0;

vbuf_fifo out_fifo
(
	.aclr(hf_reset),

	.wrclk(clk_vbuf),
	.wrreq(vbuf_readdatavalid),
	.data({vbuf_readdata[96+:24],vbuf_readdata[64+:24],vbuf_readdata[32+:24],vbuf_readdata[0+:24]}),
	.wrusedw(hf_usedw),

	.rdclk(~clk_hdmi),
	.rdreq(hf_rdreq),
	.q(hf_out)
);

reg [11:0] rd_stride;
wire [7:0] rd_burst = (burstsz < rd_stride) ? burstsz : rd_stride[7:0];

reg [27:0] vbuf_raddress;
reg  [7:0] vbuf_rburstcount;
always @(posedge clk_vbuf) begin
	reg [18:0] rdcnt;
	reg  [7:0] bcnt;
	reg        vde1, vde2;
	reg  [1:0] mcnt;
	reg  [1:0] my;
	reg [18:0] fsz; 
	reg [11:0] strd;

	vde1 <= hdmi_vde;
	vde2 <= vde1;

	if(vbuf_readdatavalid) begin
		rdcnt <= rdcnt + 1'd1;
		if(bcnt) bcnt <= bcnt - 1'd1;
		vbuf_raddress <= vbuf_raddress + 1'd1;
	end

	if(!bcnt && reading) reading <= 0;

	vbuf_read <= 0;
	if(~vbuf_waitrequest) begin
		if(!hf_reset && rdcnt<fsz && !bcnt && hf_usedw < burstsz && allow_rd) begin
			vbuf_read <= 1;
			reading   <= 1;
			bcnt <= rd_burst;
			vbuf_rburstcount <= rd_burst;
			rd_stride <= rd_stride - rd_burst;
			if(!(rd_stride - rd_burst)) rd_stride <= strd;

			if(!rdcnt) begin
				vbuf_raddress <= read_buf;
				mcnt <= my;
			end
			else if (rd_stride == strd) begin
				mcnt <= mcnt - 1'd1;
				if(!mcnt) mcnt <= my;
					else vbuf_raddress <= vbuf_raddress - strd;
			end
		end
	end

	hf_reset <= 0;
	if(vde2 & ~vde1) begin
		hf_reset <= 1;
		rdcnt <= 0;
		bcnt <= 0;
		rd_stride <= stride;
		strd <= stride;
		fsz <= framesz;
		my <= mult_y;
	end
end


reg [11:0] off_x, off_y;
reg [11:0] x, y;
reg [11:0] vh_height;
reg [11:0] vh_width;
reg  [1:0] pcnt;
reg  [1:0] hload;
wire       hf_rdreq = (x>=off_x) && (x<(vh_width+off_x)) && (y>=off_y) && (y<(vh_height+off_y)) && !hload && !pcnt;
wire       de_in = hdmi_hde & hdmi_vde;

always @(posedge clk_hdmi) begin
	reg [71:0] px_out;
	reg  [1:0] mx;
	reg        vde;

	vde <= hdmi_vde;

	if(vde & ~hdmi_vde) begin
		off_x <= (screen_w>v_width)  ? (screen_w - v_width)>>1  : 12'd0;
		off_y <= (screen_h>v_height) ? (screen_h - v_height)>>1 : 12'd0;
		vh_height <= v_height;
		vh_width  <= v_width;
		mx <= mult_x;
	end

	pcnt <= pcnt + 1'd1;
	if(pcnt == mx) begin
		pcnt <= 0;
		hload <= hload + 1'd1;
	end 

	if(~de_in || x<off_x || y<off_y) begin
		hload <= 0;
		pcnt <= 0;
	end

	hdmi_de <= de_in;

	x <= x + 1'd1;
	if(~hdmi_de & de_in) x <= 0;
	if(hdmi_de & ~de_in) y <= y + 1'd1;
	if(~hdmi_vde) y <= 0;

	if(!pcnt) {px_out, hdmi_d} <= {24'd0, px_out};
	if(hf_rdreq) {px_out, hdmi_d} <= hf_out;
end

//////////////////////////////////////////////////////////////////////////////

reg reading = 0;
reg writing = 0;

reg op_split = 0;
always @(posedge clk_vbuf) op_split <= ~op_split;

wire allow_rd = ~reading & ~writing &  op_split & ~reset;
wire allow_wr = ~reading & ~writing & ~op_split & ~reset;

//////////////////////////////////////////////////////////////////////////////

reg         vf_rdreq = 0;
wire [95:0] vf_out;
assign      vbuf_writedata = {8'h00, vf_out[95:72], 8'h00, vf_out[71:48], 8'h00, vf_out[47:24], 8'h00, vf_out[23:0]};

vbuf_fifo in_fifo
(
	.aclr(video_vs),

	.rdclk(clk_vbuf),
	.rdreq(vf_rdreq & ~vbuf_waitrequest),
	.q(vf_out),

	.wrclk(clk_video),
	.wrreq(infifo_wr),
	.data({video_de ? video_d : 24'd0, pix_acc})
);

assign vbuf_byteenable = '1;

reg [35:0] addrque[3:0] = '{0,0,0,0};

reg  [7:0] flush_size;
reg [27:0] flush_addr;
reg        flush_req = 0;
reg        flush_ack = 0;

reg [27:0] vbuf_waddress;
reg  [7:0] vbuf_wburstcount;

always @(posedge clk_vbuf) begin
	reg [7:0] ibcnt = 0;
	reg       reqd = 0;
	
	reqd <= flush_req;

	if(~vbuf_waitrequest) begin
		vbuf_write <= vf_rdreq;
		if(~vf_rdreq && writing) writing <= 0;
		if(!vf_rdreq && !vbuf_write && addrque[0] && allow_wr) begin
			{vbuf_waddress, vbuf_wburstcount} <= addrque[0];
			ibcnt <= addrque[0][7:0];
			addrque[0] <= addrque[1];
			addrque[1] <= addrque[2];
			addrque[2] <= addrque[3];
			addrque[3] <= 0;
			vf_rdreq <= 1;
			writing <= 1;
		end
		else if(flush_ack != reqd) begin
				  if(!addrque[0]) addrque[0] <= {flush_addr, flush_size};
			else if(!addrque[1]) addrque[1] <= {flush_addr, flush_size};
			else if(!addrque[2]) addrque[2] <= {flush_addr, flush_size};
			else if(!addrque[3]) addrque[3] <= {flush_addr, flush_size};
			flush_ack <= reqd;
		end

		if(vf_rdreq) begin
			if(ibcnt == 1) vf_rdreq <= 0;
			ibcnt <= ibcnt - 1'd1;
		end
	end
end

reg  [11:0] stride;
reg  [18:0] framesz;
reg  [11:0] v_height;
reg  [11:0] v_width;
reg   [1:0] mult_x;
reg   [1:0] mult_y;

reg  [71:0] pix_acc;
wire        pix_wr = ce_pixel && video_de;

reg  [27:0] cur_addr;
reg  [11:0] video_x;
reg  [11:0] video_y;

wire        infifo_tail = ~video_de && video_x[1:0];
wire        infifo_wr = (pix_wr && &video_x[1:0]) || infifo_tail;

wire  [1:0] tm_y     = (video_y  > (screen_h/2)) ? 2'b00 : (video_y  > (screen_h/3)) ? 2'b01 : (video_y  > (screen_h/4)) ? 2'b10 : 2'b11;
wire  [1:0] tm_x     = (l1_width > (screen_w/2)) ? 2'b00 : (l1_width > (screen_w/3)) ? 2'b01 : (l1_width > (screen_w/4)) ? 2'b10 : 2'b11;
wire  [1:0] tm_xy    = (tm_x < tm_y) ? tm_x : tm_y;
wire  [1:0] tmf_y    = scale_auto ? tm_xy : scale_y;
wire  [1:0] tmf_x    = scale_auto ? tm_xy : scale_x;
wire [11:0] t_height = video_y  + (tmf_y[0] ? video_y  : 12'd0) + (tmf_y[1] ? video_y<<1  : 12'd0);
wire [11:0] t_width  = l1_width + (tmf_x[0] ? l1_width : 12'd0) + (tmf_x[1] ? l1_width<<1 : 12'd0);
wire [23:0] t_fsz    = l1_stride * t_height;

reg  [11:0] l1_width;
reg  [11:0] l1_stride;
always @(posedge clk_video) begin
	reg  [7:0] loaded = 0;
	reg [11:0] strd   = 0;
	reg        old_de = 0;
	reg        old_vs = 0;

	old_vs <= video_vs;
	if(~old_vs & video_vs) begin
		cur_addr<= write_buf;
		video_x <= 0;
		video_y <= 0;
		loaded  <= 0;
		strd <= 0;
		nbuf <= nbuf + 1'd1;

		stride  <= l1_stride;
		framesz <= t_fsz[18:0];
		v_height<= t_height;
		v_width <= t_width;
		mult_x  <= tmf_x;
		mult_y  <= tmf_y;
	end

	if(pix_wr) begin
		case(video_x[1:0])
			0: pix_acc        <= video_d; // zeroes upper bits too
			1: pix_acc[47:24] <= video_d;
			2: pix_acc[71:48] <= video_d;
			3: loaded <= loaded + 1'd1;
		endcase
		if(video_x<screen_w) video_x <= video_x + 1'd1;
	end

	old_de <= video_de;
	if((!video_x[1:0] && loaded >= burstsz) || (old_de & ~video_de)) begin
		if(loaded + infifo_tail) begin
			flush_size <= loaded + infifo_tail;
			flush_addr <= cur_addr;
			flush_req  <= ~flush_req;
			loaded <= 0;
			strd   <= strd + loaded;
		end

		cur_addr <= cur_addr + loaded + infifo_tail;
		if(~video_de) begin
			if(video_y<screen_h) video_y <= video_y + 1'd1;
			video_x <= 0;
			strd    <= 0;

			// measure width by first line (same as VIP)
			if(!video_y) begin
				l1_width <= video_x;
				l1_stride  <= strd + loaded + infifo_tail;
			end
		end
	end
end

endmodule

module vbuf_fifo
(
	input	        aclr,

	input	        rdclk,
	input	        rdreq,
	output [95:0] q,

	input	        wrclk,
	input	        wrreq,
	input	 [95:0] data,
	output  [7:0] wrusedw
);

dcfifo dcfifo_component
(
	.aclr (aclr),
	.data (data),
	.rdclk (rdclk),
	.rdreq (rdreq),
	.wrclk (wrclk),
	.wrreq (wrreq),
	.q (q),
	.wrusedw (wrusedw),
	.eccstatus (),
	.rdempty (),
	.rdfull (),
	.rdusedw (),
	.wrempty (),
	.wrfull ()
);

defparam
	dcfifo_component.intended_device_family = "Cyclone V",
	dcfifo_component.lpm_numwords = 256,
	dcfifo_component.lpm_showahead = "OFF",
	dcfifo_component.lpm_type = "dcfifo",
	dcfifo_component.lpm_width = 96,
	dcfifo_component.lpm_widthu = 8,
	dcfifo_component.overflow_checking = "ON",
	dcfifo_component.rdsync_delaypipe = 5,
	dcfifo_component.read_aclr_synch = "OFF",
	dcfifo_component.underflow_checking = "ON",
	dcfifo_component.use_eab = "ON",
	dcfifo_component.write_aclr_synch = "OFF",
	dcfifo_component.wrsync_delaypipe = 5;

endmodule
