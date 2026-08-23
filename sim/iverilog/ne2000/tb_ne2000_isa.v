// tb_ne2000_isa.v -- tests T3.1 and T3.3 of NE2000_AO486_PLAN.md.
//
// Drives ne2000_isa the way rtl/soc/iobus.v does: a one-cycle bus_read /
// bus_write strobe, then hold while io_wait is high, then sample io_readdata.
// Everything here is an x86 view of the card at I/O base 0x300 -- byte ports,
// no 4-byte register spacing, no 68k anywhere.
//
// T3.1  port decode: RTL8019 ID at base+0x0A/0x0B reads 0x50/0x70; a 16-bit
//       data-port access completes as one transfer; the reset port resets.
// T3.3  ISR/IMR raise and clear the interrupt line cleanly, no stuck IRQ.

`timescale 1ns / 1ps

module tb_ne2000_isa;

reg clk = 1'b0;
reg reset = 1'b1;

reg  [5:0] io_address = 6'h00;
reg        io_read = 1'b0;
reg        io_write = 1'b0;
reg [31:0] io_writedata = 32'h0;
reg        io_32 = 1'b0;
wire [31:0] io_readdata;
wire       io_wait;
wire       irq;

reg eth_dma_ready = 1'b0;
reg [15:0] eth_dma_rdata = 16'h0000;
reg [63:0] eth_dma_rdata64 = 64'h0;
wire eth_dma_req, eth_dma_write, eth_dma_wide, eth_dma_uds, eth_dma_lds;
wire [15:1] eth_dma_addr;
wire [15:0] eth_dma_wdata;
wire [63:0] eth_dma_wdata64;

integer errors = 0;

ne2000_isa dut (
    .clk(clk), .reset(reset),
    .io_address(io_address), .io_read(io_read), .io_write(io_write),
    .io_writedata(io_writedata), .io_32(io_32),
    .io_readdata(io_readdata), .io_wait(io_wait),
    .irq(irq),
    .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
    .eth_dma_rdata64(eth_dma_rdata64),
    .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
    .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
    .eth_dma_wide(eth_dma_wide), .eth_dma_wdata64(eth_dma_wdata64),
    .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds)
);

always #5 clk = ~clk;

// ---------------------------------------------------------------------------
// iobus-shaped access tasks
// ---------------------------------------------------------------------------

// outb: one-cycle strobe, then wait out io_wait.
task automatic outb;
    input [5:0] port;
    input [7:0] value;
    integer guard;
    begin
        @(negedge clk);
        io_address   = port;
        io_writedata = {24'h0, value};
        io_32        = 1'b0;
        io_write     = 1'b1;
        @(negedge clk);
        io_write     = 1'b0;
        for (guard = 0; guard < 4000; guard = guard + 1) begin
            @(negedge clk);
            if (!io_wait) guard = 4000;
        end
    end
endtask

task automatic inb;
    input  [5:0] port;
    output [7:0] value;
    integer guard;
    begin
        @(negedge clk);
        io_address = port;
        io_32      = 1'b0;
        io_read    = 1'b1;
        @(negedge clk);
        io_read    = 1'b0;
        for (guard = 0; guard < 4000; guard = guard + 1) begin
            @(negedge clk);
            if (!io_wait) guard = 4000;
        end
        value = io_readdata[7:0];
    end
endtask

task automatic outw;
    input [5:0] port;
    input [15:0] value;
    integer guard;
    begin
        @(negedge clk);
        io_address   = port;
        io_writedata = {16'h0, value};
        io_32        = 1'b1;
        io_write     = 1'b1;
        @(negedge clk);
        io_write     = 1'b0;
        for (guard = 0; guard < 4000; guard = guard + 1) begin
            @(negedge clk);
            if (!io_wait) guard = 4000;
        end
    end
endtask

task automatic inw;
    input  [5:0] port;
    output [15:0] value;
    integer guard;
    begin
        @(negedge clk);
        io_address = port;
        io_32      = 1'b1;
        io_read    = 1'b1;
        @(negedge clk);
        io_read    = 1'b0;
        for (guard = 0; guard < 4000; guard = guard + 1) begin
            @(negedge clk);
            if (!io_wait) guard = 4000;
        end
        value = io_readdata[15:0];
    end
endtask

task automatic check8;
    input [7:0] got;
    input [7:0] expected;
    input [511:0] label;
    begin
        if (got !== expected) begin
            $display("FAIL: %0s expected 0x%02x got 0x%02x", label, expected, got);
            errors = errors + 1;
        end else $display("ok:   %0s = 0x%02x", label, got);
    end
endtask

task automatic check16;
    input [15:0] got;
    input [15:0] expected;
    input [511:0] label;
    begin
        if (got !== expected) begin
            $display("FAIL: %0s expected 0x%04x got 0x%04x", label, expected, got);
            errors = errors + 1;
        end else $display("ok:   %0s = 0x%04x", label, got);
    end
endtask

task automatic checkbit;
    input value;
    input expected;
    input [511:0] label;
    begin
        if (value !== expected) begin
            $display("FAIL: %0s expected %b got %b", label, expected, value);
            errors = errors + 1;
        end else $display("ok:   %0s = %b", label, value);
    end
endtask

// ISA register numbers (byte ports at base+N)
localparam [5:0] P_CR    = 6'h00;
localparam [5:0] P_PSTART= 6'h01;
localparam [5:0] P_PSTOP = 6'h02;
localparam [5:0] P_BNRY  = 6'h03;
localparam [5:0] P_ISR   = 6'h07;
localparam [5:0] P_RSAR0 = 6'h08;
localparam [5:0] P_RSAR1 = 6'h09;
localparam [5:0] P_ID0   = 6'h0A;   // read: RTL8019 ID0 (0x50) / write: RBCR0
localparam [5:0] P_ID1   = 6'h0B;   // read: RTL8019 ID1 (0x70) / write: RBCR1
localparam [5:0] P_RBCR0 = 6'h0A;
localparam [5:0] P_RBCR1 = 6'h0B;
localparam [5:0] P_DCR   = 6'h0E;
localparam [5:0] P_IMR   = 6'h0F;
localparam [5:0] P_DATA  = 6'h10;
localparam [5:0] P_RESET = 6'h18;

reg [7:0]  b;
reg [15:0] w;

initial begin
    reset = 1'b1;
    repeat (8) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    repeat (8) @(posedge clk);

    // ---- T3.1: the probe every NE2000 driver starts with -------------------
    outb(P_CR, 8'h21);                       // stop, page 0
    inb(P_ID0, b); check8(b, 8'h50, "base+0x0A RTL8019 ID0");
    inb(P_ID1, b); check8(b, 8'h70, "base+0x0B RTL8019 ID1");

    // Register write/read-back through byte ports.
    outb(P_PSTART, 8'h46);
    outb(P_PSTOP,  8'h80);
    outb(P_BNRY,   8'h46);
    inb(P_BNRY, b); check8(b, 8'h46, "BNRY read-back through byte port");

    // ---- T3.1: 16-bit data port --------------------------------------------
    // Remote-DMA write of one word into packet RAM at 0x4000, then read it back.
    outb(P_CR,    8'h21);
    outb(P_DCR,   8'h01);                    // WTS=1, BOS=0 (x86 order)
    outb(P_RBCR0, 8'h02);
    outb(P_RBCR1, 8'h00);
    outb(P_RSAR0, 8'h00);
    outb(P_RSAR1, 8'h40);                    // 0x4000
    outb(P_CR,    8'h12);                    // start + remote write
    outw(P_DATA,  16'h1234);
    repeat (8) @(posedge clk);

    // x86/BOS=0: D[7:0] is the first memory byte, so mem[0x4000] must be 0x34.
    check8(dut.u_core.packet_ram_inst.mem_u[0], 8'h34,
           "16-bit data-port write: mem[0x4000] (first byte) = D[7:0]");
    check8(dut.u_core.packet_ram_inst.mem_l[0], 8'h12,
           "16-bit data-port write: mem[0x4001] = D[15:8]");

    outb(P_CR,    8'h21);
    outb(P_RBCR0, 8'h02);
    outb(P_RBCR1, 8'h00);
    outb(P_RSAR0, 8'h00);
    outb(P_RSAR1, 8'h40);
    outb(P_CR,    8'h0A);                    // start + remote read
    inw(P_DATA, w);
    check16(w, 16'h1234, "16-bit data-port read-back");

    // ---- byte-mode (DCR.WTS=0) data port round trip -------------------------
    // Hardware finding 2026-07-28: DEBUG.EXE wrote AA,BB to 0x4000 and read back
    // BB,AA. DCR.BOS must NOT affect 8-bit transfers -- byte transfers have no
    // byte order. Write path never swapped; read path did.
    outb(P_CR,    8'h21);
    outb(P_DCR,   8'h00);                    // WTS=0 -> byte mode, BOS=0
    outb(P_RBCR0, 8'h04);
    outb(P_RBCR1, 8'h00);
    outb(P_RSAR0, 8'h00);
    outb(P_RSAR1, 8'h40);                    // 0x4000
    outb(P_CR,    8'h12);                    // start + remote write
    outb(P_DATA,  8'hAA);
    outb(P_DATA,  8'hBB);
    repeat (8) @(posedge clk);

    outb(P_CR,    8'h21);
    outb(P_RBCR0, 8'h04);
    outb(P_RBCR1, 8'h00);
    outb(P_RSAR0, 8'h00);
    outb(P_RSAR1, 8'h40);
    outb(P_CR,    8'h0A);                    // start + remote read
    inb(P_DATA, b); check8(b, 8'hAA, "byte-mode read back [0x4000] (wrote AA)");
    inb(P_DATA, b); check8(b, 8'hBB, "byte-mode read back [0x4001] (wrote BB)");

    // ---- T3.3: interrupt line ----------------------------------------------
    outb(P_CR,  8'h22);
    outb(P_IMR, 8'h00);
    repeat (4) @(posedge clk);
    checkbit(irq, 1'b0, "IRQ low with IMR=0");

    // Remote DMA complete (ISR.RDC) is the easiest ISR bit to raise from the
    // host side: arm a zero-length remote DMA and let it retire.
    outb(P_IMR, 8'h40);                      // unmask RDC
    outb(P_RBCR0, 8'h00);
    outb(P_RBCR1, 8'h00);
    outb(P_CR,  8'h0A);                      // remote read, count 0 -> RDC
    repeat (8) @(posedge clk);
    checkbit(irq, 1'b1, "IRQ high with ISR.RDC set and unmasked");

    outb(P_ISR, 8'h40);                      // write-1-to-clear RDC
    repeat (8) @(posedge clk);
    checkbit(irq, 1'b0, "IRQ low again after ISR clear");

    // ---- debug aperture must not alias onto the reset port -----------------
    // base+0x27 maps to canonical 0x0C7C (the reset port). It must read open
    // bus and leave ISR alone, not reset the NIC.
    outb(P_ISR, 8'hFF);                      // clear ISR
    inb(6'h27, b); check8(b, 8'hFF, "base+0x27 (unmapped debug slot) reads open bus");
    repeat (8) @(posedge clk);
    inb(P_ISR, b);
    checkbit(b[7], 1'b0, "ISR.RST still clear after base+0x27 read");

    // ---- T3.1: reset port ---------------------------------------------------
    inb(P_RESET, b);                         // read of base+0x18 triggers reset
    repeat (8) @(posedge clk);
    inb(P_ISR, b);
    checkbit(b[7], 1'b1, "ISR.RST set after reset-port read");

    if (errors == 0) $display("PASS: tb_ne2000_isa");
    else             $display("FAIL: tb_ne2000_isa (%0d error(s))", errors);
    $finish;
end

endmodule
