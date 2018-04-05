
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


reg         newres = 1;

wire [21:0] init[23] =
'{
	//video mode
	{newres, 2'd2, 7'd04, 12'd0  }, //Bank
	{newres, 2'd2, 7'd30, 12'd0  }, //Valid
	{newres, 2'd2, 7'd05, 12'd0  }, //Progressive/Interlaced
	{newres, 2'd2, 7'd06, w      }, //Active pixel count
	{newres, 2'd2, 7'd07, h      }, //Active line count
	{newres, 2'd2, 7'd09, hfp    }, //Horizontal Front Porch
	{newres, 2'd2, 7'd10, hs     }, //Horizontal Sync Length
	{newres, 2'd2, 7'd11, hb     }, //Horizontal Blanking (HFP+HBP+HSync)
	{newres, 2'd2, 7'd12, vfp    }, //Vertical Front Porch
	{newres, 2'd2, 7'd13, vs     }, //Vertical Sync Length
	{newres, 2'd2, 7'd14, vb     }, //Vertical blanking (VFP+VBP+VSync)
	{newres, 2'd2, 7'd30, 12'd1  }, //Valid
	{newres, 2'd2, 7'd00, 12'd1  }, //Go

	//mixer
	{  1'd1, 2'd1, 7'd03, w      }, //Bkg Width
	{  1'd1, 2'd1, 7'd04, h      }, //Bkg Height
	{  1'd1, 2'd1, 7'd08, posx   }, //Pos X
	{  1'd1, 2'd1, 7'd09, posy   }, //Pos Y
	{  1'd1, 2'd1, 7'd10, 12'd1  }, //Enable Video 0
	{  1'd1, 2'd1, 7'd00, 12'd1  }, //Go

	//scaler
	{  1'd1, 2'd0, 7'd03, videow }, //Output Width
	{  1'd1, 2'd0, 7'd04, videoh }, //Output Height
	{  1'd1, 2'd0, 7'd00, 12'd1  }, //Go

	22'h3FFFFF
};

reg [11:0] w;
reg [11:0] hfp;
reg [11:0] hbp;
reg [11:0] hs;
reg [11:0] hb;
reg [11:0] h;
reg [11:0] vfp;
reg [11:0] vbp;
reg [11:0] vs;
reg [11:0] vb;

reg [11:0] videow;
reg [11:0] videoh;

reg [11:0] posx;
reg [11:0] posy;

always @(posedge clk) begin
	reg  [7:0] state = 0;
	reg  [7:0] arx, ary;
	reg  [7:0] arxd, aryd;
	reg [11:0] vset, vsetd;
	reg        cfg, cfgd;
	reg [31:0] wcalc;
	reg [31:0] hcalc;
	reg [12:0] timeout = 0;

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
		timeout <= '1;
		state <= 0;
		if(reset || (~cfgd && cfg)) newres <= 1;
	end
	else
	if(timeout > 0)
	begin
		timeout <= timeout - 1'd1;
		state <= 1;
		if(!(timeout & 'h1f)) case(timeout>>5)
			5:	begin
					w   <= WIDTH;
					hfp <= HFP;
					hbp <= HBP;
					hs  <= HS;
					h   <= HEIGHT;
					vfp <= VFP;
					vbp <= VBP;
					vs  <= VS;
				end
			4: begin
					hb  <= hfp+hbp+hs;
					vb  <= vfp+vbp+vs;
				end
			3: begin
					wcalc <= vset ? (vset*arx)/ary : (h*arx)/ary;
					hcalc <= (w*ary)/arx;
				end
			2: begin
					videow <= (!vset && (wcalc > w))    ? w : wcalc[11:0];
					videoh <= vset ? vset : (hcalc > h) ? h : hcalc[11:0];
				end
			1: begin
					posx <= (w - videow)>>1;
					posy <= (h - videoh)>>1;
				end
		endcase
	end
	else
	if(~waitrequest && state)
	begin
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
