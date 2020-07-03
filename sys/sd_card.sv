// 
// sd_card.v
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
// Copyright (c) 2015-2018 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
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
// http://elm-chan.org/docs/mmc/mmc_e.html
//
/////////////////////////////////////////////////////////////////////////

//
// Made module syncrhronous. Total code refactoring. (Sorgelig)
// clk_spi must be at least 4 x sck for proper work.

module sd_card #(parameter WIDE = 0)
(
	input         clk_sys,
	input         reset,

	input         sdhc,
	
	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,
	input         sd_ack_conf,

	input  [AW:0] sd_buff_addr,
	input  [DW:0] sd_buff_dout,
	output [DW:0] sd_buff_din,
	input         sd_buff_wr,

	// SPI interface
	input         clk_spi,

	input         ss,
	input         sck,
	input         mosi,
	output reg    miso
);

localparam AW = WIDE ?  7 : 8;
localparam DW = WIDE ? 15 : 7;

assign sd_lba = sdhc ? lba : {9'd0, lba[31:9]};

wire[31:0] OCR = { 1'b1, sdhc, 30'd0 };  // bit30 = 1 -> high capaciry card (sdhc) // bit31 = 0 -> card power up finished
wire [7:0] READ_DATA_TOKEN     = 8'hfe;
wire [7:0] WRITE_DATA_RESPONSE = 8'h05;

// number of bytes to wait after a command before sending the reply
localparam NCR=3;

localparam RD_STATE_IDLE       = 0;
localparam RD_STATE_WAIT_IO    = 1;
localparam RD_STATE_SEND_TOKEN = 2;
localparam RD_STATE_SEND_DATA  = 3;
localparam RD_STATE_WAIT_M     = 4;

localparam WR_STATE_IDLE       = 0;
localparam WR_STATE_EXP_DTOKEN = 1;
localparam WR_STATE_RECV_DATA  = 2;
localparam WR_STATE_RECV_CRC0  = 3;
localparam WR_STATE_RECV_CRC1  = 4;
localparam WR_STATE_SEND_DRESP = 5;
localparam WR_STATE_BUSY       = 6;

sdbuf #(WIDE) buffer
(
	.clock_a(clk_sys),
	.address_a(sd_buff_addr),
	.data_a(sd_buff_dout),
	.wren_a(sd_ack & sd_buff_wr),
	.q_a(sd_buff_din),

	.clock_b(clk_spi),
	.address_b(buffer_ptr),
	.data_b(buffer_din),
	.wren_b(buffer_wr),
	.q_b(buffer_dout)
);

sdbuf #(WIDE) conf
(
	.clock_a(clk_sys),
	.address_a(sd_buff_addr),
	.data_a(sd_buff_dout),
	.wren_a(sd_ack_conf & sd_buff_wr),

	.clock_b(clk_spi),
	.address_b(buffer_ptr),
	.q_b(config_dout)
);

reg [31:0] lba, new_lba;
reg  [8:0] buffer_ptr;
reg  [7:0] buffer_din;
wire [7:0] buffer_dout;
wire [7:0] config_dout;
reg        buffer_wr;

always @(posedge clk_spi) begin
	reg [2:0] read_state;
	reg [2:0] write_state;
	reg [6:0] sbuf;
	reg       cmd55;
	reg [7:0] cmd;
	reg [2:0] bit_cnt;
	reg [3:0] byte_cnt;
	reg [7:0] reply;
	reg [7:0] reply0, reply1, reply2, reply3;
	reg [3:0] reply_len;
	reg       tx_finish;
	reg       rx_finish;
	reg       old_sck;
	reg       synced;
	reg [5:0] ack;
	reg       io_ack;
	reg [4:0] idle_cnt = 0;
	reg [2:0] wait_m_cnt;

	if(buffer_wr & ~&buffer_ptr) buffer_ptr <= buffer_ptr + 1'd1;
	buffer_wr <= 0;

	ack <= {ack[4:0], sd_ack};
	if(ack[5:4] == 2'b10) io_ack <= 1;
	if(ack[5:4] == 2'b01) {sd_rd,sd_wr} <= 0;

	old_sck <= sck;
	
	if(~ss)                              idle_cnt <= 31;
	else if(~old_sck && sck && idle_cnt) idle_cnt <= idle_cnt - 1'd1;

	if(reset || !idle_cnt) begin
		bit_cnt     <= 0;
		byte_cnt    <= 15;
		synced      <= 0;
		miso        <= 1;
		sbuf        <= 7'b1111111;
		tx_finish   <= 0;
		rx_finish   <= 0;
		read_state  <= RD_STATE_IDLE;
		write_state <= WR_STATE_IDLE;
	end

	if(old_sck & ~sck & ~ss) begin
		tx_finish <= 0;
		miso <= 1;				// default: send 1's (busy/wait)

		if(byte_cnt == 5+NCR) begin
			miso <= reply[~bit_cnt];

			if(bit_cnt == 7) begin
				// these three commands all have a reply_len of 0 and will thus
				// not send more than a single reply byte

				// CMD9: SEND_CSD
				// CMD10: SEND_CID
				if((cmd == 'h49) | (cmd ==  'h4a))
					read_state <= RD_STATE_SEND_TOKEN;      // jump directly to data transmission
						
				// CMD17/CMD18
				if((cmd == 'h51) | (cmd == 'h52)) begin
					io_ack <= 0;
					read_state <= RD_STATE_WAIT_IO;         // start waiting for data from io controller
					lba <= new_lba;
					sd_rd <= 1;                      // trigger request to io controller
				end
			end
		end
		else if((reply_len > 0) && (byte_cnt == 5+NCR+1)) miso <= reply0[~bit_cnt];
		else if((reply_len > 1) && (byte_cnt == 5+NCR+2)) miso <= reply1[~bit_cnt];
		else if((reply_len > 2) && (byte_cnt == 5+NCR+3)) miso <= reply2[~bit_cnt];
		else if((reply_len > 3) && (byte_cnt == 5+NCR+4)) miso <= reply3[~bit_cnt];
		else begin
			if(byte_cnt > 5+NCR && read_state==RD_STATE_IDLE && write_state==WR_STATE_IDLE) tx_finish <= 1;
		end

		// ---------- read state machine processing -------------

		case(read_state)
			RD_STATE_IDLE: ; // do nothing


			// waiting for io controller to return data
			RD_STATE_WAIT_IO: begin
				if(io_ack & (bit_cnt == 7)) read_state <= RD_STATE_SEND_TOKEN;
			end

			// send data token
			RD_STATE_SEND_TOKEN: begin
				miso <= READ_DATA_TOKEN[~bit_cnt];
	
				if(bit_cnt == 7) begin
					read_state <= RD_STATE_SEND_DATA;   // next: send data
					buffer_ptr <= 0;
					if(cmd == 'h49) buffer_ptr <= 16;
				end
			end

			// send data
			RD_STATE_SEND_DATA: begin

				miso <= ((cmd == 'h49) | (cmd == 'h4A)) ? config_dout[~bit_cnt] : buffer_dout[~bit_cnt];

				if(bit_cnt == 7) begin

					// sent 512 sector data bytes?
					if((cmd == 'h51) & &buffer_ptr) read_state <= RD_STATE_IDLE;
					else if((cmd == 'h52) & &buffer_ptr) begin
						read_state <= RD_STATE_WAIT_M;
						wait_m_cnt <= 0;
					end

					// sent 16 cid/csd data bytes?
					else if(((cmd == 'h49) | (cmd == 'h4a)) & (&buffer_ptr[3:0])) read_state <= RD_STATE_IDLE;

					// not done yet -> trigger read of next data byte
					else buffer_ptr <= buffer_ptr + 1'd1;
				end
			end

			RD_STATE_WAIT_M: begin
				if(bit_cnt == 7) begin
					wait_m_cnt <= wait_m_cnt + 1'd1;
					if(&wait_m_cnt) begin
						lba <= lba + 1;
						io_ack <= 0;
						sd_rd <= 1;
						read_state <= RD_STATE_WAIT_IO;
					end
				end
			end
		endcase

		// ------------------ write support ----------------------
		// send write data response
		if(write_state == WR_STATE_SEND_DRESP) miso <= WRITE_DATA_RESPONSE[~bit_cnt];

		// busy after write until the io controller sends ack
		if(write_state == WR_STATE_BUSY) miso <= 0;
   end

	if(~old_sck & sck & ~ss) begin

	   if(synced) bit_cnt <= bit_cnt + 1'd1;

		// assemble byte
		if(bit_cnt != 7) begin
			sbuf[6:0] <= { sbuf[5:0], mosi };

			// resync while waiting for token
			if(write_state==WR_STATE_EXP_DTOKEN) begin
				if(cmd == 'h58) begin
					if({sbuf,mosi} == 8'hfe) begin
						write_state <= WR_STATE_RECV_DATA;
						buffer_ptr <= 0;
						bit_cnt <= 0;
					end
				end
				else begin
					if({sbuf,mosi} == 8'hfc) begin
						write_state <= WR_STATE_RECV_DATA;
						buffer_ptr <= 0;
						bit_cnt <= 0;
					end
					if({sbuf,mosi} == 8'hfd) begin
						write_state <= WR_STATE_IDLE;
						rx_finish <= 1;
						bit_cnt <= 0;
					end
				end
			end
		end
		else begin
			// finished reading one byte
			// byte counter runs against 15 byte boundary
			if(byte_cnt != 15) byte_cnt <= byte_cnt + 1'd1;

			// byte_cnt > 6 -> complete command received
			// first byte of valid command is 01xxxxxx
			// don't accept new commands once a write or read command has been accepted
 			if((byte_cnt > 5) & (write_state == WR_STATE_IDLE) & (read_state == RD_STATE_IDLE) && !rx_finish) begin
				byte_cnt <= 0;
				cmd <= { sbuf, mosi};

			   // set cmd55 flag if previous command was 55
			   cmd55 <= (cmd == 'h77);
			end

 			if((byte_cnt > 5) & (read_state == RD_STATE_WAIT_M) && ({sbuf, mosi} == 8'h4c)) begin
				byte_cnt <= 0;
				rx_finish <= 0;
				cmd <= {sbuf, mosi};
				read_state <= RD_STATE_IDLE;
			end

			// parse additional command bytes
			if(byte_cnt == 0) new_lba[31:24] <= { sbuf, mosi};
			if(byte_cnt == 1) new_lba[23:16] <= { sbuf, mosi};
			if(byte_cnt == 2) new_lba[15:8]  <= { sbuf, mosi};
			if(byte_cnt == 3) new_lba[7:0]   <= { sbuf, mosi};

			// last byte (crc) received, evaluate
			if(byte_cnt == 4) begin

				// default:
				reply <= 4;      // illegal command
				reply_len <= 0;  // no extra reply bytes
				rx_finish <= 1;

				case(cmd)
					// CMD0: GO_IDLE_STATE
					'h40: reply <= 1;    // ok, busy

					// CMD1: SEND_OP_COND
					'h41: reply <= 0;    // ok, not busy

					// CMD8: SEND_IF_COND (V2 only)
					'h48: begin
							reply  <= 1;   // ok, busy

							reply0 <= 'h00;
							reply1 <= 'h00;
							reply2 <= 'h01;
							reply3 <= 'hAA;
							reply_len <= 4;
						end

					// CMD9: SEND_CSD
					'h49: reply <= 0;    // ok

					// CMD10: SEND_CID
					'h4a: reply <= 0;    // ok

					// CMD12: STOP_TRANSMISSION 
					'h4c: reply <= 0;    // ok

					// CMD16: SET_BLOCKLEN
					'h50: begin
							// we only support a block size of 512
							if(new_lba == 512) reply <= 0;  // ok
								else reply <= 'h40;         // parmeter error
						end

					// CMD17: READ_SINGLE_BLOCK
					'h51: reply <= 0;    // ok

					// CMD18: READ_MULTIPLE
					'h52: reply <= 0;    // ok

					// CMD24: WRITE_BLOCK
					'h58,
					// CMD25: WRITE_MULTIPLE
					'h59: begin
							reply <= 0;    // ok
							write_state <= WR_STATE_EXP_DTOKEN;  // expect data token
							rx_finish <=0;
							lba <= new_lba;
						end

					// ACMD41: APP_SEND_OP_COND
					'h69: if(cmd55) reply <= 0;    // ok, not busy

					// CMD55: APP_COND
					'h77: reply <= 1;    // ok, busy

					// CMD58: READ_OCR
					'h7a: begin
							reply <= 0;    // ok

							reply0 <= OCR[31:24];   // bit 30 = 1 -> high capacity card
							reply1 <= OCR[23:16];
							reply2 <= OCR[15:8];
							reply3 <= OCR[7:0];
							reply_len <= 4;
						end

					// CMD59: CRC_ON_OFF
					'h7b: reply <= 0;    // ok
				endcase
			end

				// ---------- handle write -----------
			case(write_state)
				// do nothing in idle state
				WR_STATE_IDLE: ;

				// waiting for data token
				WR_STATE_EXP_DTOKEN: begin
					buffer_ptr <= 0;
					if(cmd == 'h58) begin
						if({sbuf,mosi} == 8'hfe) write_state <= WR_STATE_RECV_DATA;
					end
					else begin
						if({sbuf,mosi} == 8'hfc) write_state <= WR_STATE_RECV_DATA;
						if({sbuf,mosi} == 8'hfd) begin
							write_state <= WR_STATE_IDLE;
							rx_finish <= 1;
						end
					end
				end

				// transfer 512 bytes
				WR_STATE_RECV_DATA: begin
					// push one byte into local buffer
					buffer_wr  <= 1;
					buffer_din <= {sbuf, mosi};

					// all bytes written?
					if(&buffer_ptr) write_state <= WR_STATE_RECV_CRC0;
				end

				// transfer 1st crc byte
				WR_STATE_RECV_CRC0:
					write_state <= WR_STATE_RECV_CRC1;

				// transfer 2nd crc byte
				WR_STATE_RECV_CRC1:
					write_state <= WR_STATE_SEND_DRESP;

				// send data response
				WR_STATE_SEND_DRESP: begin
					write_state <= WR_STATE_BUSY;
					io_ack <= 0;
					sd_wr <= 1;
				end

				// wait for io controller to accept data
				WR_STATE_BUSY:
					if(io_ack) begin
						if(cmd == 'h59) begin
							write_state <= WR_STATE_EXP_DTOKEN;
							lba <= lba + 1;
						end
						else begin
							write_state <= WR_STATE_IDLE;
							rx_finish <= 1;
						end
					end
			endcase
		end
		
		// wait for first 0 bit until start counting bits
		if(!synced && !mosi) begin
			synced   <= 1;
			bit_cnt  <= 1; // byte assembly prepare for next time loop
			sbuf     <= 7'b1111110; // byte assembly prepare for next time loop
			rx_finish<= 0;
		end else if (synced && tx_finish && rx_finish ) begin
			synced   <= 0;
			bit_cnt  <= 0;
			rx_finish<= 0;
		end
	end
end

endmodule

module sdbuf #(parameter WIDE)
(
	input             clock_a,
	input      [AW:0] address_a,
	input      [DW:0] data_a, 
	input             wren_a,
	output reg [DW:0] q_a,

	input             clock_b,
	input       [8:0] address_b,
	input       [7:0] data_b, 
	input             wren_b,
	output reg  [7:0] q_b
);

localparam AW = WIDE ?  7 : 8;
localparam DW = WIDE ? 15 : 7;

always@(posedge clock_a) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end
	else begin
		q_a <= ram[address_a];
	end
end

generate
	if(WIDE) begin
		reg [1:0][7:0] ram[1<<8];
		always@(posedge clock_b) begin
			if(wren_b) begin
				ram[address_b[8:1]][address_b[0]] <= data_b;
				q_b <= data_b;
			end
			else begin
				q_b <= ram[address_b[8:1]][address_b[0]];
			end
		end
	end
	else begin
		reg [7:0] ram[1<<9];
		always@(posedge clock_b) begin
			if(wren_b) begin
				ram[address_b] <= data_b;
				q_b <= data_b;
			end
			else begin
				q_b <= ram[address_b];
			end
		end
	end
endgenerate

endmodule
