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

module icache_read(
   
    input [31:0]            read_data,
    input [2:0]             read_length,
    
    input [31:0]            address,
    input [4:0]             length,
    
    output [11:0]           length_burst,
    output [67:0]           prefetch_line
);

//------------------------------------------------------------------------------

//------------------------------------------------------------------------------

assign length_burst =
    (address[1:0] == 2'd0)?    { 3'd4, 3'd4, 3'd4, 3'd4 } :
    (address[1:0] == 2'd1)?    { 3'd4, 3'd4, 3'd4, 3'd3 } :
    (address[1:0] == 2'd2)?    { 3'd4, 3'd4, 3'd4, 3'd2 } :
                               { 3'd4, 3'd4, 3'd4, 3'd1 };
                            
assign prefetch_line =
    (read_length[2:0] == 3'd1)?   { 4'd1,                                56'd0, read_data[31:24] } :
    (read_length[2:0] == 3'd2)?   { (length > 5'd2)? 4'd2 : length[3:0], 48'd0, read_data[31:16] } :
    (read_length[2:0] == 3'd3)?   { (length > 5'd3)? 4'd3 : length[3:0], 40'd0, read_data[31:8] } :
                                  { (length > 5'd4)? 4'd4 : length[3:0], 32'd0, read_data[31:0] };

//------------------------------------------------------------------------------

//------------------------------------------------------------------------------

// synthesis translate_off
wire _unused_ok = &{ 1'b0, address[31:4], 1'b0 };
// synthesis translate_on

//------------------------------------------------------------------------------
    
endmodule
