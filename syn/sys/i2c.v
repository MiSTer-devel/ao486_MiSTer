
module I2C_Controller
(
	input        CLK,

	input        START,
	input [23:0] I2C_DATA,
	output reg   END = 1,
	output reg   ACK = 0,

	//I2C bus
	output       I2C_SCL,
 	inout        I2C_SDA
);


//	Clock Setting
parameter CLK_Freq = 50_000_000;	//	50 MHz
parameter I2C_Freq = 400_000;		//	400 KHz

reg I2C_CLOCK;
always@(negedge CLK) begin
	integer mI2C_CLK_DIV = 0;
	if(mI2C_CLK_DIV < (CLK_Freq/I2C_Freq)) begin
		mI2C_CLK_DIV <= mI2C_CLK_DIV + 1;
	end else	begin
		mI2C_CLK_DIV <= 0;
		I2C_CLOCK    <= ~I2C_CLOCK;
	end
end

assign I2C_SCL = SCLK | I2C_CLOCK;
assign I2C_SDA = SDO  ? 1'bz : 1'b0;

reg SCLK = 1, SDO = 1;

always @(posedge CLK) begin
	reg old_clk;
	reg old_st;

	reg  [5:0] SD_COUNTER = 'b111111;
	reg [0:31] SD;

	old_clk <= I2C_CLOCK;
	old_st  <= START;

	if(~old_st && START) begin
		SCLK <= 1;
		SDO  <= 1;
		ACK  <= 0;
		END  <= 0;
		SD   <= {2'b10, I2C_DATA[23:16], 1'b1, I2C_DATA[15:8], 1'b1, I2C_DATA[7:0], 4'b1011};
		SD_COUNTER <= 0;
	end else begin
		if(~old_clk && I2C_CLOCK && ~&SD_COUNTER) begin
			SD_COUNTER <= SD_COUNTER + 6'd1;	
			case(SD_COUNTER)
				      01: SCLK <= 0;
				10,19,28: ACK  <= ACK | I2C_SDA;
				      29: SCLK <= 1;
				      32: END  <= 1;
			endcase
		end

		if(old_clk && ~I2C_CLOCK && ~SD_COUNTER[5]) SDO <= SD[SD_COUNTER[4:0]];
	end
end

endmodule
