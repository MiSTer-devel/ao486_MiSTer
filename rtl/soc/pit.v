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

module pit(
  input               clk,
  input               rst_n,

  output              irq,

  //io slave 040h-043h / 61h
  input       [2:0]   io_address,
  input               io_read,
  output reg  [7:0]   io_readdata,
  input               io_write,
  input       [7:0]   io_writedata,

  //speaker output
  output              speaker_out,

  input      [27:0]   clock_rate
);

//------------------------------------------------------------------------------ system clock

// PIT counter clock input frequency: 105/88 MHz = 1193181.81818... Hz

// Accurate accumulator-based NCO for PIT frequency
// NTSC-based master oscillator frequency     = 315/22 MHz = 14.318181818... MHz
// 315/22 * 1/4  = NTSC color burst frequency = 315/88 MHz =  3.579545454... MHz
// 315/22 * 1/12 = PIT frequency              = 105/88 MHz =  1.193181818... MHz = 13125000 / 11 Hz

localparam INCREMENT = 32'd26250000; // = 11 * (2 * PIT_frequency)
reg [31:0] clk_rate;                 // = 11 * (clock_rate)
always @(posedge clk) begin
    clk_rate <= ({4'b0, clock_rate} << 3) + ({4'b0, clock_rate} << 1) + {4'b0, clock_rate};
end

reg [31:0] sum;
reg ce_system_counter;
always @(posedge clk) begin
    if (!rst_n) begin
        sum <= 32'd0;
        ce_system_counter <= 1'b0;
    end else begin
        if ((sum + INCREMENT) >= clk_rate) begin
            sum <= (sum + INCREMENT) - clk_rate;
            ce_system_counter <= 1'b1;
        end else begin
            sum <= (sum + INCREMENT);
            ce_system_counter <= 1'b0;
        end
    end
end

reg system_clock;
always @(posedge clk) begin
    if(rst_n == 1'b0)           system_clock <= 1'b0;
    else if(ce_system_counter)  system_clock <= ~system_clock;
end

//------------------------------------------------------------------------------ read io

always @(posedge clk) if(io_read) io_readdata <=
    (io_read && io_address == 0) ? counter_0_readdata :
    (io_read && io_address == 1) ? counter_1_readdata :
    (io_read && io_address == 2) ? counter_2_readdata :
    (io_read && io_address[2])   ? { 2'b0, spk_out, counter_1_toggle, 2'b0, speaker_enable, speaker_gate } :
                                     8'd0; //control address

//------------------------------------------------------------------------------ refresh counter

reg [5:0] counter_1_cnt;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                       counter_1_cnt <= 6'd0;
    else if(ce_system_counter && counter_1_cnt == 6'd35)    counter_1_cnt <= 6'd0;
    else if(ce_system_counter)                              counter_1_cnt <= counter_1_cnt + 6'd1;
end

reg counter_1_toggle;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                       counter_1_toggle <= 1'b0;
    else if(ce_system_counter && counter_1_cnt == 6'd35)    counter_1_toggle <= ~(counter_1_toggle);
end

//------------------------------------------------------------------------------ speaker

reg speaker_gate;
always @(posedge clk) begin
    if(rst_n == 1'b0)                  speaker_gate <= 1'b0;
    else if(io_write && io_address[2]) speaker_gate <= io_writedata[0];
end

reg speaker_enable;
always @(posedge clk) begin
    if(rst_n == 1'b0)                  speaker_enable <= 1'b0;
    else if(io_write && io_address[2]) speaker_enable <= io_writedata[1];
end

assign speaker_out = spk_out & speaker_enable;

//------------------------------------------------------------------------------ counters

wire [7:0] counter_0_readdata;
wire [7:0] counter_1_readdata;
wire [7:0] counter_2_readdata;

pit_counter pit_counter_0(
    .clk                (clk),
    .rst_n              (rst_n),
    
    .clock              (system_clock),     //input
    .gate               (1'b1),             //input
    .out                (irq),              //output
    
    .data_in            (io_writedata),                                                                                                                                      //input [7:0]
    .set_control_mode   (io_write && io_address == 3 && io_writedata[7:6] == 2'b00 && io_writedata[5:4] != 2'b00),                                                           //input
    .latch_count        (io_write && io_address == 3 && ((io_writedata[7:6] == 2'b00 && io_writedata[5:4] == 2'b00) || (io_writedata[7:5] == 3'b110 && io_writedata[1]))),   //input
    .latch_status       (io_write && io_address == 3 && io_writedata[7:6] == 2'b11 && io_writedata[4] == 1'b0 && io_writedata[1]),                                           //input
    .write              (io_write && io_address == 0),                                                                                                                       //input
    .read               (io_read  && io_address == 0),                                                                                                                       //input
    
    .data_out           (counter_0_readdata)    //output [7:0]
);

pit_counter pit_counter_1(
    .clk                (clk),
    .rst_n              (rst_n),
    
    .clock              (system_clock),     //input
    .gate               (1'b1),             //input
    /* verilator lint_off PINNOCONNECT */
    .out                (),                 //output
    /* verilator lint_on PINNOCONNECT */
    
    .data_in            (io_writedata),                                                                                                                                      //input [7:0]
    .set_control_mode   (io_write && io_address == 3 && io_writedata[7:6] == 2'b01 && io_writedata[5:4] != 2'b00),                                                           //input
    .latch_count        (io_write && io_address == 3 && ((io_writedata[7:6] == 2'b01 && io_writedata[5:4] == 2'b00) || (io_writedata[7:5] == 3'b110 && io_writedata[2]))),   //input
    .latch_status       (io_write && io_address == 3 && io_writedata[7:6] == 2'b11 && io_writedata[4] == 1'b0 && io_writedata[2]),                                           //input
    .write              (io_write && io_address == 1),                                                                                                                       //input
    .read               (io_read  && io_address == 1),                                                                                                                       //input
    
    .data_out           (counter_1_readdata)    //output [7:0]
);

wire spk_out;
pit_counter pit_counter_2(
    .clk                (clk),
    .rst_n              (rst_n),
    
    .clock              (system_clock),     //input
    .gate               (speaker_gate),     //input
    .out                (spk_out),          //output
    
    .data_in            (io_writedata),                                                                                                                                      //input [7:0]
    .set_control_mode   (io_write && io_address == 3 && io_writedata[7:6] == 2'b10 && io_writedata[5:4] != 2'b00),                                                           //input
    .latch_count        (io_write && io_address == 3 && ((io_writedata[7:6] == 2'b10 && io_writedata[5:4] == 2'b00) || (io_writedata[7:5] == 3'b110 && io_writedata[3]))),   //input
    .latch_status       (io_write && io_address == 3 && io_writedata[7:6] == 2'b11 && io_writedata[4] == 1'b0 && io_writedata[3]),                                           //input
    .write              (io_write && io_address == 2),                                                                                                                       //input
    .read               (io_read  && io_address == 2),                                                                                                                       //input
    
    .data_out           (counter_2_readdata)    //output [7:0]
);

//------------------------------------------------------------------------------

endmodule
