//
// hps_ext for ao486
//
// Copyright (c) 2020 Alexey Melnikov
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

module hps_ext
(
	input             clk_sys,
	inout      [35:0] EXT_BUS,

	input      [15:0] ext_din,
	output reg [15:0] ext_dout,
	output reg [15:0] ext_addr,
	output reg        ext_rd,
	output reg        ext_wr,

	output reg        ext_midi,
	input       [7:0] ext_req,
	input       [1:0] ext_hotswap
);

assign EXT_BUS[15:0] = io_dout;
wire [15:0] io_din = EXT_BUS[31:16];
assign EXT_BUS[32] = dout_en;
wire io_strobe = EXT_BUS[33];
wire io_enable = |EXT_BUS[35:34];

localparam EXT_CMD_MIN = 'h61;
localparam EXT_CMD_MAX = 'h63;

reg [15:0] io_dout;
reg        dout_en = 0;
reg  [2:0] byte_cnt;

always@(posedge clk_sys) begin
	reg [15:0] cmd;

	{ext_rd, ext_wr} <= 0;
	if((ext_rd | ext_wr) & ~&ext_addr[7:0]) ext_addr <= ext_addr + 1'd1;

	if(~io_enable) begin
		byte_cnt <= 0;
		io_dout <= 0;
		dout_en <= 0;
	end
	else begin
		if(io_strobe) begin

			ext_dout <= io_din;

			io_dout <= 0;
			if(~&byte_cnt) byte_cnt <= byte_cnt + 1'd1;

			if(byte_cnt == 1) ext_addr <= io_din;

			if(byte_cnt == 0) begin
				cmd <= io_din;
				dout_en <= (io_din >= EXT_CMD_MIN && io_din <= EXT_CMD_MAX);
				io_dout <= {4'hE, 2'b00, ext_hotswap, ext_req};
			end
			else begin
				case(cmd)
				'h61: if(byte_cnt >= 3) begin
							ext_wr <= 1;
						end

				'h62: if(byte_cnt >= 3) begin
							io_dout <= ext_din;
							ext_rd <= 1;
						end
				'h63: if(byte_cnt == 1) ext_midi <= io_din[7];
				endcase
			end
		end
	end
end

endmodule
