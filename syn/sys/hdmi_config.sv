
module hdmi_config
(
	//	Host Side
	input			iCLK,
	input			iRST_N,
	
	// 0 - 480i
	// 1 - 480p
	// 2 - 576i
	// 3 - 576p
	// 4 - 720p
	// 5-7 - reserved
	input [2:0] iRES,
	
	// 0 - 4:3
	// 1 - 16:9
	input       iAR,
	
	input       audio_48k,

	//	I2C Side
	output		I2C_SCL,
	inout 		I2C_SDA
);

//	Internal Registers/Wires
reg        mI2C_GO = 0;
wire       mI2C_END;
wire       mI2C_ACK;
reg [15:0] LUT_DATA;
reg  [7:0] LUT_INDEX = 0;

I2C_Controller #(50_000_000, 400_000) i2c_av
(
	.CLK(iCLK),

	.I2C_SCL(I2C_SCL),		//	I2C CLOCK
	.I2C_SDA(I2C_SDA),		//	I2C DATA

	.I2C_DATA({8'h72,init_data[LUT_INDEX]}),	//	DATA:[SLAVE_ADDR,SUB_ADDR,DATA]. 0x72 is the Slave Address of the ADV7513 chip!
	.START(mI2C_GO),    		//	START transfer
	.END(mI2C_END),			//	END transfer 
	.ACK(mI2C_ACK) 			//	ACK
);

//////////////////////	Config Control	////////////////////////////
always@(posedge iCLK or negedge iRST_N) begin
	reg  [1:0] mSetup_ST = 0;

	if(!iRST_N) begin
		LUT_INDEX	<=	0;
		mSetup_ST	<=	0;
		mI2C_GO		<=	0;
	end else begin
		if(init_data[LUT_INDEX] != 16'hFFFF) begin
			case(mSetup_ST)
			0:	begin
					mI2C_GO		<=	1;
					mSetup_ST	<=	1;
				end
			1: if(~mI2C_END) mSetup_ST	<=	2;
			2:	begin
					mI2C_GO <= 0;
					if(mI2C_END) begin
						mSetup_ST <= 0;
						if(!mI2C_ACK) LUT_INDEX <= LUT_INDEX + 8'd1;
					end
				end
			endcase
		end
	end
end

wire [15:0] res480i[6] = '{'h35_1D, 'h36_92, 'h37_05, 'h38_A0, 'h39_0F, 'h3A_00};
wire [15:0] res480p[6] = '{'h35_1F, 'h36_E8, 'h37_05, 'h38_A0, 'h39_1E, 'h3A_00};
wire [15:0] res576i[6] = '{'h35_20, 'h36_D6, 'h37_05, 'h38_A0, 'h39_12, 'h3A_00};
wire [15:0] res576p[6] = '{'h35_20, 'h36_EC, 'h37_05, 'h38_A0, 'h39_24, 'h3A_00};
wire [15:0] res720p[6] = '{'h35_40, 'h36_D9, 'h37_0A, 'h38_00, 'h39_2D, 'h3A_00};

reg  [15:0] resVar[6];
always_comb begin
	case(iRES)
		0: resVar <= res480i;
		1: resVar <= res480p;
		2: resVar <= res576i;
		3: resVar <= res576p;
		4: resVar <= res720p;
		default: resVar <= res720p;
	endcase
end


////////////////////////////////////////////////////////////////////
/////////////////////	Config Data LUT	  //////////////////////////

wire [15:0] init_data[58] = 
'{
	16'h4110,					// Power Down control
	16'h9803,					// ADI required Write.
	16'h9A70,					// ADI required Write.
	16'h9C30,					// ADI required Write.
	{8'h9D, 8'b0110_0001},	// [7:4] must be b0110!.
									// [3:2] b00 = Input clock not divided. b01 = Clk divided by 2. b10 = Clk divided by 4. b11 = invalid!
									//	[1:0] must be b01!
	16'hA2A4,					// ADI required Write.
	16'hA3A4,					// ADI required Write.
	16'hE0D0,					// ADI required Write.


	resVar[0],
	resVar[1],
	resVar[2],
	resVar[3],
	resVar[4],
	resVar[5],
	
	{8'h16, 8'b0011_1000},	// Output Format 444 [7]=0.
									// [6] must be 0!
									// Colour Depth for Input Video data [5:4] b11 = 8-bit.
									// Input Style [3:2] b10 = Style 1 (ignored when using 444 input).
									// DDR Input Edge falling [1]=0 (not using DDR atm).
									// Output Colour Space RGB [0]=0.

//	{8'h16, 8'b1011_0101},	// Output Format 422 [7]=1.
									// [6] must be 0!
									// Colour Depth for Input Video data [5:4] b11 = 8-bit.
									// Input Style [3:2] b01 = Style 2.
									// DDR Input Edge falling [1]=0 (not using DDR atm).
									// Output Colour Space YPrPb [0]=1.

//	{8'h17, 8'b0110_0000},	// Aspect ratio 4:3 [1]=0. DE Generation DISabled [0]=0.
									// Vsync polarity HIGH [6]=0, LOW [6]=1.
									// Hsync polarity HIGH [5]=0, LOW [5]=1.

//	{8'h17, 8'b0110_0001},	// Aspect ratio 4:3 [1]=0. DE Generation ENabled [0]=1.

//	{8'h17, 8'b0110_0011},	// Aspect ratio 16:9 [1]=1. DE Generation ENabled [0]=1.

	{8'h17, 6'b011000, iAR, 1'b0}, // Aspect ratio 16:9 [1]=1, 4:3 [1]=0

	{8'h18, 8'b0100_0110},	// CSC disabled [7]=0.
									// CSC Scaling Factor [6:5] b10 = +/- 4.0, -16384 - 16380.
									// CSC Equation 3 [4:0] b00110.


//	{8'h3B, 8'b0000_1010},	// Pixel repetition [6:5] b00 AUTO. [4:3] b01 x2 mult of input clock. [2:1] b01 x2 pixel rep to send to HDMI Rx.

	{8'h3B, 8'b0000_0000},	// Pixel repetition [6:5] b00 AUTO. [4:3] b00 x1 mult of input clock. [2:1] b00 x1 pixel rep to send to HDMI Rx.

//	{8'h3B, 8'b0110_1010},	// Pixel repetition [6:5] b11 MANUAL. [4:3] b01 x2 mult of input clock. [2:1] b01 x2 pixel rep to send to HDMI Rx.

//	{8'h3C, 8'b0000_0110},	// VIC#6 480i-60, 2x clk, 4:3.
//	{8'h3C, 8'b0000_0001},	// VIC#1 VGA (640x480), 2x clk, 4:3.

//	{8'h3C, 8'b0000_0010},	// VIC#2 480p (720x480), 2x clk, 4:3.

	16'h4000,					// General Control Packet Enable

	{8'h48, 8'b0000_1000},	// [6]=0 Normal bus order!
									// [5] DDR Alignment.
									// [4:3] b01 Data right justified (for YCbCr 422 input modes).

	16'h49A8,					// ADI required Write.
	16'h4C00,					// ADI required Write.

	{8'h55, 8'b0001_0000},	// [7] must be 0!. Set RGB444 in AVinfo Frame [6:5], Set active format [4].
//	{8'h55, 8'b0101_0000},	// [7] must be 0!. Set YCbCr 444 in AVinfo Frame [6:5], Set active format [4].
//	{8'h55, 8'b0011_0001},	// [7] must be 0!. Set YCbCr 422 in AVinfo Frame [6:5].
									// AVI InfoFrame Valid [4].
									// Bar Info [3:2] b00 Bars invalid. b01 Bars vertical. b10 Bars horizontal. b11 Bars both.
									// Scan Info [1:0] b00 (No data). b01 TV. b10 PC. b11 None.

//	{8'h94, 8'b1000_0000},	// [7]=1 HPD Interrupt ENabled.

	16'h7301,

	16'h9400,					// HPD Interrupt disabled.

	16'h9902,					// ADI required Write.
	16'h9B18,					// ADI required Write.

	16'h9F00,					// ADI required Write.

	{8'hA1, 8'b0100_0000},	// [6]=1 Monitor Sense Power Down DISabled.
	
	16'hA408,					// ADI required Write.
	16'hA504,					// ADI required Write.
	16'hA600,					// ADI required Write.
	16'hA700,					// ADI required Write.
	16'hA800,					// ADI required Write.
	16'hA900,					// ADI required Write.
	16'hAA00,					// ADI required Write.
	16'hAB40,					// ADI required Write.
	
	{8'hAF, 8'b0001_0110},	// [7]=0 HDCP Disabled.
									// [6:5] must be b00!
									// [4]=1 Current frame IS HDCP encrypted!??? (HDCP disabled anyway?)
									// [3:2] must be b01!
									//	[1]=1 HDMI Mode.
									// [0] must be b0!

	16'hB900,					// ADI required Write.

	{8'hBA, 8'b0110_0000},	// [7:5] Input Clock delay...
									// b000 = -1.2ns.
									// b001 = -0.8ns.
									// b010 = -0.4ns.
									// b011 = No delay.
									// b100 = 0.4ns.
									// b101 = 0.8ns.
									// b110 = 1.2ns.
									// b111 = 1.6ns.
					
	16'hBB00,					// ADI required Write.
	
	{8'hD6, 8'b1100_0000},	// [7:6] HPD Control...
									// 00 = HPD is from both HPD pin or CDC HPD
									// 01 = HPD is from CDC HPD
									// 10 = HPD is from HPD pin
									// 11 = HPD is always high
	
	16'hDE9C,					// ADI required Write.
	16'hE460,					// ADI required Write.
	16'hFA7D,					// Nbr of times to search for good phase

	
									// (Audio stuff on Programming Guide, Page 66)...
	
	{8'h0A, 8'b0000_0000},	// [6:4] Audio Select. b000 = I2S.
									// [3:2] Audio Mode. (HBR stuff, leave at 00!).

	{8'h0B, 8'b0000_1110},	//
									
	{8'h0C, 8'b0000_0100},	// [7] 0 = Use sampling rate from I2S stream.   1 = Use samp rate from I2C Register.
									// [6] 0 = Use Channel Status bits from stream. 1 = Use Channel Status bits from I2C register.
									// [2] 1 = I2S0 Enable.
									// [1:0] I2S Format: 00 = Standard. 01 = Right Justified. 10 = Left Justified. 11 = AES.
									
	{8'h0D, 8'b0001_0000},	// [4:0] I2S Bit (Word) Width for Right-Justified.
	{8'h14, 8'b0000_0010},	// [3:0] Audio Word Length. b0010 = 16 bits.
	{8'h15, ~audio_48k, 7'b010_0000},	// I2S Sampling Rate [7:4]. b0000 = (44.1KHz). b0010 = 48KHz.
									// Input ID [3:1] b000 (0) = 24-bit RGB 444 or YCrCb 444 with Separate Syncs.
									
//	{8'h15, 8'b0010_0001},	// I2S Sampling Rate [7:4]. b0000 = (44.1KHz). b0010 = 48KHz.
									// Input ID [3:0] b0001 (1) = 16, 20, 24 bit YCbCr 4:2:2 with Separate Syncs.

//	{8'h15, 8'b0010_0011},	// I2S Sampling Rate [7:4]. b0000 = (44.1KHz). b0010 = 48KHz.
									// Input ID [3:0] b0011 (3) = 16, 20, 24 bit YCbCr 4:2:2 (2x Pixel Clock, with Separate Syncs).
	
	// Audio Clock Config
	16'h0100,					//  
	audio_48k ? 16'h0218 : 16'h0230,	// Set N Value 12288/6144
	16'h0300,					//

	16'h0701,					//
	16'h0822,					// Set CTS Value 74250
	16'h090A,					//

	16'hFFFF 				   // END
};

////////////////////////////////////////////////////////////////////

endmodule