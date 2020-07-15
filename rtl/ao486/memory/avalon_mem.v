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

module avalon_mem(
    // global
    input               clk,
    input               rst_n,
    
    //RESP:
    input               writeburst_do,
    output              writeburst_done,
    
    input       [31:0]  writeburst_address,
    input       [1:0]   writeburst_dword_length,
    input       [3:0]   writeburst_byteenable_0,
    input       [3:0]   writeburst_byteenable_1,
    input       [55:0]  writeburst_data,
    //END
    
    //RESP:
    input               readburst_do,
    output              readburst_done,
    
    input       [31:0]  readburst_address,
    input       [1:0]   readburst_dword_length,
    input       [3:0]   readburst_byte_length,
    output      [95:0]  readburst_data,
    //END
    
    //RESP:
    input               readcode_do,
    output              readcode_done,
    
    input       [31:0]  readcode_address,
    output      [31:0]  readcode_partial,
    //END
    
    // avalon master
    output      [31:2]  avm_address,
    output      [31:0]  avm_writedata,
    output      [3:0]   avm_byteenable,
    output      [3:0]   avm_burstcount,
    output              avm_write,
    output              avm_read,
    
    input               avm_waitrequest,
    input               avm_readdatavalid,
    input       [31:0]  avm_readdata
);

//------------------------------------------------------------------------------

reg [31:0]  bus_0;
reg [31:0]  bus_1;
reg [31:0]  bus_2;

reg [3:0]   byteenable_next;
reg [2:0]   counter;
reg [1:0]   state;

reg [31:2]  writeaddr_next;
reg [31:0]  save_data;
reg  [1:0]  save_readburst;

//------------------------------------------------------------------------------

localparam [1:0] STATE_IDLE      = 2'd0;
localparam [1:0] STATE_WRITE     = 2'd1;
localparam [1:0] STATE_READ      = 2'd2;
localparam [1:0] STATE_READ_CODE = 2'd3;

//------------------------------------------------------------------------------

wire [3:0] read_burst_byteenable =
    (readburst_byte_length == 4'd1 && readburst_address[1:0] == 2'd0)?  4'b0001 :
    (readburst_byte_length == 4'd1 && readburst_address[1:0] == 2'd1)?  4'b0010 :
    (readburst_byte_length == 4'd1 && readburst_address[1:0] == 2'd2)?  4'b0100 :
    (readburst_byte_length == 4'd1 && readburst_address[1:0] == 2'd3)?  4'b1000 :
    
    (readburst_byte_length == 4'd2 && readburst_address[1:0] == 2'd0)?  4'b0011 :
    (readburst_byte_length == 4'd2 && readburst_address[1:0] == 2'd1)?  4'b0110 :
    (readburst_byte_length == 4'd2 && readburst_address[1:0] == 2'd2)?  4'b1100 :
    
    (readburst_byte_length == 4'd3 && readburst_address[1:0] == 2'd0)?  4'b0111 :
    (readburst_byte_length == 4'd3 && readburst_address[1:0] == 2'd1)?  4'b1110 :
    
                                                                        4'b1111;

//------------------------------------------------------------------------------

assign readburst_data = 
   (save_readburst == 2'd1) ? { avm_readdata, avm_readdata, avm_readdata } :
   (save_readburst == 2'd2) ? { avm_readdata, avm_readdata, bus_0        } :
                              { avm_readdata, bus_0       , bus_1        };


assign readcode_partial = avm_readdata;

//------------------------------------------------------------------------------

assign writeburst_done = (rst_n && state == STATE_IDLE && writeburst_do && ~avm_waitrequest) ? `TRUE : `FALSE;
assign readburst_done  = (rst_n && state == STATE_READ      && counter == 3'd0 && avm_readdatavalid) ? `TRUE : `FALSE;
assign readcode_done   = (state == STATE_READ_CODE && avm_readdatavalid) ? `TRUE : `FALSE;

assign avm_address = 
   (state == STATE_IDLE  && writeburst_do)    ? writeburst_address[31:2] :
   (state == STATE_IDLE  && readburst_do)     ? readburst_address[31:2]  :
   (state == STATE_WRITE)                     ? writeaddr_next  :
   readcode_address[31:2];

assign avm_writedata  = (state == STATE_IDLE) ? writeburst_data[31:0]   : save_data;
assign avm_byteenable = 
   (state == STATE_IDLE  && writeburst_do) ? writeburst_byteenable_0 : 
   (state == STATE_IDLE)                   ? read_burst_byteenable : 
   byteenable_next;

assign avm_burstcount = 
   // (state == STATE_IDLE && writeburst_do) ? { 1'b0, writeburst_dword_length } : // ignored by L2 cache
   (state == STATE_IDLE && readburst_do)  ? { 2'b0, readburst_dword_length }  :
   4'd8;

assign avm_write = (rst_n && ((state == STATE_IDLE && writeburst_do) || state == STATE_WRITE)) ? `TRUE : `FALSE;

assign avm_read  = (rst_n && state == STATE_IDLE && ~writeburst_do && (readburst_do  || readcode_do)) ? `TRUE : `FALSE;



always @(posedge clk) begin
   if(rst_n == 1'b0) begin
      state           <= STATE_IDLE;
      bus_0           <= 32'd0;
      bus_1           <= 32'd0;
      bus_2           <= 32'd0;
      byteenable_next <= 4'd0;
      save_readburst  <= 2'd0;
   end
   else begin
      if(state == STATE_IDLE) begin
         if (~avm_waitrequest) begin
            if (writeburst_do) begin
               if (writeburst_dword_length > 2'd1) begin
                  state           <= STATE_WRITE;
               end
               save_data       <= { 8'd0, writeburst_data[55:32] };
               byteenable_next <= writeburst_byteenable_1;
               writeaddr_next  <= writeburst_address[31:2] + 30'd1;
            end
            else if (readburst_do) begin
               state          <= STATE_READ;
               counter        <= readburst_dword_length - 3'd1;
               save_readburst <= readburst_dword_length;
            end
            else if (readcode_do) begin
               state   <= STATE_READ_CODE;
               counter <= 3'd7;
            end
         end
      end
      else if (state == STATE_WRITE) begin
         if (~avm_waitrequest) begin
            state <= STATE_IDLE;
         end
      end
      else if (state == STATE_READ) begin
         if (avm_readdatavalid) begin
            if(counter == 3'd2) bus_1 <= avm_readdata;
            if(counter == 3'd1) bus_0 <= avm_readdata;
            counter <= counter - 3'd1;     
            if(counter == 3'd0) state <= STATE_IDLE;
         end
      end
      else if (state == STATE_READ_CODE) begin
         if (avm_readdatavalid) begin
            counter <= counter - 3'd1;     
            if(counter == 3'd0) state <= STATE_IDLE;
         end
      end
   end
end   

endmodule
