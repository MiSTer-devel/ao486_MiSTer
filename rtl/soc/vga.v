/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

module vga
(
	input               clk_sys,
	input               rst_n,

	//avalon slave vga io
	input       [3:0]   io_address,
	input               io_read,
	output reg  [7:0]   io_readdata,
	input               io_write,
	input       [7:0]   io_writedata,
	input               io_b_cs,
	input               io_c_cs,
	input               io_d_cs,

	//avalon slave vga memory
	input       [16:0]  mem_address,
	input               mem_read,
	output      [7:0]   mem_readdata,
	input               mem_write,
	input       [7:0]   mem_writedata,

	//interrupt (IRQ2)
	output              irq,

	input               clk_vga,
	input      [27:0]   clock_rate_vga,

	//vga
	output              vga_ce,
	input               vga_f60,
	output      [2:0]   vga_memmode,
	output reg          vga_blank_n,
	output reg          vga_off,
	output reg          vga_horiz_sync,
	output reg          vga_vert_sync,
	output reg  [7:0]   vga_r,
	output reg  [7:0]   vga_g,
	output reg  [7:0]   vga_b,

	output reg [17:0]   vga_pal_d,
	output reg  [7:0]   vga_pal_a,
	output reg          vga_pal_we,

	output reg [19:0]   vga_start_addr,
	output reg  [5:0]   vga_wr_seg,
	output reg  [5:0]   vga_rd_seg,
	output reg  [8:0]   vga_width,
	output reg  [8:0]   vga_stride,
	output reg [10:0]   vga_height,
	output reg  [3:0]   vga_flags,
	
	input               vga_lores
);

wire io_b_read  = io_read  & io_b_cs;
wire io_b_write = io_write & io_b_cs;
wire io_c_read  = io_read  & io_c_cs;
wire io_c_write = io_write & io_c_cs;
wire io_d_read  = io_read  & io_d_cs;
wire io_d_write = io_write & io_d_cs;

always @(posedge clk_sys) begin
	io_readdata <= host_io_read_wire;
	if(io_c_cs) begin
		if(io_address == 4'h1 && attrib_io_index <= 5'hF) io_readdata <= host_palette_q;
		if(io_address == 4'h9 && ~dac_is_read)            io_readdata <= 8'h3F;
		if(io_address == 4'h9 && dac_cnt == 2'd0)         io_readdata <= dac_read_q[17:12];
		if(io_address == 4'h9 && dac_cnt == 2'd1)         io_readdata <= dac_read_q[11:6];
		if(io_address == 4'h9 && dac_cnt == 2'd2)         io_readdata <= dac_read_q[5:0];
	end
end

//------------------------------------------------------------------------------

reg [27:0] clk_rate;
always @(posedge clk_vga) clk_rate <= clock_rate_vga;

reg ce_video;
reg [27:0] pixclk = 25175000;
always @(posedge clk_vga) begin
	reg [27:0] sum = 0;
	
	ce_video = 0;
	sum = sum + pixclk;
	if(sum >= clk_rate) begin
		sum = sum - clk_rate;
		ce_video = 1;
	end
end

wire [4:0] clock_select = {crtc_reg31[7:6],crtc_reg34[1],general_clock_select};
reg [27:0] pixclk_orig;
always @(posedge clk_vga) begin
	case(clock_select[3:0])
		0 : pixclk_orig <= 25175000;
		1 : pixclk_orig <= 28322000;
		2 : pixclk_orig <= 32514000;
		default : pixclk_orig <= 35900000;
	endcase
end

always @(posedge clk_vga) begin
	reg [31:0] pixcnt = 0, pix60;
	reg old_sync = 0;
	
	if(~rst_n || ~vga_f60) pixclk <= (clk_rate<pixclk_orig) ? clk_rate : pixclk_orig;
	else if(ce_video) begin
		old_sync <= vga_vert_sync;
		pixcnt <= pixcnt + 1;
		if(~old_sync & vga_vert_sync) begin
			pix60 <= {pixcnt[26:0],5'd0}+{pixcnt[27:0],4'd0}+{pixcnt[28:0],3'd0}+{pixcnt[29:0],2'd0};
			pixcnt <= 0;
		end
		
		if(pix60<15000000) pixclk <= 15000000;
		else if(pix60>clk_rate) pixclk <= clk_rate;
		else pixclk <= pix60[27:0];
	end
end

reg io_b_read_last;
always @(posedge clk_sys) if(~rst_n) io_b_read_last <= 1'b0; else if(io_b_read_last) io_b_read_last <= 1'b0; else io_b_read_last <= io_b_read;
wire io_b_read_valid = io_b_read && ~io_b_read_last;

reg io_c_read_last;
always @(posedge clk_sys) if(~rst_n) io_c_read_last <= 1'b0; else if(io_c_read_last) io_c_read_last <= 1'b0; else io_c_read_last <= io_c_read;
wire io_c_read_valid = io_c_read && ~io_c_read_last;

reg io_d_read_last;
always @(posedge clk_sys) if(~rst_n) io_d_read_last <= 1'b0; else if(io_d_read_last) io_d_read_last <= 1'b0; else io_d_read_last <= io_d_read;
wire io_d_read_valid = io_d_read && ~io_d_read_last;

reg mem_read_last;
always @(posedge clk_sys) if(~rst_n) mem_read_last <= 1'b0; else if(mem_read_last) mem_read_last <= 1'b0; else mem_read_last <= mem_read;
wire mem_read_valid = mem_read && ~mem_read_last;

//------------------------------------------------------------------------------ sequencer io

reg seq_async_reset_n;
reg seq_sync_reset_n;

reg seq_8dot_char;

reg seq_dotclock_divided;

reg seq_screen_disable; //sync works, data blank

reg [3:0] seq_map_write_enable;

reg [2:0] seq_char_map_a; // depends on seq_access_256kb
reg [2:0] seq_char_map_b; // depends on seq_access_256kb

reg seq_access_256kb;
reg seq_access_odd_even_disabled;
reg seq_access_chain4;

// not implemented sequencer regs: 
reg seq_not_impl_shift_load_2;
reg seq_not_impl_shift_load_4;

//------------------------------------------------------------------------------

reg [7:0] seq_reg6, seq_reg7;
always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd6) seq_reg6 <= io_writedata[7:0];
always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd7) seq_reg7 <= io_writedata[7:0];

always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd0) seq_async_reset_n <= io_writedata[0];
always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd0) seq_sync_reset_n  <= io_writedata[1];

always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd1) seq_8dot_char        <= io_writedata[0];
always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd1) seq_dotclock_divided <= io_writedata[3];
always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd1) seq_screen_disable   <= io_writedata[5];

always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd2) seq_map_write_enable <= io_writedata[3:0];

always @(posedge clk_sys) begin
    if(~rst_n || ~seq_sync_reset_n || ~seq_async_reset_n)  seq_char_map_a <= 3'd0;
    else if(seq_io_write && seq_io_index == 3'd3)   seq_char_map_a <= { io_writedata[5], io_writedata[3:2] };
end

always @(posedge clk_sys) begin
    if(~rst_n || ~seq_sync_reset_n || ~seq_async_reset_n) seq_char_map_b <= 3'd0;
    else if(seq_io_write && seq_io_index == 3'd3)   seq_char_map_b <= { io_writedata[4], io_writedata[1:0] };
end

always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd4) seq_access_256kb             <= io_writedata[1];
always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd4) seq_access_odd_even_disabled <= io_writedata[2];
always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd4) seq_access_chain4            <= io_writedata[3];

always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd1) seq_not_impl_shift_load_2 <= io_writedata[2];
always @(posedge clk_sys) if(seq_io_write && seq_io_index == 3'd1) seq_not_impl_shift_load_4 <= io_writedata[4];

//------------------------------------------------------------------------------

reg [7:0] host_io_read_seq;
always @(*) begin
	case(seq_io_index)
			0: host_io_read_seq = { 6'd0, seq_sync_reset_n, seq_async_reset_n };
			1: host_io_read_seq = { 2'd0, seq_screen_disable, seq_not_impl_shift_load_4, seq_dotclock_divided, seq_not_impl_shift_load_2, 1'b0, seq_8dot_char };
			2: host_io_read_seq = { 4'd0, seq_map_write_enable };
			3: host_io_read_seq = { 2'd0, seq_char_map_a[2], seq_char_map_b[2], seq_char_map_a[1:0], seq_char_map_b[1:0] };
			4: host_io_read_seq = { 4'd0, seq_access_chain4, seq_access_odd_even_disabled, seq_access_256kb, 1'b0 };
			6: host_io_read_seq = seq_reg6;
			7: host_io_read_seq = seq_reg7;
	default: host_io_read_seq = 0;
	endcase;
end

//------------------------------------------------------------------------------ crtc io

reg [8:0]   crtc_horizontal_total;
reg [7:0]   crtc_horizontal_display_size;
reg [8:0]   crtc_horizontal_blanking_start;
reg [5:0]   crtc_horizontal_blanking_end;
reg [8:0]   crtc_horizontal_retrace_start;
reg [1:0]   crtc_horizontal_retrace_skew;
reg [4:0]   crtc_horizontal_retrace_end;

reg [10:0]  crtc_vertical_total;
reg [10:0]  crtc_vertical_retrace_start;
reg [3:0]   crtc_vertical_retrace_end;
reg [10:0]  crtc_vertical_display_size;
reg [10:0]  crtc_vertical_blanking_start;
reg [7:0]   crtc_vertical_blanking_end;

reg         crtc_vertical_doublescan;

reg [4:0]   crtc_row_preset;
reg [4:0]   crtc_row_max;
reg [4:0]   crtc_row_underline;

reg         crtc_cursor_off;
reg [4:0]   crtc_cursor_row_start;
reg [4:0]   crtc_cursor_row_end;
reg [1:0]   crtc_cursor_skew;

reg [19:0]  crtc_address_start;
reg [1:0]   crtc_address_byte_panning;
reg [8:0]   crtc_address_offset;
reg [19:0]  crtc_address_cursor;
reg         crtc_address_doubleword;
reg         crtc_address_byte;
reg         crtc_address_bit0;
reg         crtc_address_bit13;
reg         crtc_address_bit14;

reg         crtc_enable_sync;

reg [10:0]  crtc_line_compare;

reg         crtc_protect;

//not implemented crtc regs:
reg [1:0]   crtc_not_impl_display_enable_skew;
reg         crtc_not_impl_5_refresh_cycles;
reg         crtc_not_impl_scan_line_clk_div_2;
reg         crtc_not_impl_address_clk_div_2;
reg         crtc_not_impl_address_clk_div_4;


//------------------------------------------------------------------------------ interrupt
reg         crtc_clear_vert_int;
reg         crtc_enable_vert_int;

reg         interrupt = 0;
always @(posedge clk_sys) begin
	reg old_r1, old_r2;
	if(~rst_n) interrupt <=0;
	else begin
		old_r1 <= dot_memory_load_vertical_retrace_start;
		old_r2 <= old_r1;
		if(~crtc_enable_vert_int) begin
			if(~old_r2 & old_r1) interrupt <=1;
			if(~crtc_clear_vert_int) interrupt <=0;
		end
		else begin
			interrupt <=0;
		end
	end
end

assign irq = interrupt;

//------------------------------------------------------------------------------

reg [7:0] crtc_reg31, crtc_reg32, crtc_reg33, crtc_reg34, crtc_reg35, crtc_reg36, crtc_reg37, crtc_reg3f;
always @(posedge clk_sys) if(~rst_n) crtc_reg31 <= 0; else if(crtc_io_write && crtc_io_index == 'h31) crtc_reg31 <= io_writedata;
always @(posedge clk_sys) if(~rst_n) crtc_reg32 <= 0; else if(crtc_io_write && crtc_io_index == 'h32) crtc_reg32 <= io_writedata;
always @(posedge clk_sys) if(~rst_n) crtc_reg33 <= 0; else if(crtc_io_write && crtc_io_index == 'h33) crtc_reg33 <= io_writedata;
always @(posedge clk_sys) if(~rst_n) crtc_reg34 <= 0; else if(crtc_io_write && crtc_io_index == 'h34) crtc_reg34 <= io_writedata;
always @(posedge clk_sys) if(~rst_n) crtc_reg35 <= 0; else if(crtc_io_write && crtc_io_index == 'h35) crtc_reg35 <= io_writedata;
always @(posedge clk_sys) if(~rst_n) crtc_reg36 <= 0; else if(crtc_io_write && crtc_io_index == 'h36) crtc_reg36 <= io_writedata;
always @(posedge clk_sys) if(~rst_n) crtc_reg37 <= 0; else if(crtc_io_write && crtc_io_index == 'h37) crtc_reg37 <= io_writedata;
always @(posedge clk_sys) if(~rst_n) crtc_reg3f <= 0; else if(crtc_io_write && crtc_io_index == 'h3f) crtc_reg3f <= io_writedata;

always @(posedge clk_sys) begin
	if(~rst_n) begin
		crtc_address_start[19:16]  <= 0;
		crtc_address_cursor[19:16] <= 0;
	end
	else if(crtc_io_write && crtc_io_index == 6'h33) begin
		crtc_address_start[19:16]  <= io_writedata[3:0];
		crtc_address_cursor[19:16] <= io_writedata[7:4];
	end
end

always @(posedge clk_sys) begin
	if(~rst_n) begin
		crtc_vertical_blanking_start[10] <= 0;
		crtc_vertical_total[10]          <= 0;
		crtc_vertical_display_size[10]   <= 0;
		crtc_vertical_retrace_start[10]  <= 0;
		crtc_line_compare[10]            <= 0;
	end
	else if(crtc_io_write && crtc_io_index == 6'h35) begin
		crtc_vertical_blanking_start[10] <= io_writedata[0];
		crtc_vertical_total[10]          <= io_writedata[1];
		crtc_vertical_display_size[10]   <= io_writedata[2];
		crtc_vertical_retrace_start[10]  <= io_writedata[3];
		crtc_line_compare[10]            <= io_writedata[4];
	end
end

always @(posedge clk_sys) begin
	if(~rst_n) begin
		crtc_horizontal_total[8]          <= 0;
		crtc_horizontal_blanking_start[8] <= 0;
		crtc_horizontal_retrace_start[8]  <= 0;
		crtc_address_offset[8]            <= 0;
	end
	else if(crtc_io_write && crtc_io_index == 6'h3f) begin
		crtc_horizontal_total[8]          <= io_writedata[0];
		crtc_horizontal_blanking_start[8] <= io_writedata[2];
		crtc_horizontal_retrace_start[8]  <= io_writedata[4];
		crtc_address_offset[8]            <= io_writedata[7];
	end
end

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h00) crtc_horizontal_total[7:0]     <= io_writedata[7:0];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h01) crtc_horizontal_display_size   <= io_writedata[7:0];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h02) crtc_horizontal_blanking_start[7:0] <= io_writedata[7:0];

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h03) crtc_not_impl_display_enable_skew <= io_writedata[6:5];

always @(posedge clk_sys) begin
	if(crtc_io_write && crtc_io_index == 5'h03)      crtc_horizontal_blanking_end <= { crtc_horizontal_blanking_end[5], io_writedata[4:0] };
	else if(crtc_io_write && crtc_io_index == 5'h05) crtc_horizontal_blanking_end <= { io_writedata[7], crtc_horizontal_blanking_end[4:0] };
end

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h04) crtc_horizontal_retrace_start[7:0] <= io_writedata[7:0];

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h05) crtc_horizontal_retrace_skew <= io_writedata[6:5];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h05) crtc_horizontal_retrace_end  <= io_writedata[4:0];
        
always @(posedge clk_sys) begin
	if(crtc_io_write && crtc_io_index == 5'h06)      crtc_vertical_total[7:0] <= io_writedata[7:0];
	else if(crtc_io_write && crtc_io_index == 5'h07) crtc_vertical_total[9:8] <= { io_writedata[5], io_writedata[0] };
end        
        
always @(posedge clk_sys) begin
	if(crtc_io_write && crtc_io_index == 5'h10)      crtc_vertical_retrace_start[7:0] <= io_writedata[7:0];
	else if(crtc_io_write && crtc_io_index == 5'h07) crtc_vertical_retrace_start[9:8] <= { io_writedata[7], io_writedata[2] };
end

always @(posedge clk_sys) begin
	if(crtc_io_write && crtc_io_index == 5'h12)      crtc_vertical_display_size[7:0] <= io_writedata[7:0];
	else if(crtc_io_write && crtc_io_index == 5'h07) crtc_vertical_display_size[9:8] <= { io_writedata[6], io_writedata[1]};
end

always @(posedge clk_sys) begin
	if(crtc_io_write_compare && crtc_io_index == 5'h18)       crtc_line_compare[7:0] <= io_writedata[7:0];
	else if(crtc_io_write_compare && crtc_io_index == 5'h07)  crtc_line_compare[8]   <= io_writedata[4];
	else if(crtc_io_write_compare && crtc_io_index == 5'h09)  crtc_line_compare[9]   <= io_writedata[6];
end

always @(posedge clk_sys) begin
	if(crtc_io_write && crtc_io_index == 5'h15)       crtc_vertical_blanking_start[7:0] <= io_writedata[7:0];
	else if(crtc_io_write && crtc_io_index == 5'h07)  crtc_vertical_blanking_start[8]   <= io_writedata[3];
	else if(crtc_io_write && crtc_io_index == 5'h09)  crtc_vertical_blanking_start[9]   <= io_writedata[5];
end

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h08) crtc_address_byte_panning <= io_writedata[6:5];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h08) crtc_row_preset           <= io_writedata[4:0];

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h09) crtc_vertical_doublescan  <= io_writedata[7];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h09) crtc_row_max              <= io_writedata[4:0];

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h0A) crtc_cursor_off           <= io_writedata[5];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h0A) crtc_cursor_row_start     <= io_writedata[4:0];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h0B) crtc_cursor_skew          <= io_writedata[6:5];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h0B) crtc_cursor_row_end       <= io_writedata[4:0];

always @(posedge clk_sys) begin
    if(crtc_io_write && crtc_io_index == 5'h0C)      crtc_address_start[15:8] <= io_writedata[7:0];
    else if(crtc_io_write && crtc_io_index == 5'h0D) crtc_address_start[7:0]  <= io_writedata[7:0];
end

always @(posedge clk_sys) begin
	if(crtc_io_write && crtc_io_index == 5'h0E)      crtc_address_cursor[15:8] <= io_writedata[7:0];
	else if(crtc_io_write && crtc_io_index == 5'h0F) crtc_address_cursor[7:0]  <= io_writedata[7:0];
end

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h11) crtc_protect                   <= io_writedata[7];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h11) crtc_not_impl_5_refresh_cycles <= io_writedata[6];
always @(posedge clk_sys) if(~rst_n) crtc_enable_vert_int <=1; else if(crtc_io_write && crtc_io_index == 5'h11) crtc_enable_vert_int  <= io_writedata[5];
always @(posedge clk_sys) if(~rst_n) crtc_clear_vert_int  <=1; else if(crtc_io_write && crtc_io_index == 5'h11) crtc_clear_vert_int   <= io_writedata[4];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h11) crtc_vertical_retrace_end      <= io_writedata[3:0];

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h13) crtc_address_offset[7:0]       <= io_writedata[7:0];

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h14) crtc_address_doubleword        <= io_writedata[6];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h14) crtc_not_impl_address_clk_div_4<= io_writedata[5];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h14) crtc_row_underline             <= io_writedata[4:0];

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h16) crtc_vertical_blanking_end <= io_writedata[7:0];

always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h17) crtc_enable_sync                  <= io_writedata[7];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h17) crtc_address_byte                 <= io_writedata[6];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h17) crtc_address_bit0                 <= io_writedata[5];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h17) crtc_not_impl_address_clk_div_2   <= io_writedata[3];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h17) crtc_not_impl_scan_line_clk_div_2 <= io_writedata[2];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h17) crtc_address_bit14                <= io_writedata[1];
always @(posedge clk_sys) if(crtc_io_write && crtc_io_index == 5'h17) crtc_address_bit13                <= io_writedata[0];

//------------------------------------------------------------------------------

reg  [7:0] host_io_read_crtc;
always @(*) begin
	case(crtc_io_index)
		'h00: host_io_read_crtc = crtc_horizontal_total[7:0];
		'h01: host_io_read_crtc = crtc_horizontal_display_size;
		'h02: host_io_read_crtc = crtc_horizontal_blanking_start[7:0];
		'h03: host_io_read_crtc = { 1'b1, crtc_not_impl_display_enable_skew, crtc_horizontal_blanking_end[4:0] };
		'h04: host_io_read_crtc = crtc_horizontal_retrace_start[7:0];
		'h05: host_io_read_crtc = { crtc_horizontal_blanking_end[5], crtc_horizontal_retrace_skew, crtc_horizontal_retrace_end };
		'h06: host_io_read_crtc = crtc_vertical_total[7:0];
		'h07: host_io_read_crtc = { crtc_vertical_retrace_start[9], crtc_vertical_display_size[9], crtc_vertical_total[9], crtc_line_compare[8], crtc_vertical_blanking_start[8],
											 crtc_vertical_retrace_start[8], crtc_vertical_display_size[8], crtc_vertical_total[8] };
		'h08: host_io_read_crtc = { 1'b0, crtc_address_byte_panning, crtc_row_preset };
		'h09: host_io_read_crtc = { crtc_vertical_doublescan, crtc_line_compare[9], crtc_vertical_blanking_start[9], crtc_row_max };
		'h0A: host_io_read_crtc = { 2'b0, crtc_cursor_off, crtc_cursor_row_start };
		'h0B: host_io_read_crtc = { 1'b0, crtc_cursor_skew, crtc_cursor_row_end };
		'h0C: host_io_read_crtc = crtc_address_start[15:8];
		'h0D: host_io_read_crtc = crtc_address_start[7:0];
		'h0E: host_io_read_crtc = crtc_address_cursor[15:8];
		'h0F: host_io_read_crtc = crtc_address_cursor[7:0];
		'h10: host_io_read_crtc = crtc_vertical_retrace_start[7:0];
		'h11: host_io_read_crtc = { crtc_protect, crtc_not_impl_5_refresh_cycles, crtc_enable_vert_int, crtc_clear_vert_int, crtc_vertical_retrace_end };
		'h12: host_io_read_crtc = crtc_vertical_display_size[7:0];
		'h13: host_io_read_crtc = crtc_address_offset[7:0];
		'h14: host_io_read_crtc = { 1'b0, crtc_address_doubleword, crtc_not_impl_address_clk_div_4, crtc_row_underline };
		'h15: host_io_read_crtc = crtc_vertical_blanking_start[7:0];
		'h16: host_io_read_crtc = crtc_vertical_blanking_end;
		'h17: host_io_read_crtc = { crtc_enable_sync, crtc_address_byte, crtc_address_bit0, 1'b0, crtc_not_impl_address_clk_div_2, crtc_not_impl_scan_line_clk_div_2, crtc_address_bit14, crtc_address_bit13 };
		'h18: host_io_read_crtc = crtc_line_compare[7:0];
		'h31: host_io_read_crtc = crtc_reg31;
		'h32: host_io_read_crtc = crtc_reg32;
		'h33: host_io_read_crtc = crtc_reg33;
		'h34: host_io_read_crtc = crtc_reg34;
		'h35: host_io_read_crtc = crtc_reg35;
		'h36: host_io_read_crtc = crtc_reg36;
		'h37: host_io_read_crtc = crtc_reg37;
		'h3f: host_io_read_crtc = crtc_reg3f;
   default: host_io_read_crtc = 0;
	
	endcase
end

//------------------------------------------------------------------------------ graphic io                                    
                                    
reg [3:0] graph_color_compare_map;
reg [3:0] graph_color_compare_dont_care;

reg [3:0] graph_write_set_map;
reg [3:0] graph_write_enable_map;
reg [1:0] graph_write_function;
reg [2:0] graph_write_rotate;
reg [7:0] graph_write_mask;
reg [1:0] graph_write_mode;

reg [1:0] graph_read_map_select;
reg       graph_read_mode;

reg [1:0] graph_shift_mode;

reg [1:0] graph_system_memory;

//not implemented graphic regs:
reg       graph_not_impl_chain_odd_even;
reg       graph_not_impl_host_odd_even;
reg       graph_not_impl_graphic_mode;

//------------------------------------------------------------------------------

always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd0) graph_write_set_map     <= io_writedata[3:0];
always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd1) graph_write_enable_map  <= io_writedata[3:0];
always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd2) graph_color_compare_map <= io_writedata[3:0];

always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd3) graph_write_function <= io_writedata[4:3];
always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd3) graph_write_rotate   <= io_writedata[2:0];

always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd4) graph_read_map_select <= io_writedata[1:0];

always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd5) graph_shift_mode             <= io_writedata[6:5];
always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd5) graph_not_impl_host_odd_even <= io_writedata[4];
always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd5) graph_read_mode              <= io_writedata[3];
always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd5) graph_write_mode             <= io_writedata[1:0];

always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd6) graph_system_memory           <= io_writedata[3:2];
always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd6) graph_not_impl_chain_odd_even <= io_writedata[1];
always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd6) graph_not_impl_graphic_mode   <= io_writedata[0];

always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd7) graph_color_compare_dont_care <= io_writedata[3:0];

always @(posedge clk_sys) if(graph_io_write && graph_io_index == 4'd8) graph_write_mask <= io_writedata[7:0];

//------------------------------------------------------------------------------

reg [7:0] host_io_read_graph;

always @(*) begin
	case(graph_io_index)
			0: host_io_read_graph = { 4'b0, graph_write_set_map };
			1: host_io_read_graph = { 4'b0, graph_write_enable_map };
			2: host_io_read_graph = { 4'b0, graph_color_compare_map };
			3: host_io_read_graph = { 3'b0, graph_write_function, graph_write_rotate };
			4: host_io_read_graph = { 6'd0, graph_read_map_select };
			5: host_io_read_graph = { 1'b0, graph_shift_mode, graph_not_impl_host_odd_even, graph_read_mode, 1'b0, graph_write_mode };
			6: host_io_read_graph = { 4'd0, graph_system_memory, graph_not_impl_chain_odd_even, graph_not_impl_graphic_mode };
			7: host_io_read_graph = { 4'd0, graph_color_compare_dont_care };
			8: host_io_read_graph = graph_write_mask;
	default: host_io_read_graph = 0;
	endcase
end

//------------------------------------------------------------------------------ attribute io

reg       attrib_pelclock_div2;

reg       attrib_color_bit5_4_enable;
reg [1:0] attrib_color_bit7_6_value;
reg [1:0] attrib_color_bit5_4_value;

reg       attrib_panning_after_compare_match;

reg [3:0] attrib_panning_value;

reg       attrib_blinking;

reg       attrib_9bit_same_as_8bit;

reg       attrib_graphic_mode;

reg [7:0] attrib_color_overscan;

reg [3:0] attrib_mask;

//not implemented attribute regs:
reg attrib_not_impl_mono_emulation;

//------------------------------------------------------------------------------
reg [7:0] attrib_reg16, attrib_reg17;
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h16) attrib_reg16 <= io_writedata[7:0];
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h17) attrib_reg17 <= io_writedata[7:0];

always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h10) attrib_color_bit5_4_enable         <= io_writedata[7];
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h10) attrib_pelclock_div2               <= io_writedata[6];
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h10) attrib_panning_after_compare_match <= io_writedata[5];
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h10) attrib_blinking                    <= io_writedata[3];
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h10) attrib_9bit_same_as_8bit           <= io_writedata[2];
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h10) attrib_not_impl_mono_emulation     <= io_writedata[1];
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h10) attrib_graphic_mode                <= io_writedata[0];

always @(posedge clk_sys) if(~rst_n) attrib_color_overscan <= 8'd0; else if(attrib_io_write && attrib_io_index == 5'h11) attrib_color_overscan <= io_writedata[7:0];

always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h12) attrib_mask <= io_writedata[3:0];

always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h13) attrib_panning_value <= io_writedata[3:0];

always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h14) attrib_color_bit7_6_value <= io_writedata[3:2];
always @(posedge clk_sys) if(attrib_io_write && attrib_io_index == 5'h14) attrib_color_bit5_4_value <= io_writedata[1:0];

//------------------------------------------------------------------------------

wire [7:0] host_io_read_attrib =
    (attrib_io_index == 5'h10)?     { attrib_color_bit5_4_enable, attrib_pelclock_div2, attrib_panning_after_compare_match, 1'b0,
                                      attrib_blinking, attrib_9bit_same_as_8bit, attrib_not_impl_mono_emulation, attrib_graphic_mode } :
    (attrib_io_index == 5'h11)?     attrib_color_overscan :
    (attrib_io_index == 5'h12)?     { 4'd0, attrib_mask } :
    (attrib_io_index == 5'h13)?     { 4'd0, attrib_panning_value } :
    (attrib_io_index == 5'h14)?     { 4'd0, attrib_color_bit7_6_value, attrib_color_bit5_4_value } :
    (attrib_io_index == 5'h16)?     attrib_reg16 :
    (attrib_io_index == 5'h17)?     attrib_reg17 :
                                    8'h00;

//------------------------------------------------------------------------------ external io

reg general_vsync;
reg general_hsync;

reg general_enable_ram;
reg general_io_space;

//not implemented external regs:
reg [1:0] general_clock_select;
reg       general_not_impl_odd_even_page;

//------------------------------------------------------------------------------

always @(posedge clk_sys) if(general_io_write_misc) general_vsync <= io_writedata[7];
always @(posedge clk_sys) if(general_io_write_misc) general_hsync <= io_writedata[6];

always @(posedge clk_sys) if(general_io_write_misc) general_not_impl_odd_even_page <= io_writedata[5];

always @(posedge clk_sys) if(general_io_write_misc) general_clock_select <= io_writedata[3:2];

always @(posedge clk_sys) if(general_io_write_misc) general_enable_ram <= io_writedata[1];
always @(posedge clk_sys) if(general_io_write_misc) general_io_space   <= io_writedata[0];

//------------------------------------------------------------------------------ io

wire host_io_ignored = 
	(general_io_space    && (io_b_read_valid || io_b_write)) ||
	(~(general_io_space) && (io_d_read_valid || io_d_write));
    
reg [2:0] seq_io_index;
always @(posedge clk_sys) if(~rst_n) seq_io_index <= 3'd0; else if(io_c_write && io_address == 4'h4) seq_io_index <= io_writedata[2:0];

wire seq_io_write = io_c_write && io_address == 4'h5;

reg [5:0] crtc_io_index;
always @(posedge clk_sys) begin
	if(~rst_n)                                                      crtc_io_index <= 6'd0;
	else if(io_b_write && io_address == 4'h4 && ~(host_io_ignored)) crtc_io_index <= io_writedata[5:0];
	else if(io_d_write && io_address == 4'h4 && ~(host_io_ignored)) crtc_io_index <= io_writedata[5:0];
end

wire crtc_io_write = ((io_b_write && io_address == 4'd5) || (io_d_write && io_address == 4'd5)) && ~(host_io_ignored) && (~(crtc_protect) || crtc_io_index >= 5'd8);

wire crtc_io_write_compare = ((io_b_write && io_address == 4'd5) || (io_d_write && io_address == 4'd5)) && ~(host_io_ignored);

reg [3:0]   graph_io_index;
always @(posedge clk_sys) if(~rst_n) graph_io_index <= 4'd0; else if(io_c_write && io_address == 4'hE) graph_io_index <= io_writedata[3:0];

wire        graph_io_write = io_c_write && io_address == 4'hF;

reg [4:0]   attrib_io_index;
reg         attrib_video_enable;
reg         attrib_flip_flop;
reg         output_enable;
always @(posedge clk_sys) begin
	if(~rst_n) {output_enable, attrib_video_enable} <= 0;
	else if(io_c_write && io_address == 4'h0 && ~(attrib_flip_flop)) begin
		attrib_video_enable <= io_writedata[5];
		if(io_writedata[5]) output_enable <= 1;
	end
end

always @(posedge clk_sys) if(~rst_n) attrib_io_index <= 5'd0; else if(io_c_write && io_address == 4'h0 && ~(attrib_flip_flop)) attrib_io_index <= io_writedata[4:0];

always @(posedge clk_sys) begin
	if(~rst_n)                                                                                                          attrib_flip_flop <= 1'b0;
	else if(((io_b_read_valid && io_address == 4'hA) || (io_d_read_valid && io_address == 4'hA)) && ~(host_io_ignored)) attrib_flip_flop <= 1'b0;
	else if(io_c_write && io_address == 4'h0)                                                                           attrib_flip_flop <= ~attrib_flip_flop;
end

wire attrib_io_write = io_c_write && io_address == 4'h0 && attrib_flip_flop;

wire general_io_write_misc = io_c_write && io_address == 4'h2;

reg [5:0] seg_rd, seg_wr;
always @(posedge clk_sys) begin
	if(~rst_n) {seg_rd, seg_wr} <= 0;
	else if(~seq_sync_reset_n || ~seq_async_reset_n) {seg_rd, seg_wr} <= 0;
	else if(io_c_write && io_address == 'hD) {seg_rd[3:0], seg_wr[3:0]} <= io_writedata;
	else if(io_c_write && io_address == 'hB) {seg_rd[5:4], seg_wr[5:4]} <= {io_writedata[5:4],io_writedata[1:0]};
end

//------------------------------------------------------------------------------

reg [7:0] dac_mask;
always @(posedge clk_sys) if(~rst_n) dac_mask <= 8'hFF; else if(io_c_write && io_address == 4'h6) dac_mask <= io_writedata[7:0];

reg       dac_is_read;
always @(posedge clk_sys) begin
	if(~rst_n)                                dac_is_read <= 1'd0;
	else if(io_c_write && io_address == 4'h7) dac_is_read <= 1'b1;
	else if(io_c_write && io_address == 4'h8) dac_is_read <= 1'b0;
end

reg [11:0] dac_write_buffer;
always @(posedge clk_sys) begin
	if(~rst_n)                                dac_write_buffer <= 12'd0;
	else if(io_c_write && io_address == 4'h9) dac_write_buffer <= { dac_write_buffer[5:0], io_writedata[5:0] };
end

reg [7:0] dac_write_index;
always @(posedge clk_sys) begin
	if(~rst_n)                                                    dac_write_index <= 8'd0;
	else if(io_c_write && io_address == 4'h8)                     dac_write_index <= io_writedata[7:0];
	else if(io_c_write && io_address == 4'h9 && dac_cnt == 2'd2)  dac_write_index <= dac_write_index + 8'd1;
end

reg [7:0] dac_reg9;
always @(posedge clk_sys) begin
	if(~rst_n)                            dac_reg9 <= 8'd0;
	else if(io_c_write && io_address == 4'h9)  dac_reg9 <= io_writedata;
end

reg [7:0] dac_read_index;
always @(posedge clk_sys) begin
	if(~rst_n)                                                            dac_read_index <= 8'd0;
	else if(io_c_write && io_address == 4'h7)                             dac_read_index <= io_writedata[7:0];
	else if(io_c_read_valid  && io_address == 4'h9 && dac_cnt == 2'd2)    dac_read_index <= dac_read_index + 8'd1;
end

reg [1:0] dac_cnt;
always @(posedge clk_sys) begin
	if(~rst_n)                                                                        dac_cnt <= 2'd0;
	else if(io_c_write && io_address == 4'h7)                                         dac_cnt <= 2'd0;
	else if(io_c_write && io_address == 4'h8)                                         dac_cnt <= 2'd0;
	else if((io_c_read_valid || io_c_write) && io_address == 4'h9 && dac_cnt == 2'd2) dac_cnt <= 2'd0;
	else if((io_c_read_valid || io_c_write) && io_address == 4'h9)                    dac_cnt <= dac_cnt + 2'd1;
end

//------------------------------------------------------------------------------

wire host_io_vertical_retrace;
wire host_io_not_displaying;

wire [7:0] host_io_read_wire = 
	(host_io_ignored)                                            ? 8'hFF :
	(io_c_read_valid && io_address == 4'hC)                      ? { general_vsync, general_hsync, general_not_impl_odd_even_page, 1'b0, general_clock_select, general_enable_ram, general_io_space } : //misc output reg
	(io_c_read_valid && io_address == 4'h2)                      ? { interrupt, 2'b0, 1'b1, 4'b0 } : //input status 0
	((io_b_read_valid || io_d_read_valid) && io_address == 4'hA) ? { 4'b0, host_io_vertical_retrace, 2'b0, host_io_not_displaying } : //input status 1
	(io_c_read_valid && io_address == 4'h0 && attrib_flip_flop)  ? 8'h00 : //attrib index in write mode
	(io_c_read_valid && io_address == 4'h0)                      ? { 2'b0, attrib_video_enable, attrib_io_index } : //attrib in address mode
	(io_c_read_valid && io_address == 4'h1)                      ? host_io_read_attrib : //attrib read
	(io_c_read_valid && io_address == 4'h4)                      ? { 5'd0, seq_io_index } : //seq index
	(io_c_read_valid && io_address == 4'h5)                      ? host_io_read_seq : //seq data
	(io_c_read_valid && io_address == 4'h6)                      ? dac_mask : //pel mask
	(io_c_read_valid && io_address == 4'h7)                      ? { 6'd0, dac_is_read? 2'b11 : 2'b00 } : //dac state
	(io_c_read_valid && io_address == 4'h8)                      ? dac_write_index :
	(io_c_read_valid && io_address == 4'h9)                      ? dac_reg9 :
	(io_c_read_valid && io_address == 4'hB)                      ? { 2'b00, seg_rd[5:4], 2'b00, seg_wr[5:4] } :
	(io_c_read_valid && io_address == 4'hD)                      ? { seg_rd[3:0], seg_wr[3:0] } :
	(io_c_read_valid && io_address == 4'hE)                      ? { 4'd0, graph_io_index } :
	(io_c_read_valid && io_address == 4'hF)                      ? host_io_read_graph :
	(io_d_read_valid && io_address == 4'h4)                      ? { 2'b0, crtc_io_index } :
	((io_b_read_valid || io_d_read_valid) && io_address == 4'h5) ? host_io_read_crtc :
	(io_b_read_valid || io_d_read_valid)                         ? 8'hFF :
																						8'h00; // 6'h1A (Feature Control Register)

//------------------------------------------------------------------------------

wire host_memory_out_of_bounds =
	(graph_system_memory == 2'd1 && mem_address > 17'h0FFFF) ||
	(graph_system_memory == 2'd2 && (mem_address < 17'h10000 || mem_address > 17'h17FFF)) ||
	(graph_system_memory == 2'd3 && mem_address < 17'h17FFF);

wire [16:0] host_address_reduced =
	(graph_system_memory == 2'd1)?  { 1'b0, mem_address[15:0] } :
	(graph_system_memory == 2'd2)?  { 2'b0, mem_address[14:0] } :
	(graph_system_memory == 2'd3)?  { 2'b0, mem_address[14:0] } :
                                    mem_address;

wire [15:0] host_address =
	(seq_access_chain4)?                { host_address_reduced[15:2], 2'b00 } :
	(~(seq_access_odd_even_disabled))?  { host_address_reduced[15:1], 1'b0 } :
                                        host_address_reduced[15:0];

assign vga_memmode = {general_enable_ram, graph_system_memory};

//------------------------------------------------------------------------------ mem read

wire [7:0] host_ram0_q;
wire [7:0] host_ram1_q;
wire [7:0] host_ram2_q;
wire [7:0] host_ram3_q;

reg [7:0] host_ram0_reg;
reg [7:0] host_ram1_reg;
reg [7:0] host_ram2_reg;
reg [7:0] host_ram3_reg;

reg host_read_out_of_bounds;
always @(posedge clk_sys) begin
	if(~rst_n)                                           host_read_out_of_bounds <= 1'b0;
	else if(mem_read_valid && host_memory_out_of_bounds) host_read_out_of_bounds <= 1'b1;
	else                                                 host_read_out_of_bounds <= 1'b0;
end

reg [16:0] host_address_reduced_last;
always @(posedge clk_sys) begin
	if(~rst_n)              host_address_reduced_last <= 17'd0;
	else if(mem_read_valid) host_address_reduced_last <= host_address_reduced;
end

reg host_read_last;
always @(posedge clk_sys) begin
	if(~rst_n)   host_read_last <= 1'd0;
	else         host_read_last <= mem_read_valid && ~(host_memory_out_of_bounds);
end

wire [7:0] host_read_mode_1 = {
	(graph_color_compare_dont_care[0]? ~(host_ram0_q[7] ^ graph_color_compare_map[0]) : 1'b1) & (graph_color_compare_dont_care[1]? ~(host_ram1_q[7] ^ graph_color_compare_map[1]) : 1'b1) &
	(graph_color_compare_dont_care[2]? ~(host_ram2_q[7] ^ graph_color_compare_map[2]) : 1'b1) & (graph_color_compare_dont_care[3]? ~(host_ram3_q[7] ^ graph_color_compare_map[3]) : 1'b1),
	(graph_color_compare_dont_care[0]? ~(host_ram0_q[6] ^ graph_color_compare_map[0]) : 1'b1) & (graph_color_compare_dont_care[1]? ~(host_ram1_q[6] ^ graph_color_compare_map[1]) : 1'b1) &
	(graph_color_compare_dont_care[2]? ~(host_ram2_q[6] ^ graph_color_compare_map[2]) : 1'b1) & (graph_color_compare_dont_care[3]? ~(host_ram3_q[6] ^ graph_color_compare_map[3]) : 1'b1),
	(graph_color_compare_dont_care[0]? ~(host_ram0_q[5] ^ graph_color_compare_map[0]) : 1'b1) & (graph_color_compare_dont_care[1]? ~(host_ram1_q[5] ^ graph_color_compare_map[1]) : 1'b1) &
	(graph_color_compare_dont_care[2]? ~(host_ram2_q[5] ^ graph_color_compare_map[2]) : 1'b1) & (graph_color_compare_dont_care[3]? ~(host_ram3_q[5] ^ graph_color_compare_map[3]) : 1'b1),
	(graph_color_compare_dont_care[0]? ~(host_ram0_q[4] ^ graph_color_compare_map[0]) : 1'b1) & (graph_color_compare_dont_care[1]? ~(host_ram1_q[4] ^ graph_color_compare_map[1]) : 1'b1) &
	(graph_color_compare_dont_care[2]? ~(host_ram2_q[4] ^ graph_color_compare_map[2]) : 1'b1) & (graph_color_compare_dont_care[3]? ~(host_ram3_q[4] ^ graph_color_compare_map[3]) : 1'b1),
	(graph_color_compare_dont_care[0]? ~(host_ram0_q[3] ^ graph_color_compare_map[0]) : 1'b1) & (graph_color_compare_dont_care[1]? ~(host_ram1_q[3] ^ graph_color_compare_map[1]) : 1'b1) &
	(graph_color_compare_dont_care[2]? ~(host_ram2_q[3] ^ graph_color_compare_map[2]) : 1'b1) & (graph_color_compare_dont_care[3]? ~(host_ram3_q[3] ^ graph_color_compare_map[3]) : 1'b1),
	(graph_color_compare_dont_care[0]? ~(host_ram0_q[2] ^ graph_color_compare_map[0]) : 1'b1) & (graph_color_compare_dont_care[1]? ~(host_ram1_q[2] ^ graph_color_compare_map[1]) : 1'b1) &
	(graph_color_compare_dont_care[2]? ~(host_ram2_q[2] ^ graph_color_compare_map[2]) : 1'b1) & (graph_color_compare_dont_care[3]? ~(host_ram3_q[2] ^ graph_color_compare_map[3]) : 1'b1),
	(graph_color_compare_dont_care[0]? ~(host_ram0_q[1] ^ graph_color_compare_map[0]) : 1'b1) & (graph_color_compare_dont_care[1]? ~(host_ram1_q[1] ^ graph_color_compare_map[1]) : 1'b1) &
	(graph_color_compare_dont_care[2]? ~(host_ram2_q[1] ^ graph_color_compare_map[2]) : 1'b1) & (graph_color_compare_dont_care[3]? ~(host_ram3_q[1] ^ graph_color_compare_map[3]) : 1'b1),
	(graph_color_compare_dont_care[0]? ~(host_ram0_q[0] ^ graph_color_compare_map[0]) : 1'b1) & (graph_color_compare_dont_care[1]? ~(host_ram1_q[0] ^ graph_color_compare_map[1]) : 1'b1) &
	(graph_color_compare_dont_care[2]? ~(host_ram2_q[0] ^ graph_color_compare_map[2]) : 1'b1) & (graph_color_compare_dont_care[3]? ~(host_ram3_q[0] ^ graph_color_compare_map[3]) : 1'b1)
};

assign mem_readdata =
	(host_read_out_of_bounds)                                                               ? 8'hFF      :
	(seq_access_chain4 && host_address_reduced_last[1:0] == 2'b00)                          ? host_ram0_q:
	(seq_access_chain4 && host_address_reduced_last[1:0] == 2'b01)                          ? host_ram1_q:
	(seq_access_chain4 && host_address_reduced_last[1:0] == 2'b10)                          ? host_ram2_q:
	(seq_access_chain4 && host_address_reduced_last[1:0] == 2'b11)                          ? host_ram3_q:
	(~graph_read_mode  && ~(seq_access_odd_even_disabled) && ~host_address_reduced_last[0]) ? host_ram0_q:
	(~graph_read_mode  && ~(seq_access_odd_even_disabled) && host_address_reduced_last[0])  ? host_ram1_q:
	(~graph_read_mode  && graph_read_map_select == 2'd0)                                    ? host_ram0_q:
	(~graph_read_mode  && graph_read_map_select == 2'd1)                                    ? host_ram1_q:
	(~graph_read_mode  && graph_read_map_select == 2'd2)                                    ? host_ram2_q:
	(~graph_read_mode  && graph_read_map_select == 2'd3)                                    ? host_ram3_q:
																			                                    host_read_mode_1;

always @(posedge clk_sys) begin
	if(~rst_n) begin
		{ host_ram0_reg, host_ram1_reg, host_ram2_reg, host_ram3_reg } <= 0;
	end
	else
	if(host_read_last) begin
		{ host_ram0_reg, host_ram1_reg, host_ram2_reg, host_ram3_reg } <= { host_ram0_q, host_ram1_q, host_ram2_q, host_ram3_q };
	end
end


//------------------------------------------------------------------------------ mem write

wire host_write = mem_write && ~(host_memory_out_of_bounds);

reg  [7:0] host_writedata_rotate;
always @(*) begin
	case(graph_write_rotate)
		0: host_writedata_rotate =   mem_writedata[7:0];
		1: host_writedata_rotate = { mem_writedata[0],   mem_writedata[7:1] };
		2: host_writedata_rotate = { mem_writedata[1:0], mem_writedata[7:2] };
		3: host_writedata_rotate = { mem_writedata[2:0], mem_writedata[7:3] };
		4: host_writedata_rotate = { mem_writedata[3:0], mem_writedata[7:4] };
		5: host_writedata_rotate = { mem_writedata[4:0], mem_writedata[7:5] };
		6: host_writedata_rotate = { mem_writedata[5:0], mem_writedata[7:6] };
		7: host_writedata_rotate = { mem_writedata[6:0], mem_writedata[7]   };
	endcase
end


wire [7:0] host_write_set_0 = (graph_write_mode == 2'd2)? {8{mem_writedata[0]}} : graph_write_enable_map[0]?  {8{graph_write_set_map[0]}} : host_writedata_rotate;
wire [7:0] host_write_set_1 = (graph_write_mode == 2'd2)? {8{mem_writedata[1]}} : graph_write_enable_map[1]?  {8{graph_write_set_map[1]}} : host_writedata_rotate;
wire [7:0] host_write_set_2 = (graph_write_mode == 2'd2)? {8{mem_writedata[2]}} : graph_write_enable_map[2]?  {8{graph_write_set_map[2]}} : host_writedata_rotate;
wire [7:0] host_write_set_3 = (graph_write_mode == 2'd2)? {8{mem_writedata[3]}} : graph_write_enable_map[3]?  {8{graph_write_set_map[3]}} : host_writedata_rotate;

reg [31:0] host_write_function;
always @(*) begin
	case(graph_write_function)
		0: host_write_function = { host_write_set_3, host_write_set_2, host_write_set_1, host_write_set_0 };
		1: host_write_function = { host_write_set_3, host_write_set_2, host_write_set_1, host_write_set_0 } & { host_ram3_reg, host_ram2_reg, host_ram1_reg, host_ram0_reg };
		2: host_write_function = { host_write_set_3, host_write_set_2, host_write_set_1, host_write_set_0 } | { host_ram3_reg, host_ram2_reg, host_ram1_reg, host_ram0_reg };
		3: host_write_function = { host_write_set_3, host_write_set_2, host_write_set_1, host_write_set_0 } ^ { host_ram3_reg, host_ram2_reg, host_ram1_reg, host_ram0_reg };
	endcase
end

wire [7:0] host_write_mask_0 = (graph_write_mask & host_write_function[7:0])   | (~(graph_write_mask) & host_ram0_reg);
wire [7:0] host_write_mask_1 = (graph_write_mask & host_write_function[15:8])  | (~(graph_write_mask) & host_ram1_reg);
wire [7:0] host_write_mask_2 = (graph_write_mask & host_write_function[23:16]) | (~(graph_write_mask) & host_ram2_reg);
wire [7:0] host_write_mask_3 = (graph_write_mask & host_write_function[31:24]) | (~(graph_write_mask) & host_ram3_reg);

wire [7:0] host_write_mode_3_mask = host_writedata_rotate & graph_write_mask;
wire [7:0] host_write_mode_3_ram0 = (host_write_mode_3_mask & {8{graph_write_set_map[0]}})   | (~(host_write_mode_3_mask) & host_ram0_reg);
wire [7:0] host_write_mode_3_ram1 = (host_write_mode_3_mask & {8{graph_write_set_map[1]}})   | (~(host_write_mode_3_mask) & host_ram1_reg);
wire [7:0] host_write_mode_3_ram2 = (host_write_mode_3_mask & {8{graph_write_set_map[2]}})   | (~(host_write_mode_3_mask) & host_ram2_reg);
wire [7:0] host_write_mode_3_ram3 = (host_write_mode_3_mask & {8{graph_write_set_map[3]}})   | (~(host_write_mode_3_mask) & host_ram3_reg);

reg [31:0] host_writedata;
always @(*) begin
	case(graph_write_mode)
		0: host_writedata = { host_write_mask_3,      host_write_mask_2,      host_write_mask_1,      host_write_mask_0 };
		1: host_writedata = { host_ram3_reg,          host_ram2_reg,          host_ram1_reg,          host_ram0_reg };
		2: host_writedata = { host_write_mask_3,      host_write_mask_2,      host_write_mask_1,      host_write_mask_0 };
		3: host_writedata = { host_write_mode_3_ram3, host_write_mode_3_ram2, host_write_mode_3_ram1, host_write_mode_3_ram0 };
	endcase
end

wire [3:0] host_write_enable_for_chain4   = (4'b0001 << host_address_reduced[1:0]);
wire [3:0] host_write_enable_for_odd_even = (4'b0101 << host_address_reduced[0]);
                                            
wire [3:0] host_write_enable = 
    {4{host_write}} & seq_map_write_enable & (
    (seq_access_chain4)?                host_write_enable_for_chain4 :
    (~(seq_access_odd_even_disabled))?  host_write_enable_for_odd_even :
                                        4'b1111); 

//------------------------------------------------------------------------------

wire dot_memory_load;
wire dot_memory_load_first_in_frame;
wire dot_memory_load_first_in_line_matched;
wire dot_memory_load_first_in_line;
wire dot_memory_load_vertical_retrace_start;

wire memory_address_load = dot_memory_load_first_in_frame || dot_memory_load_first_in_line_matched || dot_memory_load_first_in_line;

reg [15:0] memory_start_line;
always @(posedge clk_vga) if (ce_video) if(memory_address_load) memory_start_line <= memory_address;

reg [15:0] memory_address_reg;
always @(posedge clk_vga) if (ce_video) if(memory_address_load || dot_memory_load) memory_address_reg <= memory_address;

reg [4:0] memory_row_scan_reg;
always @(posedge clk_vga) if (ce_video) if(memory_address_load) memory_row_scan_reg <= memory_row_scan;

reg memory_row_scan_double;
always @(posedge clk_vga) if (ce_video) begin
    if(crtc_vertical_doublescan && (dot_memory_load_first_in_frame || dot_memory_load_first_in_line_matched))  memory_row_scan_double <= 1'b1;
    else if(crtc_vertical_doublescan && dot_memory_load_first_in_line)                                         memory_row_scan_double <= ~memory_row_scan_double;
    else if(~(crtc_vertical_doublescan) || dot_memory_load_vertical_retrace_start)                             memory_row_scan_double <= 1'b0;
end

//do not change charmap in the middle of a character row scan
reg [2:0] memory_char_map_a;
always @(posedge clk_vga) if (ce_video) begin
    if(dot_memory_load_first_in_frame || dot_memory_load_first_in_line_matched || (dot_memory_load_first_in_line && memory_row_scan == 5'd0))  memory_char_map_a <= seq_char_map_a;
end

reg [2:0] memory_char_map_b;
always @(posedge clk_vga) if (ce_video) begin
    if(dot_memory_load_first_in_frame || dot_memory_load_first_in_line_matched || (dot_memory_load_first_in_line && memory_row_scan == 5'd0))  memory_char_map_b <= seq_char_map_b;
end


reg [3:0] memory_panning_reg;
always @(posedge clk_vga) if (ce_video) begin
    if(dot_memory_load_first_in_line_matched && attrib_panning_after_compare_match)    memory_panning_reg <= 4'd0;
    else if(dot_memory_load_first_in_frame)                                            memory_panning_reg <= attrib_panning_value;
end

reg memory_load_step_a;
always @(posedge clk_vga) if (ce_video) begin
    if(dot_memory_load)    memory_load_step_a <= 1'b1;
    else                   memory_load_step_a <= 1'b0;
end

reg memory_load_step_b;
always @(posedge clk_vga) if (ce_video) begin
    if(memory_load_step_a) memory_load_step_b <= 1'b1;
    else                   memory_load_step_b <= 1'b0;
end

wire [15:0] memory_address =
    (dot_memory_load_first_in_line_matched)?                                16'd0 :
    (dot_memory_load_first_in_frame)?                                       crtc_address_start[15:0] + { 14'd0, crtc_address_byte_panning } :
    (dot_memory_load_first_in_line && memory_row_scan_double)?              memory_start_line :
    (dot_memory_load_first_in_line && memory_row_scan_reg < crtc_row_max)?  memory_start_line :
    (dot_memory_load_first_in_line)?                                        memory_start_line + { 6'd0, crtc_address_offset[8:0], 1'b0 } :
    (dot_memory_load)?                                                      memory_address_reg + 16'd1 :
                                                                            memory_address_reg;
    
wire [4:0] memory_row_scan =
    (dot_memory_load_first_in_line_matched)?                                5'd0 :
    (dot_memory_load_first_in_frame && crtc_row_preset <= crtc_row_max)?    crtc_row_preset :
    (dot_memory_load_first_in_frame)?                                       5'd0 :
    (dot_memory_load_first_in_line && memory_row_scan_double)?              memory_row_scan_reg :
    (dot_memory_load_first_in_line && memory_row_scan_reg == crtc_row_max)? 5'd0 :
    (dot_memory_load_first_in_line)?                                        memory_row_scan_reg + 5'd1 :
                                                                            memory_row_scan_reg;

wire [15:0] memory_address_step_1 =
    (crtc_address_doubleword)?  { memory_address[13:0], memory_address[15:14] } :
    (crtc_address_byte)?        memory_address :
    (crtc_address_bit0)?        { memory_address[14:0], memory_address[15] } :
                                { memory_address[14:0], memory_address[13] };

wire [15:0] memory_address_step_2 = {
    memory_address_step_1[15],
    (crtc_address_bit14)?           memory_address_step_1[14] : memory_row_scan[1],
    (crtc_address_bit13)?           memory_address_step_1[13] : memory_row_scan[0],
    memory_address_step_1[12:0]
};

reg [15:0] memory_address_reg_final;
always @(posedge clk_vga) if (ce_video) if(dot_memory_load) memory_address_reg_final <= memory_address;

wire [2:0] memory_txt_index = plane_ram1_q[3]? memory_char_map_a : memory_char_map_b;

wire [15:0] memory_txt_address_base =
    ((~(seq_access_256kb) && ~memory_txt_index[2]) || memory_txt_index == 3'b000)?   16'h0000 :
    ((~(seq_access_256kb) &&  memory_txt_index[2]) || memory_txt_index == 3'b100)?   16'h2000 :
    (memory_txt_index == 3'b001)?                                                    16'h4000 :
    (memory_txt_index == 3'b101)?                                                    16'h6000 :
    (memory_txt_index == 3'b010)?                                                    16'h8000 :
    (memory_txt_index == 3'b110)?                                                    16'hA000 :
    (memory_txt_index == 3'b011)?                                                    16'hC000 :
                                                                                     16'hE000;

wire [15:0] memory_txt_address = { memory_txt_address_base[15:13], plane_ram0_q[7:0], memory_row_scan_reg };

//------------------------------------------------------------------------------

wire [7:0] plane_ram0_q;
wire [7:0] plane_ram1_q;
wire [7:0] plane_ram2_q;
wire [7:0] plane_ram3_q;

dpram_difclk #(16,8,16,8) plane_ram_0
(
	.clk_a          (clk_sys),
	.address_a      (host_address),
	.data_a         (host_writedata[7:0]),
	.wren_a         (general_enable_ram && host_write_enable[0]),
	.q_a            (host_ram0_q),

	.clk_b          (clk_vga),
	.enable_b       (ce_video),
	.address_b      (memory_address_step_2),
	.q_b            (plane_ram0_q)
);

dpram_difclk #(16,8,16,8) plane_ram_1
(
	.clk_a          (clk_sys),
	.address_a      (host_address),
	.data_a         (host_writedata[15:8]),
	.wren_a         (general_enable_ram && host_write_enable[1]),
	.q_a            (host_ram1_q),

	.clk_b          (clk_vga),
	.enable_b       (ce_video),
	.address_b      (memory_address_step_2),
	.q_b            (plane_ram1_q)
);

dpram_difclk #(16,8,16,8) plane_ram_2
(
	.clk_a          (clk_sys),
	.address_a      (host_address),
	.data_a         (host_writedata[23:16]),
	.wren_a         (general_enable_ram && host_write_enable[2]),
	.q_a            (host_ram2_q),

	.clk_b          (clk_vga),
	.enable_b       (ce_video),
	.address_b      (memory_load_step_a ? memory_txt_address : memory_address_step_2),
	.q_b            (plane_ram2_q)
);

dpram_difclk #(16,8,16,8) plane_ram_3
(
	.clk_a          (clk_sys),
	.address_a      (host_address),
	.data_a         (host_writedata[31:24]),
	.wren_a         (general_enable_ram && host_write_enable[3]),
	.q_a            (host_ram3_q),

	.clk_b          (clk_vga),
	.enable_b       (ce_video),
	.address_b      (memory_address_step_2),
	.q_b            (plane_ram3_q)
);

//------------------------------------------------------------------------------

reg [7:0] plane_ram0;
reg [7:0] plane_ram1;
reg [7:0] plane_ram2;
reg [7:0] plane_ram3;

always @(posedge clk_vga) if (ce_video) if(memory_load_step_a) plane_ram0 <= plane_ram0_q;
always @(posedge clk_vga) if (ce_video) if(memory_load_step_a) plane_ram1 <= plane_ram1_q;
always @(posedge clk_vga) if (ce_video) if(memory_load_step_a) plane_ram2 <= plane_ram2_q;
always @(posedge clk_vga) if (ce_video) if(memory_load_step_a) plane_ram3 <= plane_ram3_q;

//------------------------------------------------------------------------------

reg [5:0] plane_shift_cnt;
always @(posedge clk_vga) if (ce_video) begin
	if(memory_load_step_b)         plane_shift_cnt <= 6'd1;
	else if(plane_shift_cnt == 6'd34)   plane_shift_cnt <= 6'd0;
	else if(plane_shift_cnt != 6'd0)    plane_shift_cnt <= plane_shift_cnt + 6'd1;
end

wire plane_shift_enable = 
    (~(seq_dotclock_divided) && plane_shift_cnt >= 6'd1) ||
    (  seq_dotclock_divided  && plane_shift_cnt >= 6'd1 && plane_shift_cnt[0]);
    
wire plane_shift_9dot =
    ~(seq_8dot_char) && plane_shift_enable &&
    (~(seq_dotclock_divided) && plane_shift_cnt == 6'd9) ||
    (  seq_dotclock_divided  && plane_shift_cnt == 6'd17);

//------------------------------------------------------------------------------

reg [7:0] plane_shift0;
reg [7:0] plane_shift1;
reg [7:0] plane_shift2;
reg [7:0] plane_shift3;

wire [7:0] plane_shift_value0 =
    (graph_shift_mode == 2'b00)? plane_ram0 :
    (graph_shift_mode == 2'b01)? { plane_ram0[6],plane_ram0[4],plane_ram0[2],plane_ram0[0], plane_ram1[6],plane_ram1[4],plane_ram1[2],plane_ram1[0] } :
                                 { plane_ram0[4],plane_ram0[0],plane_ram1[4],plane_ram1[0], plane_ram2[4],plane_ram2[0],plane_ram3[4],plane_ram3[0] };

wire [7:0] plane_shift_value1 =
    (graph_shift_mode == 2'b00)? plane_ram1 :
    (graph_shift_mode == 2'b01)? { plane_ram0[7],plane_ram0[5],plane_ram0[3],plane_ram0[1], plane_ram1[7],plane_ram1[5],plane_ram1[3],plane_ram1[1] } :
                                 { plane_ram0[5],plane_ram0[1],plane_ram1[5],plane_ram1[1], plane_ram2[5],plane_ram2[1],plane_ram3[5],plane_ram3[1] };

wire [7:0] plane_shift_value2 =
    (graph_shift_mode == 2'b00)? plane_ram2 :
    (graph_shift_mode == 2'b01)? { plane_ram2[6],plane_ram2[4],plane_ram2[2],plane_ram2[0], plane_ram3[6],plane_ram3[4],plane_ram3[2],plane_ram3[0] } :
                                 { plane_ram0[6],plane_ram0[2],plane_ram1[6],plane_ram1[2], plane_ram2[6],plane_ram2[2],plane_ram3[6],plane_ram3[2] };

wire [7:0] plane_shift_value3 =
    (graph_shift_mode == 2'b00)? plane_ram3 :
    (graph_shift_mode == 2'b01)? { plane_ram2[7],plane_ram2[5],plane_ram2[3],plane_ram2[1], plane_ram3[7],plane_ram3[5],plane_ram3[3],plane_ram3[1] } :
                                 { plane_ram0[7],plane_ram0[3],plane_ram1[7],plane_ram1[3], plane_ram2[7],plane_ram2[3],plane_ram3[7],plane_ram3[3] };

always @(posedge clk_vga) if (ce_video) begin
	if(memory_load_step_b) plane_shift0 <= plane_shift_value0;
	else if(plane_shift_enable) plane_shift0 <= { plane_shift0[6:0], 1'b0 };
end

always @(posedge clk_vga) if (ce_video) begin
	if(memory_load_step_b) plane_shift1 <= plane_shift_value1;
	else if(plane_shift_enable) plane_shift1 <= { plane_shift1[6:0], 1'b0 };
end

always @(posedge clk_vga) if (ce_video) begin
	if(memory_load_step_b) plane_shift2 <= plane_shift_value2;
	else if(plane_shift_enable) plane_shift2 <= { plane_shift2[6:0], 1'b0 };
end

always @(posedge clk_vga) if (ce_video) begin
	if(memory_load_step_b) plane_shift3 <= plane_shift_value3;
	else if(plane_shift_enable) plane_shift3 <= { plane_shift3[6:0], 1'b0 };
end

//------------------------------------------------------------------------------

reg [7:0] plane_txt_shift;

wire blink_txt_value;
wire blink_cursor_value;

wire txt_blink_enabled = attrib_blinking && plane_ram1[7] && blink_txt_value;

wire txt_underline_enable = plane_ram1[2:0] == 3'b001 && plane_ram1[6:4] == 3'b000 && crtc_row_underline > 5'd0 && crtc_row_underline - 5'd1 == memory_row_scan_reg;

wire txt_cursor_enable =
    ~(crtc_cursor_off) &&
    blink_cursor_value &&
    memory_address_reg_final == crtc_address_cursor + { 14'd0, crtc_cursor_skew } &&
    memory_row_scan_reg >= crtc_cursor_row_start &&
    memory_row_scan_reg <= crtc_cursor_row_end &&
    crtc_cursor_row_start <= crtc_cursor_row_end;

wire [7:0] plane_txt_shift_value =
    (txt_blink_enabled)?        8'd0 :
    (txt_underline_enable)?     8'hFF :
    (txt_cursor_enable)?        8'hFF :
                                plane_ram2_q;

always @(posedge clk_vga) if (ce_video) begin
	if(memory_load_step_b) plane_txt_shift <= plane_txt_shift_value;
	else if(plane_shift_enable) plane_txt_shift <= { plane_txt_shift[6:0], 1'b0 };
end

reg [3:0] txt_foreground;
always @(posedge clk_vga) if (ce_video) if(memory_load_step_b) txt_foreground <= plane_ram1[3:0];

reg [3:0] txt_background;
always @(posedge clk_vga) if (ce_video) if(memory_load_step_b) txt_background <= (attrib_blinking)? { 1'b0, plane_ram1[6:4] } : plane_ram1[7:4];

wire txt_line_graphic_char = plane_ram0 >= 8'hB0 && plane_ram0 <= 8'hDF;

//------------------------------------------------------------------------------

wire [3:0] pel_input =
    (plane_shift_9dot && attrib_9bit_same_as_8bit && pel_line_graphic_char)?   pel_input_last :
    (plane_shift_9dot)?                                                        pel_background :
    
    (attrib_graphic_mode)?  { plane_shift3[7], plane_shift2[7], plane_shift1[7], plane_shift0[7] } :
    (plane_txt_shift[7])?   txt_foreground :
                            txt_background;

reg [3:0] pel_input_last;
always @(posedge clk_vga) if (ce_video) if(plane_shift_enable) pel_input_last <= pel_input;

reg pel_line_graphic_char;
always @(posedge clk_vga) if (ce_video) if(plane_shift_enable) pel_line_graphic_char <= txt_line_graphic_char;

reg [3:0] pel_background;
always @(posedge clk_vga) if (ce_video) if(plane_shift_enable) pel_background <= txt_background;

//------------------------------------------------------------------------------

wire [3:0] pel_after_enable = attrib_mask & pel_input;

//APA blinking logic (undocumented)
wire [3:0] pel_after_blink =
    (attrib_graphic_mode && attrib_blinking && blink_txt_value)?    { 1'b1, pel_after_enable[2:0] } :
    (attrib_graphic_mode && attrib_blinking)?                       pel_after_enable ^ 4'b1000 :
                                                                    pel_after_enable;

reg [35:0] pel_shift_reg;
always @(posedge clk_vga) if (ce_video) if(plane_shift_enable) pel_shift_reg <= { pel_after_blink, pel_shift_reg[35:4] };

wire [7:0] pel_after_panning =
    (memory_panning_reg == 4'd0)? pel_shift_reg[11:4] :
    (memory_panning_reg == 4'd1)? pel_shift_reg[15:8] :
    (memory_panning_reg == 4'd2)? pel_shift_reg[19:12] :
    (memory_panning_reg == 4'd3)? pel_shift_reg[23:16] :
    (memory_panning_reg == 4'd4)? pel_shift_reg[27:20] :
    (memory_panning_reg == 4'd5)? pel_shift_reg[31:24] :
    (memory_panning_reg == 4'd6)? pel_shift_reg[35:28] :
    (memory_panning_reg == 4'd7)? { 4'd0, pel_shift_reg[35:32] } :
                                  pel_shift_reg[7:0];

reg plane_shift_enable_last;
always @(posedge clk_vga) if (ce_video) plane_shift_enable_last <= plane_shift_enable;
                                      
reg pel_color_8bit_cnt;
always @(posedge clk_vga) if (ce_video) begin
	if(plane_shift_enable && ~plane_shift_enable_last)  pel_color_8bit_cnt <= 1'b1;
	else                                                pel_color_8bit_cnt <= ~pel_color_8bit_cnt;
end

reg [7:0] pel_color_8bit_buffer;
always @(posedge clk_vga) if (ce_video) begin
	if(~pel_color_8bit_cnt) pel_color_8bit_buffer <= pel_after_panning;
end
//------------------------------------------------------------------------------

wire [5:0] pel_palette;
wire [5:0] host_palette_q;

dpram_difclk #(4,6,4,6) internal_palette_ram
(
	.clk_a          (clk_sys),
	.address_a      (attrib_io_index[3:0]),
	.data_a         (io_writedata[5:0]),
	.wren_a         (attrib_io_write && attrib_io_index < 5'h10),
	.q_a            (host_palette_q),

	.clk_b          (clk_vga),
	.enable_b       (ce_video),
	.address_b      (pel_after_panning[3:0]),
	.q_b            (pel_palette)
);

wire [7:0] pel_palette_index = {
	attrib_color_bit7_6_value,
	(attrib_color_bit5_4_enable)? attrib_color_bit5_4_value : pel_palette[5:4],
	pel_palette[3:0]
};

wire vgaprep_overscan;

wire [7:0] pel_index =
    (vgaprep_overscan)?       attrib_color_overscan :
    (~(attrib_video_enable))? 8'h00 :
    (attrib_pelclock_div2)?   { pel_color_8bit_buffer[3:0], pel_color_8bit_buffer[7:4] } :
                              pel_palette_index;

//------------------------------------------------------------------------------

wire [17:0] dac_color;
wire [17:0] dac_read_q;

dpram_difclk #(8,18,8,18) dac_ram
(
	.clk_a          (clk_sys),
	.address_a      (dac_is_read? dac_read_index : dac_write_index),
	.data_a         ({ dac_write_buffer, io_writedata[5:0] }),
	.wren_a         (io_c_write && io_address == 4'h9 && dac_cnt == 2'd2),
	.q_a            (dac_read_q),

	.clk_b          (clk_vga),
	.enable_b       (ce_video),
	.address_b      (pel_index),
	.q_b            (dac_color)
);

always @(posedge clk_sys) begin
	vga_pal_d  <= { dac_write_buffer, io_writedata[5:0] };
	vga_pal_a  <= dac_write_index;
	vga_pal_we <= io_c_write && io_address == 4'h9 && dac_cnt == 2'd2;
end

//------------------------------------------------------------------------------

wire character_last_dot = dot_cnt_enable && ((dot_cnt == 4'd8 && ~(seq_8dot_char)) || (dot_cnt == 4'd7 && seq_8dot_char));
wire line_last_dot      = horiz_cnt == crtc_horizontal_total + 8'd4 && character_last_dot;
wire screen_last_dot    = vert_cnt == crtc_vertical_total + 1'd1 && line_last_dot;

reg [3:0] dot_cnt;
reg [8:0] horiz_cnt;
reg [10:0] vert_cnt;

reg dot_cnt_div;
always @(posedge clk_vga) if (ce_video) dot_cnt_div <= ~(dot_cnt_div);

wire dot_cnt_enable = ~(seq_dotclock_divided) || dot_cnt_div;

always @(posedge clk_vga) if (ce_video) begin
	if(dot_cnt_enable && character_last_dot)   dot_cnt <= 4'd0;
	else if(dot_cnt_enable)                    dot_cnt <= dot_cnt + 4'd1;
end

always @(posedge clk_vga) if (ce_video) begin
	if(line_last_dot)           horiz_cnt <= 9'd0;
	else if(character_last_dot) horiz_cnt <= horiz_cnt + 1'd1;
end

always @(posedge clk_vga) if (ce_video) begin
	if(screen_last_dot)    vert_cnt <= 11'd0;
	else if(line_last_dot) vert_cnt <= vert_cnt + 1'd1;
end

assign dot_memory_load = 
	(   (seq_8dot_char    && ~(seq_dotclock_divided) && dot_cnt_enable    && dot_cnt == 4'd3) ||
	    (seq_8dot_char    && seq_dotclock_divided    && ~(dot_cnt_enable) && dot_cnt == 4'd6) ||
	    (~(seq_8dot_char) && ~(seq_dotclock_divided) && dot_cnt_enable    && dot_cnt == 4'd4) ||
	    (~(seq_8dot_char) && seq_dotclock_divided    && ~(dot_cnt_enable) && dot_cnt == 4'd7)
	) &&
	(   (vert_cnt == crtc_vertical_total + 1'd1 && horiz_cnt >= crtc_horizontal_total + 8'd3) ||
	    (vert_cnt < crtc_vertical_display_size && (horiz_cnt <= crtc_horizontal_display_size - 8'd2 || horiz_cnt >= crtc_horizontal_total + 8'd3)) ||
	    (vert_cnt == crtc_vertical_display_size && horiz_cnt <= crtc_horizontal_display_size - 8'd2)
	);
    
assign dot_memory_load_first_in_frame = dot_memory_load && vert_cnt == crtc_vertical_total + 1'd1 && horiz_cnt == crtc_horizontal_total + 8'd3;
assign dot_memory_load_first_in_line  = dot_memory_load && horiz_cnt == crtc_horizontal_total + 8'd3;
assign dot_memory_load_first_in_line_matched =
    dot_memory_load_first_in_line && (
    (crtc_line_compare > 0 && vert_cnt == crtc_line_compare - 1'd1) ||
    (crtc_line_compare == 0 && vert_cnt == crtc_vertical_total + 1'd1));

assign dot_memory_load_vertical_retrace_start = vert_cnt == crtc_vertical_retrace_start;
    
//------------------------------------------------------------------------------

reg host_io_vertical_retrace_last;
always @(posedge clk_vga) if (ce_video) host_io_vertical_retrace_last <= host_io_vertical_retrace;

reg [5:0] blink_cnt;
always @(posedge clk_vga) if (ce_video) if(host_io_vertical_retrace_last && !host_io_vertical_retrace) blink_cnt <= blink_cnt + 6'd1;

assign blink_txt_value    = blink_cnt[5];
assign blink_cursor_value = blink_cnt[4];

//------------------------------------------------------------------------------

reg vgaprep_horiz_blank;
always @(posedge clk_vga) if (ce_video) begin
	if(horiz_cnt == crtc_horizontal_blanking_start + 1'd1)                                                vgaprep_horiz_blank <= 1'b1;
	else if(horiz_cnt > crtc_horizontal_blanking_start && horiz_cnt[5:0] == crtc_horizontal_blanking_end) vgaprep_horiz_blank <= 1'b0;
end

reg vgaprep_vert_blank;
always @(posedge clk_vga) if (ce_video) begin
	if(vert_cnt == crtc_vertical_blanking_start + 1'd1)                                             vgaprep_vert_blank <= 1'b1;
	else if(vert_cnt > crtc_vertical_blanking_start && vert_cnt[7:0] == crtc_vertical_blanking_end) vgaprep_vert_blank <= 1'b0;
end

wire vgaprep_blank = 
	seq_screen_disable || ~(seq_sync_reset_n) || ~(seq_async_reset_n) ||
	//horizontal
	horiz_cnt == crtc_horizontal_blanking_start + 1'd1 || (horiz_cnt > crtc_horizontal_blanking_start && vgaprep_horiz_blank && horiz_cnt[5:0] != crtc_horizontal_blanking_end) ||
	//line before vertical blank
	(horiz_cnt >= crtc_horizontal_blanking_start + 1'd1 && vert_cnt == crtc_vertical_blanking_start) ||
	//last line of vertical blank
	((~(vgaprep_vert_blank) || (vert_cnt[7:0] + 8'd1 != crtc_vertical_blanking_end) || horiz_cnt < crtc_horizontal_blanking_start + 1'd1) &&
	//vertical
	(vert_cnt == crtc_vertical_blanking_start + 1'd1 || (vert_cnt > crtc_vertical_blanking_start && vgaprep_vert_blank && vert_cnt[7:0] != crtc_vertical_blanking_end)));

wire vgaprep_horiz_sync =
	horiz_cnt == (crtc_horizontal_retrace_start + { 6'd0, crtc_horizontal_retrace_skew }) ||
	(horiz_cnt > (crtc_horizontal_retrace_start + { 6'd0, crtc_horizontal_retrace_skew }) && vgareg_horiz_sync == ~(general_hsync) && horiz_cnt[4:0] != crtc_horizontal_retrace_end);
    
wire vgaprep_vert_sync =
	vert_cnt == crtc_vertical_retrace_start ||
	(vert_cnt > crtc_vertical_retrace_start && vgareg_vert_sync == ~(general_vsync) && vert_cnt[3:0] != crtc_vertical_retrace_end);
    
//one cycle before input to vgareg_*
assign vgaprep_overscan = 
	(horiz_cnt > crtc_horizontal_display_size  && ~(line_last_dot)) ||
	(horiz_cnt == crtc_horizontal_display_size && character_last_dot) ||
	(vert_cnt > crtc_vertical_display_size     && ~(screen_last_dot)) ||
	(vert_cnt == crtc_vertical_display_size    && line_last_dot);

//------------------------------------------------------------------------------

assign host_io_vertical_retrace = vgaprep_vert_sync;
assign host_io_not_displaying   = vgaprep_blank;

reg vgareg_horiz_sync;
always @(posedge clk_vga) if (ce_video) vgareg_horiz_sync <= (vgaprep_horiz_sync && crtc_enable_sync)? ~(general_hsync) : general_hsync;
always @(posedge clk_vga) if (ce_video) vga_horiz_sync <= vgareg_horiz_sync;

reg vgareg_vert_sync;
always @(posedge clk_vga) if (ce_video) vgareg_vert_sync <= (vgaprep_vert_sync && crtc_enable_sync)? ~(general_vsync) : general_vsync;
always @(posedge clk_vga) if (ce_video) vga_vert_sync <= vgareg_vert_sync;

reg vgareg_blank_n;
always @(posedge clk_vga) if (ce_video) vgareg_blank_n <= ~(vgaprep_blank|vgaprep_overscan);
always @(posedge clk_vga) if (ce_video) vga_blank_n <= vgareg_blank_n;

always @(posedge clk_vga) if (ce_video) begin
	vga_r <= output_enable ? { dac_color[17:12], dac_color[17:16] } : 8'd0;
	vga_g <= output_enable ? { dac_color[11:6],  dac_color[11:10] } : 8'd0;
	vga_b <= output_enable ? { dac_color[5:0],   dac_color[5:4]   } : 8'd0;
end

reg ce_div3;
always @(posedge clk_vga) begin
	reg [1:0] cnt;
	reg old_hs;

	if(ce_video) begin
		ce_div3 <= 0;
		cnt <= cnt + 1'd1;
		if(cnt >= 2) begin
			cnt <= 0;
			ce_div3 <= 1;
		end
		old_hs <= vga_horiz_sync;
		if(~old_hs & vga_horiz_sync) cnt <= 0;
	end
end

assign vga_ce = ce_video & ((vga_flags[1:0] == 3) ? ce_div3 : (~vga_lores | (attrib_pelclock_div2 ? pel_color_8bit_cnt : dot_cnt_enable)));

always @(posedge clk_sys) begin
	vga_rd_seg     <= seg_rd;
	vga_wr_seg     <= seg_wr;
	vga_start_addr <= crtc_address_start;
	vga_width      <= crtc_horizontal_display_size + 1'd1;
	vga_stride     <= crtc_address_offset;
	vga_height     <= crtc_vertical_display_size + 1'd1;
	vga_flags      <= {crtc_vertical_doublescan || (crtc_row_max == 1), attrib_pelclock_div2, ~attrib_reg16[7] ? 2'b00 : (attrib_reg16[5:4] == 2) ? 2'b10 : (crtc_reg37[7] && crtc_reg37[5]) ? 2'b11 : 2'b01};
	vga_off        <= seq_screen_disable || ~seq_sync_reset_n || ~seq_async_reset_n || ~output_enable;
end

//------------------------------------------------------------------------------

endmodule
