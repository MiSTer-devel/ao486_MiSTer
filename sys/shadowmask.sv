module shadowmask
(
	input             clk,
	input             clk_sys,

	input             cmd_wr,
	input      [15:0] cmd_in,

	input      [23:0] din,
	input             hs_in,vs_in,
	input             de_in,
	input             brd_in,
	input             enable,

	output reg [23:0] dout,
	output reg        hs_out,vs_out,
	output reg        de_out
);


reg  [4:0] hmax;
reg  [4:0] vmax;
reg  [7:0] mask_idx;
reg        mask_2x;
reg        mask_rotate;
reg        mask_enable;
reg [10:0] mask_lut[256];

always @(posedge clk) begin
	reg [4:0] hcount;
	reg [4:0] vcount;
	reg [3:0] hindex;
	reg [3:0] vindex;
	reg [4:0] hmax2;
	reg [4:0] vmax2;
	reg [11:0] pcnt,pde;
	reg old_hs, old_vs, old_brd;
	reg next_v;

	old_hs <= hs_in;
	old_vs <= vs_in;
	old_brd<= brd_in;

	// hcount and vcount counts pixel rows and columns
	// hindex and vindex half the value of the counters for double size patterns
	// hindex2, vindex2 swap the h and v counters for drawing rotated masks
	hindex <= mask_2x ? hcount[4:1] : hcount[3:0];
	vindex <= mask_2x ? vcount[4:1] : vcount[3:0];
	mask_idx <= mask_rotate ? {hindex,vindex} : {vindex,hindex};

	// hmax and vmax store these sizes
	// hmax2 and vmax2 swap the values to handle rotation
	hmax2 <= ((mask_rotate ? vmax : hmax) << mask_2x) | mask_2x;
	vmax2 <= ((mask_rotate ? hmax : vmax) << mask_2x) | mask_2x;

	pcnt <= pcnt+1'd1;
	if(old_brd && ~brd_in) pde <= pcnt-4'd3;

	hcount <= hcount+1'b1;
	if(hcount == hmax2 || pde == pcnt) hcount <= 0;

	if(~old_brd && brd_in) next_v <= 1;
	if(old_vs && ~vs_in) vcount <= 0;
	if(old_hs && ~hs_in) begin
		vcount <= vcount + next_v;
		next_v <= 0;
		pcnt   <= 0;
		if (vcount == vmax2) vcount <= 0;
	end
end

reg [4:0] r_mul, g_mul, b_mul; // 1.4 fixed point multipliers
always @(posedge clk) begin
	reg [10:0] lut;

	lut <= mask_lut[mask_idx];

	r_mul <= 5'b10000; g_mul <= 5'b10000; b_mul <= 5'b10000; // default 100% to all channels
	if (mask_enable) begin
		r_mul <= lut[10] ? {1'b1,lut[7:4]} : {1'b0,lut[3:0]};
		g_mul <= lut[9]  ? {1'b1,lut[7:4]} : {1'b0,lut[3:0]};
		b_mul <= lut[8]  ? {1'b1,lut[7:4]} : {1'b0,lut[3:0]};
	end
end

always @(posedge clk) begin
	reg [11:0] vid;
	reg  [7:0] r1,   g1,   b1;
	reg  [7:0] r2,   g2,   b2;
	reg  [7:0] r3_x, g3_x, b3_x; // 6.25% + 12.5%
	reg  [8:0] r3_y, g3_y, b3_y; // 25% + 50% + 100%
	reg  [8:0] r4,   g4,   b4;

	// C1 - data input
	{r1,g1,b1} <= din;
	vid <= {vid[8:0],vs_in, hs_in, de_in};

	// C2 - relax timings
	{r2,g2,b2} <= {r1,g1,b1};

	// C3 - perform multiplications
	r3_x <= ({4{r_mul[0]}} & r2[7:4]) + ({8{r_mul[1]}} & r2[7:3]);
	r3_y <= ({6{r_mul[2]}} & r2[7:2]) + ({7{r_mul[3]}} & r2[7:1]) + ({9{r_mul[4]}} & r2[7:0]);
	g3_x <= ({4{g_mul[0]}} & g2[7:4]) + ({8{g_mul[1]}} & g2[7:3]);
	g3_y <= ({6{g_mul[2]}} & g2[7:2]) + ({7{g_mul[3]}} & g2[7:1]) + ({9{g_mul[4]}} & g2[7:0]);
	b3_x <= ({4{b_mul[0]}} & b2[7:4]) + ({8{b_mul[1]}} & b2[7:3]);
	b3_y <= ({6{b_mul[2]}} & b2[7:2]) + ({7{b_mul[3]}} & b2[7:1]) + ({9{b_mul[4]}} & b2[7:0]);

	// C4 - combine results
	r4 <= r3_x + r3_y;
	g4 <= g3_x + g3_y;
	b4 <= b3_x + b3_y;

	// C5 - clamp and output
	dout <= {{8{r4[8]}} | r4[7:0], {8{g4[8]}} | g4[7:0], {8{b4[8]}} | b4[7:0]};
	{vs_out,hs_out,de_out} <= vid[11:9];
end

// clock in mask commands
always @(posedge clk_sys) begin
	reg m_enable;
	reg [7:0] idx;

	if (cmd_wr) begin
		case(cmd_in[15:13])
		3'b000: begin {m_enable, mask_rotate, mask_2x} <= cmd_in[3:1]; idx <= 0; end
		3'b001: vmax <= cmd_in[3:0];
		3'b010: hmax <= cmd_in[3:0];
		3'b011: begin mask_lut[idx] <= cmd_in[10:0]; idx <= idx + 1'd1; end
		endcase
	end

	mask_enable <= m_enable & enable;
end

endmodule
