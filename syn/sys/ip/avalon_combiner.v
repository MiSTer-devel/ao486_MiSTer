// avalon_combiner.v

`timescale 1 ps / 1 ps
module avalon_combiner
(
	input  wire        clk,                //      clock.clk
	input  wire        rst,                //      reset.reset

	output wire [6:0]  mixer_address,      //  ctl_mixer.address
	output wire [3:0]  mixer_byteenable,   //           .byteenable
	output wire        mixer_write,        //           .write
	output wire [31:0] mixer_writedata,    //           .writedata
	input  wire        mixer_waitrequest,  //           .waitrequest

	output wire [6:0]  scaler_address,     // ctl_scaler.address
	output wire [3:0]  scaler_byteenable,  //           .byteenable
	input  wire        scaler_waitrequest, //           .waitrequest
	output wire        scaler_write,       //           .write
	output wire [31:0] scaler_writedata,   //           .writedata

	output wire [7:0]  video_address,      //  ctl_video.address
	output wire [3:0]  video_byteenable,   //           .byteenable
	input  wire        video_waitrequest,  //           .waitrequest
	output wire        video_write,        //           .write
	output wire [31:0] video_writedata,    //           .writedata

	output wire        clock,              //    control.clock
	output wire        reset,              //           .reset
	input  wire [8:0]  address,            //           .address
	input  wire        write,              //           .write
	input  wire [31:0] writedata,          //           .writedata
	output wire        waitrequest         //           .waitrequest
);

assign clock = clk;
assign reset = rst;

assign mixer_address  = address[6:0];
assign scaler_address = address[6:0];
assign video_address  = address[7:0];

assign mixer_byteenable  = 4'b1111;
assign scaler_byteenable = 4'b1111;
assign video_byteenable  = 4'b1111;

wire   en_scaler = (address[8:7] == 0);
wire   en_mixer  = (address[8:7] == 1);
wire   en_video  =  address[8];

assign mixer_write  = en_mixer  & write;
assign scaler_write = en_scaler & write;
assign video_write  = en_video  & write;

assign mixer_writedata  = writedata;
assign scaler_writedata = writedata;
assign video_writedata  = writedata;

assign waitrequest = (en_mixer & mixer_waitrequest) | (en_scaler & scaler_waitrequest) | (en_video & video_waitrequest);

endmodule
