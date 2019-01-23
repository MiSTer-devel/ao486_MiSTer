// (C) 2001-2017 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel MegaCore Function License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


// $Id: //acds/rel/17.0std/ip/merlin/altera_merlin_burst_adapter/new_source/altera_incr_burst_converter.sv#1 $
// $Revision: #1 $
// $Date: 2017/01/22 $
// $Author: swbranch $

// ----------------------------------------------------------
// This component is used for INCR Avalon slave
// (slave which only supports INCR) or AXI slave.
// It converts burst length of input packet
// to match slave burst.
// ----------------------------------------------------------

`timescale 1 ns / 1 ns

module altera_incr_burst_converter
#(
  parameter
    // ----------------------------------------
    // Burst length Parameters
    // (real burst length value, not bytecount)
    // ----------------------------------------
    MAX_IN_LEN          = 16,
    MAX_OUT_LEN         = 4,
    NUM_SYMBOLS         = 4,
    ADDR_WIDTH          = 12,
    BNDRY_WIDTH         = 12,
    BURSTSIZE_WIDTH     = 3,
    IN_NARROW_SIZE      = 0,
    PURELY_INCR_AVL_SYS = 0,
    // ------------------
    // Derived Parameters
    // ------------------
    LEN_WIDTH       = log2ceil(MAX_IN_LEN) + 1,
    OUT_LEN_WIDTH   = log2ceil(MAX_OUT_LEN) + 1,
    LOG2_NUMSYMBOLS = log2ceil(NUM_SYMBOLS)
)
(
    input                               clk,
    input                               reset,
    input                               enable,

    input                               is_write,
    input [LEN_WIDTH       - 1 : 0]     in_len,
    input                               in_sop,

    input [ADDR_WIDTH      - 1 : 0]     in_addr,
    input [ADDR_WIDTH      - 1 : 0]     in_addr_reg,
    input [BNDRY_WIDTH     - 1 : 0]     in_burstwrap_reg,
    input [BURSTSIZE_WIDTH - 1 : 0]     in_size_t,
    input [BURSTSIZE_WIDTH - 1 : 0]     in_size_reg,

    // converted output length
    // out_len         : compressed burst, read
    // uncompressed_len: uncompressed, write
    output reg [LEN_WIDTH  - 1 : 0]     out_len,
    output reg [LEN_WIDTH  - 1 : 0]     uncompr_out_len,
    // Compressed address output
    output reg [ADDR_WIDTH - 1 : 0]     out_addr,
    output reg                          new_burst_export
);

    // ----------------------------------------
    // Signals for wrapping support
    // ----------------------------------------
    reg [LEN_WIDTH - 1 : 0]        remaining_len;
    reg [LEN_WIDTH - 1 : 0]        next_out_len;
    reg [LEN_WIDTH - 1 : 0]        next_rem_len;
    reg [LEN_WIDTH - 1 : 0]        uncompr_remaining_len;
    reg [LEN_WIDTH - 1 : 0]        next_uncompr_remaining_len;
    reg [LEN_WIDTH - 1 : 0]        next_uncompr_rem_len;
    reg                            new_burst;
    reg                            uncompr_sub_burst;

    // Avoid QIS warning
    wire [OUT_LEN_WIDTH - 1 : 0]   max_out_length;
    assign max_out_length  = MAX_OUT_LEN[OUT_LEN_WIDTH - 1 : 0];

    always_comb begin
        new_burst_export = new_burst;
    end

    // -------------------------------------------
    // length remaining calculation
    // -------------------------------------------

    always_comb begin : proc_uncompressed_remaining_len
        if ((in_len <= max_out_length) && is_write) begin
            uncompr_remaining_len = in_len;
        end else begin
            uncompr_remaining_len = max_out_length;
        end

        if (uncompr_sub_burst)
            uncompr_remaining_len = next_uncompr_rem_len;
    end

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            next_uncompr_rem_len  <= 0;
        end
        else if (enable) begin
            next_uncompr_rem_len  <= uncompr_remaining_len - 1'b1; // in term of length, it just reduces 1
        end
    end

    always_comb begin : proc_compressed_remaining_len
       remaining_len  = in_len;
        if (!new_burst)
            remaining_len = next_rem_len;
    end

    always_ff@(posedge clk or posedge reset) begin : proc_next_uncompressed_remaining_len
        if(reset) begin
            next_uncompr_remaining_len <= '0;
        end
        else if (enable) begin
            if (in_sop) begin
                next_uncompr_remaining_len <= in_len - max_out_length;
            end
            else if (!uncompr_sub_burst)
                next_uncompr_remaining_len <= next_uncompr_remaining_len - max_out_length;
        end
    end

    always_comb begin
        next_out_len = max_out_length;
        if (remaining_len < max_out_length) begin
            next_out_len = remaining_len;
        end
    end // always_comb

    // --------------------------------------------------
    // Length remaining calculation : compressed
    // --------------------------------------------------
    // length remaining for compressed transaction
    // for wrap, need special handling for first out length

    always_ff @(posedge clk, posedge reset) begin
        if (reset)
            next_rem_len  <= 0;
        else if (enable) begin
            if (new_burst)
                next_rem_len <= in_len - max_out_length;
            else
                next_rem_len <= next_rem_len - max_out_length;
        end
    end

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            uncompr_sub_burst <= 0;
        end
        else if (enable && is_write) begin
            uncompr_sub_burst <= (uncompr_remaining_len > 1'b1);
        end
    end


    // --------------------------------------------------
    // Control signals
    // --------------------------------------------------
    wire end_compressed_sub_burst;
    assign end_compressed_sub_burst  = (remaining_len == next_out_len);

    // new_burst:
    //  the converter takes in_len for new calculation
    always_ff @(posedge clk, posedge reset) begin
        if (reset)
            new_burst   <= 1;
        else if (enable)
            new_burst   <= end_compressed_sub_burst;
    end

    // --------------------------------------------------
    // Output length
    // --------------------------------------------------
    // register out_len for compressed trans
    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            out_len <= 0;
        end
        else if (enable) begin
            out_len <= next_out_len;
        end
    end

    // register uncompr_out_len for uncompressed trans
    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            uncompr_out_len <= '0;
        end
        else if (enable) begin
            uncompr_out_len <= uncompr_remaining_len;
        end
    end

    // --------------------------------------------------
    // Address Calculation
    // --------------------------------------------------
    reg [ADDR_WIDTH - 1 : 0]        addr_incr_sel;
    reg [ADDR_WIDTH - 1 : 0]        addr_incr_sel_reg;
    reg [ADDR_WIDTH - 1 : 0]        addr_incr_full_size;

    localparam [ADDR_WIDTH - 1 : 0] ADDR_INCR = MAX_OUT_LEN << LOG2_NUMSYMBOLS;

    generate
        if (IN_NARROW_SIZE) begin : narrow_addr_incr
            reg [ADDR_WIDTH - 1 : 0]    addr_incr_variable_size;
            reg [ADDR_WIDTH - 1 : 0]    addr_incr_variable_size_reg;

            assign addr_incr_variable_size = MAX_OUT_LEN << in_size_t;
            assign addr_incr_variable_size_reg = MAX_OUT_LEN << in_size_reg;

            assign addr_incr_sel  = addr_incr_variable_size;
            assign addr_incr_sel_reg  = addr_incr_variable_size_reg;
        end
        else begin : full_addr_incr
            assign addr_incr_full_size  = ADDR_INCR[ADDR_WIDTH - 1 : 0];
            assign addr_incr_sel  = addr_incr_full_size;
            assign addr_incr_sel_reg = addr_incr_full_size;
        end
    endgenerate


    reg [ADDR_WIDTH - 1 : 0]    next_out_addr;
    reg [ADDR_WIDTH - 1 : 0]    incremented_addr;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            out_addr <= '0;
        end else begin
            if (enable) begin
                out_addr <=  (next_out_addr);
            end
        end
    end

    generate
        if (!PURELY_INCR_AVL_SYS) begin : incremented_addr_normal
            always_ff @(posedge clk, posedge reset) begin
                if (reset) begin
                    incremented_addr <= '0;
                end
                else if (enable) begin
                    incremented_addr <= (next_out_addr + addr_incr_sel_reg);
                    if (new_burst) begin
                        incremented_addr <= (next_out_addr + addr_incr_sel);
                    end
                end
            end // always_ff @

            always_comb begin
                next_out_addr = in_addr;
                if (!new_burst) begin
                    next_out_addr = incremented_addr;
                end
            end
        end
        else begin : incremented_addr_pure_av
            always_ff @(posedge clk, posedge reset) begin
            if (reset) begin
               incremented_addr <= '0;
                end
                else if (enable) begin
                    incremented_addr <= (next_out_addr + addr_incr_sel_reg);
                end
            end // always_ff @

            always_comb begin
                next_out_addr  = in_addr;
                if (!new_burst) begin
                    next_out_addr  = (incremented_addr);
                end
            end

        end
    endgenerate

    // --------------------------------------------------
    // Calculates the log2ceil of the input value
    // --------------------------------------------------
    function integer log2ceil;
        input integer val;
        reg[31:0] i;

        begin
            i = 1;
            log2ceil = 0;

            while (i < val) begin
                log2ceil = log2ceil + 1;
                i = i[30:0] << 1;
            end
        end
    endfunction

endmodule
