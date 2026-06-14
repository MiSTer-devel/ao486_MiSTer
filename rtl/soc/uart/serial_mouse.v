// ===========================================================================
// Microsoft serial-mouse byte-stream generator (for ao486 COM3).
//
// The 16550 UART core only accepts a single serial RX wire, so to present a
// second mouse to DOS as a *serial* mouse we synthesize the classic 1200-baud
// 7N1 Microsoft mouse protocol on that wire. A stock DOS serial-mouse driver
// (e.g. CuteMouse `CTMOUSE /S3`) then detects and reads it like real hardware.
//
// Mouse-2 deltas arrive already accumulated-per-host-event from Main_MiSTer via
// hps_io UIO command 0x07 as {dx, dy, buttons} plus a toggling strobe.
//
// Protocol emitted:
//   * On RTS (or DTR) rising edge — the driver "powers/resets" the mouse during
//     detection — emit the identification byte 'M' (0x4D) so the driver knows it
//     is a Microsoft mouse.
//   * On movement / button change emit a 3-byte packet:
//        D1: 1 LB RB Y7 Y6 X7 X6    (bit6 = sync = 1)
//        D2: 0 X5 X4 X3 X2 X1 X0
//        D3: 0 Y5 Y4 Y3 Y2 Y1 Y0
//     X/Y are signed 8-bit deltas (high 2 bits in D1, low 6 bits in D2/D3).
//   * Each byte framed as start(0) + 7 data bits (LSB first) + stop(1);
//     idle line = 1 (mark).
//
// CLOCK: drive `clk` from the FIXED UART baud reference (clk_uart2, 1.8432 MHz),
// NOT clk_sys. clk_sys is reconfigured at runtime by the ao486 CPU-speed
// selector (15..100 MHz), which would shift the generated baud. The 16550
// receiver samples one bit every 16*divisor br_clk cycles; for the DOS-standard
// 1200-baud divisor (96) that is 16*96 = 1536 cycles, so CLKS_PER_BIT = 1536
// makes each generated bit exactly one receive-bit wide on the same clock.
//
// rts/dtr/strobe (and the dx/dy/btn buses) originate in the clk_sys domain, so
// they are brought across with 2-FF synchronizers below before edge detection.
// ===========================================================================

module serial_mouse #(parameter CLKS_PER_BIT = 1536)
(
	input              clk,
	input              reset,

	input              rts,      // COM3 RTS asserted (active high)
	input              dtr,      // COM3 DTR asserted (active high)

	input        [7:0] dx,       // signed delta X (accumulated host-side)
	input        [7:0] dy,       // signed delta Y
	input        [2:0] btn,      // [0]=left [1]=right [2]=middle
	input              strobe,   // toggles on each new mouse-2 update

	output reg         rx        // serial line into UART3 RX (idle = 1)
);

localparam S_IDLE = 1'b0, S_SEND = 1'b1;

// ---- CDC: rts/dtr/strobe come from the clk_sys domain; 2-FF synchronize ----
reg rts_m, rts_s, dtr_m, dtr_s, strobe_m, strobe_s;

// ---- edge / event detect (on the synchronized signals) ----
reg rts_d, dtr_d, strobe_d;
wire rts_rise   = rts_s & ~rts_d;
wire dtr_rise   = dtr_s & ~dtr_d;
wire strobe_evt = strobe_s ^ strobe_d;

// ---- pending work ----
reg              id_pending;
reg              move_pending;
reg signed [7:0] acc_x, acc_y;
reg        [2:0] btn_l;

// ---- transmit engine ----
reg        state;
reg [16:0] bit_div;
reg  [3:0] bit_idx;     // 0..8 (start + 7 data + stop)
reg  [8:0] frame;       // {stop, data[6:0], start}
reg  [1:0] byte_idx;    // current byte within the sequence
reg  [1:0] nbytes;      // 1 (ID) or 3 (packet)
reg  [6:0] pkt1, pkt2;  // 2nd/3rd packet bytes

// sign-extended accumulate so the clamp sees the true sum
wire signed [9:0] sum_x = $signed({{2{acc_x[7]}}, acc_x}) + $signed({{2{dx[7]}}, dx});
wire signed [9:0] sum_y = $signed({{2{acc_y[7]}}, acc_y}) + $signed({{2{dy[7]}}, dy});

function signed [7:0] clamp8(input signed [9:0] v);
	clamp8 = (v >  10'sd127)  ?  8'sd127 :
	         (v < -10'sd128)  ?  8'sh80  : v[7:0];  // 8'sh80 = -128 (avoids 8'sd128 overflow)
endfunction

task load_byte(input [6:0] b);
	begin
		frame   <= {1'b1, b, 1'b0};   // stop=1, 7 data, start=0
		bit_idx <= 4'd0;
		bit_div <= 17'd0;
		rx      <= 1'b0;              // drive the start bit now
	end
endtask

always @(posedge clk) begin
	if (reset) begin
		rts_m <= 0; rts_s <= 0; dtr_m <= 0; dtr_s <= 0; strobe_m <= 0; strobe_s <= 0;
		rts_d <= 0; dtr_d <= 0; strobe_d <= 0;
		id_pending <= 0; move_pending <= 0;
		acc_x <= 0; acc_y <= 0; btn_l <= 0;
		state <= S_IDLE; rx <= 1'b1; bit_div <= 0; bit_idx <= 0;
		byte_idx <= 0; nbytes <= 0;
	end
	else begin
		// 2-FF synchronizers (clk_sys -> this clk domain)
		rts_m <= rts; rts_s <= rts_m;
		dtr_m <= dtr; dtr_s <= dtr_m;
		strobe_m <= strobe; strobe_s <= strobe_m;
		// edge-detect delay taps on the synchronized signals
		rts_d <= rts_s; dtr_d <= dtr_s; strobe_d <= strobe_s;

		// driver asserted RTS/DTR -> emit Microsoft 'M' identification byte
		if (rts_rise | dtr_rise) id_pending <= 1'b1;

		// accumulate motion / latch buttons on each new host update
		if (strobe_evt) begin
			acc_x        <= clamp8(sum_x);
			acc_y        <= clamp8(sum_y);
			btn_l        <= btn;
			move_pending <= 1'b1;
		end

		case (state)
		S_IDLE: begin
			rx <= 1'b1;
			if (id_pending) begin
				id_pending <= 1'b0;
				nbytes   <= 2'd1;
				byte_idx <= 2'd0;
				load_byte(7'h4D);            // 'M'
				state <= S_SEND;
			end
			else if (move_pending && rts_s) begin
				move_pending <= 1'b0;
				// build packet from current accumulators, then clear them
				pkt1 <= {1'b0, acc_x[5:0]};
				pkt2 <= {1'b0, acc_y[5:0]};
				acc_x <= 0; acc_y <= 0;
				nbytes   <= 2'd3;
				byte_idx <= 2'd0;
				load_byte({1'b1, btn_l[0], btn_l[1], acc_y[7:6], acc_x[7:6]});
				state <= S_SEND;
			end
		end

		S_SEND: begin
			if (bit_div == CLKS_PER_BIT-1) begin
				bit_div <= 0;
				if (bit_idx == 4'd8) begin
					// stop bit just completed -> byte done
					if (byte_idx == nbytes-1) begin
						rx    <= 1'b1;
						state <= S_IDLE;
					end
					else begin
						byte_idx <= byte_idx + 1'b1;
						if (byte_idx == 2'd0) load_byte(pkt1);
						else                  load_byte(pkt2);
					end
				end
				else begin
					bit_idx <= bit_idx + 1'b1;
					rx      <= frame[bit_idx + 1];
				end
			end
			else begin
				bit_div <= bit_div + 1'b1;
			end
		end
		endcase
	end
end

endmodule
