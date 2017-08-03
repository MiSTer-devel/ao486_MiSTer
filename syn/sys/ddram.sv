//
// ddram.v
//
// DE10-nano DDR3 memory interface
//
// Copyright (c) 2017 Sorgelig
//
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
// ------------------------------------------
//

// 8-bit version

module ddram
(
	input         reset,
	input         DDRAM_CLK,

	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

   input  [27:0] addr,        // 256MB at the end of 1GB
   output  [7:0] dout,        // data output to cpu
   input   [7:0] din,         // data input from cpu
   input         we,          // cpu requests write
   input         rd,          // cpu requests read
   output        ready        // dout is valid. Ready to accept new read/write.
);

assign DDRAM_BURSTCNT = 1;
assign DDRAM_BE       = (8'd1<<ram_address[2:0]) | {8{ram_read}};
assign DDRAM_ADDR     = {4'b0011, ram_address[27:3]}; // RAM at 0x30000000
assign DDRAM_RD       = ram_read;
assign DDRAM_DIN      = ram_cache;
assign DDRAM_WE       = ram_write;

assign dout = ram_q;
assign ready = ~busy;

reg  [7:0] ram_q;
reg [27:0] ram_address;
reg        ram_read;
reg [63:0] ram_cache;
reg        ram_write;
reg  [7:0] cached;
reg        busy;


always @(posedge DDRAM_CLK)
begin
	reg old_rd, old_we;
	reg old_reset;
	reg state;

	old_reset <= reset;
	if(old_reset && ~reset)
	begin
		busy   <= 0;
		state  <= 0;
		cached <= 0;
	end

	if(!DDRAM_BUSY)
	begin
		ram_write <= 0;
		ram_read  <= 0;
		if(state)
		begin
			if(DDRAM_DOUT_READY)
			begin
				ram_q     <= DDRAM_DOUT[{ram_address[2:0], 3'b000} +:8];
				ram_cache <= DDRAM_DOUT;
				cached    <= 8'hFF;
				state     <= 0;
				busy      <= 0;
			end
		end
		else
		begin
			old_rd <= rd;
			old_we <= we;
			busy   <= 0;

			if(~old_we && we)
			begin
				ram_cache[{addr[2:0], 3'b000} +:8] <= din;
				ram_address <= addr;
				busy        <= 1;
				ram_write 	<= 1;
				cached      <= ((ram_address[27:3] == addr[27:3]) ? cached : 8'h00) | (8'd1<<addr[2:0]);
			end

			if(~old_rd && rd)
			begin
				busy <= 1;
				if((ram_address[27:3] == addr[27:3]) && (cached & (8'd1<<addr[2:0])))
				begin
					ram_q <= ram_cache[{addr[2:0], 3'b000} +:8];
				end
				else
				begin
					ram_address <= addr;
					ram_read    <= 1;
					state       <= 1;
					cached      <= 0;
				end
			end
		end
	end
end

endmodule
