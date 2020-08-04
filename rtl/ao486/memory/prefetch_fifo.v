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

module prefetch_fifo(
    input           clk,
    input           rst_n,
    
    input           pr_reset,
    
    //RESP:
    input           prefetchfifo_signal_limit_do,
    //END
    
    //RESP:
    input           prefetchfifo_signal_pf_do,
    //END
    
    //RESP:
    input           prefetchfifo_write_do,
    input   [35:0]  prefetchfifo_write_data,
    //END
    
    output  [4:0]   prefetchfifo_used,
    
    //RESP:
    input           prefetchfifo_accept_do,
    output [67:0]   prefetchfifo_accept_data,
    output          prefetchfifo_accept_empty
    //END
);

//------------------------------------------------------------------------------

wire [35:0] q;
wire        empty;
wire        bypass;

assign bypass = prefetchfifo_write_do && empty;

assign prefetchfifo_accept_data = (bypass) ? { prefetchfifo_write_data[35:32], 32'd0, prefetchfifo_write_data[31:0] } : { q[35:32], 32'd0, q[31:0] };

assign prefetchfifo_accept_empty = empty && ~bypass;

//------------------------------------------------------------------------------

simple_fifo_mlab #(
    .width      (36),
    .widthu     (4)
)
prefetch_fifo_inst(
    .clk        (clk),      //input
    .rst_n      (rst_n),    //input
    .sclr       (pr_reset), //input
    
    .rdreq      (prefetchfifo_accept_do),                                                               //input
    .wrreq      ((prefetchfifo_write_do && (~empty || ~prefetchfifo_accept_do)) || prefetchfifo_signal_limit_do || prefetchfifo_signal_pf_do),   //input
    .data       ((prefetchfifo_signal_limit_do)? { `PREFETCH_GP_FAULT, 32'd0 } :
                 (prefetchfifo_signal_pf_do)?    { `PREFETCH_PF_FAULT, 32'd0 } :
                                                     prefetchfifo_write_data),                          //input [35:0]
    
    
    .empty      (empty),                    //output
    .full       (prefetchfifo_used[4]),     //output
    .q          (q),                        //output [35:0]
    .usedw      (prefetchfifo_used[3:0])    //output [3:0]
);

//------------------------------------------------------------------------------

//------------------------------------------------------------------------------

//------------------------------------------------------------------------------

//------------------------------------------------------------------------------

endmodule
