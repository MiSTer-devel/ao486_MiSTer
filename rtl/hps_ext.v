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

module hps_ext #(parameter CLK_RATE)
(
	input             clk_sys,
	inout      [35:0] EXT_BUS,

	input             io_wait,

	input      [31:0] ext_din,
	output reg [31:0] ext_dout,
	output reg [31:0] ext_addr,
	output reg        ext_rd,
	output reg        ext_wr,
	output reg  [1:0] ext_status,
	input       [1:0] ext_req
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
reg  [9:0] byte_cnt;

always@(posedge clk_sys) begin
	reg [15:0] cmd;
	reg        ext_hilo;
	reg        old_wait;
	reg        pending;

	{ext_rd, ext_wr} <= 0;
	ext_status <= 0;

	old_wait <= io_wait;

	if(~io_enable) begin
		byte_cnt <= 0;
		io_dout <= 0;
		ext_hilo <= 0;
		old_wait <= 0;
		pending <= 0;
		dout_en <= 0;
	end else begin
		if(io_strobe) begin

			io_dout <= 0;
			if(~&byte_cnt) byte_cnt <= byte_cnt + 1'd1;

			if(byte_cnt == 0) begin
				cmd <= io_din;
				ext_hilo <= 0;
				dout_en <= (io_din >= EXT_CMD_MIN && io_din <= EXT_CMD_MAX);
			end else begin
				case(cmd)
					'h61: if(byte_cnt == 1) begin
								ext_addr[15:0] <= io_din;
								io_dout <= CLK_RATE[15:0];
							end
							else if(byte_cnt == 2) begin
								ext_addr[31:16] <= io_din;
								io_dout <= CLK_RATE[31:16];
							end
							else begin
								if(~ext_hilo) begin
									if(byte_cnt>4) ext_addr <= ext_addr + 3'd4;
									ext_dout[15:0] <= io_din;
								end
								else
								begin
									ext_dout[31:16] <= io_din;
									ext_wr <= 1;
								end
								ext_hilo <= ~ext_hilo;
							end

					'h62: if(byte_cnt == 1) begin
								ext_addr[15:0] <= io_din;
							end
							else if(byte_cnt == 2) begin
								ext_addr[31:16] <= io_din;
							end
							else begin
								if(~ext_hilo) begin
									ext_rd <= 1;
									pending <= 1;
								end
								else
								begin
									io_dout <= ext_din[31:16];
									ext_addr <= ext_addr + 3'd4;
								end
								ext_hilo <= ~ext_hilo;
							end

					'h63: begin
								io_dout <= ext_req;
								ext_status <= io_din[1:0];
							end
					default: ;
				endcase
			end
		end

		//some pending read functions
		if(old_wait & ~io_wait & pending) begin
			pending <= 0;
			case(cmd)
				'h62: io_dout <= ext_din[15:0];
			endcase
		end
	end
end

endmodule
