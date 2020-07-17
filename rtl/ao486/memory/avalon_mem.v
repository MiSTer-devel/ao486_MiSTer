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
    input       [31:0]  avm_readdata,

    input       [23:0]  dma_address,
    input               dma_write,
    input       [31:0]  dma_writedata,
    input       [3:0]   dma_byteenable,
    input               dma_read,
    output      [31:0]  dma_readdata,
    output              dma_readdatavalid,
    output              dma_waitrequest
);

//------------------------------------------------------------------------------

reg [31:0]  bus_0;
reg [31:0]  bus_1;

reg [3:0]   byteenable_next;
reg [2:0]   counter;
reg [2:0]   state;

reg [31:2]  writeaddr_next;
reg [31:0]  save_data;
reg  [1:0]  save_readburst;

//------------------------------------------------------------------------------

localparam [2:0] STATE_IDLE      = 3'd0;
localparam [2:0] STATE_WRITE     = 3'd1;
localparam [2:0] STATE_READ      = 3'd2;
localparam [2:0] STATE_READ_CODE = 3'd3;
localparam [2:0] STATE_WRITE_DMA = 3'd4;
localparam [2:0] STATE_READ_DMA  = 3'd5;

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

assign dma_readdata      = avm_readdata;
assign dma_waitrequest   = state != STATE_READ_DMA  && state != STATE_WRITE_DMA;
assign dma_readdatavalid = state == STATE_READ_DMA  && avm_readdatavalid;

assign writeburst_done   = state == STATE_IDLE      && writeburst_do && ~avm_waitrequest;
assign readburst_done    = state == STATE_READ      && counter == 3'd0 && avm_readdatavalid;
assign readcode_done     = state == STATE_READ_CODE && avm_readdatavalid;

assign avm_address = 
   (state != STATE_IDLE) ? writeaddr_next :
   writeburst_do         ? writeburst_address[31:2] :
   readburst_do          ? readburst_address[31:2] :
   readcode_do           ? readcode_address[31:2] :
                           dma_address[23:2];

assign avm_writedata  =
   (state != STATE_IDLE) ? save_data :
   writeburst_do         ? writeburst_data[31:0] :
                           dma_writedata;
	
assign avm_byteenable = 
   (state != STATE_IDLE)         ? byteenable_next :
   writeburst_do                 ? writeburst_byteenable_0 : 
   (readburst_do || readcode_do) ? read_burst_byteenable : 
                                   dma_byteenable;

assign avm_burstcount = 
   readburst_do ? { 2'b0, readburst_dword_length }  :
   readcode_do  ? 4'd8 :
                  4'd1;

wire dma_start = ~(writeburst_do | readburst_do | readcode_do);
assign avm_write = rst_n && ((state == STATE_IDLE && (writeburst_do || (dma_write && dma_start))) || state == STATE_WRITE);
assign avm_read  = rst_n && state == STATE_IDLE && ~writeburst_do && (readburst_do || readcode_do || dma_read);

always @(posedge clk) begin
   if(!rst_n) begin
      state           <= STATE_IDLE;
   end
   else begin
		case(state)
      STATE_IDLE:
         if (~avm_waitrequest) begin
            if (writeburst_do) begin
               if (writeburst_dword_length > 2'd1) begin
                  state        <= STATE_WRITE;
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
            else if (dma_write) begin
               state <= STATE_WRITE_DMA;
            end
            else if (dma_read) begin
               state <= STATE_READ_DMA;
            end
         end

		STATE_WRITE:
         if (~avm_waitrequest) begin
            state <= STATE_IDLE;
         end

		STATE_READ:
         if (avm_readdatavalid) begin
            if(counter == 3'd2) bus_1 <= avm_readdata;
            if(counter == 3'd1) bus_0 <= avm_readdata;
            counter <= counter - 3'd1;     
            if(counter == 3'd0) state <= STATE_IDLE;
         end

		STATE_READ_CODE:
         if (avm_readdatavalid) begin
            counter <= counter - 3'd1;     
            if(counter == 3'd0) state <= STATE_IDLE;
         end

		STATE_WRITE_DMA:
			begin
				state <= STATE_IDLE;
			end
      
		STATE_READ_DMA:
         if (avm_readdatavalid) begin
				state <= STATE_IDLE;
			end
		endcase
	end
end

endmodule
