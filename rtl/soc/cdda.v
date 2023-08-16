
module cdda #(parameter CLK_RATE)
(
	input             CLK,
	input             nRESET,

	output reg        WRITE_REQ,
	input             WRITE,
	input      [15:0] DIN,
	
	output reg        AUDIO_CE,
	output reg [15:0] AUDIO_L,
	output reg [15:0] AUDIO_R

);

localparam SECTOR_SIZE  = 2352*8/32;
localparam BUFFER_WIDTH = $clog2(2 * SECTOR_SIZE);
localparam BUFFER_SIZE  = 2**BUFFER_WIDTH;

reg         cen_44100;
reg  [31:0] cen_44100_cnt;
wire [31:0] cen_44100_cnt_next = cen_44100_cnt + 44100;

always @(posedge CLK) begin
	cen_44100 <= 0;
	cen_44100_cnt <= cen_44100_cnt_next;
	if (cen_44100_cnt_next >= CLK_RATE) begin
		cen_44100 <= 1;
		cen_44100_cnt <= cen_44100_cnt_next - CLK_RATE;
	end
	AUDIO_CE <= cen_44100;
end

reg OLD_WRITE, LRCK, WR_REQ, RD_REQ;

reg [15:0] DATA;

reg [BUFFER_WIDTH-1:0] READ_ADDR, WRITE_ADDR;
reg [BUFFER_WIDTH:0] AVAILABLE_COUNT;

always @(posedge CLK) begin
	if (~nRESET) begin
		OLD_WRITE <= 0;
		LRCK      <= 0;
		READ_ADDR <= 0;
		WRITE_ADDR <= 0;
		AVAILABLE_COUNT <= BUFFER_SIZE[BUFFER_WIDTH:0];
		WR_REQ <= 0;
		RD_REQ <= 0;
		WRITE_REQ <= 0;
	end else begin

		RD_REQ <= 0;
		WR_REQ <= 0;
		if(WR_REQ) WRITE_ADDR <= WRITE_ADDR + 1'b1;

		OLD_WRITE <= WRITE;
		if (~OLD_WRITE & WRITE) begin
			LRCK <= ~LRCK;
			if (~LRCK) DATA <= DIN;
			else if((WRITE_ADDR+1'd1) != READ_ADDR) WR_REQ <= 1;
		end

		if (cen_44100) begin
			if (READ_ADDR == WRITE_ADDR) begin
				AUDIO_L <= 0;
				AUDIO_R <= 0;
			end
			else begin
				RD_REQ <= 1;
				AUDIO_L <= BUFFER_Q[15:0];
				AUDIO_R <= BUFFER_Q[31:16];
				READ_ADDR <= READ_ADDR + 1'd1;
			end
		end

		AVAILABLE_COUNT <= AVAILABLE_COUNT - WR_REQ + RD_REQ;
		WRITE_REQ <= (AVAILABLE_COUNT >= SECTOR_SIZE);
	end
end

reg [31:0] BUFFER[BUFFER_SIZE];
reg [31:0] BUFFER_Q;
always @(posedge CLK) begin
	BUFFER_Q <= BUFFER[READ_ADDR];
	if (WR_REQ) BUFFER[WRITE_ADDR] <= {DIN,DATA};
end

endmodule
