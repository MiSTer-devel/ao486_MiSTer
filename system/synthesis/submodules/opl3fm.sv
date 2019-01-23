`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: opl3seq.v
// Description: Part of the Next186 SoC PC project, OPL3 
// Version 1.0
// Creation date: 13:55:57 02/27/2017
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2017 Nicolae Dumitrache
// 
// This source file may be used and distributed without 
// restriction provided that this copyright statement is not 
// removed from the file and that any derivative work contains 
// the original copyright notice and the associated disclaimer.
// 
// This source file is free software; you can redistribute it 
// and/or modify it under the terms of the GNU Lesser General 
// Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any 
// later version. 
// 
// This source is distributed in the hope that it will be 
// useful, but WITHOUT ANY WARRANTY; without even the implied 
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
// PURPOSE. See the GNU Lesser General Public License for more 
// details. 
// 
// You should have received a copy of the GNU Lesser General 
// Public License along with this source; if not, download it 
// from http://www.opencores.org/lgpl.shtml 
// 
///////////////////////////////////////////////////////////////////////////////////
// Additional Comments: 
//
// Port0 (R) = 4'b0000, Addr[1:0], qempty, ready 
// Port1 (R) = Value[7:0], advance queue
//
///////////////////////////////////////////////////////////////////////////////////

// 
// Improved reset stability and firmware portability by Sorgelig.
// 

module opl3sw #(parameter OPLCLK = 50000000)
(
	input         reset,

	// CPU interface
	input         cpu_clk,
	input   [1:0] addr,
	input   [7:0] din,
	input         wr,

	// OPL sequencer
	input         clk,   // 50Mhz (min 45Mhz)
	output [15:0] left,
	output [15:0] right
);
	 
wire  [7:0] ram_dout;
opl3_mem ram
(
	.clk(clk),
	.addr1(CPU_ADDR[12:0]),
	.we1(CPU_MREQ & CPU_WR & CE),
	.data_in1(CPU_DOUT),
	.data_out1(ram_dout),

	.addr2(OPL3Struct_base+seq_addr),
	.we2(seq_wr),
	.data_in2(seq_wdata),
	.data_out2(seq_rdata)
);

wire  [9:0] qdata;
wire        qempty;

// show ahead fifo
opl3_fifo in_queue
(
	.aclr(reset),

	.wrclk(cpu_clk),
	.data({addr, din}),
	.wrreq(wr),

	.rdclk(clk),
	.q(qdata),
	.rdreq(CE && CPU_IORQ && !CPU_WR && CPU_ADDR[0]),
	.rdempty(qempty)
);


reg stb44100;
always @(posedge clk) begin
	integer cnt;
	localparam RATE = (OPLCLK/44100)-1;

	cnt <= cnt+1;
	if(cnt == RATE) cnt <= 0;

	stb44100 <= !cnt;
end

wire        seq_wr;
wire [11:0] seq_addr;
wire [15:0] seq_rdata;
wire [15:0] seq_wdata;
wire        ready;

reg  [11:0] OPL3Struct_base = 0;
reg         seq_reset_n = 0;

always @(posedge clk) begin
	if(reset) seq_reset_n <= 0;

	if(CPU_IORQ & CPU_WR & CE) begin
		if(CPU_ADDR[0]) {seq_reset_n, OPL3Struct_base[11:7]} <= {1'b1, CPU_DOUT[4:0]};
		else OPL3Struct_base[6:0] <= CPU_DOUT[7:1];
	end
end

opl3seq opl3seq
(
	.clk(clk), 
	.reset(~seq_reset_n),
	.rd(stb44100),
	.A(A), 
	.B(B), 
	.ready(ready), 
	.ram_wr(seq_wr), 
	.ram_addr(seq_addr), 
	.ram_rdata(seq_rdata), 
	.ram_wdata(seq_wdata)
);

wire [15:0] A,B;
compressor compressor
(
	clk,
	stb44100,

	A[15:4], B[15:4],
	left,    right
);

wire [15:0] CPU_ADDR;
wire  [7:0] CPU_DOUT;
wire        CPU_WR;
wire        CPU_MREQ; 
wire        CPU_IORQ; 

NextZ80 Z80
(
	.DI(~CPU_IORQ ? ram_dout : CPU_ADDR[0] ? qdata[7:0] : {4'b0000, qdata[9:8], qempty, ready}),
	.DO(CPU_DOUT),
	.ADDR(CPU_ADDR),
	.WR(CPU_WR),
	.MREQ(CPU_MREQ),
	.IORQ(CPU_IORQ),
	.HALT(),
	.M1(),
	.CLK(clk),
	.RESET(reset),
	.INT(0),
	.NMI(0),
	.WAIT(!CE)
);

reg CE = 0;
always @(posedge clk) CE <= !CE;

endmodule

module opl3_mem
#(
	parameter
		DATA_WIDTH1    = 8,
		ADDRESS_WIDTH1 = 13,
		ADDRESS_WIDTH2 = 12,
		INIT_FILE      = "opl3prg.mem"
)
(
	input                        clk,
	input                        we1,
	input   [ADDRESS_WIDTH1-1:0] addr1,
	input      [DATA_WIDTH1-1:0] data_in1,
	output reg [DATA_WIDTH1-1:0] data_out1,

	input                        we2,
	input   [ADDRESS_WIDTH2-1:0] addr2,
	input      [DATA_WIDTH2-1:0] data_in2, 
	output reg [DATA_WIDTH2-1:0] data_out2
);

localparam RATIO = 1 << (ADDRESS_WIDTH1 - ADDRESS_WIDTH2);
localparam DATA_WIDTH2 = DATA_WIDTH1 * RATIO;
localparam RAM_DEPTH = 1 << ADDRESS_WIDTH2;

reg [RATIO-1:0] [DATA_WIDTH1-1:0] ram[0:RAM_DEPTH-1];
initial $readmemh(INIT_FILE, ram);

// Port A
always@(posedge clk) if(we1) ram[addr1 / RATIO][addr1 % RATIO] = data_in1;
always@(posedge clk) data_out1 <= ram[addr1 / RATIO][addr1 % RATIO];

// port B
always@(posedge clk) if(we2) ram[addr2] = data_in2;
always@(posedge clk) data_out2 <= ram[addr2];

endmodule

module opl3_fifo
(
	input        aclr,
	input  [9:0] data,
	input        rdclk,
	input        rdreq,
	input        wrclk,
	input        wrreq,
	output [9:0] q,
	output       rdempty
);

dcfifo	dcfifo_component (
			.aclr (aclr),
			.data (data),
			.rdclk (rdclk),
			.rdreq (rdreq),
			.wrclk (wrclk),
			.wrreq (wrreq),
			.q (q),
			.rdempty (rdempty),
			.eccstatus (),
			.rdfull (),
			.rdusedw (),
			.wrempty (),
			.wrfull (),
			.wrusedw ());
defparam
	dcfifo_component.intended_device_family = "Cyclone V",
	dcfifo_component.lpm_numwords = 1024,
	dcfifo_component.lpm_showahead = "ON",
	dcfifo_component.lpm_type = "dcfifo",
	dcfifo_component.lpm_width = 10,
	dcfifo_component.lpm_widthu = 10,
	dcfifo_component.overflow_checking = "ON",
	dcfifo_component.rdsync_delaypipe = 5,
	dcfifo_component.read_aclr_synch = "ON",
	dcfifo_component.underflow_checking = "ON",
	dcfifo_component.use_eab = "ON",
	dcfifo_component.write_aclr_synch = "ON",
	dcfifo_component.wrsync_delaypipe = 5;

endmodule
