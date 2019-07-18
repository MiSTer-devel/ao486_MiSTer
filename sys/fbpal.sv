//============================================================================
//
//  Framebuffer Palette support for MiSTer
//  (c)2019 Sorgelig
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

module fbpal
(
	input             reset,

	input             en_in,
	output reg        en_out,

	input             ram_clk,
	output reg [28:0] ram_address,
	output reg  [7:0] ram_burstcount,
	input             ram_waitrequest,
	input      [63:0] ram_readdata,
	input             ram_readdatavalid,
	output reg        ram_read,
	
	input      [31:0] fb_address,

	input             pal_en,
	output reg  [7:0] pal_a,
	output reg [23:0] pal_d,
	output reg        pal_wr
);

reg [31:0] base_addr;
always @(posedge ram_clk) base_addr <= fb_address - 4096;

reg [6:0] buf_rptr = 0;
always @(posedge ram_clk) begin
	reg [23:0] odd_d;

	if(~pal_a[0] & pal_wr) {pal_a[0], pal_d} <= {1'b1, odd_d};
	else pal_wr <= 0;

	if(~ram_waitrequest) ram_read <= 0;

	if(pal_en & ~reset) begin
		if(ram_burstcount) begin
			if(ram_readdatavalid) begin
				ram_burstcount <= 0;

				odd_d <= ram_readdata[55:32];
				pal_d <= ram_readdata[23:0];
				pal_a <= {buf_rptr, 1'b0};
				pal_wr <= 1;

				en_out <= en_in;
				buf_rptr <= buf_rptr + 1'd1;
			end
		end
		else begin
			if(~ram_waitrequest && en_out != en_in) begin
				ram_address <= base_addr[31:3] + buf_rptr;
				ram_burstcount <= 1;
				ram_read <= 1;
			end
		end
	end
	else begin
		en_out <= en_in;
		buf_rptr <= 0;
		ram_burstcount <= 0;
	end
end

endmodule
