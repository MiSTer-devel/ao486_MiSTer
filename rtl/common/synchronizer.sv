`timescale 1ns / 1ps
`default_nettype none

module synchronizer #(
    parameter DATA_WIDTH = 1
) (
    input wire clk,   // clock domain of out
    input wire [DATA_WIDTH-1:0] in,
    output logic [DATA_WIDTH-1:0] out
);
    logic [1:0] [DATA_WIDTH-1:0] sync_regs = 0;

    always_ff @(posedge clk)
    	{sync_regs[1], sync_regs[0]} <= {sync_regs[0], in};

    always_comb out = sync_regs[1];
endmodule
`default_nettype wire