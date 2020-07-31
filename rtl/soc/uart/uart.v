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
	input  wire       clk,          //            clock.clk
	input  wire       reset,        //            reset.reset

	input  wire [2:0] address,      //               io.address
	input  wire       read,         //                 .read
	output reg  [7:0] readdata,     //                 .readdata
	input  wire       write,        //                 .write
	input  wire [7:0] writedata,    //                 .writedata

	input  wire       br_clk,       //           serial.br_clk
	input  wire       rx,           //                 .rx
	output wire       tx,           //                 .tx
	input  wire       cts_n,        //                 .cts_n
	input  wire       dcd_n,        //                 .dcd_n
	input  wire       dsr_n,        //                 .dsr_n
	input  wire       ri_n,         //                 .ri_n
	output wire       rts_n,        //                 .rts_n
	output wire       br_out,       //                 .br_out
	output wire       dtr_n,        //                 .dtr_n

	output wire       irq           // interrupt_sender.irq
);

wire [7:0] data;
always @(posedge clk) if(read) readdata <= data;

gh_uart_16550 uart
(
	.clk(clk),
	.BR_clk(br_clk),
	.rst(reset),
	.CS(write|read),
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

endmodule
