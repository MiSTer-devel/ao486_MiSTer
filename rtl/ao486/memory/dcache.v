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

module dcache(
    // global
    input               clk,
    input               rst_n,
    
    //RESP:
    input               dcacheread_do,
    output              dcacheread_done,
    
    input   [3:0]       dcacheread_length,
    input   [31:0]      dcacheread_address,
    output  [63:0]      dcacheread_data,
    //END
    
    //RESP:
    input               dcachewrite_do,
    output              dcachewrite_done,
    
    input   [2:0]       dcachewrite_length,
    input   [31:0]      dcachewrite_address,
    input   [31:0]      dcachewrite_data,
    //END
    
    //REQ:
    output              readburst_do,
    input               readburst_done,
    
    output  [31:0]      readburst_address,
    output  [1:0]       readburst_dword_length,
    output  [3:0]       readburst_byte_length,
    input   [95:0]      readburst_data,
    //END
    
    //REQ:
    output              writeburst_do,
    input               writeburst_done,
    
    output      [31:0]  writeburst_address,
    output      [1:0]   writeburst_dword_length,
    output      [3:0]   writeburst_byteenable_0,
    output      [3:0]   writeburst_byteenable_1,
    output      [55:0]  writeburst_data,
    //END
    
    output              dcache_busy
);

//------------------------------------------------------------------------------

localparam [1:0] STATE_IDLE          = 2'd0;
localparam [1:0] STATE_READ_BURST    = 2'd1;
localparam [1:0] STATE_WRITE_THROUGH = 2'd2;

reg [1:0]   state;
reg [1:0]   readaddrmux;

assign dcache_busy = 1'b0;

//------------------------------------------------------------------------------

assign readburst_dword_length =
    (dcacheread_length == 4'd2 && dcacheread_address[1:0] == 2'b11)?   2'd2 :
    (dcacheread_length == 4'd3 && dcacheread_address[1]   == 1'b1)?    2'd2 :
    (dcacheread_length == 4'd4 && dcacheread_address[1:0] != 2'b00)?   2'd2 :
    (dcacheread_length <= 4'd4)?                            2'd1 :
    (dcacheread_length == 4'd5)?                            2'd2 :
    (dcacheread_length == 4'd6 && dcacheread_address[1:0] == 2'b11)?   2'd3 :
    (dcacheread_length == 4'd7 && dcacheread_address[1]   == 1'b1)?    2'd3 :
    (dcacheread_length == 4'd8 && dcacheread_address[1:0] != 2'b00)?   2'd3 :
                                                 2'd2;

assign readburst_byte_length = dcacheread_length;

assign dcacheread_data =
    (readaddrmux == 2'd0)?     readburst_data[63:0]  :
    (readaddrmux == 2'd1)?     readburst_data[71:8]  :
    (readaddrmux == 2'd2)?     readburst_data[79:16] :
                               readburst_data[87:24];

//------------------------------------------------------------------------------

assign writeburst_dword_length =
    (dcachewrite_length == 3'd2 && dcachewrite_address[1:0] == 2'b11)?  2'd2 :
    (dcachewrite_length == 3'd3 && dcachewrite_address[1]   == 1'b1)?   2'd2 :
    (dcachewrite_length == 3'd4 && dcachewrite_address[1:0] != 2'b00)?  2'd2 :
                                                2'd1;
                                                
assign writeburst_byteenable_0 =
    (dcachewrite_address[1:0] == 2'd0 && dcachewrite_length == 3'd1)?   4'b0001 :
    (dcachewrite_address[1:0] == 2'd1 && dcachewrite_length == 3'd1)?   4'b0010 :
    (dcachewrite_address[1:0] == 2'd2 && dcachewrite_length == 3'd1)?   4'b0100 :
    (dcachewrite_address[1:0] == 2'd0 && dcachewrite_length == 3'd2)?   4'b0011 :
    (dcachewrite_address[1:0] == 2'd1 && dcachewrite_length == 3'd2)?   4'b0110 :
    (dcachewrite_address[1:0] == 2'd0 && dcachewrite_length == 3'd3)?   4'b0111 :
    (dcachewrite_address[1:0] == 2'd1 && dcachewrite_length >= 3'd3)?   4'b1110 :
    (dcachewrite_address[1:0] == 2'd2 && dcachewrite_length >= 3'd2)?   4'b1100 :
    (dcachewrite_address[1:0] == 2'd0 && dcachewrite_length == 3'd4)?   4'b1111 :
                                                4'b1000; //(dcachewrite_address[1:0] == 2'd3)?

assign writeburst_byteenable_1 =
   (dcachewrite_address[1:0] == 2'd3 && dcachewrite_length == 3'd2)?   4'b0001 :
   (dcachewrite_address[1:0] == 2'd2 && dcachewrite_length == 3'd3)?   4'b0001 :
   (dcachewrite_address[1:0] == 2'd3 && dcachewrite_length == 3'd3)?   4'b0011 :
   (dcachewrite_address[1:0] == 2'd1 && dcachewrite_length == 3'd4)?   4'b0001 :
   (dcachewrite_address[1:0] == 2'd2 && dcachewrite_length == 3'd4)?   4'b0011 :
                                               4'b0111; //(dcachewrite_address[1:0] == 2'd3 && dcachewrite_length == 3'd4)? 
                                               
assign writeburst_data =
    (dcachewrite_address[1:0] == 2'd0)?   { 24'd0, dcachewrite_data[31:0] } :
    (dcachewrite_address[1:0] == 2'd1)?   { 16'd0, dcachewrite_data[31:0], 8'd0 } :
    (dcachewrite_address[1:0] == 2'd2)?   { 8'd0,  dcachewrite_data[31:0], 16'd0 } :
                              {        dcachewrite_data[31:0], 24'd0 };

//------------------------------------------------------------------------------

assign dcacheread_done = rst_n && (state == STATE_READ_BURST && readburst_done);
assign readburst_do = rst_n && (state == STATE_IDLE && ~dcachewrite_do && dcacheread_do);
assign readburst_address = dcacheread_address;

assign dcachewrite_done = rst_n && (state == STATE_IDLE && dcachewrite_do);
assign writeburst_do = rst_n && (state == STATE_IDLE && dcachewrite_do);
assign writeburst_address = dcachewrite_address;


always @(posedge clk) begin
   if(rst_n == 1'b0) begin
      state <= STATE_IDLE;
   end
   else begin
      if(state == STATE_IDLE) begin
         readaddrmux <= dcacheread_address[1:0];
         if (dcachewrite_do) begin
            state <= STATE_WRITE_THROUGH;
         end
         else if (dcacheread_do) begin
            state  <= STATE_READ_BURST;
         end
      end
      else if (state == STATE_READ_BURST) begin
         if(readburst_done) state <= STATE_IDLE;
      end
      else if (state == STATE_WRITE_THROUGH) begin
         if(writeburst_done) state <= STATE_IDLE;
      end
   end
end   

endmodule
