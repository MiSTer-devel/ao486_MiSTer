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

module simple_fifo_mlab
#(
   parameter width     = 1,
   parameter widthu    = 1
)
(
    input                       clk,
    input                       rst_n,
    input                       sclr,
    
    input                       rdreq,
    input                       wrreq,
    input       [width-1:0]     data,
    
    output                      empty,
    output reg                  full,
    output      [width-1:0]     q,
    output reg  [widthu-1:0]    usedw
);


reg [width-1:0] mem [(2**widthu)-1:0];

reg [widthu-1:0] rd_index = 0;
reg [widthu-1:0] wr_index = 0;

assign empty= usedw == 0 && ~(full);

always @(posedge clk) begin
    if(rst_n == 1'b0)           rd_index <= 0;
    else if(sclr)               rd_index <= 0;
    else if(rdreq && ~(empty))  rd_index <= rd_index + { {widthu-1{1'b0}}, 1'b1 };
end

always @(posedge clk) begin
    if(rst_n == 1'b0)                       wr_index <= 0;
    else if(sclr)                           wr_index <= 0;
    else if(wrreq && (~(full) || rdreq))    wr_index <= wr_index + { {widthu-1{1'b0}}, 1'b1 };
end

always @(posedge clk) begin
    if(rst_n == 1'b0)                                               full <= 1'b0;
    else if(sclr)                                                   full <= 1'b0;
    else if(rdreq && ~(wrreq) && full)                              full <= 1'b0;
    else if(~(rdreq) && wrreq && ~(full) && usedw == (2**widthu)-1) full <= 1'b1;
end

always @(posedge clk) begin
    if(rst_n == 1'b0)                       usedw <= 0;
    else if(sclr)                           usedw <= 0;
    else if(rdreq && ~(wrreq) && ~(empty))  usedw <= usedw - { {widthu-1{1'b0}}, 1'b1 };
    else if(~(rdreq) && wrreq && ~(full))   usedw <= usedw + { {widthu-1{1'b0}}, 1'b1 };
    else if(rdreq && wrreq && empty)        usedw <= { {widthu-1{1'b0}}, 1'b1 };
end

altdpram	altdpram_component (
			.data (data),
			.inclock (clk),
			.outclock (clk),
			.rdaddress (rd_index),
			.wraddress (wr_index),
			.wren (wrreq && (~(full) || rdreq)),
			.q (q),
			.aclr (1'b0),
			.byteena (1'b1),
			.inclocken (1'b1),
			.outclocken (1'b1),
			.rdaddressstall (1'b0),
			.rden (1'b1),
			.sclr (1'b0),
			.wraddressstall (1'b0));
defparam
	altdpram_component.indata_aclr = "OFF",
	altdpram_component.indata_reg = "INCLOCK",
	altdpram_component.intended_device_family = "Cyclone V",
	altdpram_component.lpm_type = "altdpram",
	altdpram_component.outdata_aclr = "OFF",
	altdpram_component.outdata_reg = "UNREGISTERED",
	altdpram_component.ram_block_type = "MLAB",
	altdpram_component.rdaddress_aclr = "OFF",
	altdpram_component.rdaddress_reg = "UNREGISTERED",
	altdpram_component.rdcontrol_aclr = "OFF",
	altdpram_component.rdcontrol_reg = "UNREGISTERED",
	altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
	altdpram_component.width = width,
	altdpram_component.widthad = widthu,
	altdpram_component.width_byteena = 1,
	altdpram_component.wraddress_aclr = "OFF",
	altdpram_component.wraddress_reg = "INCLOCK",
	altdpram_component.wrcontrol_aclr = "OFF",
	altdpram_component.wrcontrol_reg = "INCLOCK";

endmodule
