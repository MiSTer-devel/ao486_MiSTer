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

wire clock_rise = ~clock_last &&  clock;
wire clock_fall =  clock_last && ~clock;

reg gate_last;
always @(posedge clk) gate_last <= gate;

wire gate_rise = ~gate_last &&  gate;
wire gate_fall =  gate_last && ~gate;

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

wire write_done = write_last && ~write;
wire read_done  = read_last  && ~read;

// Write sequence flip-flop for read/write mode 3 (LSB/MSB)
// Toggles on each write in read/write mode 3: 0 = LSB write expected; 1 = MSB write expected
reg write_seq_msb;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)         write_seq_msb <= 1'b0;
    else if(write_done && rw_mode == 2'd3) write_seq_msb <= ~write_seq_msb;
end

// Read sequence flip-flop for read/write mode 3 (LSB/MSB)
// Toggles on each read in read/write mode 3 (when status is not latched): 0 = LSB read expected; 1 = MSB read expected
reg read_seq_msb;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)                           read_seq_msb <= 1'b0;
    else if(read_done && rw_mode == 2'd3 && ~status_latched) read_seq_msb <= ~read_seq_msb;
end

// The read/write sequence is determined by rw_mode
wire write_seq_done = write_done && (rw_mode != 2'd3 || write_seq_msb);
wire read_seq_done  = read_done  && (rw_mode != 2'd3 || read_seq_msb);

wire write_lsb = write && rw_mode != 2'd2 && ~write_seq_msb;
wire write_msb = write && (rw_mode == 2'd2 || write_seq_msb);

//-------------------------------------------------------------------------------------------------

// Count Register LSB (CR_L)
reg [7:0] counter_l;
always @(posedge clk) begin
    if(!rst_n)                        counter_l <= 8'd0;
    else if(write && rw_mode == 2'd2) counter_l <= 8'd0; // set lsb to zero for read/write mode 2 (not in the Intel 8254 datasheet)
    else if(write_lsb)                counter_l <= data_in;
end

// Count Register MSB (CR_M)
reg [7:0] counter_m;
always @(posedge clk) begin
    if(!rst_n)                        counter_m <= 8'd0;
    else if(write && rw_mode == 2'd1) counter_m <= 8'd0; // set msb to zero for read/write mode 1 (not in the Intel 8254 datasheet)
    else if(write_msb)                counter_m <= data_in;
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
    if(!rst_n || set_control_mode) output_latched <= 1'b0; // set_control_mode releases a latched count
    else if(latch_count)           output_latched <= 1'b1;
    else if(read_seq_done)         output_latched <= 1'b0;
end

// Null Count flag
reg null_count;
always @(posedge clk) begin
    if(!rst_n)                null_count <= 1'b0;
    else if(set_control_mode) null_count <= 1'b1;
    else if(write_seq_done)   null_count <= 1'b1;
    else if(load)             null_count <= 1'b0;
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
    if(!rst_n || set_control_mode) status_latched <= 1'b0; // set_control_mode releases a latched status
    else if(latch_status)          status_latched <= 1'b1;
    else if(read_done)             status_latched <= 1'b0;
end

// Data Out
assign data_out = 
    (status_latched)                  ? status   : 
    (rw_mode == 2'd2 || read_seq_msb) ? output_m : output_l;

//-------------------------------------------------------------------------------------------------

// In modes 0, 2, 3, 4 the counter is (re)loaded when a write sequence is completed.

// Write sequence completed flip-flop
reg written;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)                                        written <= 1'b0; // setting a new mode aborts pending load
    else if(write_seq_done && mode[1:0] != 2'b01 && ~(mode[1] && loaded)) written <= 1'b1; // only modes 0, 2, 3, 4: see "load events per mode" table
    else if(load)                                                         written <= 1'b0;
end

// Written is sampled on the rising edge of clock
reg written_sampled;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) written_sampled <= 1'b0; // setting a new mode aborts pending load
    else if(clock_rise)            written_sampled <= written;
end

//-------------------------------------------------------------------------------------------------

// In modes 1, 2, 3, 5 the gate input is rising-edge sensitive (trigger).

reg armed;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)                armed <= 1'b0;
    else if(write_seq_done && mode[1:0] == 2'b01) armed <= 1'b1; // only modes 1, 5
end

wire trigger_pulse   = gate_rise;                        // trigger = rising edge of gate
wire trigger_allowed = (armed  && mode[1:0] == 2'b01) || // in modes 1, 5 triggers are ignored until the counter is armed
                       (loaded && mode[1]);              // in modes 2, 3 triggers are ignored until the initial count is loaded

// Gate rising-edge sensitive flip-flop
reg trigger;
always @(posedge clk) begin
    if(!rst_n || set_control_mode)            trigger <= 1'b0; // setting a new mode aborts pending load
    else if(trigger_pulse && trigger_allowed) trigger <= 1'b1; // trigger start
    else if(clock_rise)                       trigger <= 1'b0; // reset flip-flop after it has been sampled
end

// Trigger is sampled on the rising edge of clock
reg trigger_sampled;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) trigger_sampled <= 1'b0; // setting a new mode aborts pending load
    else if(clock_rise)            trigger_sampled <= trigger;
end

//-------------------------------------------------------------------------------------------------

// In modes 0, 2, 3, 4 the gate input is level sensitive.

// The gate logic level is sampled on the rising edge of clock
reg gate_level_sampled;
always @(posedge clk) begin
    if(!rst_n)          gate_level_sampled <= 1'b0; // setting a new mode does not affect gate_level_sampled
    else if(clock_rise) gate_level_sampled <= gate;
end

//-------------------------------------------------------------------------------------------------

always @(posedge clk) begin
    if (!rst_n)                                                 out <= 1'b1;
    else if (set_control_mode)                                  out <= (data_in[3:1] > 3'd0);
    else begin
        case(mode)
            // In modes 0, 1, 4, 5 gate has no effect on out
            3'd0: begin
                if      (write_done && ~write_seq_msb)          out <= 1'b0;
                else if (counter == 16'd1 && enable)            out <= 1'b1;
            end
            3'd1: begin
                if      (load)                                  out <= 1'b0;
                else if (counter == 16'd1 && enable)            out <= 1'b1;
            end
            3'd2, 3'd6: begin
                if      (load || gate_fall)                     out <= 1'b1;
                else if (counter == 16'd2 && enable)            out <= 1'b0;
            end
            3'd3, 3'd7: begin
                if      (gate_fall)                             out <= 1'b1;
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

// In modes 0, 2, 3, 4, when a count is fully written it will be (re)loaded on the next clock pulse
wire load_written = clock_fall && written_sampled;

// In modes 1, 2, 3, 5 a trigger (re)loads the counter on the next clock pulse
wire load_trigger = clock_fall && trigger_sampled;

// Terminal count for modes 2, 3
// Mode 2 terminal count value: 16'd1
// Mode 3 terminal count value: (counter_l[0] && out) ? 16'd0 : 16'd2
reg terminal_count;
always @(posedge clk) begin
    terminal_count <= counter == { 14'b0, ~(counter_l[0] && out) && mode[0], ~mode[0] };
end

// In the periodic modes 2, 3 reaching the terminal count reloads the counter on the falling edge of clock
wire load_terminal = clock_fall
    && mode[1]             // modes 2, 3
    && terminal_count      // terminal count
    && loaded              // counting is disabled until the initial count is loaded
    && gate_level_sampled; // in modes 0, 2, 3, 4 the sampled gate level can disable counting

// The counter can be (re)loaded on the falling edge of clock (Intel 8254 datasheet)
wire load = load_written || load_trigger || load_terminal;

// Flag indicating if the initial count has been loaded into the counter
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

    Modes 0, 2, 3, 4: gate 1 enables counting; gate 0 disables counting

    (*) For mode 0 in read/wite mode 3 (LSB/MSB),
    writing the first byte disables counting.

*/

// The counter can be decremented on the falling edge of clock
wire enable = clock_fall
    && ~load                                      // the counter is not decremented on (re)load
    && (mode[1:0] == 2'b01 || loaded)             // in modes 0, 2, 3, 4 counting is disabled until the initial count is loaded (disabling this line will fix Lemmings 2 (with Adlib music) on the highest speed settings)
    && (mode[1:0] == 2'b01 || gate_level_sampled) // in modes 0, 2, 3, 4 the sampled gate level can disable counting
    && ~(mode == 3'd0 && write_seq_msb);          // for mode 0 in read/wite mode 3 (LSB/MSB), writing the first byte disables counting

`ifdef AO486_PIT_NO_IMMEDIATE_LOAD
// ================================================================================================
// Standard PIT behavior in accordance with the Intel 8254 datasheet never immediategly (re)loads
// the counter. The counter will always be (re)loaded on the next clock pulse. This can cause
// issues with certain timing critial code on fast enough systems.

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
// - Immediately load the initial count (reloads excluded) after it has been written
//   See also: https://github.com/joncampbell123/doslib/blob/master/hw/8254/tpcrapi4.c
// - Immediately (re)load the counter after a trigger
//   See also: https://github.com/joncampbell123/doslib/blob/master/hw/8254/tpcrapi6.c
// This behavior is not mentioned in the Intel 8254 datasheet.

// In modes 0, 2, 3, 4, immediately load the initial count (reloads will be excluded) after it has been written
wire load_written_imm = write_seq_done && mode[1:0] != 2'b01;

// In modes 1, 2, 3, 5, immediately (re)load the counter after a trigger
wire load_trigger_imm = trigger_pulse && trigger_allowed;

// Counter (re)load including immediate (re)load
wire load_imm = (load_written_imm && ~loaded_imm) || load_trigger_imm || 
                (load_written     &&  loaded_imm) || load_terminal;

// Flag indicating if the initial count has been immediately loaded into the counter
reg loaded_imm;
always @(posedge clk) begin
    if(!rst_n || set_control_mode) loaded_imm <= 1'b0;
    else if(load_imm)              loaded_imm <= 1'b1;
end

// Premature counter decrements after immediate trigger (re)load have to be prevented,
// to remain consistant with the original PIT behavior
wire enable_imm = enable && (
    mode[1:0] == 2'b00 || ~( (trigger || trigger_sampled) && trigger_allowed )
);

wire load_counter    = load_imm;
wire enable_counting = enable_imm;

// ================================================================================================
`endif

wire [15:0] counter_minus_1 =
    (bcd && !counter[15:0]) ? 16'h9999 :
    (bcd && !counter[11:0]) ? { counter[15:12] - 1'd1, 12'h999 } :
    (bcd && !counter[7:0])  ? { counter[15:8]  - 1'd1,   8'h99 } :
    (bcd && !counter[3:0])  ? { counter[15:4]  - 1'd1,    4'h9 } :
                                counter - 1'd1;

// Counting Element (CE)
// On the falling edge of clock the counter can be:
// - Reset to the (re)load value
// - Decremented
reg [15:0] counter;
always @(posedge clk) begin
    if(!rst_n)               counter <= 16'd0;
    else if(load_counter)    counter <= { counter_m, counter_l[7:1], counter_l[0] & (mode[1:0] != 2'd3) };
    else if(enable_counting) counter <= counter_minus_1 - (mode[1:0] == 2'd3);
end

//-------------------------------------------------------------------------------------------------

endmodule
