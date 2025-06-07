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
    input             set_control_mode, // 43h Reprogram Counter
    input             latch_count,      // 43h Counter Latch Command or Read-Back Counter Latch Command
    input             latch_status,     // 43h Read-Back Status Latch Command
    input             write,            // 40h, 41h, 42h Write Counter
    input             read,             // 40h, 41h, 42h Read Counter
    
    output      [7:0] data_out
);

//-------------------------------------------------------------------------------------------------

// Edge detection

reg clock_last;
always @(posedge clk) clock_last <= clock;

reg gate_last;
always @(posedge clk) gate_last <= gate;

reg write_last;
always @(posedge clk) write_last <= write;

reg read_last;
always @(posedge clk) read_last <= read;

//-------------------------------------------------------------------------------------------------

// Reprogram the counter

// BCD 0: Binary counter 16-bits
// BCD 1: Binary coded decimal (BCD) counter (4 decades)
reg bcd;
always @(posedge clk) begin
    if(!rst_n)                bcd <= 1'd0;
    else if(set_control_mode) bcd <= data_in[0];
end

// Mode 0: Interrupt on terminal count
// Mode 1: Hardware retriggerable one-shot
// Mode 2: Rate generator
// Mode 3: Square wave mode
// Mode 4: Software triggered strobe
// Mode 5: Hardware triggered strobe (retriggerable)
reg [2:0] mode;
always @(posedge clk) begin
    if(!rst_n)                mode <= 3'd2;
    else if(set_control_mode) mode <= data_in[3:1];
end

// Read/Write mode 1: Read/Write least significant byte only (LSB)
// Read/Write mode 2: Read/Write most significant byte only (MSB)
// Read/Write mode 3: Read/Write least significant byte first, then most significant byte (LSB/MSB)
reg [1:0] rw_mode;
always @(posedge clk) begin
    if(!rst_n)                rw_mode <= 2'd1;
    else if(set_control_mode) rw_mode <= data_in[5:4];
end

//-------------------------------------------------------------------------------------------------

// Write sequence flip-flop for read/write mode 3 (LSB/MSB)
reg write_seq_ff;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)                   write_seq_ff <= 1'b0;
    else if(write_last && ~write && rw_mode == 2'd3) write_seq_ff <= ~write_seq_ff;
end

// Read sequence flip-flop for read/write mode 3 (LSB/MSB)
reg read_seq_ff;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)                                    read_seq_ff <= 1'b0;
    else if(read_last && ~read && rw_mode == 2'd3 && ~status_latched) read_seq_ff <= ~read_seq_ff;
end

//-------------------------------------------------------------------------------------------------

// Note:
// The Samsung KS82C54 datasheet states that the count registers reset when
// a new mode is written. This is not mentioned in the Intel 8254 datasheet.

// Count Register LSB (CR_L)
reg [7:0] counter_l;
always @(posedge clk) begin
    if(!rst_n)                                         counter_l <= 8'd0;
    else if(set_control_mode)                          counter_l <= 8'd0; // Samsung KS82C54
    else if(write && rw_mode != 2'd2 && ~write_seq_ff) counter_l <= data_in; // write_lsb
end

// Count Register MSB (CR_M)
reg [7:0] counter_m;
always @(posedge clk) begin
    if(!rst_n)                                          counter_m <= 8'd0;
    else if(set_control_mode)                           counter_m <= 8'd0; // Samsung KS82C54
    else if(write && (rw_mode == 2'd2 || write_seq_ff)) counter_m <= data_in; // write_msb
end

// Output Latch LSB (OL_L)
reg [7:0] output_l;
always @(posedge clk) begin
    if(!rst_n)               output_l <= 8'd0;
    else if(~output_latched) output_l <= counter[7:0];
end

// Output Latch MSB (OL_M)
reg [7:0] output_m;
always @(posedge clk) begin
    if(!rst_n)               output_m <= 8'd0;
    else if(~output_latched) output_m <= counter[15:8];
end

// Output Latched state
reg output_latched;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)                                  output_latched <= 1'b0;
    else if(latch_count)                                            output_latched <= 1'b1;
    else if(read_last && ~read && (rw_mode != 2'd3 || read_seq_ff)) output_latched <= 1'b0; // read_sequence_completed
end

// Null Count flag
reg null_count;
always @(posedge clk) begin
    if(!rst_n)                                                         null_count <= 1'b0;
    else if(set_control_mode)                                          null_count <= 1'b1;
    else if(write_last && ~write && (rw_mode != 2'd3 || write_seq_ff)) null_count <= 1'b1; // write_sequence_completed
    else if(load)                                                      null_count <= 1'b0;
end

// Latched status information
reg [7:0] status;
always @(posedge clk) begin
    if(!rst_n)                               status <= 8'd0;
    else if(latch_status && ~status_latched) status <= { out, null_count, rw_mode, mode, bcd };
end

// Status Latched state
reg status_latched;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) status_latched <= 1'b0;
    else if(latch_status)          status_latched <= 1'b1;
    else if(read_last && ~read)    status_latched <= 1'b0; // read_done
end

// Data Out
assign data_out =
    (status_latched)                 ? status   :
    (rw_mode == 2'd2 || read_seq_ff) ? output_m : output_l;

//-------------------------------------------------------------------------------------------------

// In Modes 0, 2, 3 and 4 the counter is (re)loaded when a write sequence is completed.

// Write sequence completed flip-flop
reg written;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)                                     written <= 1'b0;
    else if(write_last && ~write && (rw_mode != 2'd3 || write_seq_ff)) written <= 1'b1; // write_sequence_completed
    else if(load)                                                      written <= 1'b0;
end

// Written is sampled on the rising edge of clock
reg written_sampled;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) written_sampled <= 1'b0;
    else if(~clock_last && clock)  written_sampled <= written;
end

//-------------------------------------------------------------------------------------------------

// In Modes 1, 2, 3 and 5 the gate input is rising-edge sensitive (trigger).

// Gate rising-edge sensitive flip-flop
reg trigger;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) trigger <= 1'b0;
    else if(~gate_last && gate)    trigger <= 1'b1; // trigger = rising edge of gate
    else if(~clock_last && clock)  trigger <= 1'b0; // reset flip-flop after it has been sampled
end

// Trigger is sampled on the rising edge of clock
reg trigger_sampled;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) trigger_sampled <= 1'b0;
    else if(~clock_last && clock)  trigger_sampled <= trigger;
end

//-------------------------------------------------------------------------------------------------

// In Modes 0, 2, 3 and 4 the gate input is level sensitive.

// The gate logic level is sampled on the rising edge of clock
reg gate_level_sampled;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) gate_level_sampled <= 1'b0;
    else if(~clock_last && clock)  gate_level_sampled <= gate;
end

//-------------------------------------------------------------------------------------------------

always @(posedge clk) begin
    if (!rst_n)                                                 out <= 1'b1;
    else if (set_control_mode)                                  out <= (data_in[3:1] > 3'd0);
    else begin
        case(mode)
            3'd0: begin
                if      (write_last && ~write && ~write_seq_ff) out <= 1'b0;
                else if (counter == 16'd1 && enable)            out <= 1'b1;
            end
            3'd1: begin
                if      (load)                                  out <= 1'b0;
                else if (counter == 16'd1 && enable)            out <= 1'b1;
            end
            3'd2, 3'd6: begin
                if      (load || (gate_last && ~gate))          out <= 1'b1;
                else if (counter == 16'd2 && enable)            out <= 1'b0;
            end
            3'd3, 3'd7: begin
                if      (gate_last && ~gate)                    out <= 1'b1;
                else if (load && loaded && ~trigger_sampled)    out <= ~out;
            end
            3'd4, 3'd5: begin
                if      (counter == 16'd1 && enable)            out <= 1'b0;
                else if (counter == 16'd0 && enable)            out <= 1'b1;
            end
            default: ;
        endcase
    end
end

//-------------------------------------------------------------------------------------------------

/*

    Load events per mode:

    |        |           |           |  Terminal  |
    |  Mode  |  Written  |  Trigger  |   Count    |
    |--------|-----------|-----------|------------|
    |  0     |     v     |           |            |
    |  1     |           |     v     |            |
    |  2, 6  |  ~loaded  |     v     |     v      |
    |  3, 7  |  ~loaded  |     v     |     v      |
    |  4     |     v     |           |            |
    |  5     |           |     v     |            |

*/

// In modes 0, 2, 3 and 4, when a count is written it will be (re)loaded on the next clock pulse
wire load_written = (clock_last && ~clock) && (
    mode[1:0] != 2'b01 && written_sampled && (~mode[1] || ~loaded)
);

// In modes 1, 2, 3 and 5 a trigger (re)loads the counter on the next clock pulse
wire load_trigger = (clock_last && ~clock) && (
    mode[1:0] != 2'b00 && trigger_sampled && (written || loaded)
);

// In modes 2 and 3, reaching the terminal count reloads the counter on the falling edge of clock
// Mode 2 periodic reload after terminal count value: 16'd1
// Mode 3 periodic reload after terminal count value: (counter_l[0] && out) ? 16'd0 : 16'd2
wire load_terminal = (clock_last && ~clock) && loaded && gate_level_sampled && (
    mode[1] && counter == { 14'b0, ~(counter_l[0] && out) && mode[0], ~mode[0] }
);

// The counter is (re)loaded on the falling edge of clock (according to the Intel 8254 datasheet)
wire load = load_written || load_trigger || load_terminal;

reg loaded;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) loaded <= 1'b0;
    else if(load)                  loaded <= 1'b1;
end

/*

    Gate input level sensitivity per mode:

    |        |  Gate Level  |
    |  Mode  |  Sensitive   |
    |--------|--------------|
    |  0     |      v (*)   |
    |  1     |              |
    |  2, 6  |      v       |
    |  3, 7  |      v       |
    |  4     |      v       |
    |  5     |              |

    (*) For mode 0 in LSB/MSB read/wite mode,
    writing the first byte disables counting.

*/

// Counters are decremented on the falling edge of clock
wire enable = (clock_last && ~clock) && ~load && loaded && (
    (mode[1:0] == 2'b01) ||
    (mode[1:0] != 2'b01 && gate_level_sampled && (mode != 3'd0 || ~write_seq_ff))
);

`ifdef AO486_PIT_NO_IMMEDIATE_LOAD
// ================================================================================================
// Standard PIT behavior in accordance with the Intel 8254 datasheet never immediategly (re)loads
// the counter. The counter will always be (re)loaded on the next clock pulse. This can cause
// issues with certain timing critial code on fast systems.

wire load_counter    = load;
wire enable_counting = enable;

// ================================================================================================
`else
// ================================================================================================
// According to the Intel 8254 datasheet, after a written count or a trigger (in certain modes),
// the counter is not loaded immediately, but will be loaded on the next clock pulse (a rising
// edge, then a falling edge, in that order, of a counter's clock input). On slow enough systems
// (low enough clk frequency) this delayed loading is undetectable in software. However, on fast
// enough systems the delayed loading is detectable in software and can break certain timing
// critical code. Immediate loading can help mitigate some of these issues on fast systems.
// 
// On real hardware the counter can allegedly be (re)loaded immediately:
// - Load the initial count immediately after it has been written (reloads excluded)
//   See also: https://github.com/joncampbell123/doslib/blob/master/hw/8254/tpcrapi4.c
// - Load or reload the counter immediately after a trigger
//   See also: https://github.com/joncampbell123/doslib/blob/master/hw/8254/tpcrapi6.c
// This behavior is not mentioned in the Intel 8254 datasheet.

// Load the initial count immediately after it has been written (reloads excluded)
reg load_written_imm;
always @(posedge clk) begin
    load_written_imm <= mode[1:0] != 2'b01 && (write_last && ~write && (rw_mode != 2'd3 || write_seq_ff)) && ~loaded;
end

// Load the counter immediately after a trigger
reg load_trigger_imm;
always @(posedge clk) begin
    load_trigger_imm <= mode[1:0] != 2'b00 && (~gate_last && gate) && (written || loaded);
end

wire load_counter    = load_written_imm || (load_written && loaded) || load_trigger_imm || load_terminal;
wire enable_counting = enable && ~trigger && ~trigger_sampled;

// ================================================================================================
`endif

wire [15:0] counter_minus_1 =
    (bcd && !counter[15:0]) ? 16'h9999 :
    (bcd && !counter[11:0]) ? { counter[15:12] - 1'd1, 12'h999 } :
    (bcd && !counter[7:0])  ? { counter[15:8]  - 1'd1,   8'h99 } :
    (bcd && !counter[3:0])  ? { counter[15:4]  - 1'd1,    4'h9 } :
                                counter - 1'd1;

// Counting Element (CE)
reg [15:0] counter;
always @(posedge clk) begin
    if(!rst_n)               counter <= 16'd0;
    else if(load_counter)    counter <= { counter_m, counter_l[7:1], counter_l[0] & (mode[1:0] != 2'd3) };
    else if(enable_counting) counter <= counter_minus_1 - (mode[1:0] == 2'd3);
end

//-------------------------------------------------------------------------------------------------

endmodule
