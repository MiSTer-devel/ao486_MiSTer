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
    input               dcacheread_cache_disable,
    input   [31:0]      dcacheread_address,
    output  [63:0]      dcacheread_data,
    //END
    
    //RESP:
    input               dcachewrite_do,
    output              dcachewrite_done,
    
    input   [2:0]       dcachewrite_length,
    input               dcachewrite_cache_disable,
    input   [31:0]      dcachewrite_address,
    input               dcachewrite_write_through,
    input   [31:0]      dcachewrite_data,
    //END
    
    //REQ:
    //output              readline_do,
    //input               readline_done,
    //
    //output  [31:0]      readline_address,
    //input   [127:0]     readline_line,
    //END
    
    //REQ:
    output              readburst_do,
    input               readburst_done,
    
    output  [31:0]      readburst_address,
    output  [1:0]       readburst_dword_length,
    output  [3:0]       readburst_byte_length,
    input   [95:0]      readburst_data,
    //END
    
    //REQ: write line
    //output              writeline_do,
    //input               writeline_done,
    //
    //output      [31:0]  writeline_address,
    //output      [127:0] writeline_line,
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
    
    output              dcachetoicache_write_do,
    output      [31:0]  dcachetoicache_write_address,
    
    //RESP:
    input               invddata_do,
    output              invddata_done,
    //END
    
    //RESP:
    input               wbinvddata_do,
    output              wbinvddata_done,
    //END
    
    output              dcache_busy
);

//------------------------------------------------------------------------------

reg [31:0]  address;
reg         cache_disable;
reg [3:0]   length;

reg         write_through;
reg [31:0]  write_data;

reg         is_write;
reg [1:0]   state;

//------------------------------------------------------------------------------

localparam [1:0] STATE_IDLE          = 3'd0;
localparam [1:0] STATE_READ_BURST    = 3'd1;
localparam [1:0] STATE_WRITE_THROUGH = 3'd2;

//------------------------------------------------------------------------------

wire        wbinvdread_do;
wire [7:0]  wbinvdread_address;

wire            dcache_writeline_do;
wire [31:0]     dcache_writeline_address;
wire [127:0]    dcache_writeline_line;

//------------------------------------------------------------------------------

wire            control_ram_writeline_do;
wire [31:0]     control_ram_writeline_address;
wire [127:0]    control_ram_writeline_line;

assign writeline_do         = dcache_writeline_do || control_ram_writeline_do;
assign writeline_address    = (dcache_writeline_do)? dcache_writeline_address : control_ram_writeline_address;
assign writeline_line       = (dcache_writeline_do)? dcache_writeline_line    : control_ram_writeline_line;

assign dcache_busy = 1'b0;

//------------------------------------------------------------------------------

wire [31:0] control_ram_address;
wire        control_ram_read_do;
wire        control_ram_write_do;
wire [10:0] control_ram_data;
wire [10:0] control_ram_q;

//------------------------------------------------------------------------------

wire         matched;
wire [1:0]   matched_index;
wire [127:0] matched_data_line;

wire [1:0]   plru_index;
wire [147:0] plru_data_line;

wire [10:0]  control_after_match;
wire [10:0]  control_after_line_read;
wire [10:0]  control_after_write_to_existing;
wire [10:0]  control_after_write_to_new;

wire         writeback_needed;

//------------------------------------------------------------------------------

wire [63:0] read_from_line;
wire [1:0]  read_burst_dword_length;
wire [3:0]  read_burst_byte_length;
wire [63:0] read_from_burst;

//------------------------------------------------------------------------------

wire [127:0] line_merged;
wire [1:0]   write_burst_dword_length;
wire [3:0]   write_burst_byteenable_0;
wire [3:0]   write_burst_byteenable_1;
wire [55:0]  write_burst_data;

//------------------------------------------------------------------------------

wire            data_ram0_read_do;
wire [31:0]     data_ram0_address;
wire            data_ram0_write_do;
wire [127:0]    data_ram0_data;
wire [147:0]    data_ram0_q;

wire            data_ram1_read_do;
wire [31:0]     data_ram1_address;
wire            data_ram1_write_do;
wire [127:0]    data_ram1_data;
wire [147:0]    data_ram1_q;

wire            data_ram2_read_do;
wire [31:0]     data_ram2_address;
wire            data_ram2_write_do;
wire [127:0]    data_ram2_data;
wire [147:0]    data_ram2_q;

wire            data_ram3_read_do;
wire [31:0]     data_ram3_address;
wire            data_ram3_write_do;
wire [127:0]    data_ram3_data;
wire [147:0]    data_ram3_q;

//------------------------------------------------------------------------------

assign matched = 1'b0;

dcache_read dcache_read_inst(
    
    .line       (128'b0),    //input [127:0]
    .read_data  (readburst_data),                               //input [95:0]                         
                             
    .address    (dcacheread_address),                           //input [31:0]
    .length     (dcacheread_length),                            //input [3:0]

    .read_from_line             (read_from_line),               //output [63:0]
    .read_burst_dword_length    (readburst_dword_length),       //output [1:0]
    .read_burst_byte_length     (readburst_byte_length),        //output [11:0]
    .read_from_burst            (read_from_burst)               //output [63:0]
);

dcache_write dcache_write_inst(
    
    .line       (128'b0),                                       //input [127:0]
    .address    (dcachewrite_address),                          //input [31:0]
    .length     (dcachewrite_length),                           //input [2:0]
    .write_data (dcachewrite_data),                             //input [31:0]
                               
    .write_burst_dword_length   (writeburst_dword_length),      //output [1:0]
    .write_burst_byteenable_0   (writeburst_byteenable_0),      //output [3:0]
    .write_burst_byteenable_1   (writeburst_byteenable_1),      //output [3:0]
    .write_burst_data           (writeburst_data),              //output [55:0]
    .line_merged                (line_merged)                   //output [127:0]
);

assign dcacheread_done =
   (~rst_n) ? (`FALSE) :
   (state == STATE_READ_BURST && readburst_done) ? (`TRUE) :
   `FALSE;
assign dcacheread_data = read_from_burst;

assign dcachewrite_done =
   (~rst_n) ? (`FALSE) :
   (state == STATE_IDLE && dcachewrite_do) ? (`TRUE) :
   `FALSE;   


assign readburst_do =
   (~rst_n) ? (`FALSE) :
   (state == STATE_IDLE && ~dcachewrite_do && dcacheread_do) ? (`TRUE) :
   `FALSE;
assign readburst_address = dcacheread_address;

assign writeburst_do =
   (~rst_n) ? (`FALSE) :
   (state == STATE_IDLE && dcachewrite_do) ? (`TRUE) :
   `FALSE;
assign writeburst_address = dcachewrite_address;



always @(posedge clk) begin
   if(rst_n == 1'b0) begin
      state          <= STATE_IDLE;
   end
   else begin
      if(state == STATE_IDLE) begin
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
