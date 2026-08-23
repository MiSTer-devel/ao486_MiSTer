// tb_ne2000_bos.v -- test T2.2 of NE2000_AO486_PLAN.md.
//
// Drives ne2000_core through its GENERIC host port (no Amiga glue) and asks the
// one question the ao486 port depends on: for a given DCR.BOS setting, in which
// byte lane does the host see the first byte of packet RAM?
//
// Convention established by the vendored bench suite (expect_packet_ram_byte):
// an EVEN NE2000 memory address is mem_u, i.e. the high half of the 16-bit
// packet-RAM word. The background FSM writes received frames in wire order, so
// "byte at the even address" == "earlier byte on the wire".
//
// Real DP8390 semantics: DCR.BOS=0 is 8086 byte order (first byte in D[7:0]),
// DCR.BOS=1 is 68000 byte order (first byte in D[15:8]).  x86 guests program
// BOS=0, so the ao486 glue needs BOS=0 to deliver mem[even] in D[7:0].

`timescale 1ns / 1ps

module tb_ne2000_bos;

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

// Canonical device offsets (byte) -> host word address.
localparam [14:0] REG_BASE  = 15'h0600;   // byte 0x0C00, 4 bytes per register
localparam [14:0] DATA_PORT = 15'h0620;   // byte 0x0C40

// 4 BYTES per register == 2 WORD steps in host_addr[15:1].
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

// 16-bit data-port read; returns the word the host would latch.
task automatic read_data_port;
    output [15:0] value;
    integer waits;
    reg got;
    begin
        got = 1'b0;
        value = 16'hXXXX;
        @(negedge clk);
        host_addr = DATA_PORT;
        host_sel = 1'b1;
        host_rd = 1'b1;
        host_cyc_n = 1'b0;
        host_be_hi_n = 1'b0;
        host_be_lo_n = 1'b0;
        for (waits = 0; waits < 600; waits = waits + 1) begin
            @(posedge clk);
            #1;
            if (!got && host_ack_n === 1'b0) begin
                value = host_rdata;
                got = 1'b1;
                waits = 600;
            end
        end
        @(negedge clk);
        host_rd = 1'b0;
        host_cyc_n = 1'b1;
        host_be_hi_n = 1'b1;
        host_be_lo_n = 1'b1;
        host_sel = 1'b0;
        if (!got) begin
            $display("FAIL: data-port read never acknowledged");
            errors = errors + 1;
        end
    end
endtask

task automatic poke_packet_ram_word;
    input [15:0] ne_addr;
    input [15:0] value;         // {byte at even addr, byte at odd addr}
    reg [12:0] index;
    begin
        index = (ne_addr - 16'h4000) >> 1;
        dut.packet_ram_inst.mem_u[index] = value[15:8];
        dut.packet_ram_inst.mem_l[index] = value[7:0];
    end
endtask

// Arm a remote-DMA read of `count` bytes starting at `addr`, with the given DCR.
task automatic arm_remote_read;
    input [15:0] addr;
    input [15:0] count;
    input [7:0] dcr;
    begin
        write_reg(5'h00, 8'h21);            // CR: stop, page 0, abort DMA
        write_reg(5'h0E, dcr);              // DCR
        write_reg(5'h0A, count[7:0]);       // RBCR0
        write_reg(5'h0B, count[15:8]);      // RBCR1
        write_reg(5'h08, addr[7:0]);        // RSAR0
        write_reg(5'h09, addr[15:8]);       // RSAR1
        write_reg(5'h00, 8'h0A);            // CR: start + remote read
        repeat (4) @(posedge clk);
    end
endtask

task automatic check;
    input [15:0] got;
    input [15:0] expected;
    input [511:0] label;
    begin
        if (got !== expected) begin
            $display("FAIL: %0s expected 0x%04x got 0x%04x", label, expected, got);
            errors = errors + 1;
        end else begin
            $display("ok:   %0s = 0x%04x", label, got);
        end
    end
endtask

reg [15:0] word_bos0;
reg [15:0] word_bos1;

initial begin
    reset = 1'b1;
    repeat (8) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    repeat (8) @(posedge clk);

    // mem[0x4000] = 0xAA (first byte on the wire), mem[0x4001] = 0xBB.
    poke_packet_ram_word(16'h4000, 16'hAABB);

    // DCR = WTS(bit0) | BOS(bit1). Word mode both times.
    arm_remote_read(16'h4000, 16'd2, 8'h01);   // BOS = 0 -> 8086 order
    read_data_port(word_bos0);

    poke_packet_ram_word(16'h4000, 16'hAABB);
    arm_remote_read(16'h4000, 16'd2, 8'h03);   // BOS = 1 -> 68000 order
    read_data_port(word_bos1);

    $display("");
    $display("BOS=0 (x86, 8086 order)  data port word = 0x%04x", word_bos0);
    $display("BOS=1 (68k, 68000 order) data port word = 0x%04x", word_bos1);
    $display("packet RAM: mem[0x4000]=0xAA (first wire byte), mem[0x4001]=0xBB");
    $display("");

    // DUT is instantiated with BOS_INVERT=1, i.e. the ao486/ISA configuration.
    // Real DP8390: BOS=0 puts the FIRST memory byte in D[7:0].
    check(word_bos0, 16'hBBAA, "BOS=0 word (expect first byte 0xAA in D[7:0])");
    // BOS=1 puts the first memory byte in D[15:8].
    check(word_bos1, 16'hAABB, "BOS=1 word (expect first byte 0xAA in D[15:8])");

    if (errors == 0) $display("PASS: tb_ne2000_bos");
    else             $display("FAIL: tb_ne2000_bos (%0d error(s))", errors);
    $finish;
end

endmodule
