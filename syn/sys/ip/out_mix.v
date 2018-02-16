// out_mix.v

`timescale 1 ps / 1 ps
module out_mix (
		input  wire        clk,             // Output.clk
		output reg         de,              //       .de
		output reg         h_sync,          //       .h_sync
		output reg         v_sync,          //       .v_sync
		output reg  [23:0] data,            //       .data
		output reg         vid_clk,         //  input.vid_clk
		input  wire [1:0]  vid_datavalid,   //       .vid_datavalid
		input  wire [1:0]  vid_h_sync,      //       .vid_h_sync
		input  wire [1:0]  vid_v_sync,      //       .vid_v_sync
		input  wire [47:0] vid_data,        //       .vid_data
		input  wire        underflow,       //       .underflow
		input  wire        vid_mode_change, //       .vid_mode_change
		input  wire [1:0]  vid_std,         //       .vid_std
		input  wire [1:0]  vid_f,           //       .vid_f
		input  wire [1:0]  vid_h,           //       .vid_h
		input  wire [1:0]  vid_v            //       .vid_v
	);

	reg        r_de;
	reg        r_h_sync;
	reg        r_v_sync;
	reg [23:0] r_data;
	
	always @(posedge clk) begin
		vid_clk <= ~vid_clk;
		
		if(~vid_clk) begin
			{r_de,de} <= vid_datavalid;
			{r_h_sync, h_sync} <= vid_h_sync;
			{r_v_sync, v_sync} <= vid_v_sync;
			{r_data, data} <= vid_data;
		end else begin
			de <= r_de;
			h_sync <= r_h_sync;
			v_sync <= r_v_sync;
			data <= r_data;
		end
	end

endmodule
