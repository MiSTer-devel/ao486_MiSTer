// tb_ne2000_tpsr.v -- test T2.3 of NE2000_AO486_PLAN.md.
//
// Regression guard for the transmit bug fixed in the Minimig branch on
// 2026-06-13: the transmit trigger used to require the TRANSMIT page (TPSR) to
// lie inside the RECEIVE ring [PSTART, PSTOP).  On a standard NE2000 the TX
// buffer is page 0x40 and PSTART is 0x46, so 0x40 >= 0x46 is false and every
// transmit was silently dropped -- TSR/ISR.PTX never asserted and the driver
// polled ISR forever.  The fix bounds TPSR by the physical packet-RAM page
// range [0x40, 0x80) instead.
//
// The DOS/Windows NE2000 drivers ao486 will run use exactly the layout that
// triggered the bug, so this must stay covered.
//
// Positive case: TPSR=0x40, PSTART=0x46, PSTOP=0x80 -> transmit is accepted.
// Negative case: TPSR=0x90 (outside packet RAM)    -> transmit is rejected.

`timescale 1ns / 1ps

module tb_ne2000_tpsr;

reg clk = 1'b0;
reg reset = 1'b1;

reg [15:1] host_addr = 15'h0000;
reg [15:0] host_wdata = 16'h0000;
wire [15:0] host_rdata;
reg host_rd = 1'b0;
reg host_wr_hi = 1'b0;
reg host_wr_lo = 1'b0;
reg host_cyc_n = 1'b1;
reg host_be_hi_n = 1'b1;
reg host_be_lo_n = 1'b1;
reg host_sel = 1'b0;
reg host_sel_priv = 1'b0;

reg eth_dma_ready = 1'b0;
reg [15:0] eth_dma_rdata = 16'h0000;
reg [63:0] eth_dma_rdata64 = 64'h0;
wire eth_dma_req, eth_dma_write, eth_dma_wide, eth_dma_uds, eth_dma_lds;
wire [15:1] eth_dma_addr;
wire [15:0] eth_dma_wdata;
wire [63:0] eth_dma_wdata64;
wire irq, host_ack_n;

integer errors = 0;

ne2000_core dut (
    .clk(clk), .reset(reset),
    .host_addr(host_addr), .host_wdata(host_wdata), .host_rdata(host_rdata),
    .host_rd(host_rd), .host_wr_hi(host_wr_hi), .host_wr_lo(host_wr_lo),
    .host_cyc_n(host_cyc_n),
    .host_be_hi_n(host_be_hi_n), .host_be_lo_n(host_be_lo_n),
    .host_sel_priv(host_sel_priv), .host_sel(host_sel),
    .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
    .eth_dma_rdata64(eth_dma_rdata64),
    .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
    .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
    .eth_dma_wide(eth_dma_wide), .eth_dma_wdata64(eth_dma_wdata64),
    .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
    .irq(irq), .host_ack_n(host_ack_n)
);

always #5 clk = ~clk;

localparam [14:0] REG_BASE = 15'h0600;   // byte 0x0C00, 4 bytes per register

function [14:0] reg_word;
    input [4:0] index;
    begin
        reg_word = REG_BASE + {9'h000, index, 1'b0};
    end
endfunction

// x86-style register write: one byte on the LOW lane only.
task automatic write_reg;
    input [4:0] index;
    input [7:0] value;
    begin
        @(negedge clk);
        host_addr = reg_word(index);
        host_wdata = {8'h00, value};
        host_sel = 1'b1;
        host_wr_lo = 1'b1;
        host_cyc_n = 1'b0;
        host_be_lo_n = 1'b0;
        @(posedge clk);
        @(negedge clk);
        host_wr_lo = 1'b0;
        host_cyc_n = 1'b1;
        host_be_lo_n = 1'b1;
        host_sel = 1'b0;
        host_wdata = 16'h0000;
    end
endtask

// Program a standard NE2000 ring and arm a transmit from `tx_page`.
task automatic arm_transmit;
    input [7:0] tx_page;
    begin
        write_reg(5'h00, 8'h21);        // CR: stop, page 0
        write_reg(5'h0E, 8'h01);        // DCR: word mode
        write_reg(5'h01, 8'h46);        // PSTART = 0x46
        write_reg(5'h02, 8'h80);        // PSTOP  = 0x80
        write_reg(5'h03, 8'h46);        // BNRY
        write_reg(5'h0D, 8'h00);        // TCR: normal (no loopback)
        write_reg(5'h04, tx_page);      // TPSR
        write_reg(5'h05, 8'h3C);        // TBCR0 = 60 bytes
        write_reg(5'h06, 8'h00);        // TBCR1
        write_reg(5'h00, 8'h26);        // CR: STA | TXP | abort remote DMA
        repeat (8) @(posedge clk);
    end
endtask

task automatic expect_bit;
    input value;
    input expected;
    input [511:0] label;
    begin
        if (value !== expected) begin
            $display("FAIL: %0s expected %b got %b", label, expected, value);
            errors = errors + 1;
        end else begin
            $display("ok:   %0s = %b", label, value);
        end
    end
endtask

initial begin
    reset = 1'b1;
    repeat (8) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    repeat (8) @(posedge clk);

    // Positive: the standard layout that the old RX-ring gating dropped.
    arm_transmit(8'h40);
    // "Accepted" means the TPSR bounds check passed and the transmit was taken
    // up. The pending flags are single-cycle, so check the durable evidence:
    // TSR is written on acceptance -- PTX with a live host, ABT without one
    // (BF-7). A rejected transmit leaves TSR untouched.
    expect_bit(|dut.tsr_register, 1'b1,
               "TPSR=0x40 with PSTART=0x46: transmit accepted (TSR written)");

    // Recover, then negative control: a page outside packet RAM must be ignored.
    write_reg(5'h00, 8'h21);
    repeat (8) @(posedge clk);
    reset = 1'b1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    repeat (8) @(posedge clk);

    arm_transmit(8'h90);
    expect_bit(|dut.tsr_register, 1'b0,
               "TPSR=0x90 outside packet RAM: transmit rejected (TSR untouched)");

    if (errors == 0) $display("PASS: tb_ne2000_tpsr");
    else             $display("FAIL: tb_ne2000_tpsr (%0d error(s))", errors);
    $finish;
end

endmodule
