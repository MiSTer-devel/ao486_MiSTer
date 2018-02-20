
module vip_config
(
	input             clk,
	input             reset,
	
	input       [7:0] ARX,
	input       [7:0] ARY,
	input             CFG_SET,

	input      [11:0] WIDTH,
	input      [11:0] HFP,
	input      [11:0] HBP,
	input      [11:0] HS,
	input      [11:0] HEIGHT,
	input      [11:0] VFP,
	input      [11:0] VBP,
	input      [11:0] VS,
	
	input      [11:0] VSET,

	output reg  [8:0] address,
	output reg        write,
	output reg [31:0] writedata,
	input             waitrequest
);

reg  [31:0] wcalc;
reg  [31:0] hcalc;

wire [31:0] videow = (!VSET && (wcalc > WIDTH))     ? WIDTH  : wcalc;
wire [31:0] videoh = VSET ? VSET : (hcalc > HEIGHT) ? HEIGHT : hcalc;

wire [31:0] posx   = (WIDTH - videow)>>1;
wire [31:0] posy   = (HEIGHT- videoh)>>1;

reg         newres = 1;

wire [21:0] init[23] =
'{
	//video mode
	{newres, 2'd2, 7'd04, 12'd0        }, //Bank
	{newres, 2'd2, 7'd30, 12'd0        }, //Valid
	{newres, 2'd2, 7'd05, 12'd0        }, //Progressive/Interlaced
	{newres, 2'd2, 7'd06, WIDTH        }, //Active pixel count
	{newres, 2'd2, 7'd07, HEIGHT       }, //Active line count
	{newres, 2'd2, 7'd09, HFP          }, //Horizontal Front Porch
	{newres, 2'd2, 7'd10, HS           }, //Horizontal Sync Length
	{newres, 2'd2, 7'd11, HFP+HBP+HS   }, //Horizontal Blanking (HFP+HBP+HSync)
	{newres, 2'd2, 7'd12, VFP          }, //Vertical Front Porch
	{newres, 2'd2, 7'd13, VS           }, //Vertical Sync Length
	{newres, 2'd2, 7'd14, VFP+VBP+VS   }, //Vertical blanking (VFP+VBP+VSync)
	{newres, 2'd2, 7'd30, 12'd1        }, //Valid
	{newres, 2'd2, 7'd00, 12'd1        }, //Go

	//mixer
	{  1'd1, 2'd1, 7'd03, WIDTH        }, //Bkg Width
	{  1'd1, 2'd1, 7'd04, HEIGHT       }, //Bkg Height
	{  1'd1, 2'd1, 7'd08, posx[11:0]   }, //Pos X
	{  1'd1, 2'd1, 7'd09, posy[11:0]   }, //Pos Y
	{  1'd1, 2'd1, 7'd10, 12'd1        }, //Enable Video 0
	{  1'd1, 2'd1, 7'd00, 12'd1        }, //Go

	//scaler
	{  1'd1, 2'd0, 7'd03, videow[11:0] }, //Output Width
	{  1'd1, 2'd0, 7'd04, videoh[11:0] }, //Output Height
	{  1'd1, 2'd0, 7'd00, 12'd1        }, //Go

	22'h3FFFFF
};

always @(posedge clk) begin
	reg  [7:0] state = 0;
	reg  [7:0] arx, ary;
	reg  [7:0] arxd, aryd;
	reg [11:0] vset, vsetd;
	reg        cfg, cfgd;
	integer    timeout = 0;
	
	arxd  <= ARX;
	aryd  <= ARY;
	vsetd <= VSET;
	
	cfg   <= CFG_SET;
	cfgd  <= cfg;

	write <= 0;
	if(reset || (arx != arxd) || (ary != aryd) || (vset != vsetd) || (~cfgd && cfg)) begin
		arx <= arxd;
		ary <= aryd;
		vset <= vsetd;
		timeout <= 10000;
		state <= 0;
		if(reset || (~cfgd && cfg)) newres <= 1;
	end
	else
	if(timeout > 0)
	begin
		timeout <= timeout - 1;
		state <= 1;
	end
	else
	if(~waitrequest && state)
	begin
		if(state == 1) begin
			wcalc <= VSET ? (VSET*arx)/ary : (HEIGHT*arx)/ary;
			hcalc <= (WIDTH*ary)/arx;
		end
		state <= state + 1'd1;
		write <= 0;
		if((state&3)==3) begin
			if(init[state>>2] == 22'h3FFFFF) begin
				state  <= 0;
				newres <= 0;
			end
			else begin
				writedata <= 0;
				{write, address, writedata[11:0]} <= init[state>>2];
			end
		end
	end
end

endmodule
