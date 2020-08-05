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
	input  wire       clk,      
	input  wire       reset,    
                               
	input  wire [2:0] address,  
	input  wire       read,     
	output reg  [7:0] readdata, 
	input  wire       write,    
	input  wire [7:0] writedata,
                               
	input  wire       br_clk,   
	input  wire       rx,       
	output wire       tx,       
	input  wire       cts_n,    
	input  wire       dcd_n,    
	input  wire       dsr_n,    
	input  wire       ri_n,     
	output wire       rts_n,    
	output wire       br_out,   
	output wire       dtr_n,    
                               
	output wire       irq_uart,

	input  wire       mpu_address,  
	input  wire       mpu_read,     
	output reg  [7:0] mpu_readdata, 
	input  wire       mpu_write,    
	input  wire [7:0] mpu_writedata,

	output            irq_mpu
);

assign irq_uart = ~mpu_mode & irq;
assign irq_mpu  = read_ack | (mpu_mode & ~rx_empty);

wire [7:0] data;
always @(posedge clk) if(read) readdata <= data;

always @(posedge clk) if(mpu_read) mpu_readdata <= mpu_address ? mpu_status : read_ack ? 8'hFE : data;

wire irq;
wire rx_empty, tx_empty;
gh_uart_16550 uart
(
	.clk(clk),
	.BR_clk(br_clk),
	.rst(reset | cmd_reset),
	.CS(uart_CS),
	.WR(uart_WR),
	.ADD(uart_address),
	.D(uart_writedata),
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
	.TX_Empty(tx_empty),
	.RX_Empty(rx_empty)
);

wire xCR_write = write && (address == 2 || address == 3);
wire mpu_mode = mpu_mode_r & ~xCR_write;

wire uart_CS = mpu_mode ? (!mpu_address && ((mpu_read & ~read_ack) | mpu_write)) : (read | write);
wire uart_WR = mpu_mode ? mpu_write : write;

wire [7:0] uart_writedata = mpu_write ? mpu_writedata : writedata;
wire [2:0] uart_address = (mpu_write | mpu_read) ? 3'd0 : address;

reg mpu_mode_r;
always @(posedge clk or posedge reset) begin
	if(reset) begin
		mpu_mode_r <= 0;
	end
	else begin
		if(mpu_write && mpu_address) begin
			if(mpu_writedata == 'hFF) mpu_mode_r <= 0;
			if(mpu_writedata == 'h3F) mpu_mode_r <= 1;
		end
		// write to FCR or LCR to switch MPU off
		if(xCR_write) mpu_mode_r <= 0;
	end
end

wire [7:0] mpu_status = {~(read_ack | ~rx_empty), ~tx_empty, 6'd0};

wire cmd_reset = mpu_write && mpu_address && (mpu_writedata == 'hFF);
wire cmd_init  = mpu_write && mpu_address && (mpu_writedata == 'h3F);

reg read_ack;
always @(posedge clk or posedge reset) begin
	if(reset) begin
		read_ack <= 0;
	end
	else begin
		if((cmd_reset & ~mpu_mode_r) | cmd_init) read_ack <= 1;
		if(mpu_read & !mpu_address) read_ack <= 0;
	end
end

endmodule
