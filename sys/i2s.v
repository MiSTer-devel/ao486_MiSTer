
module i2s
#(
	parameter CLK_RATE   = 50000000,
	parameter AUDIO_DW   = 16,
	parameter AUDIO_RATE = 96000
)
(
	input      reset,
	input      clk_sys,
	input      half_rate,

	output reg sclk,
	output reg lrclk,
	output reg sdata,

	input [AUDIO_DW-1:0]	left_chan,
	input [AUDIO_DW-1:0]	right_chan
);

localparam WHOLE_CYCLES          = (CLK_RATE) / (AUDIO_RATE*AUDIO_DW*4);
localparam ERROR_BASE            = 10000;
localparam [63:0] ERRORS_PER_BIT = ((CLK_RATE * ERROR_BASE) / (AUDIO_RATE*AUDIO_DW*4)) - (WHOLE_CYCLES * ERROR_BASE);

reg lpf_ce;
wire [AUDIO_DW-1:0] al, ar;

lpf_i2s lpf_l
(
   .CLK(clk_sys),
   .CE(lpf_ce),
   .IDATA(left_chan),
   .ODATA(al)
);

lpf_i2s lpf_r
(
   .CLK(clk_sys),
   .CE(lpf_ce),

   .IDATA(right_chan),
   .ODATA(ar)
);

always @(posedge clk_sys) begin
	reg [31:0] count_q;
	reg [31:0] error_q;
	reg  [7:0] bit_cnt;
	reg        skip = 0;

	reg [AUDIO_DW-1:0] left;
	reg [AUDIO_DW-1:0] right;

	reg msclk;
	reg ce;
	
	lpf_ce <= 0;

	if (reset) begin
		count_q   <= 0;
		error_q   <= 0;
		ce        <= 0;
		bit_cnt   <= 1;
		lrclk     <= 1;
		sclk      <= 1;
		msclk     <= 1;
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

		sclk <= msclk;
		if(!count_q) begin
			ce <= ~ce;
			if(~half_rate || ce) begin
				msclk <= ~msclk;
				if(msclk) begin
					skip <= ~skip;
					if(skip) lpf_ce <= 1;
					if(bit_cnt >= AUDIO_DW) begin
						bit_cnt <= 1;
						lrclk <= ~lrclk;
						if(lrclk) begin
							left  <= al;
							right <= ar;
						end
					end
					else begin
						bit_cnt <= bit_cnt + 1'd1;
					end
					sdata <= lrclk ? right[AUDIO_DW - bit_cnt] : left[AUDIO_DW - bit_cnt];
				end
			end
		end
	end
end

endmodule

module lpf_i2s
(
   input         CLK,
   input         CE,
   input  [15:0] IDATA,
   output reg [15:0] ODATA
);

reg [511:0] acc;
reg [20:0] sum;

always @(*) begin
	integer i;
	sum = 0;
	for (i = 0; i < 32; i = i+1) sum = sum + {{5{acc[(i*16)+15]}}, acc[i*16 +:16]};
end

always @(posedge CLK) begin
	if(CE) begin
		acc <= {acc[495:0], IDATA};
		ODATA <= sum[20:5];
	end
end

endmodule
