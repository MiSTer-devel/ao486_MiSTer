module pattern_vg
#(
	parameter B=8, // number of bits per channel
	X_BITS=13,
	Y_BITS=13,
	FRACTIONAL_BITS = 12
)

(
	input reset, clk_in,
	input wire [X_BITS-1:0] x,
	input wire [Y_BITS-1:0] y,
	input wire vn_in, hn_in, dn_in,
	input wire [B-1:0] r_in, g_in, b_in,
	output reg vn_out, hn_out, den_out,
	output reg [B-1:0] r_out, g_out, b_out,
	input wire [X_BITS-1:0] total_active_pix,
	input wire [Y_BITS-1:0] total_active_lines,
	input wire [7:0] pattern,
	input wire [B+FRACTIONAL_BITS-1:0] ramp_step
);
	
reg [B+FRACTIONAL_BITS-1:0] ramp_values; // 12-bit fractional end for ramp values


//wire bar_0 = y<90;
wire bar_1 = y>=90 & y<180;
wire bar_2 = y>=180 & y<270;
wire bar_3 = y>=270 & y<360;
wire bar_4 = y>=360 & y<450;
wire bar_5 = y>=450 & y<540;
wire bar_6 = y>=540 & y<630;
wire bar_7 = y>=630 & y<720;


wire red_enable = bar_1 | bar_3 | bar_5 | bar_7;
wire green_enable = bar_2 | bar_3 | bar_6 | bar_7;
wire blue_enable = bar_4 | bar_5 | bar_6 | bar_7;
	
always @(posedge clk_in)
	begin
		vn_out <= vn_in;
		hn_out <= hn_in;
		den_out <= dn_in;
	if (reset)
		ramp_values <= 0;
	else if (pattern == 8'b0) // no pattern
	begin
		r_out <= r_in;
		g_out <= g_in;
		b_out <= b_in;
	end
	else if (pattern == 8'b1) // border
	begin
		if (dn_in && ((y == 12'b0) || (x == 12'b0) || (x == total_active_pix - 1) || (y == total_active_lines - 1)))
		begin
			r_out <= 8'hFF;
			g_out <= 8'hFF;
			b_out <= 8'hFF;
		end
		else	// Double-border (OzOnE)...
		if (dn_in && ((y == 12'b0+20) || (x == 12'b0+20) || (x == total_active_pix - 1 - 20) || (y == total_active_lines - 1 - 20)))
		begin
			r_out <= 8'hD0;
			g_out <= 8'hB0;
			b_out <= 8'hB0;
		end
		else
		begin
			r_out <= r_in;
			g_out <= g_in;
			b_out <= b_in;
		end
	end
	else if (pattern == 8'd2) // moireX
	begin
		if ((dn_in) && x[0] == 1'b1)
		begin
			r_out <= 8'hFF;
			g_out <= 8'hFF;
			b_out <= 8'hFF;
		end
		else
		begin
			r_out <= 8'b0;
			g_out <= 8'b0;
			b_out <= 8'b0;
		end
	end
	else if (pattern == 8'd3) // moireY
	begin
		if ((dn_in) && y[0] == 1'b1)
		begin
			r_out <= 8'hFF;
			g_out <= 8'hFF;
			b_out <= 8'hFF;
		end
		else
		begin
			r_out <= 8'b0;
			g_out <= 8'b0;
			b_out <= 8'b0;
		end
	end
	else if (pattern == 8'd4) // Simple RAMP
	begin
		r_out <= (red_enable) ? ramp_values[B+FRACTIONAL_BITS-1:FRACTIONAL_BITS] : 8'h00;
		g_out <= (green_enable) ? ramp_values[B+FRACTIONAL_BITS-1:FRACTIONAL_BITS] : 8'h00;
		b_out <= (blue_enable) ? ramp_values[B+FRACTIONAL_BITS-1:FRACTIONAL_BITS] : 8'h00;
		
		if ((x == total_active_pix - 1) && (dn_in))
			ramp_values <= 0;
		else if ((x == 0) && (dn_in))
			ramp_values <= ramp_step;
		else if (dn_in)
			ramp_values <= ramp_values + ramp_step;
	end
end

endmodule
