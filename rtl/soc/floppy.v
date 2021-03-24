/*
 * Copyright (c) 2014, Aleksander Osman
 * Copyright (c) 2020, Alexey Melnikov
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

module floppy
(
	input             clk,
	input             rst_n,

	//dma
	output            dma_req,
	input             dma_ack,
	input             dma_tc,
	input       [7:0] dma_readdata,
	output      [7:0] dma_writedata,

	//irq
	output reg        irq,

	//io buf
	input       [2:0] io_address,
	input             io_read,
	output reg  [7:0] io_readdata,
	input             io_write,
	input       [7:0] io_writedata,

	output            fdd0_inserted,
	//management
	/*
	0x00.[0]:      media present
	0x01.[0]:      media writeprotect
	0x02.[7:0]:    media cylinders
	0x03.[7:0]:    media sectors per track
	0x04.[31:0]:   media total sector count
	0x05.[1:0]:    media heads
	*/
	input       [3:0] mgmt_address,
	input             mgmt_fddn,
	input             mgmt_write,
	input      [15:0] mgmt_writedata,
	input             mgmt_read,
	output     [15:0] mgmt_readdata,
	
	input       [1:0] wp,

	input      [27:0] clock_rate,

	output      [1:0] request
);

reg [27:0] clk_rate;
always @(posedge clk) clk_rate <= clock_rate;

//------------------------------------------------------------------------------ media management

assign mgmt_readdata = (!mgmt_address) ? {selected_drive[0], sd_sector[14:0]} : (&mgmt_address) ? fifo_readdata : 16'd1;
assign request = (state == S_SD_READ_WAIT_FOR_DATA || state == S_SD_WRITE_WAIT_FOR_EMPTY_FIFO || state == S_SD_FORMAT_WAIT_FOR_FILL) ?
					{cmd_write_normal_in_progress | cmd_format_in_progress, cmd_read_normal_in_progress} : 2'b00;

reg media_present[2];
always @(posedge clk) if(mgmt_write && mgmt_address == 4'd0) media_present[mgmt_fddn] <= mgmt_writedata[0];

assign fdd0_inserted = media_present[0];

reg [1:0] wp_sys;
always @(posedge clk) if(mgmt_write && mgmt_address == 4'd1) wp_sys[mgmt_fddn] <= mgmt_writedata[0];
wire [1:0] media_writeprotected = wp_sys | wp;

(* ramstyle = "logic" *) reg [7:0] media_cylinders[2];
always @(posedge clk) if(mgmt_write && mgmt_address == 4'd2) media_cylinders[mgmt_fddn] <= mgmt_writedata[7:0];

(* ramstyle = "logic" *) reg [7:0] media_sectors_per_track[2];
always @(posedge clk) if(mgmt_write && mgmt_address == 4'd3) media_sectors_per_track[mgmt_fddn] <= mgmt_writedata[7:0];

(* ramstyle = "logic" *) reg [15:0] media_sector_count[2];
always @(posedge clk) if(mgmt_write && mgmt_address == 4'd4 && ~mgmt_fddn) media_sector_count[0] <= mgmt_writedata;
always @(posedge clk) if(mgmt_write && mgmt_address == 4'd4 &&  mgmt_fddn) media_sector_count[1] <= mgmt_writedata;

(* ramstyle = "logic" *) reg [1:0] media_heads[2];
always @(posedge clk) if(mgmt_write && mgmt_address == 4'd5) media_heads[mgmt_fddn] <= mgmt_writedata[1:0];

wire fifo_read  = mgmt_read  && &mgmt_address;
wire fifo_write = mgmt_write && &mgmt_address;

//------------------------------------------------------------------------------ io read

wire ndma_read  = io_read  && io_address == 3'd5 && execute_ndma && cmd_read_normal_in_progress;
wire ndma_write = io_write && io_address == 3'd5 && execute_ndma && (cmd_write_normal_in_progress || cmd_format_in_progress);

wire [7:0] io_readdata_prepare =
    (io_address == 3'd2) ? { 2'b0, motor_enable[1], motor_enable[0], dma_irq_enable, enable, selected_drive } : //digital output register
    (io_address == 3'd4) ? { datareg_ready, transfer_to_cpu, execute_ndma, busy, in_seek_mode } :  //main status reg
    (ndma_read)          ? fifo_q :
    (io_address == 3'd5) ? reply[7:0] :
    (io_address == 3'd7) ? { change[selected_drive[0]], 7'h7F } :
                           8'd0;

always @(posedge clk) io_readdata <= io_readdata_prepare;

//------------------------------------------------------------------------------

wire sw_reset = 
	(io_write && io_address == 3'h2 && io_writedata[2] == 1'b0 && enable) ||
	(io_write && io_address == 3'h4 && io_writedata[7]);

reg selected_drive_r;
always @(posedge clk) selected_drive_r <= selected_drive[0];

wire [1:0] selected_drive = {1'b0, rst_n &
(
	(io_write && io_address == 3'h2) ? io_writedata[0]  :
	(cmd_recalibrate_start)          ? io_writedata[0]  :
	(cmd_seek_start)                 ? command[0]       :
	(cmd_read_id_start)              ? io_writedata[0]  :
	(cmd_format_track_start)         ? command[24]      :
	(cmd_read_write_start)           ? command[48]      :
	                                   selected_drive_r
)};

reg motor_enable[2];
reg old_motor_enable[2];
always @(posedge clk) begin
	if(~rst_n)                              motor_enable[0] <= 1'b0;
	else if(io_write && io_address == 3'h2) motor_enable[0] <= io_writedata[4];
	                                        old_motor_enable[0] <= motor_enable[0];
end

always @(posedge clk) begin
	if(~rst_n)                              motor_enable[1] <= 1'b0;
	else if(io_write && io_address == 3'h2) motor_enable[1] <= io_writedata[5];
	                                        old_motor_enable[1] <= motor_enable[1];
end

reg dma_irq_enable;
always @(posedge clk) begin
	if(~rst_n)                              dma_irq_enable <= 1'b1;
	else if(io_write && io_address == 3'h2) dma_irq_enable <= io_writedata[3];
end

reg enable;
always @(posedge clk) begin
	if(~rst_n)                              enable <= 1'b1;
	else if(io_write && io_address == 3'h2) enable <= io_writedata[2];
end

reg [1:0] data_rate;
always @(posedge clk) begin
	if(~rst_n)                              data_rate <= 2'b10;
	else if(io_write && io_address == 3'h4) data_rate <= io_writedata[1:0];
	else if(io_write && io_address == 3'h7) data_rate <= io_writedata[1:0];
end

reg datareg_ready;
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                                       datareg_ready <= 1'b1;

	else if(cmd_read_write_ok_at_start)                                         datareg_ready <= 1'b0;
	else if(cmd_read_id_ok_at_start)                                            datareg_ready <= 1'b0;
	else if(cmd_format_ok_at_start)                                             datareg_ready <= 1'b0;

	else if(execute_ndma && state == S_WAIT_FOR_EMPTY_READ_FIFO && ndma_read)   datareg_ready <= 1'b0;
	else if(execute_ndma && state == S_WAIT_FOR_EMPTY_READ_FIFO && ~fifo_empty) datareg_ready <= 1'b1;

	else if(execute_ndma && state == S_WAIT_FOR_FULL_WRITE_FIFO && ndma_write)  datareg_ready <= 1'b0;
	else if(execute_ndma && state == S_WAIT_FOR_FULL_WRITE_FIFO)                datareg_ready <= ~fifo_full;

	else if(execute_ndma && state == S_WAIT_FOR_FORMAT_INPUT && ndma_write)     datareg_ready <= 1'b0;
	else if(execute_ndma && state == S_WAIT_FOR_FORMAT_INPUT)                   datareg_ready <= format_data_count < 3'd4;

	else if(enter_result_phase)                                                 datareg_ready <= 1'b1;
end

reg execute_ndma;
always @(posedge clk) begin
	if(~rst_n)                                  execute_ndma <= 1'b0;
	else if(cmd_read_write_ok_at_start && ndma) execute_ndma <= 1'b1;
	else if(cmd_format_ok_at_start && ndma)     execute_ndma <= 1'b1;
	else if(enter_result_phase)                 execute_ndma <= 1'b0;
end

reg [2:0] ndma_irq_to;
always @(posedge clk) begin
	if(ndma_read | ndma_write | ~execute_ndma) ndma_irq_to <= 0;
	else if(~&ndma_irq_to)                     ndma_irq_to <= ndma_irq_to + 1'd1;
end

reg ndma_irq;
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                                                 ndma_irq <= 1'b0;

	else if(~execute_ndma)                                                                ndma_irq <= 1'b0;

	else if(state == S_WAIT_FOR_EMPTY_READ_FIFO && ndma_read)                             ndma_irq <= 1'b0;
	else if(state == S_WAIT_FOR_EMPTY_READ_FIFO && ~fifo_empty && &ndma_irq_to)           ndma_irq <= 1'b1;

	else if(state == S_WAIT_FOR_FULL_WRITE_FIFO && ndma_write)                            ndma_irq <= 1'b0;
	else if(state == S_WAIT_FOR_FULL_WRITE_FIFO && ~fifo_full && &ndma_irq_to)            ndma_irq <= 1'b1;

	else if(state == S_WAIT_FOR_FORMAT_INPUT && ndma_write)                               ndma_irq <= 1'b0;
	else if(state == S_WAIT_FOR_FORMAT_INPUT && format_data_count < 3'd4 && &ndma_irq_to) ndma_irq <= 1'b1;
end

reg transfer_to_cpu;
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                        transfer_to_cpu <= 1'b0;
	else if(command_first && ~enter_result_phase)                transfer_to_cpu <= 1'b0;
	else if(execute_ndma && state == S_WAIT_FOR_EMPTY_READ_FIFO) transfer_to_cpu <= 1'b1;
	else if(enter_result_phase)                                  transfer_to_cpu <= 1'b1;
	else if(io_read && io_address == 3'd5 && reply_left == 4'd1) transfer_to_cpu <= 1'b0;
end

reg busy;
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                        busy <= 1'b0;
	else if(command_first)                                       busy <= 1'b1;
	else if(cmd_recalibrate_start)                               busy <= 1'b0;
	else if(cmd_seek_start)                                      busy <= 1'b0;
	else if(cmd_specify_start)                                   busy <= 1'b0;
	else if(cmd_configure_mode_start)                            busy <= 1'b0;
	else if(cmd_perpendicular_mode_start)                        busy <= 1'b0;
	else if(enter_result_phase)                                  busy <= 1'b1;
	else if(io_read && io_address == 3'd5 && reply_left == 4'd1) busy <= 1'b0;
end

reg change[2];
always @(posedge clk) begin
	if(~rst_n)                                                          change[0] <= 1'b1;
	else if(~media_present[0])                                          change[0] <= 1'b1;
	else if(reset_changeline && ~selected_drive[0] && media_present[0]) change[0] <= 1'b0;
end

always @(posedge clk) begin
	if(~rst_n)                                                          change[1] <= 1'b1;
	else if(~media_present[1])                                          change[1] <= 1'b1;
	else if(reset_changeline &&  selected_drive[0] && media_present[1]) change[1] <= 1'b0;
end

reg [3:0] in_seek_mode;
always @(posedge clk) begin
	if(~rst_n | sw_reset)          in_seek_mode <= 4'b0000;
	else if(cmd_recalibrate_start) in_seek_mode <= 4'b0001 << io_writedata[0];
	else if(cmd_seek_start)        in_seek_mode <= 4'b0001 << command[0];
end

//------------------------------------------------------------------------------

wire command_first = io_write && io_address == 3'h5 && state == S_IDLE && !command_left && ~busy;
wire command_next  = io_write && io_address == 3'h5 && state == S_IDLE &&  command_left;

reg [71:0] command;
always @(posedge clk) begin
	if(~rst_n)             command <= 72'd0;
	else if(command_first) command <= io_writedata;
	else if(command_next)  command <= { command[63:0], io_writedata };
end

wire [3:0] command_at_first =
	(io_writedata[4:0] == 5'h03) ? 4'd2 : //specify command
	(io_writedata[4:0] == 5'h04) ? 4'd1 : //get status
	(io_writedata[4:0] == 5'h07) ? 4'd1 : //recalibrate
	(io_writedata[4:0] == 5'h0F) ? 4'd2 : //seek
	(io_writedata[4:0] == 5'h0A) ? 4'd1 : //read ID
	(io_writedata[4:0] == 5'h0D) ? 4'd5 : //format track
	(io_writedata[4:0] == 5'h05) ? 4'd8 : //write normal data
	(io_writedata[4:0] == 5'h06) ? 4'd8 : //read normal data
	(io_writedata[4:0] == 5'h12) ? 4'd1 : //perpendicular mode (Enhanced)
	(io_writedata[4:0] == 5'h13) ? 4'd3 : //configure command (Enhanced)
	                               4'd0;

reg [3:0] command_size;
always @(posedge clk) begin
	if(~rst_n)                                 command_size <= 4'd0;
	else if(command_first && command_at_first) command_size <= command_at_first;
end

reg [3:0] command_left;
always @(posedge clk) begin
	if(~rst_n)                                 command_left <= 4'd0;
	else if(command_first && command_at_first) command_left <= command_at_first;
	else if(command_next)                      command_left <= command_left - 4'd1;
end

reg [7:0] pending_command;
always @(posedge clk) begin
	if(~rst_n | sw_reset)               pending_command <= 8'h00;
	else if(cmd_read_write_ok_at_start) pending_command <= command[63:56];
	else if(cmd_read_id_ok_at_start)    pending_command <= 8'h0A;
	else if(cmd_format_ok_at_start)     pending_command <= command[39:32];
	else if(cmd_recalibrate_start)      pending_command <= 8'h07;
	else if(enter_result_phase)         pending_command <= 8'h00;
end

wire cmd_sense_interrupt_status_start = command_first && io_writedata[4:0] == 5'h08; //enters result phase
wire cmd_dump_registers_start         = command_first && io_writedata[4:0] == 5'h0E; //enters result phase
wire cmd_version_start                = command_first && io_writedata[4:0] == 5'h10; //enters result phase
wire cmd_unlock_start                 = command_first && io_writedata      == 8'h14; //enters result phase
wire cmd_lock_start                   = command_first && io_writedata      == 8'h94; //enters result phase

wire cmd_specify_start      = command_size == 4'd2 && command_next && command_left == 4'd1 && command[12:8]  == 5'h03; //immediate finish
wire cmd_get_status_start   = command_size == 4'd1 && command_next && command_left == 4'd1 && command[4:0]   == 5'h04; //enters result phase
wire cmd_recalibrate_start  = command_size == 4'd1 && command_next && command_left == 4'd1 && command[4:0]   == 5'h07; //interrupt after delay
wire cmd_seek_start         = command_size == 4'd2 && command_next && command_left == 4'd1 && command[12:8]  == 5'h0F; //interrupt after delay
wire cmd_read_id_start      = command_size == 4'd1 && command_next && command_left == 4'd1 && command[4:0]   == 5'h0A; //enters result phase
wire cmd_format_track_start = command_size == 4'd5 && command_next && command_left == 4'd1 && command[36:32] == 5'h0D; //enters result pahse
wire cmd_write_normal_start = command_size == 4'd8 && command_next && command_left == 4'd1 && command[60:56] == 5'h05; //enters result phase
wire cmd_read_normal_start  = command_size == 4'd8 && command_next && command_left == 4'd1 && command[60:56] == 5'h06; //enters result phase

wire cmd_perpendicular_mode_start = command_size == 4'd1 && command_next && command_left == 4'd1 && command[4:0]   == 5'h12; //immediate finish
wire cmd_configure_mode_start     = command_size == 4'd3 && command_next && command_left == 4'd1 && command[20:16] == 5'h13; //immediate finish

wire cmd_invalid_start = command_first &&
	io_writedata[4:0] != 5'h03 &&
	io_writedata[4:0] != 5'h04 &&
	io_writedata[4:0] != 5'h05 &&
	io_writedata[4:0] != 5'h06 &&
	io_writedata[4:0] != 5'h07 &&
	io_writedata[4:0] != 5'h08 &&
	io_writedata[4:0] != 5'h0A &&
	io_writedata[4:0] != 5'h0D &&
	io_writedata[4:0] != 5'h0E &&
	io_writedata[4:0] != 5'h0F &&
	io_writedata[4:0] != 5'h10 &&
	io_writedata[4:0] != 5'h12 &&
	io_writedata[4:0] != 5'h13 &&
	io_writedata[4:0] != 5'h14;

wire cmd_read_write_start = cmd_read_normal_start || cmd_write_normal_start;

wire cmd_read_normal_in_progress  = pending_command[4:0] == 5'h06;
wire cmd_write_normal_in_progress = pending_command[4:0] == 5'h05;
wire cmd_format_in_progress       = pending_command[4:0] == 5'h0D;
wire cmd_recalibrate_in_progress  = pending_command[4:0] == 5'h07;
wire cmd_read_id_in_progress      = pending_command[4:0] == 5'h0A;

wire enter_result_phase =
	cmd_invalid_start || cmd_sense_interrupt_status_start || cmd_dump_registers_start || cmd_version_start || cmd_unlock_start || cmd_lock_start ||
	(cmd_read_write_start && (cmd_read_write_incorrect_head_at_start || cmd_read_write_incorrect_sector_at_start || cmd_write_and_writeprotected_at_start)) ||
	(state == S_CHECK_TC && (cmd_read_write_finish || cmd_format_finish)) ||
	(cmd_format_track_start && cmd_format_writeprotected_at_start) ||
	(state == S_WAIT_FOR_FORMAT_INPUT && cmd_format_in_input_finish) ||
	cmd_get_status_start ||
	cmd_read_id_finished;

wire raise_interrupt = dma_irq_enable && (
	(cmd_read_write_start && (cmd_read_write_incorrect_head_at_start || cmd_read_write_incorrect_sector_at_start)) ||
	(cmd_write_normal_start && cmd_write_and_writeprotected_at_start) ||
	(state == S_CHECK_TC && (cmd_read_write_finish || cmd_format_finish)) ||
	(cmd_format_track_start && cmd_format_writeprotected_at_start) ||
	(state == S_WAIT_FOR_FORMAT_INPUT && cmd_format_in_input_finish) ||
	delay_last_cycle ||
	cmd_read_id_finished
);

wire reset_changeline =
	(cmd_read_write_ok_at_start) ||
	(state == S_UPDATE_SECTOR && increment_cylinder) ||
	(cmd_recalibrate_start && cylinder[selected_drive[0]] != 8'd0) ||
	(cmd_seek_start && cylinder[selected_drive[0]] != io_writedata) ||
	(old_motor_enable[selected_drive[0]] & ~motor_enable[selected_drive[0]]); // on-off-on trick to clear the change status in win98


//------------------------------------------------------------------------------ cmd: read / write

wire cmd_read_write_hang_at_start =
	~motor_enable[selected_drive[0]] ||  //motor off
	~media_present[selected_drive[0]] || //no media
	command[23:16] != 8'h02 ||           //invalid sector size
	command[47:40] >= media_cylinders[selected_drive[0]];   //invalid cylinder

wire cmd_read_write_incorrect_head_at_start   = motor_enable[selected_drive[0]] && (command[50] != command[32] || (command[32] && media_heads[selected_drive[0]] == 2'd1));
wire cmd_read_write_incorrect_sector_at_start = ~cmd_read_write_hang_at_start && (command[31:24] > media_sectors_per_track[selected_drive[0]] || command[31:24] > command[15:8]);
wire cmd_write_and_writeprotected_at_start    = ~cmd_read_write_hang_at_start && ~cmd_read_write_incorrect_sector_at_start && cmd_write_normal_start && media_writeprotected[selected_drive[0]];
    
wire cmd_read_write_ok_at_start = 
	cmd_read_write_start && ~cmd_read_write_hang_at_start && ~cmd_read_write_incorrect_head_at_start && ~cmd_read_write_incorrect_sector_at_start && ~cmd_write_and_writeprotected_at_start;
    
reg cmd_read_write_multitrack;
always @(posedge clk) begin
    if(~rst_n)                          cmd_read_write_multitrack <= 1'b0;
    else if(cmd_read_write_ok_at_start) cmd_read_write_multitrack <= command[63];
end

wire cmd_read_write_finish =
	(cmd_read_normal_in_progress || cmd_write_normal_in_progress) &&
	((~execute_ndma && dma_has_terminated) || (execute_ndma && cmd_read_write_was_ndma_terminal));

reg cmd_read_write_was_ndma_terminal;
always @(posedge clk) begin
    if(~rst_n)                                                                                 cmd_read_write_was_ndma_terminal <= 1'd0;
    else if(state == S_UPDATE_SECTOR && sector[selected_drive[0]] == eot[selected_drive[0]] && 
	        {1'b0, head[selected_drive[0]] } == (media_heads[selected_drive[0]] - 2'd1))        cmd_read_write_was_ndma_terminal <= 1'd1;
    else if(state == S_UPDATE_SECTOR)                                                          cmd_read_write_was_ndma_terminal <= 1'd0;
end

//------------------------------------------------------------------------------ cmd: read id
    
wire cmd_read_id_hang_at_start =
    ~motor_enable[selected_drive[0]] || //motor off
    ~media_present[selected_drive[0]];  //no media

wire cmd_read_id_ok_at_start = cmd_read_id_start && ~cmd_read_id_hang_at_start;
wire cmd_read_id_finished = state == S_WAIT && !command_wait_counter && cmd_read_id_in_progress;

//------------------------------------------------------------------------------ cmd: specify
    
reg [3:0] specify_srt;
always @(posedge clk) begin
    if(~rst_n)                 specify_srt <= 4'd0;
    else if(cmd_specify_start) specify_srt <= command[7:4];
end

reg [3:0] specify_hut;
always @(posedge clk) begin
    if(~rst_n)                 specify_hut <= 4'b0;
    else if(cmd_specify_start) specify_hut <= command[3:0];
end

reg [6:0] specify_hlt;
always @(posedge clk) begin
    if(~rst_n)                 specify_hlt <= 7'b0;
    else if(cmd_specify_start) specify_hlt <= io_writedata[7:1];
end

reg ndma;
always @(posedge clk) begin
    if(~rst_n)                 ndma <= 1'b0;
    else if(cmd_specify_start) ndma <= io_writedata[0];
end

//------------------------------------------------------------------------------ cmd: sense interrupt status

always @(posedge clk) begin
	reg old_enable;

	old_enable <= enable;

	if(~rst_n | sw_reset)                                irq <= 1'b0;
	else if(~old_enable & enable)                        irq <= 1'b1;
	else if(ndma_write | ndma_read)                      irq <= 1'b0;
	else if(ndma_irq | raise_interrupt)                  irq <= 1'b1;
	else if(io_read && io_address == 3'd5 && ~ndma_read) irq <= 1'b0;
end

reg [2:0] reset_sensei;
always @(posedge clk) begin
	if(~rst_n)                                                reset_sensei <= 3'd0;
	else if(sw_reset)                                         reset_sensei <= 3'd4;
	else if(raise_interrupt)                                  reset_sensei <= 3'd0;
	else if(cmd_sense_interrupt_status_start && reset_sensei) reset_sensei <= reset_sensei - 3'd1;
end

wire [1:0] reset_sensei_drive =
    (reset_sensei == 3'd4) ? 2'd0 :
    (reset_sensei == 3'd3) ? 2'd1 :
    (reset_sensei == 3'd2) ? 2'd2 :
                             2'd3;

reg pending_interrupt;
always @(posedge clk) begin
	if(~rst_n)               pending_interrupt <= 1'b0;
	else if(raise_interrupt) pending_interrupt <= 1'b1;
	else if(~irq)            pending_interrupt <= 1'b0;
end

reg pending_interrupt_last;
always @(posedge clk) pending_interrupt_last <= pending_interrupt;

//------------------------------------------------------------------------------ cmd: recalibrate / seek

reg [7:0] delay_steps;
always @(posedge clk) begin
	if(~rst_n)                                        delay_steps <= 8'd0;
	else if(cmd_recalibrate_start)                    delay_steps <= (cylinder[selected_drive[0]] == 8'd0)? 8'd0 : cylinder[selected_drive[0]] - 8'd1;
	else if(cmd_seek_start)                           delay_steps <= (cylinder[selected_drive[0]] == io_writedata)? 8'd0 : (cylinder[selected_drive[0]] > io_writedata)? cylinder[selected_drive[0]] - io_writedata - 8'd1 : io_writedata - cylinder[selected_drive[0]] - 8'd1; 
	else if(!delay_rate && !delay_srt && delay_steps) delay_steps <= delay_steps - 8'd1;
end

reg [3:0] delay_srt;
always @(posedge clk) begin
	if(~rst_n)                          delay_srt <= 4'd0;
	else if(cmd_recalibrate_start)      delay_srt <= specify_srt;
	else if(cmd_seek_start)             delay_srt <= specify_srt;
	else if(!delay_rate && delay_srt)   delay_srt <= delay_srt - 4'd1;
	else if(!delay_rate && delay_steps) delay_srt <= specify_srt;
end

wire [27:0] delay_adder = (data_rate == 2'd0)? 28'd1000 : (data_rate == 2'd1)? 28'd600 : (data_rate == 2'd2)? 28'd500 : 28'd2000;

reg [27:0] delay_adder_r;
always @(posedge clk) begin
	if(cmd_recalibrate_start)         delay_adder_r <= delay_adder;
	else if(cmd_seek_start)           delay_adder_r <= delay_adder;
	else if(delay_srt || delay_steps) delay_adder_r <= delay_adder;
end

reg [27:0] delay_rate;
always @(posedge clk) begin
	if(~rst_n)                        delay_rate <= 0;
	else if(cmd_recalibrate_start)    delay_rate <= delay_adder;
	else if(cmd_seek_start)           delay_rate <= delay_adder;
	else if(delay_rate >= clk_rate)   delay_rate <= 1;
	else if(delay_rate == 1)          delay_rate <= 0;
	else if(delay_rate)               delay_rate <= delay_rate + delay_adder_r;
	else if(delay_srt || delay_steps) delay_rate <= delay_adder;
end

wire delay_last_cycle = !delay_steps && !delay_srt && delay_rate == 16'd1;

reg [7:0] status_reg0_temp;
always @(posedge clk) begin
	if(~rst_n)                                                status_reg0_temp <= 8'd0;
	else if(pending_interrupt && ~pending_interrupt_last)     status_reg0_temp <= reply[7:0];
	else if(cmd_sense_interrupt_status_start && reset_sensei) status_reg0_temp <= { 4'hC, 2'b00, reset_sensei_drive };
end

//------------------------------------------------------------------------------ cmd: configure / lock / unlock

reg [7:0] config_config;
always @(posedge clk) begin
	if(~rst_n)                        config_config <= 8'h20;
	else if(cmd_configure_mode_start) config_config <= command[7:0];
end

reg [7:0] config_pretrk;
always @(posedge clk) begin
	if(~rst_n)                        config_pretrk <= 8'd0;
	else if(cmd_configure_mode_start) config_pretrk <= io_writedata;
end

reg [7:0] perp_mode;
always @(posedge clk) begin
	if(~rst_n)                            perp_mode <= 8'd0;
	else if(cmd_perpendicular_mode_start) perp_mode <= io_writedata;
end

reg lock;
always @(posedge clk) begin
	if(~rst_n)                lock <= 1'd0;
	else if(cmd_unlock_start) lock <= 1'd0;
	else if(cmd_lock_start)   lock <= 1'd1;
end

//------------------------------------------------------------------------------ cmd: format

wire cmd_format_writeprotected_at_start = ~cmd_format_hang_on_start && cmd_format_track_start && media_writeprotected[selected_drive[0]];
    
wire cmd_format_hang_on_start =
	~motor_enable[selected_drive[0]] ||                          //motor off
	~media_present[selected_drive[0]] ||                         //no media
	command[23:16] != 8'h02 ||                                   //invalid sector size
	command[15:8] != media_sectors_per_track[selected_drive[0]]; //invalid secotr count

wire cmd_format_ok_at_start = cmd_format_track_start && ~cmd_format_writeprotected_at_start && ~cmd_format_hang_on_start;

reg [31:0] format_data;
always @(posedge clk) begin
	if(~rst_n)                                      format_data <= 32'd0;
	else if(ndma_write && format_data_count < 3'd4) format_data <= { format_data[23:0], io_writedata };
	else if(dma_ack && format_data_count < 3'd4)    format_data <= { format_data[23:0], dma_readdata };
end

reg [2:0] format_data_count;
always @(posedge clk) begin
	if(~rst_n)                                                   format_data_count <= 3'd0;
	else if(state != S_WAIT_FOR_FORMAT_INPUT)                    format_data_count <= 3'd0;
	else if((ndma_write || dma_ack) && format_data_count < 3'd4) format_data_count <= format_data_count + 3'd1;
end

reg [7:0] format_filler_byte;
always @(posedge clk) begin
	if(~rst_n)                      format_filler_byte <= 8'd0;
	else if(cmd_format_ok_at_start) format_filler_byte <= io_writedata;
end

reg [7:0] format_sector_count;
always @(posedge clk) begin
	if(~rst_n)                                                                  format_sector_count <= 8'd0;
	else if(cmd_format_ok_at_start)                                             format_sector_count <= command[15:8];
	else if(state == S_SD_FORMAT_WAIT_FOR_FILL && &format_counter && fifo_read) format_sector_count <= format_sector_count - 8'd1;
end

wire cmd_format_in_input_finish = ~execute_ndma && dma_has_terminated;

wire cmd_format_finish = cmd_format_in_progress && (
	cmd_format_in_input_finish ||
	(execute_ndma && !format_sector_count)
);

//------------------------------------------------------------------------------ reply

reg [3:0] reply_left;
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                                        reply_left <= 4'd0;
	else if(cmd_invalid_start)                                                   reply_left <= 4'd1;
	else if(cmd_read_write_start   && cmd_read_write_incorrect_head_at_start)    reply_left <= 4'd7;
	else if(cmd_read_write_start   && cmd_read_write_incorrect_sector_at_start)  reply_left <= 4'd7;
	else if(cmd_write_normal_start && cmd_write_and_writeprotected_at_start)     reply_left <= 4'd7;
	else if(cmd_format_track_start && cmd_format_writeprotected_at_start)        reply_left <= 4'd7;
	else if(state == S_CHECK_TC && (cmd_read_write_finish || cmd_format_finish)) reply_left <= 4'd7;
	else if(state == S_WAIT_FOR_FORMAT_INPUT && cmd_format_in_input_finish)      reply_left <= 4'd7;
	else if(cmd_read_id_finished)                                                reply_left <= 4'd7;
	else if(cmd_get_status_start)                                                reply_left <= 4'd1;
	else if(cmd_sense_interrupt_status_start)                                    reply_left <= 4'd2;
	else if(cmd_dump_registers_start)                                            reply_left <= 4'd10;
	else if(cmd_version_start)                                                   reply_left <= 4'd1;
	else if(cmd_unlock_start || cmd_lock_start)                                  reply_left <= 4'd1;
	else if(io_read && io_address == 3'h5 && reply_left)                         reply_left <= reply_left - 3'd1;
end

reg [79:0] reply;
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                                     reply <= 80'd0;
	else if(cmd_invalid_start)                                                reply <= { reply[79:8], 8'h80 };
	else if(delay_last_cycle && cmd_recalibrate_in_progress)                  reply <= { reply[79:8], 8'h20 | { 6'd0, selected_drive } | ((~motor_enable[selected_drive[0]])? 8'h50 : 8'h00) };
	else if(delay_last_cycle)                                                 reply <= { reply[79:8], 8'h20 | { 5'd0, head[selected_drive[0]], selected_drive } }; 
	else if(cmd_read_write_start && cmd_read_write_incorrect_head_at_start)   reply <= { 24'd0, 8'd2, sector[selected_drive[0]], 7'b0,head[selected_drive[0]], cylinder[selected_drive[0]], 8'h00, 8'h04, (8'h40 | { 5'd0, head[selected_drive[0]],  selected_drive }) };
	else if(cmd_read_write_start && cmd_read_write_incorrect_sector_at_start) reply <= { 24'd0, 8'd2, command[31:24],            7'b0,command[32],             command[47:40],              8'h00, 8'h04, (8'h40 | { 5'd0, command[32],              selected_drive }) };
	else if(cmd_write_normal_start && cmd_write_and_writeprotected_at_start)  reply <= { 24'd0, 8'd2, command[31:24],            7'b0,command[32],             command[47:40],              8'h31, 8'h27, (8'h40 | { 5'd0, command[32],              selected_drive }) };
	else if(cmd_format_track_start && cmd_format_writeprotected_at_start)     reply <= { 24'd0, 8'd2, sector[selected_drive[0]], 7'b0,command[26],             cylinder[selected_drive[0]], 8'h31, 8'h27, (8'h40 | { 5'd0, command[26],              selected_drive }) };
	else if(state == S_CHECK_TC && cmd_read_write_finish)                     reply <= { 24'd0, 8'd2, sector[selected_drive[0]], 7'b0,head[selected_drive[0]], cylinder[selected_drive[0]], 8'h00, 8'h00, (8'h00 | { 5'd0, head[selected_drive[0]],  selected_drive }) };
	else if(state == S_CHECK_TC && cmd_format_finish)                         reply <= { 24'd0, 8'd2, sector[selected_drive[0]], 7'b0,head[selected_drive[0]], cylinder[selected_drive[0]], 8'h00, 8'h00, (8'h00 | { 5'd0, head[selected_drive[0]],  selected_drive }) };
	else if(state == S_WAIT_FOR_FORMAT_INPUT && cmd_format_in_input_finish)   reply <= { 24'd0, 8'd2, sector[selected_drive[0]], 7'b0,head[selected_drive[0]], cylinder[selected_drive[0]], 8'h00, 8'h00, (8'h40 | { 5'd0, head[selected_drive[0]],  selected_drive }) };
	else if(cmd_read_id_finished)                                             reply <= { 24'd0, 8'd2, sector[selected_drive[0]], 7'b0,head[selected_drive[0]], cylinder[selected_drive[0]], 8'h00, 8'h00, (8'h00 | { 5'd0, head[selected_drive[0]],  selected_drive }) };
	else if(cmd_get_status_start)                                             reply <= { 72'd0, 1'b0, media_writeprotected[io_writedata[0]], 1'b1, !cylinder[io_writedata[0]], 1'b1, io_writedata[2], 1'b0, io_writedata[0] };
	else if(cmd_sense_interrupt_status_start && reset_sensei)                 reply <= { 64'd0, cylinder[selected_drive[0]], 4'hC, 2'b00, reset_sensei_drive };
	else if(cmd_sense_interrupt_status_start && pending_interrupt)            reply <= { 64'd0, cylinder[selected_drive[0]], status_reg0_temp };
	else if(cmd_sense_interrupt_status_start && ~pending_interrupt)           reply <= { 64'd0, cylinder[selected_drive[0]], 8'h80 };
	else if(cmd_dump_registers_start)                                         reply <= { config_pretrk, config_config, lock, perp_mode[6:0], eot[selected_drive[0]],
	                                                                                     specify_hlt, ndma, specify_srt, specify_hut, 8'h0, 8'h0, 8'h0, cylinder[selected_drive[0]] };
	else if(cmd_version_start)                                                reply <= { 72'd0, 8'h90 };
	else if(cmd_unlock_start)                                                 reply <= 80'd0;
	else if(cmd_lock_start)                                                   reply <= { 72'd0, 8'h10 };
	else if(io_read && io_address == 3'h5)                                    reply <= { 8'd0, reply[79:8] };
end

//------------------------------------------------------------------------------ state

localparam [3:0] S_IDLE                         = 0;

localparam [3:0] S_PREPARE_COUNT                = 1;
localparam [3:0] S_COUNT_LOGICAL                = 2;

localparam [3:0] S_PREPARE                      = 3;

localparam [3:0] S_SD_CONTROL                   = 4;
localparam [3:0] S_SD_READ_WAIT_FOR_DATA        = 5;
localparam [3:0] S_WAIT_FOR_EMPTY_READ_FIFO     = 6;

localparam [3:0] S_UPDATE_SECTOR                = 7;
localparam [3:0] S_CHECK_TC                     = 8;
localparam [3:0] S_WAIT                         = 9;

localparam [3:0] S_WAIT_FOR_FULL_WRITE_FIFO     = 10;
localparam [3:0] S_SD_WRITE_WAIT_FOR_EMPTY_FIFO = 11;

localparam [3:0] S_WAIT_FOR_FORMAT_INPUT        = 12;
localparam [3:0] S_SD_FORMAT_WAIT_FOR_FILL      = 13;

reg [3:0] state;
always @(posedge clk) begin
	if(~rst_n)                                                                    state <= S_IDLE;

	//start read/write
	else if(state == S_IDLE && cmd_read_write_ok_at_start)                        state <= S_PREPARE_COUNT;

	//read
	else if(state == S_COUNT_LOGICAL && !mult_b && cmd_read_normal_in_progress)   state <= S_PREPARE;
	//sd
	else if(state == S_SD_CONTROL && cmd_read_normal_in_progress)                 state <= S_SD_READ_WAIT_FOR_DATA;
	else if(state == S_SD_READ_WAIT_FOR_DATA && fifo_full)                        state <= S_WAIT_FOR_EMPTY_READ_FIFO;
	else if(state == S_WAIT_FOR_EMPTY_READ_FIFO && fifo_empty)                    state <= S_UPDATE_SECTOR;

	//write
	else if(state == S_COUNT_LOGICAL && !mult_b && cmd_write_normal_in_progress)  state <= S_WAIT_FOR_FULL_WRITE_FIFO;
	else if(state == S_WAIT_FOR_FULL_WRITE_FIFO && fifo_full)                     state <= S_PREPARE;
	//sd
	else if(state == S_SD_CONTROL && cmd_write_normal_in_progress)                state <= S_SD_WRITE_WAIT_FOR_EMPTY_FIFO;
	else if(state == S_SD_WRITE_WAIT_FOR_EMPTY_FIFO && fifo_empty)                state <= S_UPDATE_SECTOR;

	//format
	else if(state == S_IDLE && cmd_format_ok_at_start)                            state <= S_WAIT_FOR_FORMAT_INPUT;
	else if(state == S_WAIT_FOR_FORMAT_INPUT && cmd_format_in_input_finish)       state <= S_IDLE;
	else if(state == S_WAIT_FOR_FORMAT_INPUT && format_data_count == 3'd4)        state <= S_PREPARE_COUNT;
	//count
	else if(state == S_COUNT_LOGICAL && !mult_b && cmd_format_in_progress)        state <= S_PREPARE;
	//sd
	else if(state == S_SD_CONTROL && cmd_format_in_progress)                      state <= S_SD_FORMAT_WAIT_FOR_FILL;
	else if(state == S_SD_FORMAT_WAIT_FOR_FILL && &format_counter && fifo_read)   state <= S_WAIT;

	//read id
	else if(state == S_IDLE && cmd_read_id_ok_at_start)                           state <= S_WAIT;
	else if(state == S_WAIT && !command_wait_counter && cmd_read_id_in_progress)  state <= S_IDLE;

	//count
	else if(state == S_PREPARE_COUNT)                                             state <= S_COUNT_LOGICAL;

	//sd read/write
	else if(state == S_PREPARE)                                                   state <= S_SD_CONTROL;

	//update read/write/format
	else if(state == S_UPDATE_SECTOR)                                             state <= S_WAIT;
	else if(state == S_WAIT && !command_wait_counter && ~cmd_read_id_in_progress) state <= S_CHECK_TC;
	else if(state == S_CHECK_TC && (cmd_read_write_finish || cmd_format_finish))  state <= S_IDLE;
	else if(state == S_CHECK_TC && cmd_format_in_progress)                        state <= S_WAIT_FOR_FORMAT_INPUT;
	else if(state == S_CHECK_TC)                                                  state <= S_PREPARE_COUNT;
end

reg [15:0] command_wait_counter;
always @(posedge clk) begin
	if(~rst_n)                                       command_wait_counter <= 0;
	else if(state != S_WAIT)                         command_wait_counter <= 4000; // was calculated floppy_wait_cycles but was buggy, so use fixed wait time
	else if(state == S_WAIT && command_wait_counter) command_wait_counter <= command_wait_counter - 16'd1;
end

//------------------------------------------------------------------------------ count logical sector

reg [15:0] mult_a; //sectors per track * heads
always @(posedge clk) begin
	if(~rst_n)                        mult_a <= 16'd0;
	else if(state == S_PREPARE_COUNT) mult_a <= (media_heads[selected_drive[0]] == 2'd2) ? { 7'd0, media_sectors_per_track[selected_drive[0]], 1'b0 } : { 8'b0, media_sectors_per_track[selected_drive[0]] };
	else if(state == S_COUNT_LOGICAL) mult_a <= { mult_a[14:0], 1'b0 };
end

reg [7:0] mult_b; //cylinder
always @(posedge clk) begin
	if(~rst_n)                        mult_b <= 8'd0;
	else if(state == S_PREPARE_COUNT) mult_b <= cylinder[selected_drive[0]];
	else if(state == S_COUNT_LOGICAL) mult_b <= { 1'b0, mult_b[7:1] };
end

reg [15:0] logical_sector;
always @(posedge clk) begin
	if(~rst_n)                                     logical_sector <= 16'd0;
	else if(state == S_PREPARE_COUNT)              logical_sector <= (head[selected_drive[0]] ? {8'd0, media_sectors_per_track[selected_drive[0]]} : 16'd0) + {8'd0, sector[selected_drive[0]]} - 16'd1;
	else if(state == S_COUNT_LOGICAL && mult_b[0]) logical_sector <= logical_sector + mult_a;
end

//------------------------------------------------------------------------------ location

wire increment_only_sector = sector[selected_drive[0]] < eot[selected_drive[0]] && sector[selected_drive[0]] < media_sectors_per_track[selected_drive[0]];
wire increment_cylinder    = ~increment_only_sector && (~cmd_read_write_multitrack || head[selected_drive[0]] == 1'b1);

(* ramstyle = "logic" *) reg [7:0] cylinder[2];
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                                                                                begin cylinder[0] <= 8'd0; cylinder[1] <= 8'd0; end
	else if(cmd_read_write_start && (cmd_read_write_incorrect_sector_at_start || cmd_write_and_writeprotected_at_start)) cylinder[selected_drive[0]] <= command[47:40];
	else if(cmd_read_write_ok_at_start)                                                                                  cylinder[selected_drive[0]] <= command[47:40];
	else if(cmd_recalibrate_start)                                                                                       cylinder[selected_drive[0]] <= 8'd0;
	else if(cmd_seek_start)                                                                                              cylinder[selected_drive[0]] <= io_writedata;
	else if(state == S_UPDATE_SECTOR && increment_cylinder)                                                              cylinder[selected_drive[0]] <= (cylinder[selected_drive[0]] >= media_cylinders[selected_drive[0]])? media_cylinders[selected_drive[0]] - 8'd1 : cylinder[selected_drive[0]] + 8'd1;
	else if(state == S_WAIT_FOR_FORMAT_INPUT && format_data_count == 3'd4)                                               cylinder[selected_drive[0]] <= format_data[31:24];
end

reg head[2];
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                                                                                begin head[0] <= 1'd0; head[1] <= 1'd0; end
	else if(cmd_read_write_start && (cmd_read_write_incorrect_sector_at_start || cmd_write_and_writeprotected_at_start)) head[selected_drive[0]] <= command[32];
	else if(cmd_format_track_start && cmd_format_writeprotected_at_start)                                                head[selected_drive[0]] <= command[26];
	else if(cmd_read_write_ok_at_start)                                                                                  head[selected_drive[0]] <= command[32];
	else if(cmd_format_ok_at_start)                                                                                      head[selected_drive[0]] <= command[26];
	else if(cmd_get_status_start)                                                                                        head[selected_drive[0]] <= io_writedata[2];
	else if(cmd_seek_start)                                                                                              head[selected_drive[0]] <= command[2];
	else if(cmd_read_id_start)                                                                                           head[selected_drive[0]] <= io_writedata[2];
	else if(state == S_UPDATE_SECTOR && ~increment_only_sector && cmd_read_write_multitrack)                             head[selected_drive[0]] <= ~head[selected_drive[0]];
end

(* ramstyle = "logic" *) reg [7:0] sector[2];
always @(posedge clk) begin
	if(~rst_n | sw_reset)                                                                                                begin sector[0] <= 8'd1; sector[1] <= 8'd1; end
	else if(cmd_read_write_start && (cmd_read_write_incorrect_sector_at_start || cmd_write_and_writeprotected_at_start)) sector[selected_drive[0]] <= command[31:24];
	else if(cmd_read_write_ok_at_start)                                                                                  sector[selected_drive[0]] <= command[31:24];
	else if(state == S_UPDATE_SECTOR && increment_only_sector)                                                           sector[selected_drive[0]] <= sector[selected_drive[0]] + 8'd1;
	else if(state == S_UPDATE_SECTOR && ~increment_only_sector)                                                          sector[selected_drive[0]] <= 8'd1;
	else if(state == S_WAIT_FOR_FORMAT_INPUT && format_data_count == 3'd4)                                               sector[selected_drive[0]] <= format_data[15:8];
end

(* ramstyle = "logic" *) reg [7:0] eot[2];
always @(posedge clk) begin
	if(~rst_n | sw_reset)                begin eot[0] <= 8'd0; eot[1] <= 8'd0; end
	else if(cmd_read_write_ok_at_start)  eot[selected_drive[0]] <= (command[15:8] == 8'd0)? media_sectors_per_track[selected_drive[0]] : command[15:8];
end

//------------------------------------------------------------------------------ sd

reg [8:0] format_counter;
always @(posedge clk) begin
	if(state == S_IDLE) format_counter <= 9'd0;
	else if(fifo_read)  format_counter <= format_counter + 9'd1;
end

reg [15:0] sd_sector;
always @(posedge clk) begin
	if(~rst_n)                  sd_sector <= 16'd0;
	else if(state == S_PREPARE) sd_sector <= (logical_sector >= media_sector_count[selected_drive[0]])? media_sector_count[selected_drive[0]] - 1'd1 : logical_sector;
end

//------------------------------------------------------------------------------ dma

assign dma_writedata = fifo_q;

assign dma_req = ~execute_ndma   && ~dma_has_terminated && dma_irq_enable && ~dma_ack && (
	(cmd_read_normal_in_progress  && ~fifo_empty && state == S_WAIT_FOR_EMPTY_READ_FIFO) ||
	(cmd_write_normal_in_progress && ~fifo_full && state == S_WAIT_FOR_FULL_WRITE_FIFO) ||
	(cmd_format_in_progress       && format_data_count < 3'd4 && state == S_WAIT_FOR_FORMAT_INPUT)
);

reg dma_has_terminated;
always @(posedge clk) begin
	if(~rst_n)               dma_has_terminated <= 1'd0;
	else if(state == S_IDLE) dma_has_terminated <= 1'd0;
	else if(dma_tc)          dma_has_terminated <= 1'd1;
end

//------------------------------------------------------------------------------ fifo

wire [9:0] fifo_count;
wire       fifo_empty;
wire       fifo_full = fifo_count[9];
wire [7:0] fifo_q;

reg  [7:0] fifo_readdata;
always @(posedge clk) begin
	if(~rst_n)                      fifo_readdata <= 8'b0;
	else if(cmd_format_in_progress) fifo_readdata <= format_filler_byte;
	else                            fifo_readdata <= fifo_q;
end

wire fifo_from_pc = (state == S_WAIT_FOR_FULL_WRITE_FIFO);
wire fifo_to_pc   = (state == S_WAIT_FOR_EMPTY_READ_FIFO);
wire fifo_pc_wr   = ((ndma_write || (~execute_ndma && dma_ack) || (~execute_ndma && dma_has_terminated)) && ~fifo_full);
wire fifo_pc_rd   = (ndma_read || (~execute_ndma && dma_ack));

simple_fifo #(
	.width      (8),
	.widthu     (10)
)
fifo_to_floppy_inst (
	.clk        (clk),
	.rst_n      (rst_n),

	.sclr       (state == S_IDLE),

	.data       (fifo_from_pc ? (execute_ndma ? io_writedata : dma_has_terminated ? 8'h00 : dma_readdata) : mgmt_writedata[7:0]),
	.wrreq      (fifo_from_pc ? fifo_pc_wr : fifo_write),

	.rdreq      (fifo_to_pc ? fifo_pc_rd : fifo_read),
	.q          (fifo_q),

	.empty      (fifo_empty),
	.usedw      (fifo_count)
);

//------------------------------------------------------------------------------

endmodule
