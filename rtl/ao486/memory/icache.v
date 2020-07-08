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

module icache(
    input           clk,
    input           rst_n,
    
    //RESP:
    input           pr_reset,
    //END
    
    //RESP:
    input           icacheread_do,
    input   [31:0]  icacheread_address,
    input   [4:0]   icacheread_length, // takes into account: page size and cs segment limit
    input           icacheread_cache_disable,
    //END
    
    //REQ:
    output              readcode_do,
    input               readcode_done,
    
    output      [31:0]  readcode_address,
    input       [127:0] readcode_line,
    input       [31:0]  readcode_partial,
    input               readcode_partial_done,
    //END
    
    //REQ:
    output              prefetchfifo_write_do,
    output  [135:0]     prefetchfifo_write_data,
    //END
    
    //REQ:
    output              prefetched_do,
    output [4:0]        prefetched_length
    //END
);

//------------------------------------------------------------------------------

//------------------------------------------------------------------------------

reg         state;
reg [31:0]  address;
reg [4:0]   length;
reg [11:0]  partial_length;
reg         reset_waiting;

//------------------------------------------------------------------------------

wire [4:0] partial_length_current;

//------------------------------------------------------------------------------

localparam STATE_IDLE             = 1'd0;
localparam STATE_READ             = 1'd1;

//------------------------------------------------------------------------------

//MIN(partial_length, length_saved)
assign partial_length_current =
    ({ 2'b0, partial_length[2:0] } > length)? length : { 2'b0, partial_length[2:0] };
    

//------------------------------------------------------------------------------

always @(posedge clk) begin
    if(rst_n == 1'b0)                           reset_waiting <= `FALSE;
    else if(pr_reset && state != STATE_IDLE)    reset_waiting <= `TRUE;
    else if(state == STATE_IDLE)                reset_waiting <= `FALSE;
end

//------------------------------------------------------------------------------

wire [11:0]     length_burst;
wire [11:0]     length_line;
wire [135:0]    prefetch_line;
wire [135:0]    prefetch_partial;

//------------------------------------------------------------------------------


icache_read icache_read_inst(
   
    .line           (128'b0),        //input [127:0]
    .read_data      (readcode_partial),         //input [31:0]
    .read_length    (partial_length[2:0]),      //input [2:0]
                             
    .address    ((state == STATE_IDLE)? icacheread_address : address),  //input [31:0]
    .length     ((state == STATE_IDLE)? icacheread_length : length),    //input [4:0]
                             
    .length_burst   (length_burst),     //output [11:0]
    .length_line    (length_line),      //output [11:0]
                             
    .prefetch_line      (prefetch_line),    //output [135:0]
    .prefetch_partial   (prefetch_partial)  //output [135:0]
);

assign readcode_do =
   (~rst_n) ? (`FALSE) :
   (state == STATE_IDLE && ~(pr_reset) && icacheread_do && icacheread_length > 5'd0) ? (`TRUE) :
   `FALSE;
   
assign readcode_address = { icacheread_address[31:2], 2'd0 };
   
assign prefetchfifo_write_do =
   (~rst_n) ? (`FALSE) :
   (state == STATE_READ && pr_reset == `FALSE && reset_waiting == `FALSE && (readcode_partial_done || readcode_done)) ? (`TRUE) :
   `FALSE;
   
assign prefetchfifo_write_data = prefetch_partial;
assign prefetched_length       = partial_length_current;

assign prefetched_do =
   (~rst_n) ? (`FALSE) :
   (state == STATE_READ && pr_reset == `FALSE && reset_waiting == `FALSE && (readcode_partial_done || readcode_done)) ? (`TRUE) :
   `FALSE;
   
always @(posedge clk) begin
   if(rst_n == 1'b0) begin
      state          <= STATE_IDLE;
      length         <= 5'b0;
      partial_length <= 12'b0;
   end
   else begin
      if(state == STATE_IDLE && ~(pr_reset) && icacheread_do && icacheread_length > 5'd0) begin
         state          <= STATE_READ;
         partial_length <= length_burst;
         length         <= icacheread_length;
         address        <= icacheread_address;
      end
      else if (state == STATE_READ) begin
         if(pr_reset == `FALSE && reset_waiting == `FALSE) begin
            if(readcode_partial_done || readcode_done) begin
               if(partial_length[2:0] > 3'd0 && length > 5'd0) begin
                  length         <= length - partial_length_current;
                  partial_length <= { 3'd0, partial_length[11:3] }; 
               end
            end
         end
         if(readcode_done) state <= STATE_IDLE;
      end
   end
end   

endmodule
