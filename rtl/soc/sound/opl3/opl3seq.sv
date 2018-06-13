`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: opl3seq.v
// Description: Part of the Next186 SoC PC project, OPL3 Sequencer
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
// It shares  OPL3 structure (~1.7KB DP RAM) with the main processor. It drives 36 operators at 44100Hz, with at least 45Mhz clock
///////////////////////////////////////////////////////////////////////////////////

// altera message_off 10030


`define LFO_AM_TAB_ELEMENTS 210    
`define phase_modulation_o 0     // CH18
`define panA_o             6'd4  // CH18
`define panB_o             6'd8  // CH18
`define lfo_am_depth_o     12    // CH18
`define block_fnum_o			44    // SLOT0
`define chanout_o          6'd46 // SLOT0

`define Cnt_o              6'd4
`define Incr_o					6'd8
`define op1_out_o          6'd12
`define state_o            18
`define AMmask_o           20
`define volume_o           22           
`define FB_o               24
`define mul_o					30
`define sl_o               32      
`define vib_o					34     
`define connect_o          36
`define eg_sh_ar_o         38           
`define eg_sh_dr_o         40           
`define eg_sh_rr_o         42           

module opl3seq
(
	input             clk,
	input             reset,
	input             rd, // clk synchronous pulse, read only while <ready> == 1
	output reg [15:0] A,
	output reg [15:0] B,
	output reg        ready,
	output reg        ram_wr,
	output     [11:0] ram_addr,
	input      [15:0] ram_rdata,
	output reg [15:0] ram_wdata
);

reg [13:0]lfo_am_cnt = 0;
reg [4:0]r_lfo_am_cnt = 0;
wire [13:0]lfo_am_cnt1 = lfo_am_cnt + 1'b1;
reg [9:0]lfo_pm_cnt = 0;
reg [4:0]LFO_AM; // unsigned 
reg [3:0]LFO_PM = 0; // unsigned

reg [5:0]STATE = 0;
reg [5:0]nextSTATE;
reg [5:0]RET;
reg [5:0]ram_offset; // OPL3Struct_base + (CHindex*96 + OPindex*48 + offset)
reg [4:0]ram_CHindex;  
reg [4:0]s_ram_CHindex;  
wire s_ram_CHindex17 = s_ram_CHindex == 17;
wire s_ram_CHindex18 = s_ram_CHindex == 18;
wire [4:0]s_ram_CHindex1 = s_ram_CHindex + 1'b1;
reg ram_OPindex;  
reg s_ram_OPindex;  
reg [15:0]ram_rdata_lo;
reg [15:0]eg_cnt = 0;
//   reg [22:0]noise_rng = 1;
reg [9:0]env;
reg [12:0]sinaddr;
reg [12:0]r_sinaddr;
wire [12:0]op_calc1;
wire signed [15:0]op_calc = {{3{op_calc1[12]}}, op_calc1};
reg [15:0]tmp1;
wire [13:0]outshift1 = $signed(tmp1[13:0]) >>> ram_rdata[3:0];
wire [9:0]outshift =  |ram_rdata[3:0] ? outshift1[9:0] : 10'b0000000000;
reg [17:0]pan;
reg signed [18:0]rAcc;
wire [15:0]limAcc = rAcc > 32767 ? 16'h7fff : rAcc < -32768 ? 16'h8000 : rAcc[15:0]; //   (~|rAcc[18:15] | &rAcc[18:15]) ? rAcc[15:0] : {rAcc[18], {15{!rAcc[18]}}};
reg [11:0]phmask;// = (1'b1 << ram_rdata[3:0]) - 1'b1;
wire phtest = ~|(eg_cnt & phmask);
reg cond;
wire [15:0]eg_inc1 = eg_cnt >> ram_rdata[3:0];
wire [6:0]eg_inc = ram_rdata[14:8] + eg_inc1[2:0];
reg [2:0]r_eg_inc;
wire [9:0]volume_attack1 = $signed(~ram_rdata[9:0]) >>> (~r_eg_inc[1:0]);
wire [9:0]volume_attack = {1'b0, ram_rdata[8:0]} + (r_eg_inc[2] ? 10'h000 : volume_attack1);
reg [9:0]r_volume;
wire [2:0]exp_r_eg_inc = 3'b1 << r_eg_inc;
wire [9:0]volume_dsr = ram_rdata[8:0] + exp_r_eg_inc; // new volume for decay/sustain/release
reg signed [3:0]lfo_fn_table_index_offset;
reg [11:0]inc_hi;
reg [15:0]inc_lo;
reg carry = 1'b0;
reg cy;
reg [2:0]phase;
wire [25:0]mul1 = tmp1[9:0] * ram_rdata_lo;

// tmp1 adder   
reg  [3:0]tmp1op;
reg [15:0]tmp1op1;
reg [15:0]tmp1op2;

//     .addrb(OPL3Struct_offset + {1'b1, ram_CHindex, ram_OPindex, ram_offset[5:1]})
assign ram_addr = (ram_OPindex ? 12'd24 : 12'd0) + {ram_CHindex + {ram_CHindex, ram_offset[5]}, ram_offset[4:1]};

wire [4:0] lfo_am_table [`LFO_AM_TAB_ELEMENTS] = '{ 
	0,0,0,0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3, 4,4,4,4, 5,5,5,5, 6,6,6,6, 7,7,7,7, 8,8,8,8, 9,9,9,9, 10,10,10,10, 11,11,11,11, 12,12,12,12, 13,13,13,13, 14,14,14,14,
	15,15,15,15, 16,16,16,16, 17,17,17,17, 18,18,18,18, 19,19,19,19, 20,20,20,20, 21,21,21,21, 22,22,22,22, 23,23,23,23, 24,24,24,24, 25,25,25,25, 26,26,26, 25,25,25,25,
	24,24,24,24, 23,23,23,23, 22,22,22,22, 21,21,21,21, 20,20,20,20, 19,19,19,19, 18,18,18,18, 17,17,17,17, 16,16,16,16, 15,15,15,15, 14,14,14,14, 13,13,13,13, 12,12,12,12,
	11,11,11,11, 10,10,10,10, 9,9,9,9, 8,8,8,8, 7,7,7,7, 6,6,6,6, 5,5,5,5, 4,4,4,4, 3,3,3,3, 2,2,2,2, 1,1,1,1
};

wire signed [3:0]lfo_pm_table[128] = '{
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0,-1, 0, 0, 0, 1, 0, 0, 0,-1, 0, 0, 0, 2, 1, 0,-1,-2,-1, 0, 1, 1, 0, 0, 0,-1, 0, 0, 0, 3, 1, 0,-1,-3,-1, 0, 1,
	2, 1, 0,-1,-2,-1, 0, 1, 4, 2, 0,-2,-4,-2, 0, 2, 2, 1, 0,-1,-2,-1, 0, 1, 5, 2, 0,-2,-5,-2, 0, 2, 3, 1, 0,-1,-3,-1, 0, 1, 6, 3, 0,-3,-6,-3, 0, 3, 3, 1, 0,-1,-3,-1, 0, 1, 7, 3, 0,-3,-7,-3, 0, 3
};

wire [2:0]eg_inc_tab[120] = '{ 
	4,0, 4,0, 4,0, 4,0, 4,0, 4,0, 0,0, 4,0, 4,0, 0,0, 4,0, 0,0, 4,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,1, 0,0, 0,2, 0,1, 0,1, 0,1, 0,1, 
	0,1, 1,1, 0,1, 1,1, 1,1, 1,1, 1,1, 1,1, 1,1, 1,2, 1,1, 1,2, 1,2, 1,2, 1,2, 1,2, 1,2, 2,2, 1,2, 2,2, 2,2, 2,2, 2,2, 2,2, 3,3, 3,3, 3,3, 3,3, 4,4, 4,4, 4,4, 4,4
}; // log tablle, 4 = log(0)


sampler sampler_inst
(
	.clk(clk),
	.index(r_sinaddr),
	.ampl(env[8:0]),
	.sample(op_calc1)
);

always @(posedge clk) begin
	STATE <= nextSTATE;
	s_ram_CHindex <= ram_CHindex;
	s_ram_OPindex <= ram_OPindex;
	r_sinaddr <= sinaddr;
	r_lfo_am_cnt <= lfo_am_table[lfo_am_cnt[13:6]];
	ram_rdata_lo <= ram_rdata;
	r_eg_inc <= eg_inc_tab[eg_inc];
	lfo_fn_table_index_offset <= lfo_pm_table[{ram_rdata[9:7], LFO_PM}]; //34
	{carry, tmp1} <= tmp1op1 + tmp1op2 + cy;
	pan <= pan >> 1;
	if(pan[0]) rAcc <= rAcc + {{3{ram_rdata[15]}}, ram_rdata};
	
	if(reset) STATE <= 0;
	else
	case(STATE)
		0: begin
			if(lfo_am_cnt1[13:6] == `LFO_AM_TAB_ELEMENTS) lfo_am_cnt <= 14'h0000;
			else lfo_am_cnt <= lfo_am_cnt1;
			{LFO_PM[2:0], lfo_pm_cnt} <= {LFO_PM[2:0], lfo_pm_cnt} + 1'b1;
			eg_cnt <= eg_cnt + 1'b1;
//            noise_rng <= {noise_rng[0], noise_rng[22:1]} ^ (noise_rng[0] ? 9'h181 : 9'h000);
		end
		1: begin
			LFO_AM <= r_lfo_am_cnt >> {!ram_rdata[0], 1'b0};
			LFO_PM[3] <= ram_rdata[11];
			RET <= 3;
		end
		2: s_ram_CHindex <= s_ram_CHindex17 ? 5'd0 : s_ram_CHindex1;
		3: s_ram_CHindex <= s_ram_CHindex;
		7: RET <= 8;
		8: begin
			s_ram_CHindex <= s_ram_CHindex;
			RET <= 18;
		end
		10: s_ram_OPindex <= 1'b1;
		13: env <= ram_rdata_lo[9:0] + ram_rdata[8:0] + (ram_rdata_lo[15] ? LFO_AM : 10'd0); // env = volume_calc(SLOT1);
		15: {s_ram_CHindex, s_ram_OPindex} <= {s_ram_CHindex, s_ram_OPindex};
		17: {s_ram_CHindex, s_ram_OPindex} <= {s_ram_CHindex, s_ram_OPindex};
		18: s_ram_CHindex <= s_ram_CHindex1;
		20: begin
			pan <= {ram_rdata[1:0], ram_rdata_lo};
			s_ram_CHindex <= 1;
			rAcc <= 0;
		end
		21: s_ram_CHindex <= s_ram_CHindex18 ? s_ram_CHindex : s_ram_CHindex1;
		22: A <= limAcc;
		23: begin
			pan <= {ram_rdata[1:0], ram_rdata_lo};
			s_ram_CHindex <= 1;
			rAcc <= 0;
		end
		24: s_ram_CHindex <= s_ram_CHindex18 ? 5'd0 : s_ram_CHindex1;
		25: B <= limAcc;

// advance        
		27: cond <= phtest;
		28: r_volume <= tmp1[2] ? volume_attack : volume_dsr;
		29: if(r_volume[9]) r_volume <= (tmp1[2:0] < 3) ? 10'd511 : 10'd0;

// phase gen        
		32: inc_lo <= ram_rdata;
		33: begin
			inc_hi <= ram_rdata[11:0];
			s_ram_OPindex <= s_ram_OPindex;
		end
		35: cond <= |lfo_fn_table_index_offset;
		36: if(cond && ram_rdata[0]) {inc_hi, inc_lo} <= {mul1, 2'b00} >> ~tmp1[12:10]; 
		37,38: inc_lo <= {4'b0000, inc_hi};
		39: begin
			s_ram_OPindex <= !s_ram_OPindex;
			if(s_ram_OPindex) s_ram_CHindex <= s_ram_CHindex1;
		end
	endcase
end

always @(*) begin
	ram_offset = 6'b000000;
	ram_CHindex = s_ram_CHindex;
	ram_OPindex = s_ram_OPindex;
	ram_wdata = 16'h0000;
	ram_wr = 1'b0;
	nextSTATE = STATE + 1'b1;
	sinaddr = r_sinaddr;
	tmp1op = 4'b1111;   // tmp1 <= tmp1, carry <= 0
	cy = 1'b0;
	ready = 1'b0;

	case(STATE)
		0: begin
			ram_offset = `lfo_am_depth_o;
			ram_CHindex = 18;
			ram_OPindex = 0;
		end
		1: ram_CHindex = 0;
		2: begin
			ram_offset = `chanout_o;
			ram_wr = 1'b1;
			nextSTATE = s_ram_CHindex17 ? 6'd3 : 6'd2;
		end

// chan_calc         
		3: begin 	// chip.phase_modulation = 0;
			ram_CHindex = 18;
			ram_offset = `phase_modulation_o;
			ram_wr = 1'b1;
		end
		4: ram_offset = `op1_out_o;   // op1_out[0]
		5: ram_offset = `op1_out_o+6'd2; // op1_out[1]
		6: begin
			ram_offset = `FB_o;        // read {FB, wavetable, x, x}
			tmp1op = 4'b0000; // tmp1 <= ram_rdata + ram_rdata_lo; // out = SLOT1->op1_out[0] + SLOT1->op1_out[1];
		end
		7: begin    // SLOT->op1_out[0] = SLOT->op1_out[1];
			ram_offset = `op1_out_o;
			ram_wdata = ram_rdata_lo;
			ram_wr = 1'b1;
			sinaddr = {ram_rdata[10:8], outshift}; // wavetable, out>>FB
			nextSTATE = 11; // call
		end
	
		8: begin
			ram_CHindex = 18;
			ram_offset = `phase_modulation_o;
		end
		9: begin
			ram_offset = `FB_o;       // read {FB, wavetable, x, x}
			ram_OPindex = 1;
		end
		10: begin    // SLOT->op1_out[1] = op_calc
			ram_offset = `op1_out_o+6'd2;
			ram_OPindex = 0;
			ram_wdata = tmp1;
			ram_wr = 1'b1;
			sinaddr = {ram_rdata[10:8], ram_rdata_lo[9:0]}; // wavetable, phase_modulation
		end
		11: ram_offset = `AMmask_o;   // read {TLL, AMmask}
		12: ram_offset = `volume_o;   // read volume[15:0]
		13: ram_offset = `Cnt_o+6'd2;
		14: begin
			ram_offset = `connect_o;
			sinaddr[9:0] = sinaddr[9:0] + ram_rdata[9:0];
			if(env >= 416) nextSTATE = RET;
		end
		15: {ram_CHindex, ram_OPindex, ram_offset} = ram_rdata[11:0];
		16: ram_offset = `connect_o;
		17: begin
			{ram_CHindex, ram_OPindex, ram_offset} = ram_rdata[11:0];
			ram_wdata = ram_rdata_lo + op_calc;//tmp1;
			ram_wr = 1'b1;
			nextSTATE = RET;
			tmp1op = 4'b1110; // tmp1 <= op_calc;
		end
		18: begin
			ram_offset = `panA_o;
			ram_OPindex = 0;
			ram_CHindex = 18;
			nextSTATE = s_ram_CHindex17 ? 6'd19 : 6'd3;
		end
		
		19: ram_offset = `panA_o+6'd2;
		20: begin
			ram_offset = `chanout_o;
			ram_CHindex = 0;
		end
		21: begin
			ram_offset = s_ram_CHindex18 ? `panB_o : `chanout_o;
			nextSTATE = s_ram_CHindex18 ? 6'd22 : 6'd21;
		end
		22: ram_offset = `panB_o+6'd2;
		23: begin
			ram_offset = `chanout_o;
			ram_CHindex = 0;
		end
		24: begin
			ram_offset = `chanout_o;
			nextSTATE = s_ram_CHindex18 ? 6'd25 : 6'd24;
		end

// envelope        
		25: ram_offset = `state_o;
		26: begin
			case(ram_rdata[2:0])
				3'd1: ram_offset = `eg_sh_rr_o; // release phase
				3'd2: begin // sustain phase
					ram_offset = `eg_sh_rr_o;
					if(ram_rdata[8]) nextSTATE = 31; // if (!op->eg_type)
				end
				3'd3: ram_offset = `eg_sh_dr_o; // decay phase
				3'd4: ram_offset = `eg_sh_ar_o; // attack phase
				default: nextSTATE = 31;
			endcase
			tmp1op = 4'b1100; // tmp1 <= ram_rdata; // {eg_type, state}
		end

		27: ram_offset = `volume_o;
		28: ram_offset = `sl_o;       
		29: begin
			ram_offset = `state_o;
			ram_wdata = tmp1;
			case(tmp1[1:0])
				2'b00: if(r_volume[9]) ram_wdata[2:0] = 3'd3;	// attack
				2'b11: if(r_volume >= {1'b0, ram_rdata[8:0]}) ram_wdata[2:0] = 3'd2; // decay
				2'b10:; // sustain
				2'b01: if(r_volume[9]) ram_wdata[2:0] = 3'd0;	// release
			endcase
			ram_wr = cond;
		end
		30: begin
			ram_offset = `volume_o;
			ram_wdata[9:0] = r_volume;
			ram_wr = cond;
		end
		
// phase gen        
		31: ram_offset = `Incr_o;
		32: ram_offset = `Incr_o+6'd2;

		33: begin
			ram_offset = `block_fnum_o;
			ram_OPindex = 0;
		end
		34: ram_offset = `mul_o;
		35: begin
			ram_offset = `vib_o;
			tmp1op = 4'b0001; //tmp1 <= ram_rdata_lo + lfo_fn_table_index_offset;
		end
		36: ram_offset = `Cnt_o;
		37: begin
			ram_offset = `Cnt_o+6'd2;
			tmp1op = 4'b0100; //{carry, tmp1} <= inc_lo + ram_rdata;
		end
		38: begin
			ram_offset = `Cnt_o;
			ram_wdata = tmp1;
			ram_wr = 1'b1;
			tmp1op = 4'b0100; //{carry, tmp1} <= inc_lo + ram_rdata + carry;
			cy = carry;
		end
		39: begin
			ram_offset = `Cnt_o+6'd2;
			ram_wdata = tmp1;
			ram_wr = 1'b1;
			if(!(s_ram_CHindex17 && s_ram_OPindex)) nextSTATE = 6'd25;
		end
		
		default: begin
			ready = 1'b1;
			nextSTATE = rd ? 6'd0 : 6'd40;
		end
		
	endcase

	case(tmp1op[1:0])
		2'b00: tmp1op1 = ram_rdata;
		2'b01: tmp1op1 = lfo_fn_table_index_offset;
		2'b10: tmp1op1 = op_calc;
		2'b11: tmp1op1 = tmp1;
	endcase
	
	case(tmp1op[3:2])
		2'b00: tmp1op2 = ram_rdata_lo;
		2'b01: tmp1op2 = inc_lo;
	default:  tmp1op2 = 16'h0000;
	endcase

	case(ram_rdata[3:0]) // ((1 << ram_rdata[3:0]) - 1)[11:0]
		4'h0: phmask = 12'h000;
		4'h1: phmask = 12'h001;
		4'h2: phmask = 12'h003;
		4'h3: phmask = 12'h007;
		4'h4: phmask = 12'h00f;
		4'h5: phmask = 12'h01f;
		4'h6: phmask = 12'h03f;
		4'h7: phmask = 12'h07f;
		4'h8: phmask = 12'h0ff;
		4'h9: phmask = 12'h1ff;
		4'ha: phmask = 12'h3ff;
		4'hb: phmask = 12'h7ff;
	default: phmask = 12'hfff;
	endcase
end

endmodule

module sampler
(
	input         clk, 
	input  [12:0] index,
	input   [8:0] ampl,
	output [12:0] sample
);

reg  [15:0] sin_tab[8191:0];
initial $readmemh("sin_tab_full.mem", sin_tab);

reg  [15:0] exp_tab[6655:0];
initial $readmemh("exp_tab.mem", exp_tab);

reg  [15:0] logsin;
wire [13:0] ilog = logsin[13:0] + {ampl, 4'b0000};
reg         log_rng;
reg  [15:0] isample;
assign sample = log_rng ? isample[12:0] : 13'd0;

always @(posedge clk) begin
	logsin <= sin_tab[index];
	log_rng <= ilog < 6656;
	isample <= exp_tab[ilog[12:0]];
end

endmodule
