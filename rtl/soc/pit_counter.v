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

module pit_counter(
    input             clk,
    input             rst_n,
    
    input             clock,
    input             gate,
    output reg        out,
    
    input       [7:0] data_in,
    input             set_control_mode,
    input             latch_count,
    input             latch_status,
    input             write,
    input             read,
    
    output      [7:0] data_out
);

//------------------------------------------------------------------------------

reg [2:0] mode;
always @(posedge clk) begin
    if(rst_n == 1'b0)         mode <= 3'd2;
    else if(set_control_mode) mode <= data_in[3:1];
end

reg bcd;
always @(posedge clk) begin
    if(rst_n == 1'b0)         bcd <= 1'd0;
    else if(set_control_mode) bcd <= data_in[0];
end

reg [1:0] rw_mode;
always @(posedge clk) begin
    if(rst_n == 1'b0)         rw_mode <= 2'd1;
    else if(set_control_mode) rw_mode <= data_in[5:4];
end

//------------------------------------------------------------------------------

reg [7:0] counter_l;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               counter_l <= 8'd0;
    else if(set_control_mode)                       counter_l <= 8'd0;
    else if(write && rw_mode == 2'd3 && ~msb_write) counter_l <= data_in;
    else if(write && rw_mode == 2'd1)               counter_l <= data_in;
end

reg [7:0] counter_m;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               counter_m <= 8'd0;
    else if(set_control_mode)                       counter_m <= 8'd0;
    else if(write && rw_mode == 2'd3 && msb_write)  counter_m <= data_in;
    else if(write && rw_mode == 2'd2)               counter_m <= data_in;
end

reg [7:0] output_l;
always @(posedge clk) begin
    if(rst_n == 1'b0)                       output_l <= 8'd0;
    else if(latch_count && ~output_latched) output_l <= counter[7:0];
    else if(~output_latched)                output_l <= counter[7:0];
end

reg [7:0] output_m;
always @(posedge clk) begin
    if(rst_n == 1'b0)                       output_m <= 8'd0;
    else if(latch_count && ~output_latched) output_m <= counter[15:8];
    else if(~output_latched)                output_m <= counter[15:8];
end

reg output_latched;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               output_latched <= 1'b0;
    else if(set_control_mode)                       output_latched <= 1'b0;
    else if(latch_count)                            output_latched <= 1'b1;
    else if(read && (rw_mode != 2'd3 || msb_read))  output_latched <= 1'b0;
end

reg null_counter;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                null_counter <= 1'b0;
    else if(set_control_mode)                        null_counter <= 1'b1;
    else if(write && (rw_mode != 2'd3 || msb_write)) null_counter <= 1'b1;
    else if(load)                                    null_counter <= 1'b0;
end

reg msb_write;
always @(posedge clk) begin
    if(rst_n == 1'b0)                 msb_write <= 1'b0;
    else if(set_control_mode)         msb_write <= 1'b0;
    else if(write && rw_mode == 2'd3) msb_write <= ~msb_write;
end

reg msb_read;
always @(posedge clk) begin
    if(rst_n == 1'b0)                msb_read <= 1'b0;
    else if(set_control_mode)        msb_read <= 1'b0;
    else if(read && rw_mode == 2'd3) msb_read <= ~msb_read;
end

reg [7:0] status;
always @(posedge clk) begin
    if(rst_n == 1'b0)                        status <= 8'd0;
    else if(latch_status && ~status_latched) status <= { out, null_counter, rw_mode, mode, bcd };
end

reg status_latched;
always @(posedge clk) begin
    if(rst_n == 1'b0)           status_latched <= 1'b0;
    else if(set_control_mode)   status_latched <= 1'b0;
    else if(latch_status)       status_latched <= 1'b1;
    else if(read)               status_latched <= 1'b0;
end

assign data_out =
    (status_latched)               ? status   :
    (rw_mode == 2'd3 && ~msb_read) ? output_l :
    (rw_mode == 2'd3 &&  msb_read) ? output_m :
    (rw_mode == 2'd1)              ? output_l :
                                     output_m;

//------------------------------------------------------------------------------

reg clock_last;
always @(posedge clk) clock_last <= clock;

reg clock_pulse;
always @(posedge clk) clock_pulse <= clock_last & ~clock;

reg gate_last;
always @(posedge clk) gate_last <= gate;

reg gate_sampled;
always @(posedge clk) begin
    if(rst_n == 1'b0)             gate_sampled <= 1'b0;
    else if(~clock_last && clock) gate_sampled <= gate;
end

reg trigger;
always @(posedge clk) begin
    if(rst_n == 1'b0)             trigger <= 1'b0;
    else if(~gate_last && gate)   trigger <= 1'b1;
    else if(~clock_last && clock) trigger <= 1'b0;
end

reg trigger_sampled;
always @(posedge clk) begin
    if(rst_n == 1'b0)            trigger_sampled <= 1'b0;
    else if(~clock_last & clock) trigger_sampled <= trigger;
end

//------------------------------------------------------------------------------

always @(posedge clk) begin
    if(rst_n == 1'b0)                                         out <= 1'b1;

    else if(set_control_mode && data_in[3:1] == 3'd0)         out <= 1'b0;
    else if(set_control_mode && data_in[3:1] == 3'd1)         out <= 1'b1;
    else if(set_control_mode && data_in[2:1] == 2'd2)         out <= 1'b1;
    else if(set_control_mode && data_in[2:1] == 2'd3)         out <= 1'b1;
    else if(set_control_mode && data_in[3:1] == 3'd4)         out <= 1'b1;
    else if(set_control_mode && data_in[3:1] == 3'd5)         out <= 1'b1;

    else if(mode      == 3'd0 && load)                        out <= 1'b0;
    else if(mode      == 3'd0 && counter == 16'd1 && enable)  out <= 1'b1;

    else if(mode      == 3'd1 && load)                        out <= 1'b0;
    else if(mode      == 3'd1 && counter == 16'd1 && enable)  out <= 1'b1;

    else if(mode[1:0] == 2'd2 && ~gate)                       out <= 1'b1;
    else if(mode[1:0] == 2'd2 && load)                        out <= 1'b1;
    else if(mode[1:0] == 2'd2 && counter == 16'd2 && enable)  out <= 1'b0;

    else if(mode[1:0] == 2'd3 && ~gate)                       out <= 1'b1;
    else if(mode[1:0] == 2'd3 && load)                        out <= ~out;

    else if(mode      == 3'd4 && load)                        out <= 1'b1;
    else if(mode      == 3'd4 && counter == 16'd2 && enable)  out <= 1'b0;
    else if(mode      == 3'd4 && counter == 16'd1 && enable)  out <= 1'b1;

    else if(mode      == 3'd5 && counter == 16'd2 && enable)  out <= 1'b0;
    else if(mode      == 3'd5 && counter == 16'd1 && enable)  out <= 1'b1;
end

//------------------------------------------------------------------------------

reg written;
always @(posedge clk) begin
    if(rst_n == 1'b0)                              written <= 1'b0;
    else if(set_control_mode)                      written <= 1'b0;
    else if(write && rw_mode != 2'd3)              written <= 1'b1;
    else if(write && rw_mode == 2'd3 && msb_write) written <= 1'b1;
    else if(load)                                  written <= 1'b0;
end

reg control_set;
always @(posedge clk) begin
    if(rst_n == 1'b0)         control_set <= 1'b0;
    else if(set_control_mode) control_set <= 1'b1;
    else if(load)             control_set <= 1'b0;
end

reg loaded;
always @(posedge clk) begin
    if(rst_n == 1'b0)         loaded <= 1'b0;
    else if(set_control_mode) loaded <= 1'b0;
    else if(load)             loaded <= 1'b1;
end

wire load = clock_pulse && (
    (mode      == 3'd0 &&   written) ||
    (mode      == 3'd1 &&  (written && control_set) && trigger_sampled) ||
    (mode[1:0] == 2'd2 && ((written && control_set) || trigger_sampled || (loaded && gate_sampled && counter == 16'd1))) ||
    (mode[1:0] == 2'd3 && ((written && control_set) || trigger_sampled || (loaded && gate_sampled && counter == ((counter_l[0] & out) ? 16'd0 : 16'd2)))) ||
    (mode      == 3'd4 &&   written) ||
    (mode      == 3'd5 && ((written && control_set) || loaded) && trigger_sampled)
);

wire enable = ~load && loaded && clock_pulse && ( 
    (mode      == 3'd0 && gate_sampled) ||
    (mode      == 3'd1) ||
    (mode[1:0] == 2'd2 && gate_sampled) ||
	 (mode[1:0] == 2'd3 && gate_sampled) ||
    (mode      == 3'd4 && gate_sampled) ||
    (mode      == 3'd5)
);

//------------------------------------------------------------------------------

wire [15:0] counter_minus_1 =
    (bcd && !counter[15:0]) ? 16'h9999 :
    (bcd && !counter[11:0]) ? { counter[15:12] - 1'd1, 12'h999 } :
    (bcd && !counter[7:0])  ? { counter[15:8]  - 1'd1,   8'h99 } :
    (bcd && !counter[3:0])  ? { counter[15:4]  - 1'd1,    4'h9 } :
                                counter - 1'd1;

reg [15:0] counter;
always @(posedge clk) begin
    if(rst_n == 1'b0) counter <= 16'd0;
    else if(load)     counter <= {counter_m, counter_l[7:1], counter_l[0] & (mode[1:0] != 2'd3)};
    else if(enable)   counter <= counter_minus_1 - (mode[1:0] == 2'd3);
end

//------------------------------------------------------------------------------

endmodule
