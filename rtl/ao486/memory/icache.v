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
    
    input           cache_disable,

    //RESP:
    input           pr_reset,
    
    input [31:0]    prefetch_address,
    input [31:0]    delivered_eip,
    output reg      reset_prefetch = 1'd0,
    //END
    
    //RESP:
    input           icacheread_do,
    input   [31:0]  icacheread_address,
    input   [4:0]   icacheread_length, // takes into account: page size and cs segment limit
    //END
    
    //REQ:
    output              readcode_do,
    input               readcode_done,
    
    output      [31:0]  readcode_address,
    input       [31:0]  readcode_partial,
    //END
    
    //REQ:
    output              prefetchfifo_write_do,
    output  [35:0]      prefetchfifo_write_data,
    //END
    
    //REQ:
    output              prefetched_do,
    output [4:0]        prefetched_length,
    //END
    
    input   [27:2]      snoop_addr,
    input   [31:0]      snoop_data,
    input    [3:0]      snoop_be,
    input               snoop_we
);

//------------------------------------------------------------------------------

localparam STATE_IDLE = 1'd0;
localparam STATE_READ = 1'd1;

reg          state;
reg [4:0]    length;
reg [11:0]   partial_length;
reg          reset_waiting;
             
wire [4:0]   partial_length_current;

wire [11:0]  length_burst;

wire         readcode_cache_do;
wire [31:0]  readcode_cache_address;
wire         readcode_cache_valid;
wire         readcode_cache_done;
wire [31:0]  readcode_cache_data;

reg          prefetch_checknext;
reg  [31:0]  prefetch_checkaddr;
reg  [31:0]  min_check;
reg  [31:0]  max_check;
reg   [1:0]  reset_prefetch_count = 2'd0;


//------------------------------------------------------------------------------

wire reset_combined = reset_prefetch | pr_reset;

always @(posedge clk) begin
   prefetch_checknext <= 1'b0;
   prefetch_checkaddr <= { 4'd0, snoop_addr, 2'd0 };
   min_check          <= delivered_eip;
   max_check          <= prefetch_address + 5'd20; // cache read burst is 16 bytes, so we need to look a bit further, additional + 4 because of 1 cycle delay.
   
   if (snoop_we) prefetch_checknext <= 1'b1;
   
   if (prefetch_checknext && prefetch_checkaddr >= min_check && prefetch_checkaddr <= max_check) begin
      reset_prefetch       <= 1'b1;
      reset_prefetch_count <= 2'd2;
   end
   
   if (reset_prefetch_count > 2'd0) begin
      reset_prefetch_count <= reset_prefetch_count - 1'd1;
      if (reset_prefetch_count == 2'd1) reset_prefetch <= 1'd0;
   end
   
end

//------------------------------------------------------------------------------

//MIN(partial_length, length_saved)
assign partial_length_current =
    ({ 2'b0, partial_length[2:0] } > length)? length : { 2'b0, partial_length[2:0] };
    
//------------------------------------------------------------------------------

always @(posedge clk) begin
    if(rst_n == 1'b0)                                 reset_waiting <= `FALSE;
    else if(reset_combined && state != STATE_IDLE)    reset_waiting <= `TRUE;
    else if(state == STATE_IDLE)                      reset_waiting <= `FALSE;
end

//------------------------------------------------------------------------------

assign length_burst =
    (icacheread_address[1:0] == 2'd0)? { 3'd4, 3'd4, 3'd4, 3'd4 } :
    (icacheread_address[1:0] == 2'd1)? { 3'd4, 3'd4, 3'd4, 3'd3 } :
    (icacheread_address[1:0] == 2'd2)? { 3'd4, 3'd4, 3'd4, 3'd2 } :
                                       { 3'd4, 3'd4, 3'd4, 3'd1 };
                            
assign prefetchfifo_write_data =
    (partial_length[2:0] == 3'd1)?   {                  4'd1 ,              24'd0, readcode_cache_data[31:24] } :
    (partial_length[2:0] == 3'd2)?   { (length > 5'd2)? 4'd2 : length[3:0], 16'd0, readcode_cache_data[31:16] } :
    (partial_length[2:0] == 3'd3)?   { (length > 5'd3)? 4'd3 : length[3:0],  8'd0, readcode_cache_data[31:8] } :
                                     { (length > 5'd4)? 4'd4 : length[3:0],        readcode_cache_data[31:0] };

//------------------------------------------------------------------------------

l1_icache l1_icache_inst(
   
    .CLK             (clk),
    .RESET           (~rst_n),
    .pr_reset        (reset_combined),
	 
    .DISABLE         (cache_disable),

    .CPU_REQ         (readcode_cache_do),
    .CPU_ADDR        (readcode_cache_address),
    .CPU_VALID       (readcode_cache_valid),
    .CPU_DONE        (readcode_cache_done),
    .CPU_DATA        (readcode_cache_data),
    
    .MEM_REQ         (readcode_do),
    .MEM_ADDR        (readcode_address),
    .MEM_DONE        (readcode_done),
    .MEM_DATA        (readcode_partial),
    
    .snoop_addr      (snoop_addr),
    .snoop_data      (snoop_data),
    .snoop_be        (snoop_be),
    .snoop_we        (snoop_we)
);

assign readcode_cache_do =
   (~rst_n) ? (`FALSE) :
   (state == STATE_IDLE && ~(reset_combined) && icacheread_do && icacheread_length > 5'd0) ? (`TRUE) :
   `FALSE;
   
assign readcode_cache_address = { icacheread_address[31:2], 2'd0 };
   
assign prefetchfifo_write_do =
   (~rst_n) ? (`FALSE) :
   (state == STATE_READ && reset_combined == `FALSE && reset_waiting == `FALSE && readcode_cache_valid) ? (`TRUE) :
   `FALSE;
   
assign prefetched_length       = partial_length_current;

assign prefetched_do =
   (~rst_n) ? (`FALSE) :
   (state == STATE_READ && reset_combined == `FALSE && reset_waiting == `FALSE && readcode_cache_valid) ? (`TRUE) :
   `FALSE;
   
always @(posedge clk) begin
   if(rst_n == 1'b0) begin
      state          <= STATE_IDLE;
      length         <= 5'b0;
      partial_length <= 12'b0;
   end
   else begin
      if(state == STATE_IDLE && ~(reset_combined) && icacheread_do && icacheread_length > 5'd0) begin
         state          <= STATE_READ;
         partial_length <= length_burst;
         length         <= icacheread_length;
      end
      else if (state == STATE_READ) begin
         if(reset_combined == `FALSE && reset_waiting == `FALSE) begin
            if(readcode_cache_valid) begin
               if(partial_length[2:0] > 3'd0 && length > 5'd0) begin
                  length         <= length - partial_length_current;
                  partial_length <= { 3'd0, partial_length[11:3] }; 
               end
            end
         end
         if(readcode_cache_done) state <= STATE_IDLE;
      end
   end
end     

endmodule
