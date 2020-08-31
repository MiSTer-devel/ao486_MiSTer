/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 * 
 * Fixes and Sound Blaster 16 support (C) 2017-2020 Alexey Melnikov
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

module sound_dsp
(
	input             clk,
	input             rst_n,

	input      [27:0] clock_rate,

	output reg        irq8,
	output reg        irq16,

	//io slave 0-Fh
	input       [3:0] io_address,
	input             io_read,
	output      [7:0] io_readdata,
	input             io_write,
	input       [7:0] io_writedata,

	//dma
	output            dma_req8,
	output            dma_req16,
	input             dma_ack,
	input      [15:0] dma_readdata,
	output     [15:0] dma_writedata,
	input             dma_16_en,
	input             sbp,
	input             sbp_stereo,

	//audio
	output reg [15:0] sample_value_l,
	output reg [15:0] sample_value_r
);

//------------------------------------------------------------------------------

reg io_read_last;
always @(posedge clk) begin if(rst_n == 1'b0) io_read_last <= 1'b0; else if(io_read_last) io_read_last <= 1'b0; else io_read_last <= io_read; end 
wire io_read_valid = io_read && io_read_last == 1'b0;

//------------------------------------------------------------------------------

assign io_readdata =
		(io_address == 4'hA) ? read_buffer[15:8] :
		(io_address == 4'hC) ? {write_ready, 7'h7F } :
		(io_address == 4'hE) ? {read_ready, 7'h7F } :
                             8'hFF;

//------------------------------------------------------------------------------

wire highspeed_start = cmd_high_auto_dma_out || cmd_high_single_dma_out || cmd_high_auto_dma_input || cmd_high_single_dma_input;

reg highspeed_mode;
always @(posedge clk) begin
    if(rst_n == 1'b0)           highspeed_mode <= 1'b0;
    else if(highspeed_reset)    highspeed_mode <= 1'b0;
    else if(highspeed_start)    highspeed_mode <= 1'b1;
    else if(dma_finished)       highspeed_mode <= 1'b0;
end

reg midi_uart_mode;
always @(posedge clk) begin
    if(rst_n == 1'b0)           midi_uart_mode <= 1'b0;
    else if(midi_uart_reset)    midi_uart_mode <= 1'b0;
    else if(cmd_midi_uart)      midi_uart_mode <= 1'b1;
end

reg reset_reg;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                               reset_reg <= 1'b0;
    else if(io_write && io_address == 4'h6 && ~(highspeed_mode))    reset_reg <= io_writedata[0];
end

wire highspeed_reset = io_write && io_address == 4'h6 &&  highspeed_mode;
wire midi_uart_reset = io_write && io_address == 4'h6 && ~highspeed_mode &&  midi_uart_mode && reset_reg && ~io_writedata[0];
wire sw_reset        = io_write && io_address == 4'h6 && ~highspeed_mode && ~midi_uart_mode && reset_reg && ~io_writedata[0];

//------------------------------------------------------------------------------ dummy input

wire input_strobe = cmd_direct_input || dma_input;

reg input_direction;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                       input_direction <= 1'b0;
    else if(sw_reset)                                                       input_direction <= 1'b0;
    else if(input_strobe && ~(input_direction) && input_sample == 8'd254)   input_direction <= 1'b1;
    else if(input_strobe && input_direction    && input_sample == 8'd1)     input_direction <= 1'b0;
end

reg [7:0] input_sample;
always @(posedge clk) begin
    if(rst_n == 1'b0)                           input_sample <= 8'd128;
    else if(sw_reset)                           input_sample <= 8'd128;
    else if(input_strobe && ~(input_direction)) input_sample <= input_sample + 8'd1;
    else if(input_strobe && input_direction)    input_sample <= input_sample - 8'd1;
end

assign dma_writedata = (dma_id_active) ? {dma_id_value,dma_id_value} : {input_sample,input_sample};

//------------------------------------------------------------------------------

localparam [511:0] dsp_cmd_len = {
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd2, 2'd1, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  // 0xf0
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd1,  2'd0, 2'd1, 2'd0, 2'd1,  // 0xe0
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  // 0xd0
	2'd3, 2'd3, 2'd3, 2'd3,  2'd3, 2'd3, 2'd3, 2'd3,  2'd3, 2'd3, 2'd3, 2'd3,  2'd3, 2'd3, 2'd3, 2'd3,  // 0xc0
	2'd3, 2'd3, 2'd3, 2'd3,  2'd3, 2'd3, 2'd3, 2'd3,  2'd3, 2'd3, 2'd3, 2'd3,  2'd3, 2'd3, 2'd3, 2'd3,  // 0xb0
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  // 0xa0
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  // 0x90
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd2,  // 0x80
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd2, 2'd2, 2'd2, 2'd2,  2'd0, 2'd0, 2'd0, 2'd0,  // 0x70
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  // 0x60
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  // 0x50
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd2,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd2, 2'd2, 2'd1,  // 0x40
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd1,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  // 0x30
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd2,  2'd0, 2'd0, 2'd0, 2'd0,  // 0x20
	2'd0, 2'd0, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd0,  2'd2, 2'd2, 2'd2, 2'd2,  2'd0, 2'd0, 2'd0, 2'd1,  // 0x10
	2'd1, 2'd2, 2'd0, 2'd0,  2'd0, 2'd0, 2'd0, 2'd1,  2'd0, 2'd0, 2'd2, 2'd1,  2'd0, 2'd0, 2'd0, 2'd0   // 0x00
};

wire [1:0] cmd_len    = dsp_cmd_len[(io_writedata*2) +:2];

wire       cmd_start  = !write_left && io_write && io_address == 4'hC && (~midi_uart_mode && ~highspeed_mode);
wire       cmd_cont   =  write_left && io_write && io_address == 4'hC;
wire       cmd_finish = cmd_recv_d & ~cmd_recv;

wire [7:0] cmd        = cmd_finish ? cmd_curr : 8'h00;

wire write_ready = midi_uart_mode || highspeed_mode;

reg cmd_recv;
always @(posedge clk) begin
	if(rst_n == 1'b0)        cmd_recv <= 1'd0;
	else if(sw_reset)        cmd_recv <= 1'd0;
	else if(cmd_start)       cmd_recv <= 1'd1;
	else if(!write_left)     cmd_recv <= 1'd0;
end

reg cmd_recv_d;
always @(posedge clk) begin
	if(rst_n == 1'b0)        cmd_recv_d <= 1'd0;
	else if(sw_reset)        cmd_recv_d <= 1'd0;
	else                     cmd_recv_d <= cmd_recv;
end

reg [1:0] write_left;
always @(posedge clk) begin
	if(rst_n == 1'b0)        write_left <= 2'd0;
	else if(sw_reset)        write_left <= 2'd0;
	else if(cmd_start)       write_left <= cmd_len;
	else if(cmd_cont)        write_left <= write_left - 2'd1;
end

reg [7:0] cmd_curr;
always @(posedge clk) begin
	if(rst_n == 1'b0)        cmd_curr <= 8'd0;
	else if(sw_reset)        cmd_curr <= 8'd0;
	else if(cmd_start)       cmd_curr <= io_writedata;
end

reg [23:0] write_buffer;
always @(posedge clk) begin
	if(rst_n == 1'b0)        write_buffer <= 24'd0;
	else if(sw_reset)        write_buffer <= 24'd0;
	else if(cmd_start)       write_buffer <= 24'd0;
	else if(cmd_cont)        write_buffer <= { write_buffer[15:0], io_writedata };
end

//------------------------------------------------------------------------------

//wire cmd_csp_cmd3               = cmd == 8'h03;
//wire cmd_csp_set_mode           = cmd == 8'h04;
//wire cmd_csp_set_par            = cmd == 8'h05;
wire cmd_csp_get_ver            = cmd == 8'h08;
//wire cmd_csp_set_reg            = cmd == 8'h0E;
wire cmd_csp_get_reg            = cmd == 8'h0F;

wire cmd_direct_output          = cmd == 8'h10;
wire cmd_single_dma_output      = cmd == 8'h14;
wire cmd_single_2_adpcm_out     = cmd == 8'h16;
wire cmd_single_2_adpcm_out_ref = cmd == 8'h17;
wire cmd_auto_dma_out           = cmd == 8'h1C;
wire cmd_auto_2_adpcm_out_ref   = cmd == 8'h1F;

wire cmd_direct_input           = cmd == 8'h20;
wire cmd_single_dma_input       = cmd == 8'h24;
wire cmd_auto_dma_input         = cmd == 8'h2C;

//wire cmd_midi_polling_input     = cmd == 8'h30;
//wire cmd_midi_interrupt_input   = cmd == 8'h31;
wire cmd_midi_uart              = { cmd[7:2], 2'b00 } == 8'h34;
//wire cmd_midi_output            = cmd == 8'h38;

wire cmd_set_time_constant      = cmd == 8'h40;
wire cmd_set_sample_rate        =(cmd == 8'h41 || cmd == 8'h42) && ~sbp;
wire cmd_auto_dma_continue      =(cmd == 8'h45 || cmd == 8'h47) && ~sbp;
wire cmd_set_block_size         = cmd == 8'h48;

wire cmd_single_4_adpcm_out     = cmd == 8'h74;
wire cmd_single_4_adpcm_out_ref = cmd == 8'h75;
wire cmd_single_3_adpcm_out     = cmd == 8'h76;
wire cmd_single_3_adpcm_out_ref = cmd == 8'h77;
wire cmd_auto_4_adpcm_out_ref   = cmd == 8'h7D;
wire cmd_auto_3_adpcm_out_ref   = cmd == 8'h7F;

wire cmd_pause_dac              = cmd == 8'h80;

wire cmd_high_auto_dma_out      = cmd == 8'h90;
wire cmd_high_single_dma_out    = cmd == 8'h91;
wire cmd_high_auto_dma_input    = cmd == 8'h98;
wire cmd_high_single_dma_input  = cmd == 8'h99;

wire cmd_new_dma                =(cmd[7:4] == 4'hB || cmd[7:4] == 4'hC) && ~sbp;

wire cmd_dma_pause_start        = cmd == 8'hD0 || (cmd == 8'hD5 && ~sbp);
wire cmd_speaker_on             = cmd == 8'hD1;
wire cmd_speaker_off            = cmd == 8'hD3;
wire cmd_dma_pause_end          = cmd == 8'hD4 || (cmd == 8'hD6 && ~sbp);
wire cmd_speaker_status         = cmd == 8'hD8;
wire cmd_auto_dma_exit          = cmd == 8'hDA || (cmd == 8'hD9 && ~sbp);

wire cmd_dsp_identification     = cmd == 8'hE0;
wire cmd_dsp_version            = cmd == 8'hE1;
wire cmd_dma_id                 = cmd == 8'hE2;
wire cmd_copyright              = cmd == 8'hE3;
wire cmd_test_register_write    = cmd == 8'hE4;
wire cmd_test_register_read     = cmd == 8'hE8;

wire cmd_trigger_irq8           = cmd == 8'hF2;
wire cmd_trigger_irq16          =(cmd == 8'hF3 && ~sbp);
wire cmd_f8_zero                = cmd == 8'hF8;
wire cmd_f9_test                = cmd == 8'hF9;

wire cmd_new_single_output      = cmd_new_dma & ~cmd[2] & ~cmd[3];
wire cmd_new_auto_output        = cmd_new_dma &  cmd[2] & ~cmd[3];
wire cmd_new_single_input       = cmd_new_dma & ~cmd[2] &  cmd[3];
wire cmd_new_auto_input         = cmd_new_dma &  cmd[2] &  cmd[3];
wire cmd_new_block_size         = cmd_new_dma;

/*
 Cx/Bx - Program 8/16-bit DMA mode digitized sound I/O
         Command sequence:  Command, Mode, Lo(Length-1), Hi(Length-1)
         Command:
         ╔════╤════╤════╤══════╤═══════╤══════╤═══════╤════╗
         ║ D7 │ D6 │ D5 │  D4  │  D3   │  D2  │  D1   │ D0 ║
         ╠════╪════╪════╪══════╪═══════╪══════╪═══════╪════╣
         ║  1 │  * │  * │ 16/8 │  A/D  │  A/I │ FIFO  │  0 ║
         ╚════╧════╧════┼──────┼───────┼──────┼───────┼════╝
                        │ 0=8  │ 0=D/A │ 0=SC │ 0=off │
                        │ 1=16 │ 1=A/D │ 1=AI │ 1=on  │
                        └──────┴───────┴──────┴───────┘
         Common commands:
           C8/B8 - single-cycle input
           C0/B0 - single-cycle output
           CE/BE - auto-initialized input
           C6/B6 - auto-initialized output

         Mode:
         ╔════╤════╤══════════╤════════════╤════╤════╤════╤════╗
         ║ D7 │ D6 │    D5    │     D4     │ D3 │ D2 │ D1 │ D0 ║
         ╠════╪════╪══════════╪════════════╪════╪════╪════╪════╣
         ║  0 │  0 │  Stereo  │   Signed   │  0 │  0 │  0 │  0 ║
         ╚════╧════┼──────────┼────────────┼════╧════╧════╧════╝
                   │ 0=Mono   │ 0=unsigned │
                   │ 1=Stereo │ 1=signed   │
                   └──────────┴────────────┘
*/

//------------------------------------------------------------------------------ reply

wire read_ready = ~midi_uart_mode && (read_buffer_size || copy_cnt);

wire read_reply = io_read_valid && io_address == 4'hA;

reg [1:0] read_buffer_size;
always @(posedge clk) begin
	if(rst_n == 1'b0)                       read_buffer_size <= 2'd0;
	else if(sw_reset)                       read_buffer_size <= 2'd1;
	else if(cmd_dsp_version)                read_buffer_size <= 2'd2;
	else if(cmd_direct_input)               read_buffer_size <= 2'd1;
	else if(cmd_speaker_status)             read_buffer_size <= 2'd1;
	else if(cmd_dsp_identification)         read_buffer_size <= 2'd1;
	else if(cmd_f8_zero)                    read_buffer_size <= 2'd1;
	else if(cmd_test_register_read)         read_buffer_size <= 2'd1;
	else if(cmd_csp_get_ver & ~sbp)         read_buffer_size <= 2'd1;
	else if(cmd_csp_get_reg & ~sbp)         read_buffer_size <= 2'd1;
	else if(cmd_f9_test & ~sbp)             read_buffer_size <= 2'd1;
	else if(cmd)                            read_buffer_size <= 2'd0; // all other commands

	else if(read_reply && read_buffer_size) read_buffer_size <= read_buffer_size - 2'd1;
end

localparam COPY_STR = 368'h434F505952494748542028432920435245415449564520544543484E4F4C4F4759204C54442C20313939322E0000;

reg [5:0] copy_cnt;
always @(posedge clk) begin
	if(~rst_n | sw_reset)                   copy_cnt <= 6'd0;
	else if(cmd_copyright)                  copy_cnt <= 6'd45;
	else if(cmd)                            copy_cnt <= 6'd0;
	else if(read_reply && copy_cnt)         copy_cnt <= copy_cnt - 1'd1;
end

reg [15:0] read_buffer;
always @(posedge clk) begin
	if(rst_n == 1'b0)                       read_buffer <= 16'd0;
	else if(sw_reset)                       read_buffer <= { 8'hAA, 8'hAA };
	else if(cmd_dsp_version)                read_buffer <= sbp ? { 8'h03, 8'h02 } : { 8'h04, 8'h05 };
	else if(cmd_direct_input)               read_buffer <= { input_sample, input_sample };
	else if(cmd_speaker_status)             read_buffer <= (speaker_on)? 16'hFFFF : 16'h0000;
	else if(cmd_dsp_identification)         read_buffer <= { ~write_buffer[7:0], ~write_buffer[7:0] };
	else if(cmd_f8_zero)                    read_buffer <= { 8'h00, 8'h00 };
	else if(cmd_test_register_read)         read_buffer <= { test_register, test_register };
	else if(cmd_copyright)                  read_buffer <= 16'd0;
	else if(cmd_csp_get_ver & ~sbp)         read_buffer <= 16'hFFFF;
	else if(cmd_csp_get_reg & ~sbp)         read_buffer <= (write_buffer[7:0] == 8'h09) ? 16'hF8F8 : 16'hFFFF;
	else if(cmd_f9_test & ~sbp)             read_buffer <= (write_buffer[7:0] == 8'h0E) ? 16'hFFFF :
                                                          (write_buffer[7:0] == 8'h0F) ? 16'h0707 :
																			 (write_buffer[7:0] == 8'h37) ? 16'h3838 : 16'h0000;	

	else if(read_reply && read_buffer_size) read_buffer[15:8] <= read_buffer[7:0]; // repeat last byte
	else if(copy_cnt)                       read_buffer[15:8] <= COPY_STR[(copy_cnt*8) +:8];
end

//------------------------------------------------------------------------------ 'weird dma identification' from DosBox

reg [7:0] dma_id_value;
always @(posedge clk) begin
	if(rst_n == 1'b0)   dma_id_value <= 8'hAA;
	else if(sw_reset)   dma_id_value <= 8'hAA;
	else if(cmd_dma_id) dma_id_value <= dma_id_value + (write_buffer[7:0] ^ dma_xor_value);
end

reg [7:0] dma_xor_value;
always @(posedge clk) begin
	if(rst_n == 1'b0)   dma_xor_value <= 8'h96;
	else if(sw_reset)   dma_xor_value <= 8'h96;
	else if(cmd_dma_id) dma_xor_value <= {dma_xor_value[1:0],dma_xor_value[7:2]};
end

reg dma_id_active;
always @(posedge clk) begin
	if(rst_n == 1'b0)   dma_id_active <= 1'b0;
	else if(sw_reset)   dma_id_active <= 1'b0;
	else if(cmd_dma_id) dma_id_active <= 1'b1;
	else if(dma_ack_w)  dma_id_active <= 1'b0;
end

//------------------------------------------------------------------------------

reg [7:0] test_register;
always @(posedge clk) begin
	if(rst_n == 1'b0)                   test_register <= 8'd0;
	else if(cmd_test_register_write)    test_register <= write_buffer[7:0];
end

reg speaker_on; // not affecting actual output on DSP 4.xx
always @(posedge clk) begin
	if(rst_n == 1'b0)           speaker_on <= 1'b0;
	else if(sw_reset)           speaker_on <= 1'b0;
	else if(cmd_speaker_on)     speaker_on <= 1'b1;
	else if(cmd_speaker_off)    speaker_on <= 1'b0;
end

reg [15:0] block_size;
always @(posedge clk) begin
	if(rst_n == 1'b0)                                block_size <= 16'd0;
	else if(sw_reset)                                block_size <= 16'd0;
	else if(cmd_set_block_size | cmd_new_block_size) block_size <= { write_buffer[7:0], write_buffer[15:8] };
end

reg pause_dma;
always @(posedge clk) begin
	if(rst_n == 1'b0)                                                   pause_dma <= 1'b0;
	else if(sw_reset)                                                   pause_dma <= 1'b0;
	else if(cmd_dma_pause_start)                                        pause_dma <= 1'b1;
	else if(cmd_dma_pause_end || dma_single_start || dma_auto_start)    pause_dma <= 1'b0;
end

//------------------------------------------------------------------------------ pause dac

wire pause_interrupt = !pause_counter && ce_smp && &pause_period;

reg pause_active;
always @(posedge clk) begin
	if(rst_n == 1'b0)                        pause_active <= 1'b0;
	else if(sw_reset)                        pause_active <= 1'b0;
	else if(cmd_pause_dac)                   pause_active <= 1'b1;
	else if(!pause_counter && !pause_period) pause_active <= 1'b0;
end

reg [15:0] pause_counter;
always @(posedge clk) begin
	if(rst_n == 1'b0)                        pause_counter <= 16'd0;
	else if(sw_reset)                        pause_counter <= 16'd0;
	else if(cmd_pause_dac)                   pause_counter <= { write_buffer[7:0], write_buffer[15:8] };
	else if(!pause_period && pause_counter)  pause_counter <= pause_counter - 1'd1;
end

reg [7:0] pause_period;
always @(posedge clk) begin
	if(rst_n == 1'b0)                       pause_period <= 8'd0;
	else if(sw_reset)                       pause_period <= 8'd0;
	else if(cmd_pause_dac)                  pause_period <= period;
	else if(!pause_period && pause_counter) pause_period <= period;
	else if(ce_smp && pause_period)         pause_period <= pause_period + 1'd1;
end

reg [7:0] period;
always @(posedge clk) begin
	if(rst_n == 1'b0)                       period <= 128;
	else if(sw_reset)                       period <= 128;
	else if(cmd_set_time_constant)          period <= write_buffer[7:0];
	else if(cmd_set_sample_rate)            period <= 255;
end

reg ce_smp;
always @(posedge clk) begin
	reg [27:0] sum = 0;

	ce_smp = 0;
	sum = sum + clk_smp;
	if(sum >= clock_rate) begin
		sum = sum - clock_rate;
		ce_smp = 1;
	end
end

reg [27:0] clk_smp;
always @(posedge clk) begin
	if(!rst_n || sw_reset || cmd_set_time_constant) clk_smp <= 1000000;
	else if(cmd_set_sample_rate)                    clk_smp <= write_buffer[15:0];
end

//------------------------------------------------------------------------------ irq

always @(posedge clk) begin
	if(~rst_n || sw_reset)                                                        irq8 <= 1'b0;
	else if((dma_finished || dma_auto_restart || pause_interrupt) && ~dma_16_req) irq8 <= 1'b1;
	else if(cmd_trigger_irq8)                                                     irq8 <= 1'b1;
	else if(io_read_valid && io_address == 4'hE)                                  irq8 <= 1'b0;
end

always @(posedge clk) begin
	if(~rst_n || sw_reset)                                                        irq16 <= 1'b0;
	else if((dma_finished || dma_auto_restart || pause_interrupt) && dma_16_req)  irq16 <= 1'b1;
	else if(cmd_trigger_irq16)                                                    irq16 <= 1'b1;
	else if(io_read_valid && io_address == 4'hF)                                  irq16 <= 1'b0;
end

//------------------------------------------------------------------------------ dma commands

localparam [4:0] S_IDLE                 = 5'd0;
localparam [4:0] S_OUT_SINGLE_8_BIT     = 5'd1;
localparam [4:0] S_OUT_SINGLE_4_BIT     = 5'd2;
localparam [4:0] S_OUT_SINGLE_3_BIT     = 5'd3;
localparam [4:0] S_OUT_SINGLE_2_BIT     = 5'd4;
localparam [4:0] S_OUT_SINGLE_4_BIT_REF = 5'd5;
localparam [4:0] S_OUT_SINGLE_3_BIT_REF = 5'd6;
localparam [4:0] S_OUT_SINGLE_2_BIT_REF = 5'd7;
localparam [4:0] S_OUT_AUTO_8_BIT       = 5'd8;
localparam [4:0] S_OUT_AUTO_4_BIT_REF   = 5'd9;
localparam [4:0] S_OUT_AUTO_3_BIT_REF   = 5'd10;
localparam [4:0] S_OUT_AUTO_2_BIT_REF   = 5'd11;
localparam [4:0] S_IN_SINGLE            = 5'd12;
localparam [4:0] S_IN_AUTO              = 5'd13;
localparam [4:0] S_OUT_SINGLE_HIGH      = 5'd14;
localparam [4:0] S_OUT_AUTO_HIGH        = 5'd15;
localparam [4:0] S_IN_SINGLE_HIGH       = 5'd16;
localparam [4:0] S_IN_AUTO_HIGH         = 5'd17;
localparam [4:0] S_OUT_SINGLE_NEW       = 5'd18;
localparam [4:0] S_OUT_AUTO_NEW         = 5'd19;
localparam [4:0] S_IN_SINGLE_NEW        = 5'd20;
localparam [4:0] S_IN_AUTO_NEW          = 5'd21;

reg [4:0] dma_command;

always @(posedge clk) begin
	if(rst_n == 1'b0)                           dma_command <= S_IDLE;
	else if(sw_reset)                           dma_command <= S_IDLE;

	else if(cmd_single_dma_output)              dma_command <= S_OUT_SINGLE_8_BIT;
	else if(cmd_single_4_adpcm_out)             dma_command <= S_OUT_SINGLE_4_BIT;
	else if(cmd_single_3_adpcm_out)             dma_command <= S_OUT_SINGLE_3_BIT;
	else if(cmd_single_2_adpcm_out)             dma_command <= S_OUT_SINGLE_2_BIT;

	else if(cmd_single_4_adpcm_out_ref)         dma_command <= S_OUT_SINGLE_4_BIT_REF;
	else if(cmd_single_3_adpcm_out_ref)         dma_command <= S_OUT_SINGLE_3_BIT_REF;
	else if(cmd_single_2_adpcm_out_ref)         dma_command <= S_OUT_SINGLE_2_BIT_REF;

	else if(cmd_auto_dma_out)                   dma_command <= S_OUT_AUTO_8_BIT;
	else if(cmd_auto_4_adpcm_out_ref)           dma_command <= S_OUT_AUTO_4_BIT_REF;
	else if(cmd_auto_3_adpcm_out_ref)           dma_command <= S_OUT_AUTO_3_BIT_REF;
	else if(cmd_auto_2_adpcm_out_ref)           dma_command <= S_OUT_AUTO_2_BIT_REF;

	else if(cmd_single_dma_input)               dma_command <= S_IN_SINGLE;
	else if(cmd_auto_dma_input)                 dma_command <= S_IN_AUTO;

	else if(cmd_high_single_dma_out)            dma_command <= S_OUT_SINGLE_HIGH;
	else if(cmd_high_auto_dma_out)              dma_command <= S_OUT_AUTO_HIGH;

	else if(cmd_high_single_dma_input)          dma_command <= S_IN_SINGLE_HIGH;
	else if(cmd_high_auto_dma_input)            dma_command <= S_IN_AUTO_HIGH;

	else if(cmd_new_single_output)              dma_command <= S_OUT_SINGLE_NEW;
	else if(cmd_new_auto_output)                dma_command <= S_OUT_AUTO_NEW;
	else if(cmd_new_single_input)               dma_command <= S_IN_SINGLE_NEW;
	else if(cmd_new_auto_input)                 dma_command <= S_IN_AUTO_NEW;

	else if(dma_single_start || dma_auto_start) dma_command <= S_IDLE;
end

//------------------------------------------------------------------------------ dma

wire dma_single_start = dma_restart_possible && (
    dma_command == S_OUT_SINGLE_8_BIT || dma_command == S_OUT_SINGLE_4_BIT     || dma_command == S_OUT_SINGLE_3_BIT     || dma_command == S_OUT_SINGLE_2_BIT     ||
                                         dma_command == S_OUT_SINGLE_4_BIT_REF || dma_command == S_OUT_SINGLE_3_BIT_REF || dma_command == S_OUT_SINGLE_2_BIT_REF ||
    dma_command == S_IN_SINGLE ||
    dma_command == S_OUT_SINGLE_HIGH || dma_command == S_IN_SINGLE_HIGH ||
	 dma_command == S_OUT_SINGLE_NEW  || dma_command == S_IN_SINGLE_NEW
);

wire dma_auto_start = dma_restart_possible && (
    dma_command == S_OUT_AUTO_8_BIT || dma_command == S_OUT_AUTO_4_BIT_REF || dma_command == S_OUT_AUTO_3_BIT_REF || dma_command == S_OUT_AUTO_2_BIT_REF ||
    dma_command == S_IN_AUTO ||
    dma_command == S_OUT_AUTO_HIGH || dma_command == S_IN_AUTO_HIGH ||
	 dma_command == S_OUT_AUTO_NEW  || dma_command == S_IN_AUTO_NEW
);

wire dma_new_start = dma_restart_possible && (
	 dma_command == S_OUT_SINGLE_NEW  || dma_command == S_IN_SINGLE_NEW ||
	 dma_command == S_OUT_AUTO_NEW  || dma_command == S_IN_AUTO_NEW
);

wire dma_normal_req = dma_in_progress && dma_wait == 16'd0 && adpcm_wait == 2'd0 && ~(pause_dma);

wire dma_valid  = dma_normal_req && dma_ack_w && ~dma_id_active;
wire dma_output = ~dma_is_input && dma_valid;
wire dma_input  =  dma_is_input && dma_valid;

wire dma_finished = dma_in_progress && ~dma_autoinit && (
    ((dma_valid|dma_ack_stereo) && dma_left == 17'd1 && adpcm_type == ADPCM_NONE) ||
    (adpcm_output && dma_left == 17'd0 && adpcm_type != ADPCM_NONE && adpcm_wait == 2'd1)
);
    
wire dma_auto_restart = dma_in_progress && dma_autoinit && (
    ((dma_valid|dma_ack_stereo) && dma_left == 17'd1 && adpcm_type == ADPCM_NONE) ||
    (adpcm_output && dma_left == 17'd0 && adpcm_type != ADPCM_NONE && adpcm_wait == 2'd1)
);

wire dma_restart_possible = !dma_wait && (!adpcm_wait || (adpcm_type != ADPCM_NONE && adpcm_wait == 2'd1)) && (~(dma_in_progress) || dma_auto_restart || pause_dma);

reg [16:0] dma_left;
always @(posedge clk) begin
	if(rst_n == 1'b0)                           dma_left <= 17'd0;
	else if(sw_reset)                           dma_left <= 17'd0;
	else if(dma_single_start)                   dma_left <= {1'b0, write_buffer[7:0], write_buffer[15:8] } + 1'd1;
	else if(dma_auto_start || dma_auto_restart) dma_left <= {1'b0, block_size} + 1'd1;
	else if(dma_ack_stereo && dma_left > 17'd0) dma_left <= dma_left - 1'd1;
	else if(dma_valid && dma_left > 17'd0)      dma_left <= dma_left - 1'd1;
	else if(dma_finished)                       dma_left <= 17'd0;
end

reg dma_in_progress;
always @(posedge clk) begin
	if(rst_n == 1'b0)                           dma_in_progress <= 1'b0;
	else if(sw_reset)                           dma_in_progress <= 1'b0;
	else if(dma_single_start || dma_auto_start) dma_in_progress <= 1'b1;
	else if(dma_finished)                       dma_in_progress <= 1'b0;
end

reg dma_is_input;
always @(posedge clk) begin
	if(rst_n == 1'b0)                                                         dma_is_input <= 1'b0;
	else if(sw_reset)                                                         dma_is_input <= 1'b0;
	else if((dma_single_start || dma_auto_start) 
	 && (   dma_command == S_IN_SINGLE      || dma_command == S_IN_AUTO
	     || dma_command == S_IN_SINGLE_HIGH || dma_command == S_IN_AUTO_HIGH
		  || dma_command == S_IN_SINGLE_NEW  || dma_command == S_IN_AUTO_NEW)) dma_is_input <= 1'b1;
	else if(dma_single_start || dma_auto_start)                               dma_is_input <= 1'b0;
end

reg dma_autoinit;
always @(posedge clk) begin
	if(rst_n == 1'b0)              dma_autoinit <= 1'b0;
	else if(sw_reset)              dma_autoinit <= 1'b0;
	else if(dma_single_start)      dma_autoinit <= 1'b0;
	else if(dma_auto_start)        dma_autoinit <= 1'b1;
	else if(cmd_auto_dma_exit)     dma_autoinit <= 1'b0;
	else if(cmd_auto_dma_continue) dma_autoinit <= 1'b1;
end

reg [7:0] dma_wait;
always @(posedge clk) begin
	if(rst_n == 1'b0)                                                                                                 dma_wait <= 8'd0;
	else if(sw_reset)                                                                                                 dma_wait <= 8'd0;
	else if(dma_finished || dma_valid || adpcm_output || (~dma_in_progress && (dma_single_start || dma_auto_start)))  dma_wait <= period;
	else if(ce_smp && dma_wait)                                                                                       dma_wait <= dma_wait + 1'd1;
end

reg [3:0] dma_format; // 16/8, sbp_stereo/mono, sb16_stereo/mono, signed/unsigned
always @(posedge clk) begin
	if(~rst_n || sw_reset)                     dma_format <= 0;
	else if(dma_new_start)                     dma_format <= {cmd_curr[4], 1'b0, write_buffer[21:20]};
	else if(dma_single_start | dma_auto_start) dma_format <= {1'b0, sbp_stereo, 2'b00};
end

reg sbp_lr;
always @(posedge clk) begin
	if(dma_single_start|dma_auto_start) sbp_lr <= 0;
	else if(sample_output)              sbp_lr <= ~sbp_lr;
end

wire   dma_16_req = dma_format[3];
wire   dma_16_use = dma_16_req & dma_16_en;

wire   dma_req   = dma_id_active || dma_normal_req;
assign dma_req8  = dma_req & ~dma_16_use;
assign dma_req16 = dma_req &  dma_16_use;

wire   dma_ack_w      = dma_ack_f & (~dma_format[1] |  sample_lr);
wire   dma_ack_stereo = dma_ack_f & ( dma_format[1] & ~sample_lr);

reg        sample_output;
reg        sample_lr;
reg [15:0] sample_dma[2];
always @(posedge clk) begin
	sample_lr <= dma_req & (sample_lr ^ (dma_ack_f & dma_format[1]));
	sample_output <= dma_output;

	if(dma_ack) begin
		if(~dma_16_req)    sample_dma[sample_lr]       <= {dma_readdata[7:0],8'd0};
		else if(dma_16_en) sample_dma[sample_lr]       <= dma_readdata;
		else if(~dma_hcnt) sample_dma[sample_lr][7:0]  <= dma_readdata[7:0];
		else               sample_dma[sample_lr][15:8] <= dma_readdata[7:0];
	end
end

wire dma_ack_f = dma_ack & (dma_hcnt | dma_16_en | ~dma_16_req);
reg  dma_hcnt;
always @(posedge clk) dma_hcnt <= dma_req & (dma_hcnt ^ dma_ack);

//------------------------------------------------------------------------------ adpcm

localparam [1:0] ADPCM_NONE = 2'd0;
localparam [1:0] ADPCM_4BIT = 2'd1;
localparam [1:0] ADPCM_3BIT = 2'd2;
localparam [1:0] ADPCM_2BIT = 2'd3;

wire adpcm_reference_start = 
    (dma_single_start || dma_auto_start) && (
    dma_command == S_OUT_SINGLE_2_BIT_REF || dma_command == S_OUT_SINGLE_3_BIT_REF || dma_command == S_OUT_SINGLE_4_BIT_REF ||
    dma_command == S_OUT_AUTO_2_BIT_REF   || dma_command == S_OUT_AUTO_3_BIT_REF   || dma_command == S_OUT_AUTO_4_BIT_REF
);

wire adpcm_output = !dma_wait && adpcm_wait;

reg adpcm_reference_awaiting;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               adpcm_reference_awaiting <= 1'b0;
    else if(sw_reset)                               adpcm_reference_awaiting <= 1'b0;
    else if(adpcm_reference_start)                  adpcm_reference_awaiting <= 1'b1;
    else if(dma_single_start || dma_auto_start)     adpcm_reference_awaiting <= 1'b0;
    else if(adpcm_reference_awaiting && dma_output) adpcm_reference_awaiting <= 1'b0;
    else if(dma_finished)                           adpcm_reference_awaiting <= 1'b0;
end

reg adpcm_reference_output;
always @(posedge clk) begin
    if(rst_n == 1'b0)   adpcm_reference_output <= 1'b0;
    else                adpcm_reference_output <= adpcm_reference_awaiting;
end

reg [1:0] adpcm_wait;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               adpcm_wait <= 2'd0;
    else if(sw_reset)                               adpcm_wait <= 2'd0;
    else if(dma_single_start || dma_auto_start)     adpcm_wait <= 2'd0;
    else if(adpcm_reference_awaiting && dma_output) adpcm_wait <= 2'd0;
    else if(dma_output && adpcm_type == ADPCM_2BIT) adpcm_wait <= 2'd3;
    else if(dma_output && adpcm_type == ADPCM_3BIT) adpcm_wait <= 2'd2;
    else if(dma_output && adpcm_type == ADPCM_4BIT) adpcm_wait <= 2'd1;
    else if(adpcm_output && adpcm_wait > 2'd0)      adpcm_wait <= adpcm_wait - 2'd1;
end

reg [7:0] adpcm_sample;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                   adpcm_sample <= 8'd0;
    else if(sw_reset)                                   adpcm_sample <= 8'd0;
    else if(dma_output)                                 adpcm_sample <= dma_readdata[7:0];
    else if(adpcm_output && adpcm_type == ADPCM_2BIT)   adpcm_sample <= { adpcm_sample[5:0], 2'b0 };
    else if(adpcm_output && adpcm_type == ADPCM_3BIT)   adpcm_sample <= { adpcm_sample[4:0], 3'b0 };
    else if(adpcm_output && adpcm_type == ADPCM_4BIT)   adpcm_sample <= { adpcm_sample[3:0], 4'b0 };
end

reg adpcm_active;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                   adpcm_active <= 1'b0;
    else if(sw_reset)                                   adpcm_active <= 1'b0;
    else if(adpcm_reference_awaiting && dma_output)     adpcm_active <= 1'b0;
    else if(adpcm_type != ADPCM_NONE && dma_output)     adpcm_active <= 1'b1;
    else if(adpcm_output)                               adpcm_active <= 1'b1;
    else                                                adpcm_active <= 1'b0;
end

wire [7:0] adpcm_active_value =
    (adpcm_type == ADPCM_2BIT)?     adpcm_2bit_reference_next :
    (adpcm_type == ADPCM_3BIT)?     adpcm_3bit_reference_next :
                                    adpcm_4bit_reference_next;

reg [1:0] adpcm_type;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                                                                                                                       adpcm_type <= ADPCM_NONE;
    else if(sw_reset)                                                                                                                                                       adpcm_type <= ADPCM_NONE;
    else if((dma_single_start || dma_auto_start) && (dma_command == S_OUT_SINGLE_2_BIT_REF || dma_command == S_OUT_SINGLE_2_BIT || dma_command == S_OUT_AUTO_2_BIT_REF))    adpcm_type <= ADPCM_2BIT;
    else if((dma_single_start || dma_auto_start) && (dma_command == S_OUT_SINGLE_3_BIT_REF || dma_command == S_OUT_SINGLE_3_BIT || dma_command == S_OUT_AUTO_3_BIT_REF))    adpcm_type <= ADPCM_3BIT;
    else if((dma_single_start || dma_auto_start) && (dma_command == S_OUT_SINGLE_4_BIT_REF || dma_command == S_OUT_SINGLE_4_BIT || dma_command == S_OUT_AUTO_4_BIT_REF))    adpcm_type <= ADPCM_4BIT;
    else if((dma_single_start || dma_auto_start))                                                                                                                           adpcm_type <= ADPCM_NONE;
    else if(dma_finished)                                                                                                                                                   adpcm_type <= ADPCM_NONE;
end

reg [2:0] adpcm_step;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                   adpcm_step <= 3'd0;
    else if(sw_reset)                                   adpcm_step <= 3'd0;
    else if(adpcm_active && adpcm_type == ADPCM_2BIT)   adpcm_step <= adpcm_2bit_step_next;
    else if(adpcm_active && adpcm_type == ADPCM_3BIT)   adpcm_step <= adpcm_3bit_step_next;
    else if(adpcm_active && adpcm_type == ADPCM_4BIT)   adpcm_step <= adpcm_4bit_step_next;
    else if(adpcm_reference_awaiting && dma_output)     adpcm_step <= 3'd0;
end

reg [7:0] adpcm_reference;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                   adpcm_reference <= 8'd0;
    else if(sw_reset)                                   adpcm_reference <= 8'd0;
    else if(adpcm_active && adpcm_type == ADPCM_2BIT)   adpcm_reference <= adpcm_2bit_reference_next;
    else if(adpcm_active && adpcm_type == ADPCM_3BIT)   adpcm_reference <= adpcm_3bit_reference_next;
    else if(adpcm_active && adpcm_type == ADPCM_4BIT)   adpcm_reference <= adpcm_4bit_reference_next;
    else if(adpcm_reference_awaiting && dma_output)     adpcm_reference <= dma_readdata[7:0];
end

//------------------------------------------------------------------------------ adpcm 2 bit

wire [1:0] adpcm_2bit_sample = adpcm_sample[7:6];

wire [7:0] adpcm_2bit_reference_adjust =
    (adpcm_step[2:0] == 3'd0)?      { 7'd0, adpcm_2bit_sample[0] } :
    (adpcm_step[2:0] == 3'd1)?      { 6'd0, adpcm_2bit_sample[0], 1'b1 } :
    (adpcm_step[2:0] == 3'd2)?      { 5'd0, adpcm_2bit_sample[0], 2'b10 } :
    (adpcm_step[2:0] == 3'd3)?      { 4'd0, adpcm_2bit_sample[0], 3'b100 } :
    (adpcm_step[2:0] == 3'd4)?      { 3'd0, adpcm_2bit_sample[0], 4'b1000 } :
                                    { 2'd0, adpcm_2bit_sample[0], 5'b10000 }; //adpcm_step[2:0] == 3'd5

wire [8:0] adpcm_2bit_reference_sum = adpcm_reference + adpcm_2bit_reference_adjust;
wire [8:0] adpcm_2bit_reference_sub = adpcm_reference - adpcm_2bit_reference_adjust;

wire [7:0] adpcm_2bit_reference_next =
    (adpcm_2bit_sample[1] && adpcm_2bit_reference_sub[8])?  8'd0 :
    (adpcm_2bit_sample[1])?                                 adpcm_2bit_reference_sub[7:0] :
    (adpcm_2bit_reference_sum[8])?                          8'd255 :
                                                            adpcm_2bit_reference_sum[7:0];
wire [2:0] adpcm_2bit_step_next =
    (adpcm_step < 3'd5 && adpcm_2bit_sample[0] == 1'b1)?    adpcm_step + 3'd1 :
    (adpcm_step > 3'd0 && adpcm_2bit_sample[0] == 1'b0)?    adpcm_step - 3'd1 :
                                                            adpcm_step;

//------------------------------------------------------------------------------ adpcm 3 bit

wire [2:0] adpcm_3bit_sample = adpcm_sample[7:5];

wire [7:0] adpcm_3bit_reference_adjust =
    (adpcm_step[2:0] == 3'd0)?                                  { 6'd0, adpcm_3bit_sample[1:0] } :
    (adpcm_step[2:0] == 3'd1)?                                  { 5'd0, adpcm_3bit_sample[1:0], 1'b1 } :
    (adpcm_step[2:0] == 3'd2)?                                  { 4'd0, adpcm_3bit_sample[1:0], 2'b10 } :
    (adpcm_step[2:0] == 3'd3)?                                  { 3'd0, adpcm_3bit_sample[1:0], 3'b100 } :
    (adpcm_step[2:0] == 3'd4 && adpcm_3bit_sample == 3'd0)?     8'd5 :
    (adpcm_step[2:0] == 3'd4 && adpcm_3bit_sample == 3'd1)?     8'd15 :
    (adpcm_step[2:0] == 3'd4 && adpcm_3bit_sample == 3'd2)?     8'd25 :
                                                                8'd35;
    
wire [8:0] adpcm_3bit_reference_sum = adpcm_reference + adpcm_3bit_reference_adjust;
wire [8:0] adpcm_3bit_reference_sub = adpcm_reference - adpcm_3bit_reference_adjust;

wire [7:0] adpcm_3bit_reference_next =
    (adpcm_3bit_sample[2] && adpcm_3bit_reference_sub[8])?  8'd0 :
    (adpcm_3bit_sample[2])?                                 adpcm_3bit_reference_sub[7:0] :
    (adpcm_3bit_reference_sum[8])?                          8'd255 :
                                                            adpcm_3bit_reference_sum[7:0];
wire [2:0] adpcm_3bit_step_next =
    (adpcm_step < 3'd4 && adpcm_3bit_sample[1:0] == 2'b11)? adpcm_step + 3'd1 :
    (adpcm_step > 3'd0 && adpcm_3bit_sample[1:0] == 2'b00)? adpcm_step - 3'd1 :
                                                            adpcm_step;

//------------------------------------------------------------------------------ adpcm 4 bit

wire [3:0] adpcm_4bit_sample = adpcm_sample[7:4];

wire [7:0] adpcm_4bit_reference_adjust =
    (adpcm_step[2:0] == 3'd0)?      { 5'd0, adpcm_4bit_sample[2:0] } :
    (adpcm_step[2:0] == 3'd1)?      { 4'd0, adpcm_4bit_sample[2:0], 1'b1 } :
    (adpcm_step[2:0] == 3'd2)?      { 3'd0, adpcm_4bit_sample[2:0], 2'b10 } :
                                    { 2'd0, adpcm_4bit_sample[2:0], 3'b100 }; //adpcm_step[2:0] == 3'd3
    
wire [8:0] adpcm_4bit_reference_sum = adpcm_reference + adpcm_4bit_reference_adjust;
wire [8:0] adpcm_4bit_reference_sub = adpcm_reference - adpcm_4bit_reference_adjust;

wire [7:0] adpcm_4bit_reference_next =
    (adpcm_4bit_sample[3] && adpcm_4bit_reference_sub[8])?  8'd0 :
    (adpcm_4bit_sample[3])?                                 adpcm_4bit_reference_sub[7:0] :
    (adpcm_4bit_reference_sum[8])?                          8'd255 :
                                                            adpcm_4bit_reference_sum[7:0];
wire [2:0] adpcm_4bit_step_next =
    (adpcm_step < 3'd3 && adpcm_4bit_sample[2:0] >= 3'd5)?  adpcm_step + 3'd1 :
    (adpcm_step > 3'd0 && adpcm_4bit_sample[2:0] == 3'd0)?  adpcm_step - 3'd1 :
                                                            adpcm_step;

//------------------------------------------------------------------------------

wire [15:0] sample =
    (adpcm_reference_output)?   {adpcm_sample, adpcm_sample} :
    (adpcm_active)?             {adpcm_active_value, adpcm_active_value} :
                                {write_buffer[7:0], write_buffer[7:0]};

always @(posedge clk) begin
	if((~speaker_on & sbp) | pause_active) begin
		sample_value_l <= 0;
		sample_value_r <= 0;
	end
	else if(sample_output && adpcm_type == ADPCM_NONE) begin
		if(dma_format[2]) begin
			if(~sbp_lr) sample_value_l <= {sample_dma[0][15] ^ ~dma_format[0], sample_dma[0][14:0]};
			else        sample_value_r <= {sample_dma[0][15] ^ ~dma_format[0], sample_dma[0][14:0]};
		end
		else begin
			sample_value_l <= {            sample_dma[0][15] ^ ~dma_format[0],            sample_dma[0][14:0]};
			sample_value_r <= {sample_dma[dma_format[1]][15] ^ ~dma_format[0], sample_dma[dma_format[1]][14:0]};
		end
	end
	else if(cmd_direct_output | adpcm_active | (~adpcm_reference_awaiting & adpcm_reference_output)) begin
		sample_value_l <= {~sample[15], sample[14:0]};
		sample_value_r <= {~sample[15], sample[14:0]};
	end
end
	
//------------------------------------------------------------------------------

endmodule
