
module vip_config
(
	input             clk,
	input             reset,
	
	input       [7:0] ARX,
	input       [7:0] ARY,

	output reg  [8:0] address,
	output reg        write,
	output reg [31:0] writedata,
	input             waitrequest
);

//Any input video resolution up to 1920x1080 is supported.

//Output video parameters.
//It's good to keep 1280x720@60 resolution among all cores as most compatible resolution.
parameter  WIDTH  = 1280;
parameter  HEIGHT = 720;
parameter  HFP    = 110;
parameter  HBP    = 220;
parameter  HS     = 40;
parameter  VFP    = 5;
parameter  VBP    = 20;
parameter  VS     = 5;


reg  [31:0] wcalc;
reg  [31:0] hcalc;

wire [31:0] videow = (wcalc > WIDTH)  ? WIDTH  : wcalc;
wire [31:0] videoh = (hcalc > HEIGHT) ? HEIGHT : hcalc;

wire [31:0] posx   = (WIDTH - videow)>>1;
wire [31:0] posy   = (HEIGHT- videoh)>>1;


always @(posedge clk) begin
	reg [7:0] state = 0;
	reg [7:0] arx, ary;
	integer timeout = 0;

	if(reset || (!state && ((arx != ARX) || (ary != ARY)))) begin
		arx <= ARX;
		ary <= ARY;
		timeout <= 0;
		write   <= 0;
	end
	else
	if(timeout < 1000000)
	begin
		timeout <= timeout + 1;
		write <= 0;
		state <= 1;
	end
	else
	if(~waitrequest && state)
	begin
		state <= state + 1'd1;
		write <= 1;

		case(state)
			01: begin
					wcalc <= (HEIGHT*arx)/ary;
					hcalc <= (WIDTH*ary)/arx;
				end
		endcase
		
		if(state&3) write <= 0;
		else 
		case(state>>2)
			//scaler
			01: begin
					address   <= 'h003; //Output Width
					writedata <= videow;
				end
			02: begin
					address   <= 'h004; //Output Height
					writedata <= videoh;
				end
			03: begin
					address   <= 'h000; //Go
					writedata <= 1;
				end

			//mixer
			10: begin
					address   <= 'h083; //Bkg Width
					writedata <= WIDTH;
				end
			11: begin
					address   <= 'h084; //Bkg Height
					writedata <= HEIGHT;
				end
			12: begin
					address   <= 'h088; //Pos X
					writedata <= posx;
				end
			13: begin
					address   <= 'h089; //Pos Y
					writedata <= posy;
				end
			14: begin
					address   <= 'h08A; //Enable Video 0
					writedata <= 1;
				end
			15: begin
					address   <= 'h080; //Go
					writedata <= 1;
				end

			//video mode
			20: begin
					address   <= 'h104; //Bank
					writedata <= 0;
				end
			21: begin
					address   <= 'h105; //Progressive/Interlaced
					writedata <= 0;
				end
			22: begin
					address   <= 'h106; //Active pixel count
					writedata <= WIDTH;
				end
			23: begin
					address   <= 'h107; //Active line count
					writedata <= HEIGHT;
				end
			24: begin
					address   <= 'h109; //Horizontal Front Porch
					writedata <= HFP;
				end
			25: begin
					address   <= 'h10A; //Horizontal Sync Length
					writedata <= HS;
				end
			26: begin
					address   <= 'h10B; //Horizontal Blanking (HFP+HBP+HSync)
					writedata <= HFP+HBP+HS;
				end
			27: begin
					address   <= 'h10C; //Vertical Front Porch
					writedata <= VFP;
				end
			28: begin
					address   <= 'h10D; //Vertical Sync Length
					writedata <= VS;
				end
			29: begin
					address   <= 'h10E; //Vertical blanking (VFP+VBP+VSync)
					writedata <= VFP+VBP+VS;
				end
			30: begin
					address   <= 'h11E; //Valid
					writedata <= 1;
				end
			31: begin
					address   <= 'h100; //Go
					writedata <= 1;
				end

			default: write  <= 0;
		endcase
	end
end

endmodule
