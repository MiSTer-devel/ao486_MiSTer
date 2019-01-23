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


// $Id: //acds/rel/17.0std/ip/merlin/altera_merlin_burst_adapter/new_source/altera_default_burst_converter.sv#1 $
// $Revision: #1 $
// $Date: 2017/01/22 $
// $Author: swbranch $

// --------------------------------------------
// Default Burst Converter
// Notes:
//  1) If burst type FIXED and slave is AXI,
//     passthrough the transaction.
//  2) Else, converts burst into non-bursting
//     transactions (length of 1).
// --------------------------------------------

`timescale 1 ns / 1 ns

module altera_default_burst_converter
#(
    parameter PKT_BURST_TYPE_W  = 2,
    parameter PKT_BURSTWRAP_W   = 5,
    parameter PKT_ADDR_W        = 12,
    parameter PKT_BURST_SIZE_W  = 3,
    parameter IS_AXI_SLAVE      = 0,
    parameter LEN_W             = 2
)
(
    input                                    clk,
    input                                    reset,
    input                                    enable,

    input      [PKT_BURST_TYPE_W - 1 : 0]    in_bursttype,
    input      [PKT_BURSTWRAP_W  - 1 : 0]    in_burstwrap_reg,
    input      [PKT_BURSTWRAP_W  - 1 : 0]    in_burstwrap_value,
    input      [PKT_ADDR_W       - 1 : 0]    in_addr,
    input      [PKT_ADDR_W       - 1 : 0]    in_addr_reg,
    input      [LEN_W            - 1 : 0]    in_len,
    input      [PKT_BURST_SIZE_W - 1 : 0]    in_size_value,

    input                                    in_is_write,

    output reg [PKT_ADDR_W       - 1 : 0]    out_addr,
    output reg [LEN_W            - 1 : 0]    out_len,

    output reg                               new_burst
);

    // ---------------------------------------------------
    // AXI Burst Type Encoding
    // ---------------------------------------------------
    typedef enum bit  [1:0]
    {
     FIXED       = 2'b00,
     INCR        = 2'b01,
     WRAP        = 2'b10,
     RESERVED    = 2'b11
    } AxiBurstType;

    // -------------------------------------------
    // Internal Signals
    // -------------------------------------------
    wire [LEN_W - 1 : 0]    unit_len = {{LEN_W - 1 {1'b0}}, 1'b1};
    reg  [LEN_W - 1 : 0]    next_len;
    reg  [LEN_W - 1 : 0]    remaining_len;
    reg  [PKT_ADDR_W       - 1 : 0]    next_incr_addr;
    reg  [PKT_ADDR_W       - 1 : 0]    incr_wrapped_addr;
    reg  [PKT_ADDR_W       - 1 : 0]    extended_burstwrap_value;
    reg  [PKT_ADDR_W       - 1 : 0]    addr_incr_variable_size_value;

    // -------------------------------------------
    // Byte Count Converter
    // -------------------------------------------
    // Avalon Slave: Read/Write, the out_len is always 1 (unit_len).
    // AXI Slave: Read/Write, the out_len is always the in_len (pass through) of a given cycle.
    //            If bursttype RESERVED, out_len is always 1 (unit_len).
    generate if (IS_AXI_SLAVE == 1)
        begin : axi_slave_out_len
            always_ff @(posedge clk, posedge reset) begin
                if (reset) begin
                    out_len <= {LEN_W{1'b0}};
                end
                else if (enable) begin
                    out_len <= (in_bursttype == FIXED) ? in_len : unit_len;
                end
            end
        end
    else // IS_AXI_SLAVE == 0
        begin : non_axi_slave_out_len
            always_comb begin
                out_len = unit_len;
            end
        end
    endgenerate


    always_comb begin : proc_extend_burstwrap
        extended_burstwrap_value = {{(PKT_ADDR_W - PKT_BURSTWRAP_W){in_burstwrap_reg[PKT_BURSTWRAP_W - 1]}}, in_burstwrap_value};
        addr_incr_variable_size_value = {{(PKT_ADDR_W - 1){1'b0}}, 1'b1} << in_size_value;
    end

    // -------------------------------------------
    // Address Converter
    // -------------------------------------------
    // Write: out_addr = in_addr at every cycle (pass through).
    // Read: out_addr = in_addr at every new_burst. Subsequent addresses calculated by converter.

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            next_incr_addr <= {PKT_ADDR_W{1'b0}};
            out_addr <= {PKT_ADDR_W{1'b0}};
        end
        else if (enable) begin
            next_incr_addr <= next_incr_addr + addr_incr_variable_size_value;
            if (new_burst) begin
                next_incr_addr <= in_addr + addr_incr_variable_size_value;
            end
            out_addr <= incr_wrapped_addr;
        end
    end

    always_comb begin
        incr_wrapped_addr = in_addr;
        if (!new_burst) begin
            // This formula calculates addresses of WRAP bursts and works perfectly fine for other burst types too.
            incr_wrapped_addr = (in_addr_reg & ~extended_burstwrap_value) | (next_incr_addr & extended_burstwrap_value);
        end
    end

    // -------------------------------------------
    // Control Signals
    // -------------------------------------------

    // Determine the min_len.
    //     1) FIXED read to AXI slave: One-time passthrough, therefore the min_len == in_len.
    //     2) FIXED write to AXI slave: min_len == 1.
    //     3) FIXED read/write to Avalon slave: min_len == 1.
    //     4) RESERVED read/write to AXI/Avalon slave: min_len == 1.
    wire [LEN_W  - 1 : 0] min_len;
    generate if (IS_AXI_SLAVE == 1)
        begin : axi_slave_min_len
            assign min_len = (!in_is_write && (in_bursttype == FIXED)) ? in_len : unit_len;
        end
    else // IS_AXI_SLAVE == 0
        begin : non_axi_slave_min_len
            assign min_len = unit_len;
        end
    endgenerate

    // last_beat calculation.
    wire last_beat = (remaining_len == min_len);

    // next_len calculation.
    always_comb begin
        remaining_len = in_len;
        if (!new_burst) remaining_len = next_len;
    end

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            next_len <= 1'b0;
        end
        else if (enable) begin
            next_len <= remaining_len - unit_len;
        end
    end

    // new_burst calculation.
    always_ff @(posedge clk, posedge reset) begin
       if (reset) begin
            new_burst <= 1'b1;
        end
        else if (enable) begin
            new_burst <= last_beat;
        end
    end

endmodule
