// in_split.v


`timescale 1 ps / 1 ps
module in_split (
		input  wire        clk,                //  input.clk
		input  wire        ce,                 //       .ce
		input  wire        de,                 //       .de
		input  wire        h_sync,             //       .h_sync
		input  wire        v_sync,             //       .v_sync
		input  wire        f,                  //       .f
		input  wire [23:0] data,               //       .data
		output wire        vid_clk,            // Output.vid_clk
		output reg         vid_datavalid,      //       .vid_datavalid
		output reg  [1:0]  vid_de,             //       .vid_de
		output reg  [1:0]  vid_f,              //       .vid_f
		output reg  [1:0]  vid_h_sync,         //       .vid_h_sync
		output reg  [1:0]  vid_v_sync,         //       .vid_v_sync
		output reg  [47:0] vid_data,           //       .vid_data
		output wire        vid_locked,         //       .vid_locked
		output wire [7:0]  vid_color_encoding, //       .vid_color_encoding
		output wire [7:0]  vid_bit_width,      //       .vid_bit_width
		input  wire        clipping,           //       .clipping
		input  wire        overflow,           //       .overflow
		input  wire        sof,                //       .sof
		input  wire        sof_locked,         //       .sof_locked
		input  wire        refclk_div,         //       .refclk_div
		input  wire        padding             //       .padding
	);

	assign vid_bit_width = 0;
	assign vid_color_encoding = 0;
	assign vid_locked = 1;
	assign vid_clk = clk;

	always @(posedge clk) begin
		reg odd = 0;
		
		vid_datavalid <= 0;
		if(ce) begin
			vid_de[odd] <= de;
			vid_f[odd] <= f;
			vid_h_sync[odd] <= h_sync;
			vid_v_sync[odd] <= v_sync;
			if(odd) vid_data[47:24] <= data;
				else vid_data[23:0] <= data;
			
			odd <= ~odd;
			vid_datavalid <= odd;
		end
	end
endmodule
