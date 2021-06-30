//
//  video freeze with sync
//  (C) Alexey Melnikov
//
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


module video_freezer
(
	input  clk,

	output sync,
	input  freeze,

	input  hs_in,
	input  vs_in,
	input  hbl_in,
	input  vbl_in,

	output hs_out,
	output vs_out,
	output hbl_out,
	output vbl_out
);

sync_lock #(33) vs_lock
(
	.clk(clk),
	.sync_in(vs_in),
	.sync_out(vs_out),
	.de_in(vbl_in),
	.de_out(vbl_out),
	.freeze(freeze)
);

wire sync_pt;
sync_lock #(21) hs_lock
(
	.clk(clk),
	.sync_in(hs_in),
	.sync_out(hs_out),
	.de_in(hbl_in),
	.de_out(hbl_out),
	.freeze(freeze),
	.sync_pt(sync_pt)
);

reg sync_o;
always @(posedge clk) begin
	reg old_hs, old_vs;
	reg vs_sync;

	old_vs <= vs_out;
	
	if(~old_vs & vs_out) vs_sync <= 1;
	if(sync_pt & vs_sync) begin
		vs_sync <= 0;
		sync_o <= ~sync_o;
	end
end

assign sync = sync_o; 

endmodule


module sync_lock #(parameter WIDTH)
(
	input   clk,

	input   sync_in,
	input   de_in,

	output  sync_out,
	output  de_out,

	input   freeze,
	output  sync_pt,
	output  valid
);

reg [WIDTH-1:0] f_len, s_len, de_start, de_end;
reg sync_valid;

reg old_sync;
always @(posedge clk) old_sync <= sync_in;

always @(posedge clk) begin
	reg [WIDTH-1:0] cnti;
	reg f_valid;
	reg old_de;

	cnti <= cnti + 1'd1;
	if(~old_sync & sync_in) begin
		if(sync_valid) f_len <= cnti;
		f_valid <= 1;
		sync_valid <= f_valid;
		cnti <= 0;
	end

	if(old_sync & ~sync_in & sync_valid) s_len <= cnti;
	
	old_de <= de_in;
	if(~old_de & de_in & sync_valid) de_start <= cnti;
	if(old_de & ~de_in & sync_valid) de_end   <= cnti;

	if(freeze) {f_valid, sync_valid} <= 0;
end

reg sync_o, de_o, sync_o_pre;
always @(posedge clk) begin
	reg [WIDTH-1:0] cnto;

	cnto <= cnto + 1'd1;
	if(old_sync & ~sync_in & sync_valid) cnto <= s_len + 2'd2;
	if(cnto == f_len) cnto <= 0;

	sync_o_pre <= (cnto == (s_len>>1)); // middle in sync
	if(cnto == f_len) sync_o <= 1;
	if(cnto == s_len) sync_o <= 0;
	if(cnto == de_start) de_o <= 1;
	if(cnto == de_end)   de_o <= 0;
end

assign sync_out = freeze ? sync_o : sync_in;
assign valid    = sync_valid;
assign sync_pt  = sync_o_pre;
assign de_out   = freeze ? de_o   : de_in;

endmodule
