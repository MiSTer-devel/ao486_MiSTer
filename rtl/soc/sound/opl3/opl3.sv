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

module opl3
    import opl3_pkg::*;
(
    input wire clk,
    input wire [7:0] opl_reg [NUM_BANKS][NUM_REGISTERS_PER_BANK],
    output logic signed [SAMPLE_WIDTH-1:0] sample_l = 0,
    output logic signed [SAMPLE_WIDTH-1:0] sample_r = 0
);
    logic sample_clk_en = 0;

    logic mt1;
    logic mt2;
    logic st1;
    logic st2;
    logic [REG_CONNECTION_SEL_WIDTH-1:0] connection_sel;
    logic is_new;
    logic nts;                     // keyboard split selection
    logic [REG_FNUM_WIDTH-1:0] fnum [NUM_BANKS][NUM_CHANNELS_PER_BANK];
    logic [REG_MULT_WIDTH-1:0] mult [NUM_BANKS][NUM_OPERATORS_PER_BANK];
    logic [REG_BLOCK_WIDTH-1:0] block [NUM_BANKS][NUM_CHANNELS_PER_BANK];
    logic [REG_WS_WIDTH-1:0] ws [NUM_BANKS][NUM_OPERATORS_PER_BANK];
    logic vib [NUM_BANKS][NUM_OPERATORS_PER_BANK];
    logic dvb;
    logic kon [NUM_BANKS][NUM_CHANNELS_PER_BANK];
    logic [REG_ENV_WIDTH-1:0] ar [NUM_BANKS][NUM_OPERATORS_PER_BANK]; // attack rate
    logic [REG_ENV_WIDTH-1:0] dr [NUM_BANKS][NUM_OPERATORS_PER_BANK]; // decay rate
    logic [REG_ENV_WIDTH-1:0] sl [NUM_BANKS][NUM_OPERATORS_PER_BANK]; // sustain level
    logic [REG_ENV_WIDTH-1:0] rr [NUM_BANKS][NUM_OPERATORS_PER_BANK]; // release rate
    logic [REG_TL_WIDTH-1:0] tl [NUM_BANKS][NUM_OPERATORS_PER_BANK];  // total level
    logic ksr [NUM_BANKS][NUM_OPERATORS_PER_BANK];                    // key scale rate
    logic [REG_KSL_WIDTH-1:0] ksl [NUM_BANKS][NUM_OPERATORS_PER_BANK]; // key scale level
    logic egt [NUM_BANKS][NUM_OPERATORS_PER_BANK];                     // envelope type
    logic am [NUM_BANKS][NUM_OPERATORS_PER_BANK];                      // amplitude modulation (tremolo)
    logic dam;                             // depth of tremolo
    logic ryt;
    logic bd;
    logic sd;
    logic tom;
    logic tc;
    logic hh;
    logic cha [NUM_BANKS][NUM_CHANNELS_PER_BANK];
    logic chb [NUM_BANKS][NUM_CHANNELS_PER_BANK];
    logic chc [NUM_BANKS][NUM_CHANNELS_PER_BANK];
    logic chd [NUM_BANKS][NUM_CHANNELS_PER_BANK];
    logic [REG_FB_WIDTH-1:0] fb [NUM_BANKS][NUM_CHANNELS_PER_BANK];
    logic cnt [NUM_BANKS][NUM_CHANNELS_PER_BANK];

    logic signed [SAMPLE_WIDTH-2:0] channel_a;
    logic signed [SAMPLE_WIDTH-2:0] channel_b;
    logic signed [SAMPLE_WIDTH-2:0] channel_c;
    logic signed [SAMPLE_WIDTH-2:0] channel_d;

    logic [$clog2(CLK_DIV_COUNT)-1:0] counter = 0;

    always_ff @(posedge clk)
        if (counter == CLK_DIV_COUNT - 1)
            counter <= 0;
        else
            counter <= counter + 1;

    always_ff @(posedge clk)
        sample_clk_en <= (counter == CLK_DIV_COUNT - 1);

    channels channels (
        .*
    );

    always_ff @(posedge clk) begin
        sample_l <= channel_a + channel_c;
        sample_r <= channel_b + channel_d;
    end

    register_file register_file (
        .*
    );
endmodule
`default_nettype wire  // re-enable implicit net type declarations
