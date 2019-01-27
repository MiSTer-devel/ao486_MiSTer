module joystick
(
	////////////////////////	Clock Input	 	////////////////////////
	input RESET_N,
	input CLOCK,

	input [2:0] JOY_ADDR,
	input JOY_READ,
	output [7:0] JOY_DO,
	
	input JOY_WRITE,
	input [7:0] JOY_DI,
	
	input [11:0] joystick_0,
	input [11:0] joystick_1
);

assign JOY_DO = {joystick_0[7:4], JOY2_Y>0, JOY2_X>0, JOY1_Y>0, JOY1_X>0};


reg [15:0] JOY1_X;
reg [15:0] JOY1_Y;

reg [15:0] JOY2_X;
reg [15:0] JOY2_Y;

reg [7:0] CLK_DIV;

always @(posedge CLOCK or negedge RESET_N)
if (!RESET_N) begin
	JOY1_X <= 1'b1;
	JOY1_Y <= 1'b1;
	JOY2_X <= 1'b1;
	JOY2_Y <= 1'b1;
end
else begin
	CLK_DIV <= CLK_DIV + 1'b1;

	if (JOY_WRITE && JOY_ADDR==3'd1) begin
		JOY1_X <= 1'b1;
		JOY1_Y <= 1'b1;
		JOY2_X <= 1'b1;
		JOY2_Y <= 1'b1;
	end
	
	if (CLK_DIV==0) begin
		if (JOY1_X>0) JOY1_X <= JOY1_X - 1'b1;
		if (JOY1_Y>0) JOY1_Y <= JOY1_Y - 1'b1;
		if (JOY2_X>0) JOY2_X <= JOY2_X - 1'b1;
		if (JOY2_Y>0) JOY2_Y <= JOY2_Y - 1'b1;
	end


end


endmodule
