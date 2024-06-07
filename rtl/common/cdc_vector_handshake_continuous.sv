/*
Can be used in place of asynchronous FIFO for applications with infrequent transitions
to pass vector across CDC. Continuously passes value across but holds current value for
single bit synchronized handshaking feedback loop. Works for both fast->slow and
slow->fast clock differences.
*/
`timescale 1ns / 1ps
`default_nettype none

module cdc_vector_handshake_continuous #(
    parameter DATA_WIDTH = 0
) (
    input wire clk_in,
    input wire clk_out,
    input wire [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out = 0
);
    logic [DATA_WIDTH-1:0] data_hold_clk_in = 0;
    logic new_value_clk_in = 0;
    logic new_value_clk_out;
    logic ack_clk_in;

    always_ff @(posedge clk_in)
        if (ack_clk_in)
            new_value_clk_in <= 0;
        else if (!new_value_clk_in) begin
            new_value_clk_in <= 1;
            data_hold_clk_in <= data_in;
        end

    synchronizer new_value_sync (
        .clk(clk_out),
        .in(new_value_clk_in),
        .out(new_value_clk_out)
    );

    synchronizer ack_sync (
        .clk(clk_in),
        .in(new_value_clk_out),
        .out(ack_clk_in)
    );

    always_ff @(posedge clk_out)
        if (new_value_clk_out)
            data_out <= data_hold_clk_in;
endmodule
`default_nettype wire