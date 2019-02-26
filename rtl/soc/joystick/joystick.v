`timescale 1 ps / 1 ps
module joystick
(
	input         rst_n,      //    reset.reset_n
	input         clk,        //    clock.clk
	input  [5:0]  dig_1,      // joystick.dig_1
	input  [5:0]  dig_2,      //         .dig_2
	input [15:0]  ana_1,      //         .ana_1
	input [15:0]  ana_2,      //         .ana_2
	output [31:0] readdata,   //       io.readdata
	input         write,      //         .write
	input  [31:0] writedata,  //         .writedata
	input  [3:0]  byteenable  //         .byteenable
);

assign readdata = {16'hFFFF, !JOY2_BUT2, !JOY2_BUT1, !JOY1_BUT2, !JOY1_BUT1, JOY2_Y>0, JOY2_X>0, JOY1_Y>0, JOY1_X>0, 8'hFF};

reg [8:0] JOY1_X;
reg [8:0] JOY1_Y;

reg [8:0] JOY2_X;
reg [8:0] JOY2_Y;


// When using the 90.5 MHz clk, an 8-bit CLK_DIV and 9-bit X/Y value gives a reading of around 1400 microseconds using the JoyCheck DOS program (by Henrik K Jensen).
//
// The "standard" maximum X/Y timing value for old-skool PC joysticks is around 1124 microseconds, so have a good range now for ao486.
//
// 
// It should be possible to increase the resolution of the X/Y counters by also decreasing the width of CLK_DIV. eg...
//
//  9-bit X/Y counter. 8-bit CLK_DIV.
// 10-bit X/Y counter. 7-bit CLK_DIV.
// 11-bit X/Y counter. 6-bit CLK_DIV.
// 12-bit X/Y counter. 5-bit CLK_DIV.
//
//
// (For digital joysticks / joypads, the "resolution" obviously isn't too important, but the aim is to add support for analog joysticks later.)
// 
//
// Notes...
//
// 90.5 MHz = 11.05ns per clk tick.
//
// So, assuming an 8-bit clk divider...
//
// 24us   (standard minimum value) = 2172 clk ticks.
// 1124us (standard maximum value) = 101,719 clk ticks.
//
// With an 8-bit clk divider, the min X/Y counter value would then be around 8.
// And the max X/Y counter value would be around 397.
//
//
reg [8:0] CLK_DIV;

wire JOY1_RIGHT = dig_1[0];
wire JOY1_LEFT  = dig_1[1];
wire JOY1_DOWN  = dig_1[2];
wire JOY1_UP    = dig_1[3];
wire JOY1_BUT1  = dig_1[4];
wire JOY1_BUT2  = dig_1[5];

wire JOY2_RIGHT = dig_2[0];
wire JOY2_LEFT  = dig_2[1];
wire JOY2_DOWN  = dig_2[2];
wire JOY2_UP    = dig_2[3];
wire JOY2_BUT1  = dig_2[4];
wire JOY2_BUT2  = dig_2[5];

wire [8:0] j1x_r  = {ana_1[7],ana_1[7:0]};
wire [8:0] j1y_r  = {ana_1[15],ana_1[15:8]};
wire [8:0] j2x_r  = {ana_2[7],ana_2[7:0]};
wire [8:0] j2y_r  = {ana_2[15],ana_2[15:8]};

wire [8:0] j1x = j1x_r + {j1x_r[8],j1x_r[8:1]} + 9'd200;
wire [8:0] j1y = j1y_r + {j1y_r[8],j1y_r[8:1]} + 9'd200;
wire [8:0] j2x = j2x_r + {j2x_r[8],j2x_r[8:1]} + 9'd200;
wire [8:0] j2y = j2y_r + {j2y_r[8],j2y_r[8:1]} + 9'd200;


always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		JOY1_X <= 9'd197;
		JOY1_Y <= 9'd197;
		JOY2_X <= 9'd197;
		JOY2_Y <= 9'd197;
	end
	else begin
		CLK_DIV <= CLK_DIV + 1'b1;

		if (write & byteenable[1]) begin
			JOY1_X <= j1x_r ? j1x : (JOY1_LEFT) ? 9'd8 : (JOY1_RIGHT) ? 9'd391 : 9'd200;
			JOY1_Y <= j1y_r ? j1y : (JOY1_UP)   ? 9'd8 : (JOY1_DOWN)  ? 9'd391 : 9'd200;
			
			JOY2_X <= j2x_r ? j2x : (JOY2_LEFT) ? 9'd8 : (JOY2_RIGHT) ? 9'd391 : 9'd200;
			JOY2_Y <= j2y_r ? j2y : (JOY2_UP)   ? 9'd8 : (JOY2_DOWN)  ? 9'd391 : 9'd200;
			
			CLK_DIV <= 1;
		end

		if (CLK_DIV==265) begin
			CLK_DIV <= 0;
			if (JOY1_X>0) JOY1_X <= JOY1_X - 1'b1;
			if (JOY1_Y>0) JOY1_Y <= JOY1_Y - 1'b1;
			if (JOY2_X>0) JOY2_X <= JOY2_X - 1'b1;
			if (JOY2_Y>0) JOY2_Y <= JOY2_Y - 1'b1;
		end
	end
end

endmodule
