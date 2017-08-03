module sync_vg
#(
	parameter X_BITS=12,
	Y_BITS=12
)
(
	input wire clk,
	input wire reset,
	input wire interlaced,
	input wire [Y_BITS-1:0] v_total_0,
	input wire [Y_BITS-1:0] v_fp_0,
	input wire [Y_BITS-1:0] v_bp_0,
	input wire [Y_BITS-1:0] v_sync_0,
	input wire [Y_BITS-1:0] v_total_1,
	input wire [Y_BITS-1:0] v_fp_1,
	input wire [Y_BITS-1:0] v_bp_1,
	input wire [Y_BITS-1:0] v_sync_1,
	input wire [X_BITS-1:0] h_total,
	input wire [X_BITS-1:0] h_fp,
	input wire [X_BITS-1:0] h_bp,
	input wire [X_BITS-1:0] h_sync,
	input wire [X_BITS-1:0] hv_offset_0,
	input wire [X_BITS-1:0] hv_offset_1,
	output reg vs_out,
	output reg hs_out,
	output reg hde_out,
	output reg vde_out,
	output reg [Y_BITS:0] v_count_out,
	output reg [X_BITS-1:0] h_count_out,
	output reg [X_BITS-1:0] x_out,
	output reg [Y_BITS:0] y_out,
	output reg field_out,
	output wire clk_out
);

reg [X_BITS-1:0] h_count;
reg [Y_BITS-1:0] v_count;
reg field;
reg [Y_BITS-1:0] v_total;
reg [Y_BITS-1:0] v_fp;
reg [Y_BITS-1:0] v_bp;
reg [Y_BITS-1:0] v_sync;
reg [X_BITS-1:0] hv_offset;

assign clk_out = !clk;

/* horizontal counter */
always @(posedge clk)
	if (reset)
		h_count <= 0;
	else
	if (h_count < h_total - 1)
		h_count <= h_count + 1'd1;
	else
		h_count <= 0;
		
/* vertical counter */
always @(posedge clk)
	if (reset)
		v_count <= 0;
	else
	if (h_count == h_total - 1)
	begin
		if (v_count == v_total - 1)
			v_count <= 0;
		else
			v_count <= v_count + 1'd1;
	end

/* field */
always @(posedge clk)
	if (reset)
	begin
		field <= 0;
		v_total <= v_total_0;
		v_fp <= interlaced ? v_fp_1 : v_fp_0; // In the interlaced mode this value must be inverted as v_fp_1 is still in field0
		v_bp <= v_bp_0;
		v_sync <= v_sync_0;
		hv_offset <= hv_offset_0;
	end 
	else 
	if ((interlaced) && ((v_count == v_total - 1) && (h_count == h_total - 1)))
	begin
		field <= field + interlaced;
		v_total <= field ? v_total_0 : v_total_1;
		v_fp <= field ? v_fp_1 : v_fp_0; // This order is inverted as v_fp_1 is still in field0
		v_bp <= field ? v_bp_0 : v_bp_1;
		v_sync <= field ? v_sync_0 : v_sync_1;
		hv_offset <= field ? hv_offset_0 : hv_offset_1;
	end

always @(posedge clk)
	if (reset)
		{ vs_out, hs_out, hde_out, vde_out, field_out } <= 4'b0;
	else begin
		hs_out <= ((h_count < h_sync));

		hde_out <= (h_count >= h_sync + h_bp) && (h_count <= h_total - h_fp - 1);
		vde_out <= (v_count >= v_sync + v_bp) && (v_count <= v_total - v_fp - 1);

		if ((v_count == 0) && (h_count == hv_offset))
			vs_out <= 1'b1;
		else if ((v_count == v_sync) && (h_count == hv_offset))
			vs_out <= 1'b0;

		/* H_COUNT_OUT and V_COUNT_OUT */
		h_count_out <= h_count;
		if (field)
			v_count_out <= v_count + v_total_0;
		else
			v_count_out <= v_count;

		/* X and Y coords � for a backend pattern generator */
		x_out <= h_count - (h_sync + h_bp);
		if (interlaced)
			y_out <= { (v_count - (v_sync + v_bp)) , field };
		else
			y_out <= { 1'b0, (v_count - (v_sync + v_bp)) };
			field_out <= field;

	end

endmodule
