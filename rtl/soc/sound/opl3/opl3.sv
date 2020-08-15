/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

module opl3
#(
	parameter            OPLCLK = 64000000 // opl_clk in Hz
)
(
	input                clk,
	input                clk_opl,
	input                rst_n,
	output               irq_n,

	input                ce_1us, // from clk

	input          [1:0] addr,
	output         [7:0] dout,
	input          [7:0] din,
	input                we,
	input                rd,

	output signed [15:0] sample_l,
	output signed [15:0] sample_r
);

//------------------------------------------------------------------------------

assign dout  = { timer1_overflow | timer2_overflow, timer1_overflow, timer2_overflow, 5'd0 };
assign irq_n = ~(timer1_overflow | timer2_overflow);

//------------------------------------------------------------------------------

reg old_write;
always @(posedge clk) old_write <= we;

wire write = (~old_write & we);

reg [8:0] index;
always @(posedge clk) begin
    if(rst_n == 0) index <= 0;
    else if(~addr[0] && write) index <= {addr[1], din};
end

wire       io_write     = (addr[0] && write);
wire [7:0] io_writedata = din;

//------------------------------------------------------------------------------ timer 1

reg [7:0] timer1_preset;
always @(posedge clk) begin
    if(rst_n == 0)                  timer1_preset <= 0;
    else if(io_write && index == 2) timer1_preset <= io_writedata;
end

reg timer1_mask;
reg timer1_active;
always @(posedge clk) begin
    if(rst_n == 0)                                      {timer1_mask, timer1_active} <= 0;
    else if(io_write && index == 4 && ~io_writedata[7]) {timer1_mask, timer1_active} <= {io_writedata[6], io_writedata[0]};
end

wire timer1_pulse;
timer #(79) timer1( clk, ce_1us, timer1_preset, timer1_active, timer1_pulse );

reg timer1_overflow;
always @(posedge clk) begin
	if(rst_n == 0)                                          timer1_overflow <= 0;
	else begin
		if(io_write && index == 4 /*&& io_writedata[7]*/)    timer1_overflow <= 0;
		if((timer1_pulse || force_overflow) && ~timer1_mask) timer1_overflow <= 1;
	end
end


//------------------------------------------------------------------------------ timer 2

reg [7:0] timer2_preset;
always @(posedge clk) begin
    if(rst_n == 0)                  timer2_preset <= 0;
    else if(io_write && index == 3) timer2_preset <= io_writedata;
end

reg timer2_mask;
reg timer2_active;
always @(posedge clk) begin
    if(rst_n == 0)                                      {timer2_mask, timer2_active} <= 0;
    else if(io_write && index == 4 && ~io_writedata[7]) {timer2_mask, timer2_active} <= {io_writedata[5], io_writedata[1]};
end

wire timer2_pulse;
timer #(319) timer2( clk, ce_1us, timer2_preset, timer2_active, timer2_pulse );

reg timer2_overflow;
always @(posedge clk) begin
	if(rst_n == 0)                                          timer2_overflow <= 0;
	else begin
		if(io_write && index == 4 /*&& io_writedata[7]*/)    timer2_overflow <= 0;
		if((timer2_pulse || force_overflow) && ~timer2_mask) timer2_overflow <= 1;
	end
end

reg force_overflow;
always @(posedge clk) begin
	reg [16:0] cnt;
	reg  [5:0] rdcnt;
	reg old_rd;

	if(ce_1us && ~&cnt) cnt <= cnt + 1'd1;

	force_overflow <= 0;

	old_rd <= rd;
	if(~old_rd && rd) begin
		cnt <= 0;
		if(~&rdcnt) begin
			rdcnt <= rdcnt + 1'd1;
			if(rdcnt == 20) force_overflow <= 1;
		end
	end
	else if((cnt >= 100000) || (io_write && index == 4)) begin
		rdcnt <= 0;
		cnt <= 0;
	end
end

//------------------------------------------------------------------------------

opl3sw #(OPLCLK) opl3
(
    .reset(~rst_n),

    .cpu_clk(clk),
    .addr(addr),
    .din(din),
    .wr(write),

    .clk(clk_opl),
    .left(sample_l),
    .right(sample_r)
);

endmodule

module timer #(parameter RES)
(
	input         clk,
	input         ce_1us,
	input   [7:0] preset,
	input         active,
	output reg    overflow_pulse
);

always @(posedge clk) begin
	reg [7:0] counter;
	reg [8:0] sub_counter;

	overflow_pulse <= 0;

	if(active) begin
		if(ce_1us) begin
			sub_counter <= sub_counter - 1'd1;
			if(!sub_counter) begin
				sub_counter <= RES[8:0];
				counter     <= counter + 1'd1;
				if(&counter) begin
					overflow_pulse <= 1;
					counter <= preset;
				end
			end
		end
	end
	else begin
		counter <= preset;
		sub_counter <= RES[8:0];
	end
end
    
endmodule
