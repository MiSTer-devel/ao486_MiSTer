// uart.v

// This file was auto-generated as a prototype implementation of a module
// created in component editor.  It ties off all outputs to ground and
// ignores all inputs.  It needs to be edited to make it do something
// useful.
//
// This file will not be automatically regenerated.  You should check it in
// to your version control system if you want to keep it.

`timescale 1 ps / 1 ps
module uart (
	input            clk,
	input            reset,

	input      [2:0] address,
	input            write,
	input      [7:0] writedata,
	input            read,
	output reg [7:0] readdata,
	input            uart_cs,
	input            mpu_cs,

	input            br_clk,
	input            rx,
	output           tx,
	input            cts_n,
	input            dcd_n,
	input            dsr_n,
	input            ri_n,
	output           rts_n,
	output           br_out,
	output           dtr_n,

	output           irq_uart,
	output           irq_mpu
);

assign irq_uart = ~mpu_mode_r & irq;
assign irq_mpu  = read_ack | (mpu_mode_r & ~rx_empty);

reg read_ack, mpu_mode_r;
wire irq, rx_empty, tx_full;

wire [7:0] data;

wire [7:0] mpu_status = {~(read_ack | ~rx_empty), tx_full, 6'd0};
wire cmd_reset = mpu_cs && write && address[0] && (writedata == 'hFF);

wire xCR_write = uart_cs && write && (address == 2 || address == 3);
wire mpu_mode = mpu_mode_r & ~xCR_write;

wire uart_strobe = mpu_mode ? (mpu_cs & ~address[0] & ((read & ~read_ack) | write)) : (uart_cs & (read | write));

gh_uart_16550 uart
(
	.clk(clk),
	.BR_clk(br_clk),
	.rst(reset | cmd_reset),
	.CS(uart_strobe),
	.WR(write),
	.ADD(address),
	.D(writedata),
	.RD(data),

	.B_CLK(br_out),

	.sRX(rx),
	.CTSn(cts_n),
	.DSRn(dsr_n),
	.RIn(ri_n),
	.DCDn(dcd_n),

	.sTX(tx),
	.DTRn(dtr_n),
	.RTSn(rts_n),
	.IRQ(irq),

	.MPU_MODE(mpu_mode),
	.TX_Empty(),
	.TX_Full(tx_full),
	.RX_Empty(rx_empty)
);

always @(posedge clk or posedge reset) begin
	if(reset) begin
		mpu_mode_r <= 0;
		read_ack <= 0;
	end
	else begin
		if(read & uart_cs) readdata <= data;
		if(read & mpu_cs)  readdata <= address[0] ? mpu_status : read_ack ? 8'hFE : data;

		if(write & mpu_cs & address[0]) begin
			case (writedata)
				'hFF:    begin mpu_mode_r <= 0; read_ack <= ~mpu_mode_r; end
				'h3F:    begin mpu_mode_r <= 1; read_ack <= 1;           end
				default: begin mpu_mode_r <= 1; read_ack <= 1;           end  //answer to any command, fake smart mode
			endcase
		end

		if(mpu_cs & read & ~address[0]) read_ack   <= 0;

		// write to FCR or LCR to switch MPU off
		if(xCR_write) mpu_mode_r <= 0;
	end
end

endmodule
