/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: opl3.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 24 Feb 2015
#
#   DESCRIPTION:
#
#   CHANGE HISTORY:
#   24 Feb 2015        Greg Taylor
#       Initial version
#
#   Copyright (C) 2014 Greg Taylor <gtaylor@sonic.net>
#    
#   This file is part of OPL3 FPGA.
#    
#   OPL3 FPGA is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#   
#   OPL3 FPGA is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#   
#   You should have received a copy of the GNU Lesser General Public License
#   along with OPL3 FPGA.  If not, see <http://www.gnu.org/licenses/>.
#   
#   Original Java Code: 
#   Copyright (C) 2008 Robson Cozendey <robson@cozendey.com>
#   
#   Original C++ Code: 
#   Copyright (C) 2012  Steffen Ohrendorf <steffen.ohrendorf@gmx.de>
#   
#   Some code based on forum posts in: 
#   http://forums.submarine.org.uk/phpBB/viewforum.php?f=9,
#   Copyright (C) 2010-2013 by carbon14 and opl3    
#   
#******************************************************************************/
`timescale 1ns / 1ps
`default_nettype none // disable implicit net type declarations

import opl3_pkg::*;

module opl3
(
    input  wire clk,
    input  wire [7:0] opl_reg[512],

    output reg signed [SAMPLE_WIDTH-1:0] sample_l = 0,
    output reg signed [SAMPLE_WIDTH-1:0] sample_r = 0
);

logic sample_clk_en;

wire [REG_TIMER_WIDTH-1:0] timer1;
wire [REG_TIMER_WIDTH-1:0] timer2;
wire irq_rst;
wire mt1;
wire mt2;
wire st1;
wire st2;
wire [REG_CONNECTION_SEL_WIDTH-1:0] connection_sel;
wire is_new;
wire nts;                     // keyboard split selection     
wire [REG_FNUM_WIDTH-1:0] fnum [2][9];
wire [REG_MULT_WIDTH-1:0] mult [2][18];
wire [REG_BLOCK_WIDTH-1:0] block [2][9];
wire [REG_WS_WIDTH-1:0] ws [2][18];
wire vib [2][18];
wire dvb;
wire kon [2][9];  
wire [REG_ENV_WIDTH-1:0] ar [2][18]; // attack rate
wire [REG_ENV_WIDTH-1:0] dr [2][18]; // decay rate
wire [REG_ENV_WIDTH-1:0] sl [2][18]; // sustain level
wire [REG_ENV_WIDTH-1:0] rr [2][18]; // release rate
wire [REG_TL_WIDTH-1:0] tl [2][18];  // total level
wire ksr [2][18];                    // key scale rate
wire [REG_KSL_WIDTH-1:0] ksl [2][18]; // key scale level
wire egt [2][18];                     // envelope type
wire am [2][18];                      // amplitude modulation (tremolo)
wire dam;                             // depth of tremolo
wire ryt;
wire bd;
wire sd;
wire tom;
wire tc;
wire hh;
wire cha [2][9];
wire chb [2][9];
wire chc [2][9];
wire chd [2][9];
wire [REG_FB_WIDTH-1:0] fb [2][9];
wire cnt [2][9];
wire irq;

wire signed [SAMPLE_WIDTH-1:0] channel_a;
wire signed [SAMPLE_WIDTH-1:0] channel_b;
wire signed [SAMPLE_WIDTH-1:0] channel_c;
wire signed [SAMPLE_WIDTH-1:0] channel_d;   

logic [$clog2(CLK_DIV_COUNT)-1:0] counter = 0;
 
always_ff @(posedge clk) begin
	if (counter == CLK_DIV_COUNT - 1) counter <= 0;
	else counter <= counter + 1'd1;
end

always_ff @(posedge clk) begin
	sample_clk_en <= (counter == CLK_DIV_COUNT - 1);
end
	  
always_ff @(posedge clk) begin
	sample_l <= ({channel_a[SAMPLE_WIDTH-1], channel_a[SAMPLE_WIDTH-1:1]} + {channel_c[SAMPLE_WIDTH-1], channel_c[SAMPLE_WIDTH-1:1]});
	sample_r <= ({channel_b[SAMPLE_WIDTH-1], channel_b[SAMPLE_WIDTH-1:1]} + {channel_d[SAMPLE_WIDTH-1], channel_d[SAMPLE_WIDTH-1:1]});
end

channels channels(.*);
register_file register_file(.*); 

endmodule
`default_nettype wire  // re-enable implicit net type declarations
