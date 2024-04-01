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

module opl
    import opl3_pkg::*;
(
    input                clk,
    input                clk_opl,
    input                rst_n,

	input       [3:0]    address,
	input                read,
	output reg  [7:0]    readdata,
	input                write,
	input       [7:0]    writedata,
	input                fm_mode,

    //sample
    output signed [15:0] sample_l,
    output signed [15:0] sample_r
);
localparam logic [14:0] period_80us = 2400;

//------------------------------------------------------------------------------

wire [7:0] io_readdata = { timer1_overflow | timer2_overflow, timer1_overflow, timer2_overflow, fm_mode ? 5'd0 : 5'd6 };

assign readdata = (address == 8) ? io_readdata : 8'hFF;

//------------------------------------------------------------------------------

reg [$clog2(NUM_REGISTERS_PER_BANK)-1] opl3_address;
reg opl3_bank;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0) begin
        opl3_bank <= 0;
        opl3_address <= 0;
    end
    else if (address[2:0] == 0 && write) begin
        opl3_bank <= 0;
        opl3_address <= writedata;
    end
    else if (fm_mode && address == 2 && write) begin
        opl3_bank <= 1;
        opl3_address <= writedata;
    end
end

wire io_write = (address[2:0] == 1 || (fm_mode && address == 3)) && write;
//------------------------------------------------------------------------------ timer 1

reg [7:0] timer1_preset;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                           timer1_preset <= 0;
    else if(io_write && opl3_bank == 0 && opl3_address == 2) timer1_preset <= writedata;
end

reg timer1_mask;
reg timer1_active;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                                            {timer1_mask, timer1_active} <= 0;
    else if(io_write && opl3_bank == 0 && opl3_address == 4 && ~writedata[7]) {timer1_mask, timer1_active} <= {writedata[6], writedata[0]};
end

wire timer1_pulse;
timer timer1( clk, period_80us, timer1_preset, timer1_active, timer1_pulse );

reg timer1_overflow;
always @(posedge clk or negedge rst_n) begin
	if(rst_n == 0)                                                          timer1_overflow <= 0;
	else begin
		if(io_write && opl3_bank == 0 && opl3_address == 4 && writedata[7]) timer1_overflow <= 0;
		if(~timer1_mask && timer1_pulse)                                    timer1_overflow <= 1;
	end
end


//------------------------------------------------------------------------------ timer 2

reg [7:0] timer2_preset;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                           timer2_preset <= 0;
    else if(io_write && opl3_bank == 0 && opl3_address == 3) timer2_preset <= writedata;
end

reg timer2_mask;
reg timer2_active;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                                            {timer2_mask, timer2_active} <= 0;
    else if(io_write && opl3_bank == 0 && opl3_address == 4 && ~writedata[7]) {timer2_mask, timer2_active} <= {writedata[5], writedata[1]};
end

wire timer2_pulse;
timer timer2( clk, {period_80us, 2'b00}, timer2_preset, timer2_active, timer2_pulse );

reg timer2_overflow;
always @(posedge clk or negedge rst_n) begin
	if(rst_n == 0)                                                          timer2_overflow <= 0;
	else begin
		if(io_write && opl3_bank == 0 && opl3_address == 4 && writedata[7]) timer2_overflow <= 0;
		if(~timer2_mask && timer2_pulse)                                    timer2_overflow <= 1;
	end
end

reg [7:0] opl_reg[NUM_BANKS][NUM_REGISTERS_PER_BANK];
always_ff @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)    opl_reg                          <= '{default: 0};
    else if(io_write) opl_reg[opl3_bank][opl3_address] <= writedata;
end

opl3 opl3
(
	.*,
   .clk(clk_opl)
);

endmodule

module timer
(
	input         clk,
	input  [14:0] resolution,
	input   [7:0] init,
	input         active,
	output reg    overflow_pulse
);

always @(posedge clk) begin
	reg  [7:0] counter     = 0;
	reg [14:0] sub_counter = 0;
	reg        old_act;

	old_act <= active;
	overflow_pulse <= 0;

	if(~old_act && active) begin
		counter <= init;
		sub_counter <= resolution;
	end
	else if(active) begin
		sub_counter <= sub_counter - 1'd1;
		if(!sub_counter) begin
			sub_counter <= resolution;
			counter     <= counter + 1'd1;
			if(&counter) begin
				overflow_pulse <= 1;
				counter <= init;
			end
		end
	end
end

endmodule
