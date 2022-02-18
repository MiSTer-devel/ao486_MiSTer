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

module ps2
(
	input                   clk,
	input                   rst_n,

	output reg              irq_keyb,
	output reg              irq_mouse,

	input       [3:0]       io_address,
	input                   io_read,
	output reg  [7:0]       io_readdata,
	input                   io_write,
	input       [7:0]       io_writedata,

	input                   io_cs,  //0x60-0x67
	input                   ctl_cs, //0x90-0x9F

	//output port
	output reg              output_a20_enable,
	output reg              output_reset_n,

	output                  a20_enable,

	//ps2 keyboard
	input                   ps2_kbclk,
	input                   ps2_kbdat,
	output                  ps2_kbclk_out,
	output                  ps2_kbdat_out,

	//ps2 mouse
	input                   ps2_mouseclk,
	input                   ps2_mousedat,
	output                  ps2_mouseclk_out,
	output                  ps2_mousedat_out
);

wire io_m_read    = io_read  & io_cs;
wire io_m_write   = io_write & io_cs;
wire sysctl_write = io_write & ctl_cs;

always @(posedge clk) begin
    if(io_cs) io_readdata <= io_readdata_next;
    else      io_readdata <= sysctl_readdata_next;
end

//------------------------------------------------------------------------------

reg io_read_last;
always @(posedge clk) begin
	if(rst_n == 1'b0)     io_read_last <= 1'b0;
	else if(io_read_last) io_read_last <= 1'b0;
	else                  io_read_last <= io_m_read;
end
wire io_read_valid = io_m_read && ~io_read_last;

//------------------------------------------------------------------------------ io read

wire [7:0] io_readdata_next =
    (io_read_valid && io_address[2:0] == 3'd4)? {
        status_keyboardparityerror,
        status_timeout,
        ~(mouse_fifo_empty),
        1'b1, //keyboard inhibit
        status_lastcommand,
        status_system,
        status_inputbufferfull,
        status_outputbufferfull
    } :
    (status_mousebufferfull) ? mouse_fifo_q :
                               keyb_fifo_q_final;

//------------------------------------------------------------------------------ sysctl read

wire [7:0] sysctl_readdata_next =
    (io_address == 4'h2) ? { 6'd0, output_a20_enable, 1'b0 } :
                             8'hFF;


//------------------------------------------------------------------------------ output

assign a20_enable = output_a20_enable;

always @(posedge clk) begin
    if(rst_n == 1'b0)                           output_a20_enable <= 1'b1;
    else if(cmd_write_output_port)              output_a20_enable <= io_writedata[1];
    else if(cmd_disable_a20)                    output_a20_enable <= 1'b0;
    else if(cmd_enable_a20)                     output_a20_enable <= 1'b1;
    else if(sysctl_write && io_address == 4'h2) output_a20_enable <= io_writedata[1];
end

always @(posedge clk) begin
    if(rst_n == 1'b0)                           output_reset_n <= 1'b1;
    else if(cmd_write_output_port)              output_reset_n <= io_writedata[0];
    else if(cmd_reset)                          output_reset_n <= 1'b0;
    else if(sysctl_write && io_address == 4'h2) output_reset_n <= ~io_writedata[0];
end

//------------------------------------------------------------------------------

reg status_keyboardparityerror;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                       status_keyboardparityerror <= 1'b0;
    else if(keyb_recv_parity_err || mouse_recv_parity_err)  status_keyboardparityerror <= 1'b1;
    else if(io_read_valid && io_address[2:0] == 3'd4)       status_keyboardparityerror <= 1'b0;
end

reg status_timeout;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                   status_timeout <= 1'b0;
    else if(keyb_timeout_reset || mouse_timeout_reset)  status_timeout <= 1'b1;
    else if(io_read_valid && io_address[2:0] == 3'd4)   status_timeout <= 1'b0;
end

reg status_lastcommand;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                  status_lastcommand <= 1'b1;
    else if(io_m_write && io_address[2:0] == 3'd0)     status_lastcommand <= 1'b0;
    else if(io_m_write && io_address[2:0] == 3'd4)     status_lastcommand <= 1'b1;
end

reg translate;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   translate <= 1'b1;
    else if(cmd_write_command_byte)     translate <= io_writedata[6];
end

reg disable_mouse;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   disable_mouse <= 1'b0;
    else if(cmd_write_command_byte)     disable_mouse <= io_writedata[5];
    else if(cmd_disable_mouse)          disable_mouse <= 1'b1;
    else if(cmd_enable_mouse)           disable_mouse <= 1'b0;
    else if(write_to_mouse)             disable_mouse <= 1'b0;
end

reg disable_mouse_visible;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   disable_mouse_visible <= 1'b0;
    else if(cmd_write_command_byte)     disable_mouse_visible <= io_writedata[5];
    else if(cmd_disable_mouse)          disable_mouse_visible <= 1'b1;
    else if(cmd_enable_mouse)           disable_mouse_visible <= 1'b0;
end

reg disable_keyboard;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   disable_keyboard <= 1'b0;
    else if(cmd_write_command_byte)     disable_keyboard <= io_writedata[4];
    else if(cmd_disable_keyb)           disable_keyboard <= 1'b1;
    else if(cmd_enable_keyb)            disable_keyboard <= 1'b0;
    else if(write_to_keyb)              disable_keyboard <= 1'b0;
end

reg status_system;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   status_system <= 1'b0;
    else if(cmd_write_command_byte)     status_system <= io_writedata[2];
    else if(cmd_self_test)              status_system <= 1'b1;
end

reg allow_irq_mouse;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   allow_irq_mouse <= 1'b1;
    else if(cmd_write_command_byte)     allow_irq_mouse <= io_writedata[1];
end

reg allow_irq_keyb;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   allow_irq_keyb <= 1'b1;
    else if(cmd_write_command_byte)     allow_irq_keyb <= io_writedata[0];
end

//------------------------------------------------------------------------------ interrupts

always @(posedge clk) begin
    if(rst_n == 1'b0)                                                                                       irq_keyb <= 1'b0;
    else if(io_read_valid && io_address[2:0] == 3'd0 && status_outputbufferfull && ~(status_mousebufferfull))    irq_keyb <= 1'b0;
    else if(allow_irq_keyb && status_outputbufferfull && ~(status_mousebufferfull))                         irq_keyb <= 1'b1;
end

always @(posedge clk) begin
    if(rst_n == 1'b0)                                                           irq_mouse <= 1'b0;
    else if(io_read_valid && io_address[2:0] == 3'd0 && status_mousebufferfull) irq_mouse <= 1'b0;
    else if(allow_irq_mouse && status_mousebufferfull)                          irq_mouse <= 1'b1;
end

wire outputbuffer_idle = ~(status_mousebufferfull) && ~(status_outputbufferfull);

reg status_mousebufferfull;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                   status_mousebufferfull <= 1'b0;
    else if(io_read_valid && io_address[2:0] == 3'd0)   status_mousebufferfull <= 1'b0;
    else if(outputbuffer_idle && ~(mouse_fifo_empty))   status_mousebufferfull <= 1'b1;
end

reg status_outputbufferfull;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                           status_outputbufferfull <= 1'b0;
    else if(io_read_valid && io_address[2:0] == 3'd0)                           status_outputbufferfull <= 1'b0;
    else if(outputbuffer_idle && (~(mouse_fifo_empty) || ~(keyb_fifo_empty)))   status_outputbufferfull <= 1'b1;
end

//------------------------------------------------------------------------------ io write / controller commands

reg expecting_port_60h;
always @(posedge clk) begin
    if(rst_n == 1'b0)                              expecting_port_60h <= 1'b0;
    else if(io_m_write && io_address[2:0] == 3'd0) expecting_port_60h <= 1'b0;
    else if(cmd_with_param_first_byte)             expecting_port_60h <= 1'b1;
    else if(io_m_write && io_address[2:0] == 3'd4) expecting_port_60h <= 1'b0;
end

reg [7:0] last_command;
always @(posedge clk) begin
    if(rst_n == 1'b0)                              last_command <= 8'h00;
    else if(io_m_write && io_address[2:0] == 3'd4) last_command <= io_writedata;
end

wire cmd_with_param_first_byte  = io_m_write && io_address[2:0] == 3'd4 && (
    io_writedata == 8'h60 || //write command byte
    io_writedata == 8'hCB || //write keyboard controller mode
    io_writedata == 8'hD1 || //write output port
    io_writedata == 8'hD3 || //write mouse output port
    io_writedata == 8'hD4 || //write to mouse
    io_writedata == 8'hD2    //write keyboard output buffer
);

wire cmd_with_param             = io_m_write && io_address[2:0] == 3'd0 && expecting_port_60h && ~(status_inputbufferfull);
wire cmd_without_param          = io_m_write && io_address[2:0] == 3'd4 && ~(cmd_with_param_first_byte);

wire cmd_write_command_byte     = cmd_with_param && last_command == 8'h60;
wire cmd_write_output_port      = cmd_with_param && last_command == 8'hD1;
wire cmd_write_to_keyb_output   = cmd_with_param && last_command == 8'hD2;
wire cmd_write_to_mouse_output  = cmd_with_param && last_command == 8'hD3;
wire cmd_write_to_mouse         = cmd_with_param && last_command == 8'hD4;

wire cmd_read_command_byte      = cmd_without_param && io_writedata == 8'h20;
wire cmd_disable_mouse          = cmd_without_param && io_writedata == 8'hA7;
wire cmd_enable_mouse           = cmd_without_param && io_writedata == 8'hA8;
wire cmd_test_mouse_port        = cmd_without_param && io_writedata == 8'hA9;
wire cmd_self_test              = cmd_without_param && io_writedata == 8'hAA;
wire cmd_interface_test         = cmd_without_param && io_writedata == 8'hAB;
wire cmd_disable_keyb           = cmd_without_param && io_writedata == 8'hAD;
wire cmd_enable_keyb            = cmd_without_param && io_writedata == 8'hAE;
wire cmd_read_input_port        = cmd_without_param && io_writedata == 8'hC0;
wire cmd_read_controller_mode   = cmd_without_param && io_writedata == 8'hCA;
wire cmd_read_output_port       = cmd_without_param && io_writedata == 8'hD0;
wire cmd_disable_a20            = cmd_without_param && io_writedata == 8'hDD;
wire cmd_enable_a20             = cmd_without_param && io_writedata == 8'hDF;
wire cmd_reset                  = cmd_without_param && io_writedata == 8'hFE;

//------------------------------------------------------------------------------ controller reply - not device

wire [7:0] command_byte = {
    1'b0,
    translate,
    disable_mouse_visible,
    disable_keyboard,
    1'b0,
    status_system,
    allow_irq_mouse,
    allow_irq_keyb
};

wire [7:0] output_port = {
    1'b0,
    1'b0,
    irq_mouse,
    irq_keyb,
    1'b0,
    1'b0,
    output_a20_enable,
    1'b1
};

reg [7:0] keyb_reply;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   keyb_reply <= 8'h00;
    else if(cmd_write_to_keyb_output)   keyb_reply <= io_writedata;
    else if(cmd_read_command_byte)      keyb_reply <= command_byte;
    else if(cmd_test_mouse_port)        keyb_reply <= 8'h00;
    else if(cmd_self_test)              keyb_reply <= 8'h55;
    else if(cmd_interface_test)         keyb_reply <= 8'h00;
    else if(cmd_read_input_port)        keyb_reply <= 8'h80;
    else if(cmd_read_controller_mode)   keyb_reply <= 8'h01;
    else if(cmd_read_output_port)       keyb_reply <= output_port;
end

reg keyb_reply_valid;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   keyb_reply_valid <= 1'b0;
    else if(cmd_write_to_keyb_output)   keyb_reply_valid <= 1'b1;
    else if(cmd_read_command_byte)      keyb_reply_valid <= 1'b1;
    else if(cmd_test_mouse_port)        keyb_reply_valid <= 1'b1;
    else if(cmd_self_test)              keyb_reply_valid <= 1'b1;
    else if(cmd_interface_test)         keyb_reply_valid <= 1'b1;
    else if(cmd_read_input_port)        keyb_reply_valid <= 1'b1;
    else if(cmd_read_controller_mode)   keyb_reply_valid <= 1'b1;
    else if(cmd_read_output_port)       keyb_reply_valid <= 1'b1;
    else if(ps2_kb_reply_done)          keyb_reply_valid <= 1'b0;
end

reg [7:0] mouse_reply;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   mouse_reply <= 8'd0;
    else if(cmd_write_to_mouse_output)  mouse_reply <= io_writedata;
end

reg mouse_reply_valid;
always @(posedge clk) begin
    if(rst_n == 1'b0)                   mouse_reply_valid <= 1'b0;
    else if(cmd_write_to_mouse_output)  mouse_reply_valid <= 1'b1;
    else if(ps2_mouse_reply_done)       mouse_reply_valid <= 1'b0;
end

//------------------------------------------------------------------------------ write to device

wire write_to_keyb  = io_m_write && io_address[2:0] == 3'd0 && ~(expecting_port_60h) && ~(status_inputbufferfull);
wire write_to_mouse = cmd_write_to_mouse;

reg status_inputbufferfull;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                       status_inputbufferfull <= 1'b0;
    else if(write_to_keyb || write_to_mouse)                status_inputbufferfull <= 1'b1;
    else if(input_write_done && status_outputbufferfull)    status_inputbufferfull <= 1'b0;
end

reg input_write_done;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                   input_write_done <= 1'b0;
    else if(write_to_keyb || write_to_mouse)            input_write_done <= 1'b0;
    else if(ps2_kb_write_done || ps2_mouse_write_done)  input_write_done <= 1'b1;
end

reg input_for_mouse;
always @(posedge clk) begin
    if(rst_n == 1'b0)       input_for_mouse <= 1'b0;
    else if(write_to_keyb)  input_for_mouse <= 1'b0;
    else if(write_to_mouse) input_for_mouse <= 1'b1;
end

reg [7:0] inputbuffer;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                       inputbuffer <= 8'd0;
    else if(write_to_keyb || write_to_mouse)                inputbuffer <= io_writedata;
    else if(ps2_kb_write_shift || ps2_mouse_write_shift)    inputbuffer <= { 1'b0, inputbuffer[7:1] };
end

//------------------------------------------------------------------------------ ps/2 for keyboard

assign ps2_kbclk_out = ~ps2_kbclk_ena;
assign ps2_kbdat_out = ~ps2_kbdat_ena | ps2_kbdat_host;

reg ps2_kbclk_ena;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                               ps2_kbclk_ena <= 1'b0;
    else if(keyb_timeout_reset)                                                     ps2_kbclk_ena <= 1'b0;
    else if(keyb_state == PS2_SEND_INHIBIT || keyb_state == PS2_WAIT_START)         ps2_kbclk_ena <= 1'b1;
    else if(keyb_state == PS2_SEND_CLOCK_RELEASE || keyb_state == PS2_WAIT_FINISH)  ps2_kbclk_ena <= 1'b0;
end

reg ps2_kbdat_ena;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                           ps2_kbdat_ena <= 1'b0;
    else if(keyb_timeout_reset)                                 ps2_kbdat_ena <= 1'b0;
    else if(keyb_state == PS2_SEND_DATA_LOW)                    ps2_kbdat_ena <= 1'b1;
    else if(ps2_kb_write_shift && keyb_bit_counter == 4'd9)     ps2_kbdat_ena <= 1'b0;  //stop bit
end

reg ps2_kbdat_host;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                       ps2_kbdat_host <= 1'b0;
    else if(keyb_state == PS2_SEND_DATA_LOW)                ps2_kbdat_host <= 1'b0;              //start bit
    else if(ps2_kb_write_shift && keyb_bit_counter < 4'd8)  ps2_kbdat_host <= inputbuffer[0];    //data bits
    else if(ps2_kb_write_shift && keyb_bit_counter == 4'd8) ps2_kbdat_host <= ~(keyb_parity);    //parity bit
end

reg [15:0] keyb_clk_mv;
reg keyb_clk_mv_wait;
reg was_ps2_kbclk;
always @(posedge clk) begin
    if(rst_n == 1'b0) begin
        keyb_clk_mv         <= 16'd0;
        keyb_clk_mv_wait    <= 1'b0;
        was_ps2_kbclk       <= 1'b0;
    end
    else begin
        keyb_clk_mv <= { keyb_clk_mv[14:0], keyb_kbclk };
    
        if(keyb_clk_mv_wait == 1'b0 && keyb_clk_mv[15:12] == 4'b1111 && keyb_clk_mv[3:0] == 4'b0000) begin
            was_ps2_kbclk <= 1'b1;
            keyb_clk_mv_wait <= 1'b1;
        end
        else if(keyb_clk_mv_wait == 1'b1 && keyb_clk_mv[15:0] == 16'h0000) begin
            keyb_clk_mv_wait <= 1'b0;
            was_ps2_kbclk <= 1'b0;
        end
        else begin
            was_ps2_kbclk <= 1'b0;
        end
    end
end

reg keyb_kbclk;
always @(posedge clk) begin
    if(rst_n == 1'b0)   keyb_kbclk <= 1'b1;
    else                keyb_kbclk <= ps2_kbclk;
end    

reg keyb_kbdat;
always @(posedge clk) begin
    if(rst_n == 1'b0)   keyb_kbdat <= 1'b1;
    else                keyb_kbdat <= ps2_kbdat;
end    

reg [25:0] keyb_timeout;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                       keyb_timeout <= 26'h0;
    else if(keyb_state == PS2_SEND_INHIBIT || keyb_state == PS2_RECV_START) keyb_timeout <= 26'h3FFFFFF;
    else if(keyb_state == PS2_IDLE)                                         keyb_timeout <= 26'h0;
    else if(keyb_timeout > 26'd0)                                           keyb_timeout <= keyb_timeout - 26'd1;
end

wire keyb_timeout_reset = keyb_timeout == 26'd1;

reg [12:0] keyb_timer;
always @(posedge clk) begin
    if(rst_n == 1'b0)                           keyb_timer <= 13'd0;
    else if(keyb_timeout_reset)                 keyb_timer <= 13'd0;                  
    
    else if(keyb_state == PS2_SEND_INHIBIT)     keyb_timer <= 13'd8191;
    else if(keyb_state == PS2_WAIT_START)       keyb_timer <= 13'd8191;
    
    else if(keyb_timer > 13'd0)                 keyb_timer <= keyb_timer - 13'd1;
end

reg [3:0] keyb_bit_counter;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               keyb_bit_counter <= 4'd0;
    else if(keyb_timeout_reset)                     keyb_bit_counter <= 4'd0;
    
    else if(keyb_state == PS2_SEND_CLOCK_RELEASE)   keyb_bit_counter <= 4'd0;
    else if(ps2_kb_write_shift)                     keyb_bit_counter <= keyb_bit_counter + 4'd1;
    
    else if(keyb_state == PS2_RECV_START)           keyb_bit_counter <= 4'd0;
    else if(keyb_recv)                              keyb_bit_counter <= keyb_bit_counter + 4'd1;
end

reg keyb_parity;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               keyb_parity <= 1'b0;
    
    else if(keyb_state == PS2_SEND_CLOCK_RELEASE)   keyb_parity <= 1'b0;
    else if(ps2_kb_write_shift)                     keyb_parity <= keyb_parity ^ inputbuffer[0];
    
    else if(keyb_state == PS2_RECV_START)           keyb_parity <= 1'b0;
    else if(keyb_recv)                              keyb_parity <= keyb_parity ^ keyb_kbdat;
end

reg [7:0] keyb_recv_buffer;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               keyb_recv_buffer <= 8'd0;
    else if(keyb_recv && keyb_bit_counter < 4'd8)   keyb_recv_buffer <= { keyb_kbdat, keyb_recv_buffer[7:1] };
end

wire keyb_recv              = keyb_state == PS2_RECV_BITS && was_ps2_kbclk;
wire keyb_recv_ok           = keyb_recv && keyb_bit_counter == 4'd8 && ~(keyb_parity) == keyb_kbdat;
wire keyb_recv_parity_err   = keyb_recv && keyb_bit_counter == 4'd8 && ~(keyb_parity) != keyb_kbdat;

reg keyb_recv_result;
always @(posedge clk) begin
    if(rst_n == 1'b0)                      keyb_recv_result <= 1'b0;
    else if(keyb_state == PS2_RECV_BITS)   keyb_recv_result <= keyb_recv_ok;
end
wire keyb_recv_final = keyb_state == PS2_RECV_WAIT_FOR_IDLE && keyb_kbclk == 1'b1 && keyb_kbdat == 1'b1 && keyb_recv_result;

reg keyb_translate_escape;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                       keyb_translate_escape <= 1'b0;
    else if(keyb_timeout_reset)                             keyb_translate_escape <= 1'b0;
    else if(keyb_recv_ok && keyb_translate_escape == 1'b0)  keyb_translate_escape <= translate && keyb_recv_buffer == 8'hF0;
    else if(keyb_recv_final && keyb_recv_buffer != 8'hF0)   keyb_translate_escape <= 1'b0;
end
  
localparam [3:0] PS2_IDLE                   = 4'd0;

localparam [3:0] PS2_SEND_INHIBIT           = 4'd1;
localparam [3:0] PS2_SEND_INHIBIT_WAIT      = 4'd2;
localparam [3:0] PS2_SEND_DATA_LOW          = 4'd3;
localparam [3:0] PS2_SEND_CLOCK_RELEASE     = 4'd4;
localparam [3:0] PS2_SEND_BITS              = 4'd5;
localparam [3:0] PS2_SEND_WAIT_FOR_ACK      = 4'd6;
localparam [3:0] PS2_SEND_WAIT_FOR_IDLE     = 4'd7;
localparam [3:0] PS2_SEND_FINISHED          = 4'd8;

localparam [3:0] PS2_RECV_START             = 4'd9;
localparam [3:0] PS2_RECV_BITS              = 4'd10;
localparam [3:0] PS2_RECV_WAIT_FOR_STOP     = 4'd11;
localparam [3:0] PS2_RECV_WAIT_FOR_IDLE     = 4'd12;

localparam [3:0] PS2_WAIT_START             = 4'd13;
localparam [3:0] PS2_WAIT                   = 4'd14;
localparam [3:0] PS2_WAIT_FINISH            = 4'd15;

reg [3:0] keyb_state;

always @(posedge clk) begin
    if(rst_n == 1'b0)                                                                                               keyb_state <= PS2_IDLE;
    else if(keyb_timeout_reset)                                                                                     keyb_state <= PS2_IDLE;
    
    //buffer full
    else if(keyb_state == PS2_IDLE && (keyb_fifo_counter >= 7'd60 || disable_keyboard))                                                                     keyb_state <= PS2_WAIT_START;
    else if(keyb_state == PS2_WAIT_START)                                                                                                                   keyb_state <= PS2_WAIT;
    else if(keyb_state == PS2_WAIT && keyb_timer == 13'd1 && status_inputbufferfull && ~(input_write_done) && ~(input_for_mouse) && ~(disable_keyboard))    keyb_state <= PS2_SEND_INHIBIT;
    else if(keyb_state == PS2_WAIT && keyb_timer == 13'd1 && (keyb_fifo_counter >= 7'd60 || disable_keyboard))                                              keyb_state <= PS2_WAIT_START;
    else if(keyb_state == PS2_WAIT && keyb_timer == 13'd1)                                                                                                  keyb_state <= PS2_WAIT_FINISH;
    else if(keyb_state == PS2_WAIT_FINISH)                                                                                                                  keyb_state <= PS2_IDLE;
    
    //send
    else if(keyb_state == PS2_IDLE && status_inputbufferfull && ~(input_write_done) && ~(input_for_mouse))  keyb_state <= PS2_SEND_INHIBIT;
    else if(keyb_state == PS2_SEND_INHIBIT)                                                                 keyb_state <= PS2_SEND_INHIBIT_WAIT;
    else if(keyb_state == PS2_SEND_INHIBIT_WAIT && keyb_timer == 13'd8)                                     keyb_state <= PS2_SEND_DATA_LOW;
    else if(keyb_state == PS2_SEND_DATA_LOW)                                                                keyb_state <= PS2_SEND_INHIBIT_WAIT;
    else if(keyb_state == PS2_SEND_INHIBIT_WAIT && keyb_timer == 13'd1)                                     keyb_state <= PS2_SEND_CLOCK_RELEASE;
    else if(keyb_state == PS2_SEND_CLOCK_RELEASE)                                                           keyb_state <= PS2_SEND_BITS;
    else if(keyb_state == PS2_SEND_BITS && ps2_kb_write_shift && keyb_bit_counter == 4'd9)                  keyb_state <= PS2_SEND_WAIT_FOR_ACK;
    else if(keyb_state == PS2_SEND_WAIT_FOR_ACK && was_ps2_kbclk && keyb_kbdat == 1'b0)                     keyb_state <= PS2_SEND_WAIT_FOR_IDLE;
    else if(keyb_state == PS2_SEND_WAIT_FOR_IDLE && keyb_kbclk == 1'b1 && keyb_kbdat == 1'b1)               keyb_state <= PS2_SEND_FINISHED;
    else if(keyb_state == PS2_SEND_FINISHED)                                                                keyb_state <= PS2_IDLE;
    
    //recv
    else if(keyb_state == PS2_IDLE && was_ps2_kbclk && keyb_kbdat == 1'b0)                          keyb_state <= PS2_RECV_START;
    else if(keyb_state == PS2_RECV_START)                                                           keyb_state <= PS2_RECV_BITS;
    else if(keyb_state == PS2_RECV_BITS && (keyb_recv_ok || keyb_recv_parity_err))                  keyb_state <= PS2_RECV_WAIT_FOR_STOP;
    else if(keyb_state == PS2_RECV_WAIT_FOR_STOP && was_ps2_kbclk && keyb_kbdat == 1'b1)            keyb_state <= PS2_RECV_WAIT_FOR_IDLE;
    else if(keyb_state == PS2_RECV_WAIT_FOR_IDLE && keyb_kbclk == 1'b1 && keyb_kbdat == 1'b1)       keyb_state <= PS2_IDLE;
end

wire [6:0]  keyb_fifo_counter = { keyb_fifo_full, keyb_fifo_usedw };
wire        keyb_fifo_full;
wire [5:0]  keyb_fifo_usedw;

wire [7:0]  keyb_fifo_q;
wire        keyb_fifo_empty;

wire [7:0] keyb_fifo_q_final = (keyb_fifo_empty)? keyb_fifo_q_last : keyb_fifo_q;

reg [7:0] keyb_fifo_q_last;
always @(posedge clk) begin
    if(rst_n == 1'b0)           keyb_fifo_q_last <= 8'd0;
    else if(~(keyb_fifo_empty)) keyb_fifo_q_last <= keyb_fifo_q;
end

wire ps2_kb_write_shift = keyb_state == PS2_SEND_BITS && was_ps2_kbclk;

wire ps2_kb_write_done = keyb_state == PS2_SEND_FINISHED;

wire ps2_kb_reply_done = keyb_reply_valid && keyb_fifo_counter < 7'd60 && ~(keyb_recv_final);

simple_fifo #(
    .width      (8),
    .widthu     (6)
)
keyb_fifo(
    .clk        (clk),
    .rst_n      (rst_n),
    
    .sclr       (cmd_self_test),                                                                                                //input
    
    .wrreq      (ps2_kb_reply_done || (keyb_recv_final && (~(translate) || keyb_recv_buffer != 8'hF0))),                        //input
	 .data       ((ps2_kb_reply_done)? keyb_reply : (translate)? ({ keyb_translate_escape, 7'd0 } | keyb_recv_buffer) : keyb_recv_buffer),  //input [7:0]
    .full       (keyb_fifo_full),                                                                                               //output
    .usedw      (keyb_fifo_usedw),                                                                                              //output [5:0]
    
    .rdreq      (io_read_valid && io_address[2:0] == 3'd0 && status_outputbufferfull && ~(status_mousebufferfull)),                  //input
    .q          (keyb_fifo_q),                                                                                                  //output [7:0]
    .empty      (keyb_fifo_empty)                                                                                               //output
);

//------------------------------------------------------------------------------ ps/2 for mouse

assign ps2_mouseclk_out    = ~ps2_mouseclk_ena;
assign ps2_mousedat_out    = ~ps2_mousedat_ena | ps2_mousedat_host;

reg ps2_mouseclk_ena;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                                   ps2_mouseclk_ena <= 1'b0;
    else if(mouse_timeout_reset)                                                        ps2_mouseclk_ena <= 1'b0;
    else if(mouse_state == PS2_SEND_INHIBIT || mouse_state == PS2_WAIT_START)           ps2_mouseclk_ena <= 1'b1;
    else if(mouse_state == PS2_SEND_CLOCK_RELEASE || mouse_state == PS2_WAIT_FINISH)    ps2_mouseclk_ena <= 1'b0;
end

reg ps2_mousedat_ena;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                               ps2_mousedat_ena <= 1'b0;
    else if(mouse_timeout_reset)                                    ps2_mousedat_ena <= 1'b0;
    else if(mouse_state == PS2_SEND_DATA_LOW)                       ps2_mousedat_ena <= 1'b1;
    else if(ps2_mouse_write_shift && mouse_bit_counter == 4'd9)     ps2_mousedat_ena <= 1'b0;  //stop bit
end

reg ps2_mousedat_host;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                           ps2_mousedat_host <= 1'b0;
    else if(mouse_state == PS2_SEND_DATA_LOW)                   ps2_mousedat_host <= 1'b0;               //start bit
    else if(ps2_mouse_write_shift && mouse_bit_counter < 4'd8)  ps2_mousedat_host <= inputbuffer[0];     //data bits
    else if(ps2_mouse_write_shift && mouse_bit_counter == 4'd8) ps2_mousedat_host <= ~(mouse_parity);    //parity bit
end

reg [15:0] mouse_clk_mv;
reg mouse_clk_mv_wait;
reg was_ps2_mouseclk;
always @(posedge clk) begin
    if(rst_n == 1'b0) begin
        mouse_clk_mv         <= 16'd0;
        mouse_clk_mv_wait    <= 1'b0;
        was_ps2_mouseclk       <= 1'b0;
    end
    else begin
        mouse_clk_mv <= { mouse_clk_mv[14:0], mouse_mouseclk };
    
        if(mouse_clk_mv_wait == 1'b0 && mouse_clk_mv[15:12] == 4'b1111 && mouse_clk_mv[3:0] == 4'b0000) begin
            was_ps2_mouseclk <= 1'b1;
            mouse_clk_mv_wait <= 1'b1;
        end
        else if(mouse_clk_mv_wait == 1'b1 && mouse_clk_mv[15:0] == 16'h0000) begin
            mouse_clk_mv_wait <= 1'b0;
            was_ps2_mouseclk <= 1'b0;
        end
        else begin
            was_ps2_mouseclk <= 1'b0;
        end
    end
end

reg mouse_mouseclk;
always @(posedge clk) begin
    if(rst_n == 1'b0)   mouse_mouseclk <= 1'b1;
    else                mouse_mouseclk <= ps2_mouseclk;
end    

reg mouse_mousedat;
always @(posedge clk) begin
    if(rst_n == 1'b0)   mouse_mousedat <= 1'b1;
    else                mouse_mousedat <= ps2_mousedat;
end

reg [25:0] mouse_timeout;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                           mouse_timeout <= 26'h0;
    else if(mouse_state == PS2_SEND_INHIBIT || mouse_state == PS2_RECV_START)   mouse_timeout <= 26'h3FFFFFF;
    else if(mouse_state == PS2_IDLE)                                            mouse_timeout <= 26'h0;
    else if(mouse_timeout > 26'd0)                                              mouse_timeout <= mouse_timeout - 26'd1;
end

wire mouse_timeout_reset = mouse_timeout == 26'd1;

reg [12:0] mouse_timer;
always @(posedge clk) begin
    if(rst_n == 1'b0)                           mouse_timer <= 13'd0;
    else if(mouse_timeout_reset)                mouse_timer <= 13'd0;
    else if(mouse_state == PS2_SEND_INHIBIT)    mouse_timer <= 13'd8191;
    else if(mouse_state == PS2_WAIT_START)      mouse_timer <= 13'd8191;
    
    else if(mouse_timer > 13'd0)                mouse_timer <= mouse_timer - 13'd1;
end

reg [3:0] mouse_bit_counter;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               mouse_bit_counter <= 4'd0;
    else if(mouse_timeout_reset)                    mouse_bit_counter <= 4'd0;
    
    else if(mouse_state == PS2_SEND_CLOCK_RELEASE)  mouse_bit_counter <= 4'd0;
    else if(ps2_mouse_write_shift)                  mouse_bit_counter <= mouse_bit_counter + 4'd1;
    
    else if(mouse_state == PS2_RECV_START)          mouse_bit_counter <= 4'd0;
    else if(mouse_recv)                             mouse_bit_counter <= mouse_bit_counter + 4'd1;
end

reg mouse_parity;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               mouse_parity <= 1'b0;
    
    else if(mouse_state == PS2_SEND_CLOCK_RELEASE)  mouse_parity <= 1'b0;
    else if(ps2_mouse_write_shift)                  mouse_parity <= mouse_parity ^ inputbuffer[0];
    
    else if(mouse_state == PS2_RECV_START)          mouse_parity <= 1'b0;
    else if(mouse_recv)                             mouse_parity <= mouse_parity ^ mouse_mousedat;
end

reg [7:0] mouse_recv_buffer;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               mouse_recv_buffer <= 8'd0;
    else if(mouse_recv && mouse_bit_counter < 4'd8) mouse_recv_buffer <= { mouse_mousedat, mouse_recv_buffer[7:1] };
end

wire mouse_recv              = mouse_state == PS2_RECV_BITS && was_ps2_mouseclk;
wire mouse_recv_ok           = mouse_recv && mouse_bit_counter == 4'd8 && ~(mouse_parity) == mouse_mousedat;
wire mouse_recv_parity_err   = mouse_recv && mouse_bit_counter == 4'd8 && ~(mouse_parity) != mouse_mousedat;

reg mouse_recv_result;
always @(posedge clk) begin
    if(rst_n == 1'b0)                       mouse_recv_result <= 1'b0;
    else if(mouse_state == PS2_RECV_BITS)   mouse_recv_result <= mouse_recv_ok;
end
wire mouse_recv_final = mouse_state == PS2_RECV_WAIT_FOR_IDLE && mouse_mouseclk == 1'b1 && mouse_mousedat == 1'b1 && mouse_recv_result;

reg [3:0] mouse_state;

always @(posedge clk) begin
    if(rst_n == 1'b0)                                                                                                       mouse_state <= PS2_IDLE;
    else if(mouse_timeout_reset)                                                                                            mouse_state <= PS2_IDLE;
    
    //buffer full
    else if(mouse_state == PS2_IDLE && (mouse_fifo_counter >= 7'd60 || disable_mouse))                                                                  mouse_state <= PS2_WAIT_START;
    else if(mouse_state == PS2_WAIT_START)                                                                                                              mouse_state <= PS2_WAIT;
    else if(mouse_state == PS2_WAIT && mouse_timer == 13'd1 && status_inputbufferfull && ~(input_write_done) && input_for_mouse && ~(disable_mouse))    mouse_state <= PS2_SEND_INHIBIT;
    else if(mouse_state == PS2_WAIT && mouse_timer == 13'd1 && (mouse_fifo_counter >= 7'd60 || disable_mouse))                                          mouse_state <= PS2_WAIT_START;
    else if(mouse_state == PS2_WAIT && mouse_timer == 13'd1)                                                                                            mouse_state <= PS2_WAIT_FINISH;
    else if(mouse_state == PS2_WAIT_FINISH)                                                                                                             mouse_state <= PS2_IDLE;

    //send
    else if(mouse_state == PS2_IDLE && status_inputbufferfull && ~(input_write_done) && input_for_mouse)    mouse_state <= PS2_SEND_INHIBIT;
    else if(mouse_state == PS2_SEND_INHIBIT)                                                                mouse_state <= PS2_SEND_INHIBIT_WAIT;
    else if(mouse_state == PS2_SEND_INHIBIT_WAIT && mouse_timer == 13'd8)                                   mouse_state <= PS2_SEND_DATA_LOW;
    else if(mouse_state == PS2_SEND_DATA_LOW)                                                               mouse_state <= PS2_SEND_INHIBIT_WAIT;
    else if(mouse_state == PS2_SEND_INHIBIT_WAIT && mouse_timer == 13'd1)                                   mouse_state <= PS2_SEND_CLOCK_RELEASE;
    else if(mouse_state == PS2_SEND_CLOCK_RELEASE)                                                          mouse_state <= PS2_SEND_BITS;
    else if(mouse_state == PS2_SEND_BITS && ps2_mouse_write_shift && mouse_bit_counter == 4'd9)             mouse_state <= PS2_SEND_WAIT_FOR_ACK;
    else if(mouse_state == PS2_SEND_WAIT_FOR_ACK && was_ps2_mouseclk && mouse_mousedat == 1'b0)             mouse_state <= PS2_SEND_WAIT_FOR_IDLE;
    else if(mouse_state == PS2_SEND_WAIT_FOR_IDLE && mouse_mouseclk == 1'b1 && mouse_mousedat == 1'b1)      mouse_state <= PS2_SEND_FINISHED;
    else if(mouse_state == PS2_SEND_FINISHED)                                                               mouse_state <= PS2_IDLE;

    //recv
    else if(mouse_state == PS2_IDLE && was_ps2_mouseclk && mouse_mousedat == 1'b0)                      mouse_state <= PS2_RECV_START;
    else if(mouse_state == PS2_RECV_START)                                                              mouse_state <= PS2_RECV_BITS;
    else if(mouse_state == PS2_RECV_BITS && (mouse_recv_ok || mouse_recv_parity_err))                   mouse_state <= PS2_RECV_WAIT_FOR_STOP;
    else if(mouse_state == PS2_RECV_WAIT_FOR_STOP && was_ps2_mouseclk && mouse_mousedat == 1'b1)        mouse_state <= PS2_RECV_WAIT_FOR_IDLE;
    else if(mouse_state == PS2_RECV_WAIT_FOR_IDLE && mouse_mouseclk == 1'b1 && mouse_mousedat == 1'b1)  mouse_state <= PS2_IDLE;
end

wire [6:0]  mouse_fifo_counter = { mouse_fifo_full, mouse_fifo_usedw };
wire        mouse_fifo_full;
wire [5:0]  mouse_fifo_usedw;

wire [7:0]  mouse_fifo_q;
wire        mouse_fifo_empty;

wire ps2_mouse_write_shift = mouse_state == PS2_SEND_BITS && was_ps2_mouseclk;

wire ps2_mouse_write_done = mouse_state == PS2_SEND_FINISHED;

wire ps2_mouse_reply_done = mouse_reply_valid && mouse_fifo_counter < 7'd60 && ~(mouse_recv_final);

simple_fifo #(
    .width      (8),
    .widthu     (6)
)
mouse_fifo(
    .clk        (clk),
    .rst_n      (rst_n),
    
    .sclr       (cmd_self_test),                                                //input
    
    .wrreq      (ps2_mouse_reply_done || mouse_recv_final),                     //input
    .data       ((ps2_mouse_reply_done)? mouse_reply : mouse_recv_buffer),      //input [7:0]
    .full       (mouse_fifo_full),                                              //output
    .usedw      (mouse_fifo_usedw),                                             //output [5:0]
    
    .rdreq      (io_read_valid && io_address[2:0] == 3'd0 && status_mousebufferfull),//input
    .q          (mouse_fifo_q),                                                 //output [7:0]
    .empty      (mouse_fifo_empty)                                              //output
);


//------------------------------------------------------------------------------

endmodule
