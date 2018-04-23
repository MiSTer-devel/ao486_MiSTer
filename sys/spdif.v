
module spdif
#(
    parameter CLK_RATE   = 50000000,
    parameter AUDIO_RATE = 48000
)
(
    input        clk_i,
    input        rst_i,
    input        half_rate,

    input [15:0] audio_r,
    input [15:0] audio_l,

    output       spdif_o
);

localparam WHOLE_CYCLES          = (CLK_RATE) / (AUDIO_RATE*128);
localparam ERROR_BASE            = 10000;
localparam [63:0] ERRORS_PER_BIT = ((CLK_RATE * ERROR_BASE) / (AUDIO_RATE*128)) - (WHOLE_CYCLES * ERROR_BASE);

reg         bit_clk_q;

// Clock pulse generator
always @ (posedge clk_i) begin
	reg [31:0]  count_q;
	reg [31:0]  error_q;
	reg ce;

	if (rst_i) begin
		count_q   <= 0;
		error_q   <= 0;
		bit_clk_q <= 1;
		ce        <= 0;
	end
	else
	begin
		if(count_q == WHOLE_CYCLES-1) begin
			if (error_q < (ERROR_BASE - ERRORS_PER_BIT)) begin
				error_q <= error_q + ERRORS_PER_BIT[31:0];
				count_q <= 0;
			end else begin
				error_q <= error_q + ERRORS_PER_BIT[31:0] - ERROR_BASE;
				count_q <= count_q + 1;
			end
		end else if(count_q == WHOLE_CYCLES) begin
			count_q <= 0;
		end else begin
			count_q <= count_q + 1;
		end

		bit_clk_q <= 0;
		if(!count_q) begin
			ce <= ~ce;
			if(~half_rate || ce) bit_clk_q <= 1;
		end
	end
end

spdif_out spdif_out
(
	.clock(clk_i),
	.ce(bit_clk_q),
	.reset(rst_i),

	.left_in(audio_l),
	.right_in(audio_r),
	.spdif(spdif_o)
);

endmodule


module spdif_out
(
	input        reset,
	input        clock,

	// SPDIF bit output enable
	// For 44.1KHz, 44100×32×2×2 = 5,644,800Hz
	// For 48KHz,   48000×32×2×2 = 6,144,000Hz
	input        ce,

	input [15:0] left_in,
	input [15:0] right_in,
	output reg   spdif
);
 
reg  [63:0] subFrame;
reg   [8:0] subFrame_cnt;
wire [15:0] sample = subFrame_cnt[0] ? left_in : right_in;

wire [7:0] preamble = (subFrame_cnt == 9'd383) ? 8'b10011100 : (subFrame_cnt[0] ? 8'b10010011 : 8'b10010110);

always @(negedge clock) begin
	reg [5:0] bit_cnt;

	if(reset) {bit_cnt, spdif, subFrame[63], subFrame_cnt} <= 0;
	else
	if(ce) begin
		bit_cnt <= bit_cnt + 1'b1;
		if (!bit_cnt) begin
			subFrame <= {preamble, 16'b1010101010101010,
			             1'b1, sample[0],  1'b1, sample[1],  1'b1, sample[2],  1'b1, sample[3],
			             1'b1, sample[4],  1'b1, sample[5],  1'b1, sample[6],  1'b1, sample[7],
			             1'b1, sample[8],  1'b1, sample[9],  1'b1, sample[10], 1'b1, sample[11],
			             1'b1, sample[12], 1'b1, sample[13], 1'b1, sample[14], 1'b1, sample[15],
			             1'b1, 1'b0,       1'b1, 1'b0,       1'b1, 1'b0,       1'b1, ^sample};
			             //      V                 U                 C                 P

			// 192*2-1
			if (subFrame_cnt == 9'd383) subFrame_cnt <= 0;
				else	subFrame_cnt <= subFrame_cnt + 1'b1;
		end
			else subFrame <= {subFrame[62:0], 1'b0};

		spdif <= spdif ^ subFrame[63];
	end
end

endmodule
