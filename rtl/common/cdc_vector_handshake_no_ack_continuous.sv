/*
Can be used in place of asynchronous FIFO for applications with infrequent transitions
to pass vector across CDC, where clk_in and clk_out frequencies are known and bounded.
Continuously passes value across but holds current value stable for HOLD_INPUT_CYCLES
while 1 resolves through single bit handshake synchronizer. Works for both fast->slow
and slow->fast clock differences.
*/
`timescale 1ns / 1ps
`default_nettype none

module cdc_vector_handshake_no_ack_continuous #(
    parameter DATA_WIDTH = 0,
    parameter MAX_INPUT_CLK_FREQ = 0,
    parameter MIN_OUTPUT_CLK_FREQ = 0
) (
    input wire clk_in,
    input wire clk_out,
    input wire [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out = 0
);
    // inputs must be held in clk_in clock domain to pass 1 through the synchronizer
    // in the receiving clock domain, at least 2 clk_out cycles
    localparam int HOLD_INPUT_CYCLES = (MAX_INPUT_CLK_FREQ/MIN_OUTPUT_CLK_FREQ)*2 + 1;

    logic [DATA_WIDTH-1:0] data_in_clk_in_hold = 0;
    logic [HOLD_INPUT_CYCLES*2-1:0] new_value_clk_in_hold_sr = 1;
    logic new_value_clk_in = 0;
    logic new_value_clk_out;

    always_ff @(posedge clk_in) begin
        // hold low for HOLD_INPUT_CYCLES so a 0 resolves through synchronizer
        // and we don't immediately latch the next value while new_value_clk_out is
        // still high from the previous input value as it's delayed. New value transition
        // during this period could cause metastability.
        if (new_value_clk_in_hold_sr[HOLD_INPUT_CYCLES-1])
            new_value_clk_in <= 0;

        new_value_clk_in_hold_sr <= new_value_clk_in_hold_sr << 1;

        if (new_value_clk_in_hold_sr[HOLD_INPUT_CYCLES*2-1]) begin
            // hold high for HOLD_INPUT_CYCLES
            new_value_clk_in <= 1;
            new_value_clk_in_hold_sr[0] <= 1;
            data_in_clk_in_hold <= data_in;
        end
    end

    synchronizer new_value_sync (
        .clk(clk_out),
        .in(new_value_clk_in),
        .out(new_value_clk_out)
    );

    always_ff @(posedge clk_out)
        if (new_value_clk_out)
            data_out <= data_in_clk_in_hold;
endmodule
`default_nettype wire