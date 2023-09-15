
module cdda #(parameter CLK_AUDIO_RATE)
(
	input             CLK,
	output reg        CDDA_REQ,
	input             CDDA_WR,
	input      [31:0] CDDA_DATA,
	input       [3:0] VOLUME_L,
	input       [3:0] VOLUME_R,

	input             CLK_AUDIO,
	output reg        AUDIO_CE,
	output reg [15:0] AUDIO_L,
	output reg [15:0] AUDIO_R
);

localparam SECTOR_SIZE  = 2352*8/32;
localparam BUFFER_WIDTH = $clog2(2 * SECTOR_SIZE);
localparam BUFFER_SIZE  = 2**BUFFER_WIDTH;

reg         clk_44100;
reg  [31:0] clk_44100_cnt;
wire [31:0] clk_44100_cnt_next = clk_44100_cnt + 88200;

always @(posedge CLK_AUDIO) begin
	reg old_clk;

	clk_44100_cnt <= clk_44100_cnt_next;
	if (clk_44100_cnt_next >= CLK_AUDIO_RATE) begin
		clk_44100 <= ~clk_44100;
		clk_44100_cnt <= clk_44100_cnt_next - CLK_AUDIO_RATE;
	end

	AUDIO_CE <= 0;
	old_clk <= clk_44100;
	if(~old_clk & clk_44100) begin
		AUDIO_CE <= 1;
		AUDIO_L <= $signed(audio_l) >>> ~VOLUME_L;
		AUDIO_R <= $signed(audio_r) >>> ~VOLUME_R;
	end
end

reg        wr_req;
reg [15:0] audio_l;
reg [15:0] audio_r;

reg [BUFFER_WIDTH-1:0] read_addr, write_addr;
reg   [BUFFER_WIDTH:0] filled_cnt = 0;
initial filled_cnt = 0;

always @(posedge CLK) begin
	reg old_clk;
	reg clk_d1, clk_d2;
	reg old_wr = 0, rd_req = 0;
	
	rd_req <= 0;
	wr_req <= 0;
	if(wr_req) write_addr <= write_addr + 1'b1;

	old_wr <= CDDA_WR;
	if(~old_wr && CDDA_WR && (write_addr+1'd1) != read_addr) wr_req <= 1;

	clk_d1 <= clk_44100;
	clk_d2 <= clk_d1;
	if(clk_d2 == clk_d1) begin
		old_clk <= clk_d2;
		if(old_clk & ~clk_d2) begin
			if(read_addr == write_addr) begin
				audio_l <= 0;
				audio_r <= 0;
			end
			else begin
				rd_req <= 1;
				audio_l <= buffer_q[15:0];
				audio_r <= buffer_q[31:16];
				read_addr <= read_addr + 1'd1;
			end
		end
	end

	filled_cnt <= filled_cnt + wr_req - rd_req;
	CDDA_REQ <= (BUFFER_SIZE[BUFFER_WIDTH:0] - filled_cnt >= SECTOR_SIZE[BUFFER_WIDTH:0]);
end

reg [31:0] buffer[BUFFER_SIZE];
reg [31:0] buffer_q;
always @(posedge CLK) begin
	buffer_q <= buffer[read_addr];
	if (wr_req) buffer[write_addr] <= CDDA_DATA;
end

endmodule
