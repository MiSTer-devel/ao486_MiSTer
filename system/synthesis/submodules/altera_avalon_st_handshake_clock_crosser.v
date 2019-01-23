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


// $File: //acds/rel/17.0std/ip/avalon_st/altera_avalon_st_handshake_clock_crosser/altera_avalon_st_handshake_clock_crosser.v $
// $Revision: #1 $
// $Date: 2017/01/22 $
// $Author: swbranch $
//------------------------------------------------------------------------------
// Clock crosser module with handshaking mechanism
//------------------------------------------------------------------------------

`timescale 1ns / 1ns

module altera_avalon_st_handshake_clock_crosser
#(
    parameter DATA_WIDTH       = 8,
              BITS_PER_SYMBOL  = 8,
              USE_PACKETS      = 0,

              // ------------------------------
              // Optional signal widths
              // ------------------------------
              USE_CHANNEL      = 0,
              CHANNEL_WIDTH    = 1,
              USE_ERROR        = 0,
              ERROR_WIDTH      = 1,

              VALID_SYNC_DEPTH = 2,
              READY_SYNC_DEPTH = 2,

              USE_OUTPUT_PIPELINE = 1,

              // ------------------------------
              // Derived parameters
              // ------------------------------
              SYMBOLS_PER_BEAT = DATA_WIDTH / BITS_PER_SYMBOL,
              EMPTY_WIDTH = log2ceil(SYMBOLS_PER_BEAT)
)
(
    input in_clk,
    input in_reset,
    input out_clk,
    input out_reset,

    output in_ready,
    input  in_valid,
    input [DATA_WIDTH - 1 : 0]      in_data,
    input [CHANNEL_WIDTH - 1 : 0]   in_channel,
    input [ERROR_WIDTH - 1 : 0]     in_error,
    input in_startofpacket,
    input in_endofpacket,
    input [(EMPTY_WIDTH ? (EMPTY_WIDTH - 1) : 0) : 0] in_empty,

    input  out_ready,
    output out_valid,
    output [DATA_WIDTH - 1 : 0]     out_data,
    output [CHANNEL_WIDTH - 1 : 0]  out_channel,
    output [ERROR_WIDTH - 1 : 0]    out_error,
    output out_startofpacket,
    output out_endofpacket,
    output [(EMPTY_WIDTH ? (EMPTY_WIDTH - 1) : 0) : 0] out_empty
);

    // ------------------------------
    // Payload-specific widths
    // ------------------------------
    localparam PACKET_WIDTH = (USE_PACKETS) ? 2 + EMPTY_WIDTH : 0;
    localparam PCHANNEL_W   = (USE_CHANNEL) ? CHANNEL_WIDTH : 0;
    localparam PERROR_W     = (USE_ERROR) ? ERROR_WIDTH : 0;

    localparam PAYLOAD_WIDTH = DATA_WIDTH + 
        PACKET_WIDTH +
        PCHANNEL_W +
        EMPTY_WIDTH +
        PERROR_W;

   
    wire [PAYLOAD_WIDTH - 1: 0] in_payload;
    wire [PAYLOAD_WIDTH - 1: 0] out_payload;
   
    // ------------------------------
    // Assign in_data and other optional sink interface 
    // signals to in_payload.
    // ------------------------------
    assign in_payload[DATA_WIDTH - 1 : 0] = in_data;
    generate
        // optional packet inputs
        if (PACKET_WIDTH) begin
            assign in_payload[
                DATA_WIDTH + PACKET_WIDTH - 1 : 
                DATA_WIDTH
            ] = {in_startofpacket, in_endofpacket};
        end
        // optional channel input
        if (USE_CHANNEL) begin
            assign in_payload[
              DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W - 1 : 
              DATA_WIDTH + PACKET_WIDTH
            ] = in_channel;
        end
        // optional empty input
        if (EMPTY_WIDTH) begin
            assign in_payload[
                DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W + EMPTY_WIDTH - 1 : 
                DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W
            ] = in_empty;
        end
        // optional error input
        if (USE_ERROR) begin
            assign in_payload[
                DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W + EMPTY_WIDTH + PERROR_W - 1 : 
                DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W + EMPTY_WIDTH
            ] = in_error;
        end
    endgenerate

    // --------------------------------------------------
    // Pipe the input payload to our inner module which handles the
    // actual clock crossing
    // --------------------------------------------------
    altera_avalon_st_clock_crosser
    #(
        .SYMBOLS_PER_BEAT    (1),
        .BITS_PER_SYMBOL     (PAYLOAD_WIDTH),
        .FORWARD_SYNC_DEPTH  (VALID_SYNC_DEPTH),
        .BACKWARD_SYNC_DEPTH (READY_SYNC_DEPTH),
        .USE_OUTPUT_PIPELINE (USE_OUTPUT_PIPELINE)
    ) clock_xer (
        .in_clk    (in_clk      ),
        .in_reset  (in_reset    ),
        .in_ready  (in_ready    ),
        .in_valid  (in_valid    ),
        .in_data   (in_payload  ),
        .out_clk   (out_clk     ),
        .out_reset (out_reset   ),
        .out_ready (out_ready   ),
        .out_valid (out_valid   ),
        .out_data  (out_payload )
    );

    // --------------------------------------------------
    // Split out_payload into the output signals.
    // --------------------------------------------------
    assign out_data = out_payload[DATA_WIDTH - 1 : 0];

    generate
        // optional packet outputs
        if (USE_PACKETS) begin
            assign {out_startofpacket, out_endofpacket} = 
                out_payload[DATA_WIDTH + PACKET_WIDTH - 1 : DATA_WIDTH];
        end else begin
            // avoid a "has no driver" warning.
            assign {out_startofpacket, out_endofpacket} = 2'b0;
        end
   
        // optional channel output
        if (USE_CHANNEL) begin
            assign out_channel = out_payload[
              DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W - 1 : 
              DATA_WIDTH + PACKET_WIDTH
            ];
        end else begin
            // avoid a "has no driver" warning.
            assign out_channel = 1'b0;
        end

        // optional empty output
        if (EMPTY_WIDTH) begin
            assign out_empty = out_payload[
              DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W + EMPTY_WIDTH - 1 : 
              DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W
            ];
        end else begin
            // avoid a "has no driver" warning.
            assign out_empty = 1'b0;
        end

        // optional error output
        if (USE_ERROR) begin
            assign out_error = out_payload[
              DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W + EMPTY_WIDTH + PERROR_W - 1 : 
              DATA_WIDTH + PACKET_WIDTH + PCHANNEL_W + EMPTY_WIDTH
            ];
        end else begin
            // avoid a "has no driver" warning.
            assign out_error = 1'b0;
        end
    endgenerate

    // --------------------------------------------------
    // Calculates the log2ceil of the input value.
    // --------------------------------------------------
    function integer log2ceil;
        input integer val;
        integer i;

        begin
            i = 1;
            log2ceil = 0;

            while (i < val) begin
                log2ceil = log2ceil + 1;
                i = i << 1;
            end
        end
    endfunction

endmodule
