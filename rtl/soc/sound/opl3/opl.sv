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

import opl3_pkg::*;

module opl
(
    input               clk,
    input               clk_opl,
    input               rst_n,

    //sb slave 220h-22Fh
    input       [3:0]   sb_address,
    input               sb_read,
    output      [7:0]   sb_readdata,
    input               sb_write,
    input       [7:0]   sb_writedata,

    //fm music io slave 388h-38Bh
    input       [1:0]   fm_address,
    input               fm_read,
    output      [7:0]   fm_readdata,
    input               fm_write,
    input       [7:0]   fm_writedata,
	 input               fm_mode,

    //sample
    output signed [15:0] sample_l,
    output signed [15:0] sample_r,

    //mgmt slave
    /*
    256.[12:0]:  cycles in 80us
    */
    input       [8:0]   mgmt_address,
    input               mgmt_write,
    input       [31:0]  mgmt_writedata
);


//------------------------------------------------------------------------------

wire [7:0] io_readdata = { timer1_overflow | timer2_overflow, timer1_overflow, timer2_overflow, fm_mode ? 5'd0 : 5'd6 };

assign sb_readdata = (sb_address == 8) ? io_readdata : 8'hFF;
assign fm_readdata =       !fm_address ? io_readdata : 8'hFF;

//------------------------------------------------------------------------------

reg [8:0] index;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                  index <= 0;
    else if(      sb_address[2:0] == 0 && sb_write) index <= {1'b0, sb_writedata};
    else if(           fm_address == 0 && fm_write) index <= {1'b0, fm_writedata};
    else if(fm_mode && sb_address == 2 && sb_write) index <= {1'b1, sb_writedata};
    else if(fm_mode && fm_address == 2 && fm_write) index <= {1'b1, fm_writedata};
end

wire       io_write     = (((sb_address[2:0] == 1 || (fm_mode && sb_address == 3)) && sb_write) || ((fm_address == 1 || (fm_mode && fm_address == 3)) && fm_write));
wire [7:0] io_writedata = (sb_write)? sb_writedata : fm_writedata;

//------------------------------------------------------------------------------ timer 1

reg [7:0] timer1_preset;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                  timer1_preset <= 0;
    else if(io_write && index == 2) timer1_preset <= io_writedata;
end

reg timer1_mask;
reg timer1_active;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                      {timer1_mask, timer1_active} <= 0;
    else if(io_write && index == 4 && ~io_writedata[7]) {timer1_mask, timer1_active} <= {io_writedata[6], io_writedata[0]};
end

wire timer1_pulse;
timer timer1( clk, period_80us, timer1_preset, timer1_active, timer1_pulse );

reg timer1_overflow;
always @(posedge clk or negedge rst_n) begin
	if(rst_n == 0)                                   timer1_overflow <= 0;
	else begin
		if(io_write && index == 4 && io_writedata[7]) timer1_overflow <= 0;
		if(~timer1_mask && timer1_pulse)              timer1_overflow <= 1;
	end
end


//------------------------------------------------------------------------------ timer 2

reg [7:0] timer2_preset;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                  timer2_preset <= 0;
    else if(io_write && index == 3) timer2_preset <= io_writedata;
end

reg timer2_mask;
reg timer2_active;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                      {timer2_mask, timer2_active} <= 0;
    else if(io_write && index == 4 && ~io_writedata[7]) {timer2_mask, timer2_active} <= {io_writedata[5], io_writedata[1]};
end

wire timer2_pulse;
timer timer2( clk, {period_80us, 2'b00}, timer2_preset, timer2_active, timer2_pulse );

reg timer2_overflow;
always @(posedge clk or negedge rst_n) begin
	if(rst_n == 0)                                       timer2_overflow <= 0;
	else begin
		if(io_write && index == 4 && io_writedata[7])     timer2_overflow <= 0;
		if(~timer2_mask && timer2_pulse)                  timer2_overflow <= 1;
	end
end


//------------------------------------------------------------------------------ mgmt

reg [12:0] period_80us;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                               period_80us <= 2400;
    else if(mgmt_write && mgmt_address == 256)   period_80us <= mgmt_writedata[12:0];
end

//------------------------------------------------------------------------------

reg [7:0] opl_reg[512];
always_ff @(posedge clk or negedge rst_n) begin
   if(rst_n == 0)    opl_reg <= '{512{8'd0}};
	else if(io_write) opl_reg[index] <= io_writedata;
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
