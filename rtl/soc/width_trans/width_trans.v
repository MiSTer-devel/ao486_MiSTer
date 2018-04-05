// width_trans.v

`timescale 1 ps / 1 ps
module width_trans
(
	input  wire        clk,           // clock.clk
	input  wire        reset,         // reset.reset
	input  wire [2:0]  in_address,    //    in.address
	input  wire        in_read,       //      .read
	output wire [7:0]  in_readdata,   //      .readdata
	input  wire        in_write,      //      .write
	input  wire [7:0]  in_writedata,  //      .writedata
	output wire [8:0]  out_address,   //   out.address
	output wire        out_read,      //      .read
	input  wire [31:0] out_readdata,  //      .readdata
	output wire        out_write,     //      .write
	output wire [31:0] out_writedata  //      .writedata
);

assign out_address   = {in_address, 2'b00};
assign out_read      = in_read;
assign in_readdata   = out_readdata[7:0];
assign out_write     = in_write;
assign out_writedata = {24'd0, in_writedata};

endmodule
