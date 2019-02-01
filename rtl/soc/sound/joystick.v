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

	assign JOY_DO = {!JOY2_BUT2, !JOY2_BUT1, !JOY1_BUT2, !JOY1_BUT1, JOY2_Y<9'd511, JOY2_X<9'd511, JOY1_Y<9'd511, JOY1_X<9'd511};


reg [11:0] JOY1_X;
reg [11:0] JOY1_Y;

reg [11:0] JOY2_X;
reg [11:0] JOY2_Y;

reg [7:0] CLK_DIV;

wire JOY1_RIGHT = joystick_0[0];
wire JOY1_LEFT  = joystick_0[1];
wire JOY1_DOWN  = joystick_0[2];
wire JOY1_UP 	 = joystick_0[3];
wire JOY1_BUT1  = joystick_0[4];
wire JOY1_BUT2  = joystick_0[5];
wire JOY1_BUT3  = joystick_0[6];
wire JOY1_BUT4  = joystick_0[7];

wire JOY2_RIGHT = joystick_1[0];
wire JOY2_LEFT  = joystick_1[1];
wire JOY2_DOWN  = joystick_1[2];
wire JOY2_UP 	 = joystick_1[3];
wire JOY2_BUT1  = joystick_1[4];
wire JOY2_BUT2  = joystick_1[5];
wire JOY2_BUT3  = joystick_1[6];
wire JOY2_BUT4  = joystick_1[7];


always @(posedge CLOCK or negedge RESET_N)
if (!RESET_N) begin
	JOY1_X <= 12'd4095;
	JOY1_Y <= 12'd4095;
	JOY2_X <= 12'd4095;
	JOY2_Y <= 12'd4095;
end
else begin
	CLK_DIV <= CLK_DIV + 1'b1;

	if (JOY_WRITE && JOY_ADDR==3'd1) begin
		JOY1_X <= (JOY1_LEFT) ? 12'd4095 : (JOY1_RIGHT) ? 12'd0 : 12'd2047;
		JOY1_Y <= (JOY1_UP)   ? 12'd4095 : (JOY1_DOWN)  ? 12'd0 : 12'd2047;
		
		JOY2_X <= (JOY2_LEFT) ? 12'd4095 : (JOY2_RIGHT) ? 12'd0 : 12'd2047;
		JOY2_Y <= (JOY2_UP)   ? 12'd4095 : (JOY2_DOWN)  ? 12'd0 : 12'd2047;
	end
	
	if (CLK_DIV==0) begin
		if (JOY1_X<12'd4095) JOY1_X <= JOY1_X + 1'b1;
		if (JOY1_Y<12'd4095) JOY1_Y <= JOY1_Y + 1'b1;
		if (JOY2_X<12'd4095) JOY2_X <= JOY2_X + 1'b1;
		if (JOY2_Y<12'd4095) JOY2_Y <= JOY2_Y + 1'b1;
	end

end


endmodule
