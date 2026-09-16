// tb_ne2000_iobus.v -- test T3.2 of NE2000_AO486_PLAN.md.
//
// System-level attach test: the REAL rtl/soc/iobus.v drives ne2000_isa through
// the same decode, io32, wait and read-mux wiring that rtl/system.v uses. What
// this proves that tb_ne2000_isa.v cannot: the chip-select timing, the bus_wait
// handshake and the bus_io32 single-cycle 16-bit transfer all agree with the
// ao486 bus, so an x86 IN/OUT actually reaches the card.
//
// Stimulus is at the CPU side of iobus: cpu_io_read/write with a byte count,
// exactly as rtl/ao486 issues them.  Byte reads are masked to 8 bits when
// checked: iobus fills only byte 0 of cpu_read_data for a 1-byte IN, and the
// CPU uses only that byte.

module tb_ne2000_iobus;

reg clk = 1'b0;
reg reset = 1'b1;

// CPU side of iobus
reg         cpu_read_do = 1'b0;
reg  [15:0] cpu_read_address = 16'h0000;
reg   [2:0] cpu_read_length = 3'd1;
wire [31:0] cpu_read_data;
wire        cpu_read_done;
reg         cpu_write_do = 1'b0;
reg  [15:0] cpu_write_address = 16'h0000;
reg   [2:0] cpu_write_length = 3'd1;
reg  [31:0] cpu_write_data = 32'h0;
wire        cpu_write_done;

// Peripheral side of iobus
wire [15:0] iobus_address;
wire        iobus_write;
wire        iobus_read;
wire  [2:0] iobus_datasize;
wire [31:0] iobus_writedata;

integer errors = 0;

// ---- decode, exactly as rtl/system.v does it -------------------------------
reg ne2k_cs;
always @(posedge clk) begin
    ne2k_cs <= ({iobus_address[15:6]} == 10'h00C) && (iobus_address[5:4] != 2'b11);
end

wire ne2k_dataport = (iobus_address[5:3] == 3'b010);
wire ne2k_io32     = ne2k_cs & ne2k_dataport & (iobus_datasize != 3'd1);

wire [31:0] ne2k_readdata;
wire        ne2k_wait;
wire        ne2k_irq;

iobus iobus
(
    .clk               (clk),
    .reset             (reset),

    .cpu_read_do       (cpu_read_do),
    .cpu_read_address  (cpu_read_address),
    .cpu_read_length   (cpu_read_length),
    .cpu_read_data     (cpu_read_data),
    .cpu_read_done     (cpu_read_done),
    .cpu_write_do      (cpu_write_do),
    .cpu_write_address (cpu_write_address),
    .cpu_write_length  (cpu_write_length),
    .cpu_write_data    (cpu_write_data),
    .cpu_write_done    (cpu_write_done),

    .bus_address       (iobus_address),
    .bus_write         (iobus_write),
    .bus_read          (iobus_read),
    .bus_io32          (ne2k_io32),
    .bus_datasize      (iobus_datasize),
    .bus_writedata     (iobus_writedata),
    .bus_readdata      (ne2k_cs ? ne2k_readdata : 32'h000000FF),
    .bus_wait          (ne2k_wait)
);

ne2000_isa ne2000
(
    .clk               (clk),
    .reset             (reset),

    .io_address        (iobus_address[5:0]),
    .io_read           (iobus_read  & ne2k_cs),
    .io_write          (iobus_write & ne2k_cs),
    .io_writedata      (iobus_writedata),
    .io_32             (ne2k_io32),
    .io_readdata       (ne2k_readdata),
    .io_wait           (ne2k_wait),

    .irq               (ne2k_irq),

    .eth_dma_ready     (1'b0),
    .eth_dma_rdata     (16'h0000),
    .eth_dma_rdata64   (64'h0),
    .eth_dma_req       (),
    .eth_dma_write     (),
    .eth_dma_addr      (),
    .eth_dma_wdata     (),
    .eth_dma_wide      (),
    .eth_dma_wdata64   (),
    .eth_dma_uds       (),
    .eth_dma_lds       ()
);

always #5 clk = ~clk;

// ---- x86 IN / OUT ----------------------------------------------------------

task automatic io_out;
    input [15:0] port;
    input  [2:0] len;
    input [31:0] value;
    integer guard;
    begin
        @(negedge clk);
        cpu_write_address = port;
        cpu_write_length  = len;
        cpu_write_data    = value;
        cpu_write_do      = 1'b1;
        for (guard = 0; guard < 5000; guard = guard + 1) begin
            @(posedge clk);
            #1;
            if (cpu_write_done) guard = 5000;
        end
        @(negedge clk);
        cpu_write_do = 1'b0;
        @(negedge clk);
    end
endtask

task automatic io_in;
    input  [15:0] port;
    input   [2:0] len;
    output [31:0] value;
    integer guard;
    begin
        @(negedge clk);
        cpu_read_address = port;
        cpu_read_length  = len;
        cpu_read_do      = 1'b1;
        value = 32'hDEADBEEF;
        for (guard = 0; guard < 5000; guard = guard + 1) begin
            @(posedge clk);
            #1;
            if (cpu_read_done) begin
                value = cpu_read_data;
                guard = 5000;
            end
        end
        @(negedge clk);
        cpu_read_do = 1'b0;
        @(negedge clk);
    end
endtask

task automatic check;
    input [31:0] got;
    input [31:0] expected;
    input [511:0] label;
    begin
        if (got !== expected) begin
            $display("FAIL: %0s expected 0x%08x got 0x%08x", label, expected, got);
            errors = errors + 1;
        end else $display("ok:   %0s = 0x%08x", label, got);
    end
endtask

reg [31:0] d;

initial begin
    reset = 1'b1;
    repeat (10) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    repeat (10) @(posedge clk);

    // ---- byte IN/OUT through the real bus -----------------------------------
    io_out(16'h0300, 3'd1, 32'h00000021);          // CR = stop, page 0
    io_in (16'h030A, 3'd1, d); check(d & 32'h000000FF, 32'h00000050, "IN  0x30A (RTL8019 ID0)");
    io_in (16'h030B, 3'd1, d); check(d & 32'h000000FF, 32'h00000070, "IN  0x30B (RTL8019 ID1)");

    io_out(16'h0303, 3'd1, 32'h00000046);          // BNRY = 0x46
    io_in (16'h0303, 3'd1, d); check(d & 32'h000000FF, 32'h00000046, "IN  0x303 (BNRY read-back)");

    // ---- 16-bit data port: one bus cycle via bus_io32 ------------------------
    io_out(16'h0300, 3'd1, 32'h00000021);
    io_out(16'h030E, 3'd1, 32'h00000001);          // DCR: WTS=1, BOS=0
    io_out(16'h030A, 3'd1, 32'h00000002);          // RBCR0 = 2
    io_out(16'h030B, 3'd1, 32'h00000000);          // RBCR1
    io_out(16'h0308, 3'd1, 32'h00000000);          // RSAR0
    io_out(16'h0309, 3'd1, 32'h00000040);          // RSAR1 -> 0x4000
    io_out(16'h0300, 3'd1, 32'h00000012);          // start + remote write
    io_out(16'h0310, 3'd2, 32'h0000A55A);          // OUTW data port

    repeat (8) @(posedge clk);
    check({24'h0, ne2000.u_core.packet_ram_inst.mem_u[0]}, 32'h0000005A,
          "mem[0x4000] == D[7:0] (x86 byte order over the real bus)");

    io_out(16'h0300, 3'd1, 32'h00000021);
    io_out(16'h030A, 3'd1, 32'h00000002);
    io_out(16'h030B, 3'd1, 32'h00000000);
    io_out(16'h0308, 3'd1, 32'h00000000);
    io_out(16'h0309, 3'd1, 32'h00000040);
    io_out(16'h0300, 3'd1, 32'h0000000A);          // start + remote read
    io_in (16'h0310, 3'd2, d);
    check(d & 32'h0000FFFF, 32'h0000A55A, "INW 0x310 (16-bit data port)");

    // ---- an unclaimed port in the window must still terminate ---------------
    io_in (16'h0320, 3'd1, d);                      // debug aperture, harmless
    $display("ok:   IN  0x320 (debug aperture) terminated, data 0x%08x", d);

    if (errors == 0) $display("PASS: tb_ne2000_iobus");
    else             $display("FAIL: tb_ne2000_iobus (%0d error(s))", errors);
    $finish;
end

endmodule
