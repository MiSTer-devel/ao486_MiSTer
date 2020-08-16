

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

// Gravis Pro:
// Gravis Gamepad Pro uses a serial protocol. Button 0 is 20-25khz 50% duty cycle clock for P1, and
// Button 1 is the data line, with 1 indicating a button is held, and 0 not held. The same applies
// to Player 2, but with buttons 2 and 3. The analog axis pins appear to be unused, but possibly
// should be set to either 0 or 1 and left there. I have left them in case there is any variant of
// this controller that also has an analog input. They seem not to matter. On each falling edge of
// each B0 clock, the state of B1 is read. Frames are 24 bits long and is formatted as follows:

//  -----------------------------------------------
// |0      |1      |1      |1      |1      |1      |
// |0      |Select |Start  |R2     |Blue   |       |
// |0      |L2     |Green  |Yellow |Red    |       |
// |0      |L1     |R1     |Up     |Down   |       |
// |0      |Right  |Left   |       |       |       |
//  -----------------------------------------------

// There is a frame identification header of 0 and then 5 1's, after which the button states are
// read out in groups of four bits or less, each group preceeded by a 0. Presumptively this format
// prevents any false positives for frame header detection.

// 4525 divider, For a 20 khz clk at 90.5mhz master clk. We use 40khz to handle each phase of the
// 20khz clock.
// 2262 to handle highs and lows.

module joystick
(
	input         rst_n,
	input         clk,
	input         clk_grav,
	input [13:0]  dig_1,
	input [13:0]  dig_2,
	input [15:0]  ana_1,
	input [15:0]  ana_2,
	input  [1:0]  mode,

	output reg [7:0] readdata,
	input         write
);

always @(posedge clk) readdata <= {jb4, jb3, jb2, jb1, |JOY2_Y, |JOY2_X, |JOY1_Y, |JOY1_X};

reg  [7:0] JOY1_X,JOY1_Y,JOY2_X,JOY2_Y;
reg [10:0] CLK_DIV;

wire JOY1_RIGHT = dig_1[0];
wire JOY1_LEFT  = dig_1[1];
wire JOY1_DOWN  = dig_1[2];
wire JOY1_UP    = dig_1[3];
wire JOY1_BUT1  = dig_1[4];
wire JOY1_BUT2  = dig_1[5];
wire JOY1_BUT3  = dig_1[6];
wire JOY1_BUT4  = dig_1[7];
wire JOY1_START = dig_1[8];
wire JOY1_SEL   = dig_1[9];
wire JOY1_R1    = dig_1[10];
wire JOY1_L1    = dig_1[11];
wire JOY1_R2    = dig_1[12];
wire JOY1_L2    = dig_1[13];

wire JOY2_RIGHT = dig_2[0];
wire JOY2_LEFT  = dig_2[1];
wire JOY2_DOWN  = dig_2[2];
wire JOY2_UP    = dig_2[3];
wire JOY2_BUT1  = dig_2[4];
wire JOY2_BUT2  = dig_2[5];
wire JOY2_BUT3  = dig_2[6];
wire JOY2_BUT4  = dig_2[7];
wire JOY2_START = dig_2[8];
wire JOY2_SEL   = dig_2[9];
wire JOY2_R1    = dig_2[10];
wire JOY2_L1    = dig_2[11];
wire JOY2_R2    = dig_2[12];
wire JOY2_L2    = dig_2[13];

reg       jb1, jb2, jb3, jb4;
reg [1:0] gravis_out = 0;
reg       gravis_clk = 0;

always @(posedge clk) begin : joy_block
	reg [4:0] gravis_pos;
	reg use_dpad1, use_dpad2;

	if (!rst_n) begin
		JOY1_X <= 128;
		JOY1_Y <= 128;
		JOY2_X <= 128;
		JOY2_Y <= 128;
		gravis_clk <= 0;
		gravis_out <= 0;
		gravis_pos <= 0;
		{jb1, jb2, jb3, jb4} <= 4'b1111;
		use_dpad1 <= 1;
		use_dpad2 <= 1;
	end
	else begin
		jb1 <= mode == 2 ? gravis_clk : !JOY1_BUT1;
		jb2 <= mode == 2 ? gravis_out[0] : !JOY1_BUT2;
		jb3 <= mode == 2 ? gravis_clk : (mode == 1 ? !JOY1_BUT3 : !JOY2_BUT1);
		jb4 <= mode == 2 ? gravis_out[1] : (mode == 1 ? !JOY1_BUT4 : !JOY2_BUT2);

		gravis_clk <= clk_grav;
		if (~gravis_clk & clk_grav) begin
			gravis_pos <= gravis_pos == 23 ? 5'd0 : gravis_pos + 5'd1;

			case (gravis_pos)
				0, 6, 11, 16, 21:
				    gravis_out <= 0;

				1, 2, 3, 4, 5:
				    gravis_out <= 1;

				 7: gravis_out <= {JOY2_SEL,   JOY1_SEL};
				 8: gravis_out <= {JOY2_START, JOY1_START};
				 9: gravis_out <= {JOY2_R2,    JOY1_R2};
				10: gravis_out <= {JOY2_BUT4,  JOY1_BUT4};

				12: gravis_out <= {JOY2_L2,    JOY1_L2};
				13: gravis_out <= {JOY2_BUT2,  JOY1_BUT2};
				14: gravis_out <= {JOY2_BUT1,  JOY1_BUT1};
				15: gravis_out <= {JOY2_BUT3,  JOY1_BUT3};

				17: gravis_out <= {JOY2_L1,    JOY1_L1};
				18: gravis_out <= {JOY2_R1,    JOY1_R1};
				19: gravis_out <= {JOY2_UP,    JOY1_UP};
				20: gravis_out <= {JOY2_DOWN,  JOY1_DOWN};

				22: gravis_out <= {JOY2_RIGHT, JOY1_RIGHT};
				23: gravis_out <= {JOY2_LEFT,  JOY1_LEFT};
			endcase
		end
		
		CLK_DIV <= CLK_DIV + 1'b1;
		if (CLK_DIV==100) begin
			CLK_DIV <= 0;
			if (JOY1_X) JOY1_X <= JOY1_X - 1'b1;
			if (JOY1_Y) JOY1_Y <= JOY1_Y - 1'b1;
			if (JOY2_X) JOY2_X <= JOY2_X - 1'b1;
			if (JOY2_Y) JOY2_Y <= JOY2_Y - 1'b1;
		end

		if((ana_1[7:0] > 60 && ana_1[7:0] < 196) || (ana_1[15:8] > 60 && ana_1[15:8] < 196)) use_dpad1 <= 0;
		else if(dig_1[3:0]) use_dpad1 <= 1;

		if((ana_2[7:0] > 60 && ana_2[7:0] < 196) || (ana_2[15:8] > 60 && ana_2[15:8] < 196)) use_dpad2 <= 0;
		else if(dig_2[3:0]) use_dpad2 <= 1;

		if (write) begin
			JOY1_X <= ~use_dpad1 ? {~ana_1[7],  ana_1[6:0]}  : JOY1_LEFT  ? 8'd4 : JOY1_RIGHT ? 8'd252 : 8'd128;
			JOY1_Y <= ~use_dpad1 ? {~ana_1[15], ana_1[14:8]} : JOY1_UP    ? 8'd4 : JOY1_DOWN  ? 8'd252 : 8'd128;

			JOY2_X <= ~use_dpad2 ? {~ana_2[7],  ana_2[6:0]}  : JOY2_LEFT  ? 8'd4 : JOY2_RIGHT ? 8'd252 : 8'd128;
			JOY2_Y <= ~use_dpad2 ? {~ana_2[15], ana_2[14:8]} : JOY2_UP    ? 8'd4 : JOY2_DOWN  ? 8'd252 : 8'd128;

			CLK_DIV <= 0;
		end
	end
end

endmodule
