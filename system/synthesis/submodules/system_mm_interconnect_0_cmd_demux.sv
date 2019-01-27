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


// $Id: //acds/rel/17.0std/ip/merlin/altera_merlin_demultiplexer/altera_merlin_demultiplexer.sv.terp#1 $
// $Revision: #1 $
// $Date: 2017/01/22 $
// $Author: swbranch $

// -------------------------------------
// Merlin Demultiplexer
//
// Asserts valid on the appropriate output
// given a one-hot channel signal.
// -------------------------------------

`timescale 1 ns / 1 ns

// ------------------------------------------
// Generation parameters:
//   output_name:         system_mm_interconnect_0_cmd_demux
//   ST_DATA_W:           94
//   ST_CHANNEL_W:        21
//   NUM_OUTPUTS:         21
//   VALID_WIDTH:         21
// ------------------------------------------

//------------------------------------------
// Message Supression Used
// QIS Warnings
// 15610 - Warning: Design contains x input pin(s) that do not drive logic
//------------------------------------------

module system_mm_interconnect_0_cmd_demux
(
    // -------------------
    // Sink
    // -------------------
    input  [21-1      : 0]   sink_valid,
    input  [94-1    : 0]   sink_data, // ST_DATA_W=94
    input  [21-1 : 0]   sink_channel, // ST_CHANNEL_W=21
    input                         sink_startofpacket,
    input                         sink_endofpacket,
    output                        sink_ready,

    // -------------------
    // Sources 
    // -------------------
    output reg                      src0_valid,
    output reg [94-1    : 0] src0_data, // ST_DATA_W=94
    output reg [21-1 : 0] src0_channel, // ST_CHANNEL_W=21
    output reg                      src0_startofpacket,
    output reg                      src0_endofpacket,
    input                           src0_ready,

    output reg                      src1_valid,
    output reg [94-1    : 0] src1_data, // ST_DATA_W=94
    output reg [21-1 : 0] src1_channel, // ST_CHANNEL_W=21
    output reg                      src1_startofpacket,
    output reg                      src1_endofpacket,
    input                           src1_ready,

    output reg                      src2_valid,
    output reg [94-1    : 0] src2_data, // ST_DATA_W=94
    output reg [21-1 : 0] src2_channel, // ST_CHANNEL_W=21
    output reg                      src2_startofpacket,
    output reg                      src2_endofpacket,
    input                           src2_ready,

    output reg                      src3_valid,
    output reg [94-1    : 0] src3_data, // ST_DATA_W=94
    output reg [21-1 : 0] src3_channel, // ST_CHANNEL_W=21
    output reg                      src3_startofpacket,
    output reg                      src3_endofpacket,
    input                           src3_ready,

    output reg                      src4_valid,
    output reg [94-1    : 0] src4_data, // ST_DATA_W=94
    output reg [21-1 : 0] src4_channel, // ST_CHANNEL_W=21
    output reg                      src4_startofpacket,
    output reg                      src4_endofpacket,
    input                           src4_ready,

    output reg                      src5_valid,
    output reg [94-1    : 0] src5_data, // ST_DATA_W=94
    output reg [21-1 : 0] src5_channel, // ST_CHANNEL_W=21
    output reg                      src5_startofpacket,
    output reg                      src5_endofpacket,
    input                           src5_ready,

    output reg                      src6_valid,
    output reg [94-1    : 0] src6_data, // ST_DATA_W=94
    output reg [21-1 : 0] src6_channel, // ST_CHANNEL_W=21
    output reg                      src6_startofpacket,
    output reg                      src6_endofpacket,
    input                           src6_ready,

    output reg                      src7_valid,
    output reg [94-1    : 0] src7_data, // ST_DATA_W=94
    output reg [21-1 : 0] src7_channel, // ST_CHANNEL_W=21
    output reg                      src7_startofpacket,
    output reg                      src7_endofpacket,
    input                           src7_ready,

    output reg                      src8_valid,
    output reg [94-1    : 0] src8_data, // ST_DATA_W=94
    output reg [21-1 : 0] src8_channel, // ST_CHANNEL_W=21
    output reg                      src8_startofpacket,
    output reg                      src8_endofpacket,
    input                           src8_ready,

    output reg                      src9_valid,
    output reg [94-1    : 0] src9_data, // ST_DATA_W=94
    output reg [21-1 : 0] src9_channel, // ST_CHANNEL_W=21
    output reg                      src9_startofpacket,
    output reg                      src9_endofpacket,
    input                           src9_ready,

    output reg                      src10_valid,
    output reg [94-1    : 0] src10_data, // ST_DATA_W=94
    output reg [21-1 : 0] src10_channel, // ST_CHANNEL_W=21
    output reg                      src10_startofpacket,
    output reg                      src10_endofpacket,
    input                           src10_ready,

    output reg                      src11_valid,
    output reg [94-1    : 0] src11_data, // ST_DATA_W=94
    output reg [21-1 : 0] src11_channel, // ST_CHANNEL_W=21
    output reg                      src11_startofpacket,
    output reg                      src11_endofpacket,
    input                           src11_ready,

    output reg                      src12_valid,
    output reg [94-1    : 0] src12_data, // ST_DATA_W=94
    output reg [21-1 : 0] src12_channel, // ST_CHANNEL_W=21
    output reg                      src12_startofpacket,
    output reg                      src12_endofpacket,
    input                           src12_ready,

    output reg                      src13_valid,
    output reg [94-1    : 0] src13_data, // ST_DATA_W=94
    output reg [21-1 : 0] src13_channel, // ST_CHANNEL_W=21
    output reg                      src13_startofpacket,
    output reg                      src13_endofpacket,
    input                           src13_ready,

    output reg                      src14_valid,
    output reg [94-1    : 0] src14_data, // ST_DATA_W=94
    output reg [21-1 : 0] src14_channel, // ST_CHANNEL_W=21
    output reg                      src14_startofpacket,
    output reg                      src14_endofpacket,
    input                           src14_ready,

    output reg                      src15_valid,
    output reg [94-1    : 0] src15_data, // ST_DATA_W=94
    output reg [21-1 : 0] src15_channel, // ST_CHANNEL_W=21
    output reg                      src15_startofpacket,
    output reg                      src15_endofpacket,
    input                           src15_ready,

    output reg                      src16_valid,
    output reg [94-1    : 0] src16_data, // ST_DATA_W=94
    output reg [21-1 : 0] src16_channel, // ST_CHANNEL_W=21
    output reg                      src16_startofpacket,
    output reg                      src16_endofpacket,
    input                           src16_ready,

    output reg                      src17_valid,
    output reg [94-1    : 0] src17_data, // ST_DATA_W=94
    output reg [21-1 : 0] src17_channel, // ST_CHANNEL_W=21
    output reg                      src17_startofpacket,
    output reg                      src17_endofpacket,
    input                           src17_ready,

    output reg                      src18_valid,
    output reg [94-1    : 0] src18_data, // ST_DATA_W=94
    output reg [21-1 : 0] src18_channel, // ST_CHANNEL_W=21
    output reg                      src18_startofpacket,
    output reg                      src18_endofpacket,
    input                           src18_ready,

    output reg                      src19_valid,
    output reg [94-1    : 0] src19_data, // ST_DATA_W=94
    output reg [21-1 : 0] src19_channel, // ST_CHANNEL_W=21
    output reg                      src19_startofpacket,
    output reg                      src19_endofpacket,
    input                           src19_ready,

    output reg                      src20_valid,
    output reg [94-1    : 0] src20_data, // ST_DATA_W=94
    output reg [21-1 : 0] src20_channel, // ST_CHANNEL_W=21
    output reg                      src20_startofpacket,
    output reg                      src20_endofpacket,
    input                           src20_ready,


    // -------------------
    // Clock & Reset
    // -------------------
    (*altera_attribute = "-name MESSAGE_DISABLE 15610" *) // setting message suppression on clk
    input clk,
    (*altera_attribute = "-name MESSAGE_DISABLE 15610" *) // setting message suppression on reset
    input reset

);

    localparam NUM_OUTPUTS = 21;
    wire [NUM_OUTPUTS - 1 : 0] ready_vector;

    // -------------------
    // Demux
    // -------------------
    always @* begin
        src0_data          = sink_data;
        src0_startofpacket = sink_startofpacket;
        src0_endofpacket   = sink_endofpacket;
        src0_channel       = sink_channel >> NUM_OUTPUTS;

        src0_valid         = sink_channel[0] && sink_valid[0];

        src1_data          = sink_data;
        src1_startofpacket = sink_startofpacket;
        src1_endofpacket   = sink_endofpacket;
        src1_channel       = sink_channel >> NUM_OUTPUTS;

        src1_valid         = sink_channel[1] && sink_valid[1];

        src2_data          = sink_data;
        src2_startofpacket = sink_startofpacket;
        src2_endofpacket   = sink_endofpacket;
        src2_channel       = sink_channel >> NUM_OUTPUTS;

        src2_valid         = sink_channel[2] && sink_valid[2];

        src3_data          = sink_data;
        src3_startofpacket = sink_startofpacket;
        src3_endofpacket   = sink_endofpacket;
        src3_channel       = sink_channel >> NUM_OUTPUTS;

        src3_valid         = sink_channel[3] && sink_valid[3];

        src4_data          = sink_data;
        src4_startofpacket = sink_startofpacket;
        src4_endofpacket   = sink_endofpacket;
        src4_channel       = sink_channel >> NUM_OUTPUTS;

        src4_valid         = sink_channel[4] && sink_valid[4];

        src5_data          = sink_data;
        src5_startofpacket = sink_startofpacket;
        src5_endofpacket   = sink_endofpacket;
        src5_channel       = sink_channel >> NUM_OUTPUTS;

        src5_valid         = sink_channel[5] && sink_valid[5];

        src6_data          = sink_data;
        src6_startofpacket = sink_startofpacket;
        src6_endofpacket   = sink_endofpacket;
        src6_channel       = sink_channel >> NUM_OUTPUTS;

        src6_valid         = sink_channel[6] && sink_valid[6];

        src7_data          = sink_data;
        src7_startofpacket = sink_startofpacket;
        src7_endofpacket   = sink_endofpacket;
        src7_channel       = sink_channel >> NUM_OUTPUTS;

        src7_valid         = sink_channel[7] && sink_valid[7];

        src8_data          = sink_data;
        src8_startofpacket = sink_startofpacket;
        src8_endofpacket   = sink_endofpacket;
        src8_channel       = sink_channel >> NUM_OUTPUTS;

        src8_valid         = sink_channel[8] && sink_valid[8];

        src9_data          = sink_data;
        src9_startofpacket = sink_startofpacket;
        src9_endofpacket   = sink_endofpacket;
        src9_channel       = sink_channel >> NUM_OUTPUTS;

        src9_valid         = sink_channel[9] && sink_valid[9];

        src10_data          = sink_data;
        src10_startofpacket = sink_startofpacket;
        src10_endofpacket   = sink_endofpacket;
        src10_channel       = sink_channel >> NUM_OUTPUTS;

        src10_valid         = sink_channel[10] && sink_valid[10];

        src11_data          = sink_data;
        src11_startofpacket = sink_startofpacket;
        src11_endofpacket   = sink_endofpacket;
        src11_channel       = sink_channel >> NUM_OUTPUTS;

        src11_valid         = sink_channel[11] && sink_valid[11];

        src12_data          = sink_data;
        src12_startofpacket = sink_startofpacket;
        src12_endofpacket   = sink_endofpacket;
        src12_channel       = sink_channel >> NUM_OUTPUTS;

        src12_valid         = sink_channel[12] && sink_valid[12];

        src13_data          = sink_data;
        src13_startofpacket = sink_startofpacket;
        src13_endofpacket   = sink_endofpacket;
        src13_channel       = sink_channel >> NUM_OUTPUTS;

        src13_valid         = sink_channel[13] && sink_valid[13];

        src14_data          = sink_data;
        src14_startofpacket = sink_startofpacket;
        src14_endofpacket   = sink_endofpacket;
        src14_channel       = sink_channel >> NUM_OUTPUTS;

        src14_valid         = sink_channel[14] && sink_valid[14];

        src15_data          = sink_data;
        src15_startofpacket = sink_startofpacket;
        src15_endofpacket   = sink_endofpacket;
        src15_channel       = sink_channel >> NUM_OUTPUTS;

        src15_valid         = sink_channel[15] && sink_valid[15];

        src16_data          = sink_data;
        src16_startofpacket = sink_startofpacket;
        src16_endofpacket   = sink_endofpacket;
        src16_channel       = sink_channel >> NUM_OUTPUTS;

        src16_valid         = sink_channel[16] && sink_valid[16];

        src17_data          = sink_data;
        src17_startofpacket = sink_startofpacket;
        src17_endofpacket   = sink_endofpacket;
        src17_channel       = sink_channel >> NUM_OUTPUTS;

        src17_valid         = sink_channel[17] && sink_valid[17];

        src18_data          = sink_data;
        src18_startofpacket = sink_startofpacket;
        src18_endofpacket   = sink_endofpacket;
        src18_channel       = sink_channel >> NUM_OUTPUTS;

        src18_valid         = sink_channel[18] && sink_valid[18];

        src19_data          = sink_data;
        src19_startofpacket = sink_startofpacket;
        src19_endofpacket   = sink_endofpacket;
        src19_channel       = sink_channel >> NUM_OUTPUTS;

        src19_valid         = sink_channel[19] && sink_valid[19];

        src20_data          = sink_data;
        src20_startofpacket = sink_startofpacket;
        src20_endofpacket   = sink_endofpacket;
        src20_channel       = sink_channel >> NUM_OUTPUTS;

        src20_valid         = sink_channel[20] && sink_valid[20];

    end

    // -------------------
    // Backpressure
    // -------------------
    assign ready_vector[0] = src0_ready;
    assign ready_vector[1] = src1_ready;
    assign ready_vector[2] = src2_ready;
    assign ready_vector[3] = src3_ready;
    assign ready_vector[4] = src4_ready;
    assign ready_vector[5] = src5_ready;
    assign ready_vector[6] = src6_ready;
    assign ready_vector[7] = src7_ready;
    assign ready_vector[8] = src8_ready;
    assign ready_vector[9] = src9_ready;
    assign ready_vector[10] = src10_ready;
    assign ready_vector[11] = src11_ready;
    assign ready_vector[12] = src12_ready;
    assign ready_vector[13] = src13_ready;
    assign ready_vector[14] = src14_ready;
    assign ready_vector[15] = src15_ready;
    assign ready_vector[16] = src16_ready;
    assign ready_vector[17] = src17_ready;
    assign ready_vector[18] = src18_ready;
    assign ready_vector[19] = src19_ready;
    assign ready_vector[20] = src20_ready;

    assign sink_ready = |(sink_channel & ready_vector);

endmodule

