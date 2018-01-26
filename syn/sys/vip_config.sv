
module vip_config
(
	input             clk,
	input             reset,
	
	input       [7:0] ARX,
	input       [7:0] ARY,

	input      [11:0] WIDTH,
	input      [11:0] HFP,
	input      [11:0] HBP,
	input      [11:0] HS,
	input      [11:0] HEIGHT,
	input      [11:0] VFP,
	input      [11:0] VBP,
	input      [11:0] VS,

	output reg  [8:0] address,
	output reg        write,
	output reg [31:0] writedata,
	input             waitrequest
);

reg  [31:0] wcalc;
reg  [31:0] hcalc;

wire [31:0] videow = (wcalc > WIDTH)  ? WIDTH  : wcalc;
wire [31:0] videoh = (hcalc > HEIGHT) ? HEIGHT : hcalc;

wire [31:0] posx   = (WIDTH - videow)>>1;
wire [31:0] posy   = (HEIGHT- videoh)>>1;


always @(posedge clk) begin
	reg [7:0] state = 0;
	reg [7:0] arx, ary;
	reg [7:0] arxd, aryd;
	integer   timeout = 0;
	
	arxd <= ARX;
	aryd <= ARY;

	write <= 0;
	if(reset || (!state && ((arx != arxd) || (ary != aryd)))) begin
		arx <= arxd;
		ary <= aryd;
		timeout <= 10000;
	end
	else
	if(timeout > 0)
	begin
		timeout <= timeout - 1;
		if(timeout == 1) begin
			state <= 1;
			wcalc <= (HEIGHT*arx)/ary;
			hcalc <= (WIDTH*ary)/arx;
		end
	end
	else
	if(~waitrequest && state)
	begin
		state <= state + 1'd1;
		write <= 1;

		if(state&3) write <= 0;
		else 
		case(state>>2)
			//scaler
			30: begin
					address   <= 'h003; //Output Width
					writedata <= videow;
				end
			31: begin
					address   <= 'h004; //Output Height
					writedata <= videoh;
				end
			32: begin
					address   <= 'h000; //Go
					writedata <= 1;
				end

			//mixer
			20: begin
					address   <= 'h083; //Bkg Width
					writedata <= WIDTH;
				end
			21: begin
					address   <= 'h084; //Bkg Height
					writedata <= HEIGHT;
				end
			22: begin
					address   <= 'h088; //Pos X
					writedata <= posx;
				end
			23: begin
					address   <= 'h089; //Pos Y
					writedata <= posy;
				end
			24: begin
					address   <= 'h08A; //Enable Video 0
					writedata <= 1;
				end
			25: begin
					address   <= 'h080; //Go
					writedata <= 1;
				end

			//video mode
			01: begin
					address   <= 'h104; //Bank
					writedata <= 0;
				end
			02: begin
					address   <= 'h105; //Progressive/Interlaced
					writedata <= 0;
				end
			03: begin
					address   <= 'h106; //Active pixel count
					writedata <= WIDTH;
				end
			04: begin
					address   <= 'h107; //Active line count
					writedata <= HEIGHT;
				end
			05: begin
					address   <= 'h109; //Horizontal Front Porch
					writedata <= HFP;
				end
			06: begin
					address   <= 'h10A; //Horizontal Sync Length
					writedata <= HS;
				end
			07: begin
					address   <= 'h10B; //Horizontal Blanking (HFP+HBP+HSync)
					writedata <= HFP+HBP+HS;
				end
			08: begin
					address   <= 'h10C; //Vertical Front Porch
					writedata <= VFP;
				end
			09: begin
					address   <= 'h10D; //Vertical Sync Length
					writedata <= VS;
				end
			10: begin
					address   <= 'h10E; //Vertical blanking (VFP+VBP+VSync)
					writedata <= VFP+VBP+VS;
				end
			11: begin
					address   <= 'h11E; //Valid
					writedata <= 1;
				end
			12: begin
					address   <= 'h100; //Go
					writedata <= 1;
				end

			default: write  <= 0;
		endcase
	end
end

endmodule
