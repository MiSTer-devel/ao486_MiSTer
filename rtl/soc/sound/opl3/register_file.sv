/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: register_file.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 2 Nov 2014
#
#   DESCRIPTION:
#
#   CHANGE HISTORY:
#   2 Nov 2014    Greg Taylor
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
`default_nettype none  // disable implicit net type declarations

import opl3_pkg::*;

module register_file (
    input wire clk,
    input wire [7:0] opl_reg [NUM_BANKS][NUM_REGISTERS_PER_BANK],
    output logic mt1,
    output logic mt2,
    output logic st1,
    output logic st2,
    output logic [REG_CONNECTION_SEL_WIDTH-1:0] connection_sel,
    output logic is_new,
    output logic nts,                     // keyboard split selection
    output logic [REG_FNUM_WIDTH-1:0] fnum [2][9],
    output logic [REG_MULT_WIDTH-1:0] mult [2][18],
    output logic [REG_BLOCK_WIDTH-1:0] block [2][9],
    output logic [REG_WS_WIDTH-1:0] ws [2][18],
    output logic vib [2][18],
    output logic dvb,
    output logic kon [2][9],
    output logic [REG_ENV_WIDTH-1:0] ar [2][18], // attack rate
    output logic [REG_ENV_WIDTH-1:0] dr [2][18], // decay rate
    output logic [REG_ENV_WIDTH-1:0] sl [2][18], // sustain level
    output logic [REG_ENV_WIDTH-1:0] rr [2][18], // release rate
    output logic [REG_TL_WIDTH-1:0] tl [2][18],  // total level
    output logic ksr [2][18],                    // key scale rate
    output logic [REG_KSL_WIDTH-1:0] ksl [2][18], // key scale level
    output logic egt [2][18],                     // envelope type
    output logic am [2][18],                      // amplitude modulation (tremolo)
    output logic dam,                             // depth of tremolo
    output logic ryt,
    output logic bd,
    output logic sd,
    output logic tom,
    output logic tc,
    output logic hh,
    output logic cha [2][9],
    output logic chb [2][9],
    output logic chc [2][9],
    output logic chd [2][9],
    output logic [REG_FB_WIDTH-1:0] fb [2][9],
    output logic cnt [2][9]
);
    /*
     * Registers that are specific to a particular bank
     */
    always_comb begin
        mt1 = opl_reg[0][4][6];
        mt2 = opl_reg[0][4][5];
        st2 = opl_reg[0][4][1];
        st1 = opl_reg[0][4][0];
        connection_sel = opl_reg[1][REG_CONNECTION_SEL_WIDTH-1:0];

        is_new = opl_reg[1][0];
        nts = opl_reg[0][8][6];

        dam = opl_reg[0]['hBD][7];
        dvb = opl_reg[0]['hBD][6];
        ryt = opl_reg[0]['hBD][5];
        bd  = opl_reg[0]['hBD][4];
        sd  = opl_reg[0]['hBD][3];
        tom = opl_reg[0]['hBD][2];
        tc  = opl_reg[0]['hBD][1];
        hh  = opl_reg[0]['hBD][0];
    end

    for (genvar bank = 0; bank < 2; bank++) begin
        for (genvar i = 0; i < 6; i++)
            always_comb begin
                am[bank][i]   = opl_reg[bank]['h20][7];
                vib[bank][i]  = opl_reg[bank]['h20][6];
                egt[bank][i]  = opl_reg[bank]['h20][5];
                ksr[bank][i]  = opl_reg[bank]['h20][4];
                mult[bank][i] = opl_reg[bank]['h20][3:0];

                ksl[bank][i] = opl_reg[bank]['h40][7:6];
                tl[bank][i]  = opl_reg[bank]['h40][5:0];

                ar[bank][i] = opl_reg[bank]['h60][7:4];
                dr[bank][i] = opl_reg[bank]['h60][3:0];

                sl[bank][i] = opl_reg[bank]['h80][7:4];
                rr[bank][i] = opl_reg[bank]['h80][3:0];

                ws[bank][i] = opl_reg[bank]['hE0][2:0];
            end

        for (genvar i = 8; i < 14; i++)
            always_comb begin
                am[bank][i-2]   = opl_reg[bank]['h20][7];
                vib[bank][i-2]  = opl_reg[bank]['h20][6];
                egt[bank][i-2]  = opl_reg[bank]['h20][5];
                ksr[bank][i-2]  = opl_reg[bank]['h20][4];
                mult[bank][i-2] = opl_reg[bank]['h20][3:0];

                ksl[bank][i-2] = opl_reg[bank]['h40][7:6];
                tl[bank][i-2]  = opl_reg[bank]['h40][5:0];

                ar[bank][i-2] = opl_reg[bank]['h60][7:4];
                dr[bank][i-2] = opl_reg[bank]['h60][3:0];

                sl[bank][i-2] = opl_reg[bank]['h80][7:4];
                rr[bank][i-2] = opl_reg[bank]['h80][3:0];

                ws[bank][i-2] = opl_reg[bank]['hE0][2:0];
            end

        for (genvar i = 16; i < 22; i++)
            always_comb begin
                am[bank][i-4]   = opl_reg[bank]['h20][7];
                vib[bank][i-4]  = opl_reg[bank]['h20][6];
                egt[bank][i-4]  = opl_reg[bank]['h20][5];
                ksr[bank][i-4]  = opl_reg[bank]['h20][4];
                mult[bank][i-4] = opl_reg[bank]['h20][3:0];

                ksl[bank][i-4] = opl_reg[bank]['h40][7:6];
                tl[bank][i-4]  = opl_reg[bank]['h40][5:0];

                ar[bank][i-4] = opl_reg[bank]['h60][7:4];
                dr[bank][i-4] = opl_reg[bank]['h60][3:0];

                sl[bank][i-4] = opl_reg[bank]['h80][7:4];
                rr[bank][i-4] = opl_reg[bank]['h80][3:0];

                ws[bank][i-4] = opl_reg[bank]['hE0][2:0];
            end

        for (genvar i = 0; i < 9; i++)
            always_comb begin
                fnum[bank][i][7:0] = opl_reg[bank]['hA0];

                kon[bank][i]       = opl_reg[bank]['hB0][5];
                block[bank][i]     = opl_reg[bank]['hB0][4:2];
                fnum[bank][i][9:8] = opl_reg[bank]['hB0][1:0];

                chd[bank][i] = opl_reg[bank]['hC0][7];
                chc[bank][i] = opl_reg[bank]['hC0][6];
                chb[bank][i] = opl_reg[bank]['hC0][5];
                cha[bank][i] = opl_reg[bank]['hC0][4];

                fb[bank][i]  = opl_reg[bank]['hC0][3:1];
                cnt[bank][i] = opl_reg[bank]['hC0][0];
            end
    end
endmodule
`default_nettype wire  // re-enable implicit net type declarations