// uart.v
// Copyright (C) 2020 Alexey Melnikov

module uart
(
	input            clk,
	input            reset,

	input      [2:0] address,
	input            write,
	input      [7:0] writedata,
	input            read,
	output reg [7:0] readdata,
	input            cs,

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

	output           irq
);

wire [7:0] data;

gh_uart_16550 uart_16550
(
	.clk(clk),
	.BR_clk(br_clk),
	.rst(reset),
	.CS(cs & (read | write)),
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
	.IRQ(irq)
);

always @(posedge clk) if(read & cs) readdata <= data;

endmodule

module mpu
(
	input            clk,
	input            reset,

	input            address,
	input            write,
	input      [7:0] writedata,
	input            read,
	output reg [7:0] readdata,
	input            cs,

	input            double_rate,
	input            br_clk,

	input            rx,
	output           tx,
	output           br_out,

	output           irq
);

assign irq  = read_ack | ~rx_empty;

wire rx_empty, tx_full;
wire [7:0] data;

gh_uart_16550 #(1'b1) uart_16550
(
	.clk(clk),
	.BR_clk(br_clk),
	.rst(reset),
	.CS(cs & ~address & ((read & ~read_ack) | write)),
	.WR(write),
	.ADD(0),
	.D(writedata),
	.RD(data),

	.B_CLK(br_out),

	.sRX(rx),
	.sTX(tx),
	.RIn(1),
	.CTSn(0),
	.DSRn(0),
	.DCDn(0),

	.DIV2(double_rate),
	.TX_Full(tx_full),
	.RX_Empty(rx_empty)
);

reg read_ack;
reg mpu_dumb;
always @(posedge clk) begin
	if(reset) begin
		read_ack <= 0;
		mpu_dumb <= 0;
	end
	else if(cs) begin
		if(address) begin
			if(read) readdata <= {~(read_ack | ~rx_empty), tx_full, 6'd0};
			if(write) begin
				read_ack <= ~mpu_dumb;
				if(writedata == 8'hFF) mpu_dumb <= 0;
				if(writedata == 8'h3F) mpu_dumb <= 1;
			end
		end
		else if(read) begin
			readdata <= read_ack ? 8'hFE : data;
			read_ack <= 0;
		end
	end
end

endmodule
