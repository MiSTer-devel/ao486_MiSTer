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

`include "defines.v"

//PARSED_COMMENTS: this file contains parsed script comments

module memory_read(
    // global
    input               clk,
    input               rst_n,
    
    // read step
    input               rd_reset,
    
    //RESP:
    input               read_do,
    output              read_done,
    output reg          read_page_fault,
    output reg          read_ac_fault,
    
    input       [1:0]   read_cpl,
    input       [31:0]  read_address,
    input       [3:0]   read_length,
    input               read_lock,
    input               read_rmw,
    output      [63:0]  read_data,
    //END
    
    //REQ:
    output              tlbread_do,
    input               tlbread_done,
    input               tlbread_page_fault,
    input               tlbread_ac_fault,
    input               tlbread_retry,
    
    output      [1:0]   tlbread_cpl,
    output      [31:0]  tlbread_address,
    output      [3:0]   tlbread_length,
    output      [3:0]   tlbread_length_full,
    output              tlbread_lock,
    output              tlbread_rmw,
    input       [63:0]  tlbread_data
    //END
);

//------------------------------------------------------------------------------

reg [1:0]   state;
reg [55:0]  buffer;
reg [3:0]   length_2_reg;
reg [31:0]  address_2_reg;
reg         reset_waiting;

reg         read_done_next;
reg [63:0]  read_data_next;

//------------------------------------------------------------------------------

wire [63:0] merged;
wire [4:0]  left_in_line;
wire [3:0]  length_1;
wire [3:0]  length_2;
wire [31:0] address_2;

//------------------------------------------------------------------------------

localparam [1:0] STATE_IDLE        = 2'd0;
localparam [1:0] STATE_WAIT        = 2'd1;
localparam [1:0] STATE_FIRST       = 2'd2;
localparam [1:0] STATE_SECOND      = 2'd3;

//------------------------------------------------------------------------------

assign left_in_line = 5'd16 - { 1'b0, read_address[3:0] };

assign length_1 = (left_in_line >= { 1'd0, read_length })? read_length : left_in_line[3:0];

assign length_2 = read_length - length_1;

assign address_2 = { read_address[31:4], 4'd0 } + 32'd16;

assign tlbread_cpl         = read_cpl;
assign tlbread_length_full = read_length;
assign tlbread_lock        = read_lock;
assign tlbread_rmw         = read_rmw;

//------------------------------------------------------------------------------

reg [3:0]  length_1_save;
always @(posedge clk) length_1_save <= length_1;

assign merged =
    (length_1_save == 4'd1)? { tlbread_data[55:0], buffer[7:0] } :
    (length_1_save == 4'd2)? { tlbread_data[47:0], buffer[15:0] } :
    (length_1_save == 4'd3)? { tlbread_data[39:0], buffer[23:0] } :
    (length_1_save == 4'd4)? { tlbread_data[31:0], buffer[31:0] } :
    (length_1_save == 4'd5)? { tlbread_data[23:0], buffer[39:0] } :
    (length_1_save == 4'd6)? { tlbread_data[15:0], buffer[47:0] } :
                             { tlbread_data[7:0],  buffer[55:0] };

//------------------------------------------------------------------------------

always @(posedge clk) begin
    if(rst_n == 1'b0)                           reset_waiting <= `FALSE;
    else if(rd_reset && state != STATE_IDLE)    reset_waiting <= `TRUE;
    else if(state == STATE_IDLE)                reset_waiting <= `FALSE;
end

always @(posedge clk) begin
    if(rst_n == 1'b0)                               read_page_fault <= `FALSE;
    else if(rd_reset)                               read_page_fault <= `FALSE;
    else if(tlbread_page_fault && ~(reset_waiting)) read_page_fault <= `TRUE;
end

always @(posedge clk) begin
    if(rst_n == 1'b0)                               read_ac_fault <= `FALSE;
    else if(rd_reset)                               read_ac_fault <= `FALSE;
    else if(tlbread_ac_fault && ~(reset_waiting))   read_ac_fault <= `TRUE;
end

//------------------------------------------------------------------------------

assign tlbread_address = (state == STATE_SECOND) ? address_2_reg : read_address;
assign tlbread_length  = (state == STATE_SECOND) ? length_2_reg : length_1;

assign tlbread_do =
    (state == STATE_IDLE && read_do && ~(read_done_next) && ~(rd_reset) && ~(read_page_fault) && ~(read_ac_fault))? 1'b1 :
    (state == STATE_WAIT)?   1'b1 :
    (state == STATE_FIRST)?  1'b1 :
    (state == STATE_SECOND)? 1'b1 :
    1'b0;


assign read_done = (state == STATE_WAIT && ~(tlbread_page_fault || tlbread_ac_fault || (tlbread_retry && reset_waiting)) && tlbread_done && ~rd_reset && ~reset_waiting)? 1'b1 : read_done_next;
assign read_data = (state == STATE_WAIT) ? tlbread_data : read_data_next;


always @(posedge clk) begin
   if(!rst_n) begin
      state <= STATE_IDLE;
   end
   else begin
      read_done_next <= 1'b0;
   
		case(state)
         STATE_IDLE:
            begin
               length_2_reg  <= length_2;
               address_2_reg <= { address_2[31:4], 4'd0 };
               if(read_do && ~(read_done_next) && ~(rd_reset) && ~(read_page_fault) && ~(read_ac_fault)) begin
                  if (length_2 == 4'd0) begin
                     state <= STATE_WAIT;
                  end else begin
                     state <= STATE_FIRST;
                  end
               end
            end
            
         STATE_WAIT:
            if(tlbread_page_fault || tlbread_ac_fault || (tlbread_retry && reset_waiting)) begin
               state <= STATE_IDLE;  
            end else if(tlbread_done) begin
               state          <= STATE_IDLE;
               read_data_next <= tlbread_data;
            end
         
         
         STATE_FIRST:
            begin
               if(tlbread_page_fault || tlbread_ac_fault || (tlbread_retry && reset_waiting)) begin
                  state <= STATE_IDLE;  
               end else if(tlbread_done) begin
                  buffer <= tlbread_data[55:0];
                  state  <= STATE_SECOND;
               end
            end
            
         STATE_SECOND:
            begin
               if(tlbread_page_fault || tlbread_ac_fault || tlbread_done || (tlbread_retry && reset_waiting)) begin
                  state <= STATE_IDLE;
               end
               
               if(tlbread_done && rd_reset == `FALSE && reset_waiting == `FALSE) begin
                  read_done_next <= 1'b1;
                  read_data_next <= merged;
               end
            end
         
      endcase
   end
end


endmodule
