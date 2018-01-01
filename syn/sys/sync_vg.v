module sync_vg
#(
	parameter X_BITS=12, Y_BITS=12
)
(
	input wire clk,
	input wire reset,

	input wire [Y_BITS-1:0] v_total,
	input wire [Y_BITS-1:0] v_fp,
	input wire [Y_BITS-1:0] v_bp,
	input wire [Y_BITS-1:0] v_sync,
	input wire [X_BITS-1:0] h_total,
	input wire [X_BITS-1:0] h_fp,
	input wire [X_BITS-1:0] h_bp,
	input wire [X_BITS-1:0] h_sync,
	input wire [X_BITS-1:0] hv_offset,

	output reg vs_out,
	output reg hs_out,
	output reg hde_out,
	output reg vde_out,
	output reg [Y_BITS-1:0] v_count_out,
	output reg [X_BITS-1:0] h_count_out,
	output reg [X_BITS-1:0] x_out,
	output reg [Y_BITS-1:0] y_out
);

reg [X_BITS-1:0] h_count;
reg [Y_BITS-1:0] v_count;

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

always @(posedge clk)
	if (reset)
		{ vs_out, hs_out, hde_out, vde_out } <= 0;
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
		v_count_out <= v_count;

		/* X and Y coords for a backend pattern generator */
		x_out <= h_count - (h_sync + h_bp);
		y_out <= v_count - (v_sync + v_bp);
	end

endmodule
