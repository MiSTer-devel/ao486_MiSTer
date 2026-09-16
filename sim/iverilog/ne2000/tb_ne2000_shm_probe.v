// tb_ne2000_shm_probe.v -- Phase 1 transport bench (T1.1 / T1.2 for ao486).
//
// Full chain, exactly as built in hardware:
//
//   probe registers (clk_sys) -> ne2000_shm_probe -> eth_dma_*
//     -> ne2000_ddr_mailbox (CDC to clk_avl, 16->64 lane map)
//     -> ne2000_ddram_arbiter (m1; m0 = the ao486 memory controller)
//     -> behavioural f2sdram slave with latency and backpressure
//
// Proves before hardware:
//   1. a probe write lands at the byte address the HPS would mmap
//      (0x1FF00000 + window offset), with the documented lane/byte layout
//   2. a probe read returns what the "HPS" put there
//   3. concurrent priority-master bursts are not corrupted by probe traffic
//   4. a stalled transport is retired by the probe watchdog, not hung
//
// Single clock domain, matching hardware: ao486 sets DDRAM_CLK = clk_sys
// (rtl/system.v), so the mailbox never crosses domains -- which is also why the
// 1-cycle-reply pulse-width hazard A2065 hit at 114 MHz cannot bite here.

`timescale 1ns / 1ps

module tb_ne2000_shm_probe;

reg clk_sys = 1'b0;
reg clk_avl = 1'b0;
reg reset   = 1'b1;

always #5    clk_sys = ~clk_sys;      // 100 MHz
always #5    clk_avl = ~clk_avl;      // DDRAM_CLK == clk_sys on ao486

integer errors = 0;

// ---- probe register interface ---------------------------------------------
reg  [3:0] io_address = 4'h0;
reg        io_read = 1'b0;
reg        io_write = 1'b0;
reg  [7:0] io_writedata = 8'h00;
wire [7:0] io_readdata;

// ---- probe <-> mailbox ------------------------------------------------------
wire        eth_dma_req, eth_dma_write, eth_dma_wide, eth_dma_uds, eth_dma_lds;
wire [15:1] eth_dma_addr;
wire [15:0] eth_dma_wdata;
wire [63:0] eth_dma_wdata64;
wire        eth_dma_ready;
wire [15:0] eth_dma_rdata;

reg         stall_transport = 1'b0;

ne2000_shm_probe #(.TIMEOUT_CYCLES(16'd400)) probe
(
    .clk(clk_sys), .reset(reset),
    .io_address(io_address), .io_read(io_read), .io_write(io_write),
    .io_writedata(io_writedata), .io_readdata(io_readdata),
    .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
    .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
    .eth_dma_wide(eth_dma_wide), .eth_dma_wdata64(eth_dma_wdata64),
    .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
    .eth_dma_ready(eth_dma_ready & ~stall_transport), .eth_dma_rdata(eth_dma_rdata)
);

// ---- mailbox ----------------------------------------------------------------
wire [28:0] m1_address;
wire  [7:0] m1_burstcount, m1_byteenable;
wire [63:0] m1_writedata;
wire        m1_read, m1_write, m1_waitrequest;
wire [63:0] m1_readdata;
wire        m1_readdatavalid;

ne2000_ddr_mailbox mbx
(
    .clk_sys(clk_sys), .reset_sys(reset),
    .eth_dma_req(eth_dma_req & ~stall_transport), .eth_dma_write(eth_dma_write),
    .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
    .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
    .eth_dma_wide(eth_dma_wide), .eth_dma_wdata64(eth_dma_wdata64),
    .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata), .eth_dma_rdata64(),

    .clk_avl(clk_avl), .reset_avl(reset),
    .avl_address(m1_address), .avl_burstcount(m1_burstcount),
    .avl_byteenable(m1_byteenable), .avl_writedata(m1_writedata),
    .avl_read(m1_read), .avl_write(m1_write),
    .avl_waitrequest(m1_waitrequest), .avl_readdata(m1_readdata),
    .avl_readdatavalid(m1_readdatavalid), .dbg()
);

// ---- priority master (ao486 memory controller stand-in) --------------------
reg  [28:0] m0_address = 29'h0;
reg   [7:0] m0_burstcount = 8'd1;
reg  [63:0] m0_writedata = 64'h0;
reg         m0_read = 1'b0, m0_write = 1'b0;
wire        m0_waitrequest;
wire [63:0] m0_readdata;
wire        m0_readdatavalid;

wire [28:0] s_address;
wire  [7:0] s_burstcount, s_byteenable;
wire [63:0] s_writedata;
wire        s_read, s_write, s_waitrequest;
wire [63:0] s_readdata;
wire        s_readdatavalid;

ne2000_ddram_arbiter arb
(
    .clk(clk_avl), .rst(reset),
    .m0_address(m0_address), .m0_burstcount(m0_burstcount), .m0_byteenable(8'hFF),
    .m0_writedata(m0_writedata), .m0_read(m0_read), .m0_write(m0_write),
    .m0_waitrequest(m0_waitrequest), .m0_readdata(m0_readdata),
    .m0_readdatavalid(m0_readdatavalid),

    .m1_address(m1_address), .m1_burstcount(m1_burstcount),
    .m1_byteenable(m1_byteenable), .m1_writedata(m1_writedata),
    .m1_read(m1_read), .m1_write(m1_write), .m1_waitrequest(m1_waitrequest),
    .m1_readdata(m1_readdata), .m1_readdatavalid(m1_readdatavalid),

    .s_address(s_address), .s_burstcount(s_burstcount), .s_byteenable(s_byteenable),
    .s_writedata(s_writedata), .s_read(s_read), .s_write(s_write),
    .s_waitrequest(s_waitrequest), .s_readdata(s_readdata),
    .s_readdatavalid(s_readdatavalid)
);

// ---- behavioural f2sdram slave ----------------------------------------------
// Sparse memory keyed by 64-bit word address, with wait states and read latency.
localparam [28:0] WINDOW_WORD_BASE = 29'h03FE0000;   // 0x1FF00000 >> 3

reg [63:0] mem [0:1023];
integer    i;

reg        rd_pending = 1'b0;
reg [63:0] rd_data = 64'h0;
reg  [2:0] rd_delay = 3'd0;
reg  [2:0] wait_ctr = 3'd0;

assign s_waitrequest = (wait_ctr != 3'd0);

always @(posedge clk_avl) begin
    if (reset) begin
        wait_ctr   <= 3'd0;
        rd_pending <= 1'b0;
        rd_delay   <= 3'd0;
    end
    else begin
        if (wait_ctr != 3'd0) wait_ctr <= wait_ctr - 3'd1;

        if (!s_waitrequest && (s_read || s_write)) begin
            wait_ctr <= 3'd2;                            // backpressure
            if (s_write) begin
                for (i = 0; i < 8; i = i + 1)
                    if (s_byteenable[i])
                        mem[s_address - WINDOW_WORD_BASE][i*8 +: 8] <=
                            s_writedata[i*8 +: 8];
            end
            else begin
                rd_data    <= mem[s_address - WINDOW_WORD_BASE];
                rd_pending <= 1'b1;
                rd_delay   <= 3'd3;                      // read latency
            end
        end

        if (rd_pending) begin
            if (rd_delay != 3'd0) rd_delay <= rd_delay - 3'd1;
            else                  rd_pending <= 1'b0;
        end
    end
end

assign s_readdata      = rd_data;
assign s_readdatavalid = rd_pending && (rd_delay == 3'd0);

// ---------------------------------------------------------------------------
// Probe register access helpers (byte ports, as the guest sees them)
// ---------------------------------------------------------------------------
task automatic pwrite;
    input [3:0] a;
    input [7:0] d;
    begin
        @(negedge clk_sys);
        io_address = a; io_writedata = d; io_write = 1'b1;
        @(negedge clk_sys);
        io_write = 1'b0;
    end
endtask

task automatic pread;
    input  [3:0] a;
    output [7:0] d;
    begin
        @(negedge clk_sys);
        io_address = a; io_read = 1'b1;
        @(negedge clk_sys);
        d = io_readdata;
        io_read = 1'b0;
    end
endtask

// Run one probe transfer and wait for it to retire.
task automatic do_transfer;
    input [15:0] byte_addr;
    input [15:0] wdata;
    input        is_write;
    output [7:0] status;
    integer guard;
    reg [7:0] st;
    begin
        pwrite(4'h8, byte_addr[7:0]);
        pwrite(4'h9, byte_addr[15:8]);
        if (is_write) begin
            pwrite(4'hA, wdata[7:0]);
            pwrite(4'hB, wdata[15:8]);
        end
        pwrite(4'hC, is_write ? 8'h02 : 8'h01);

        st = 8'h00;
        for (guard = 0; guard < 3000; guard = guard + 1) begin
            pread(4'hC, st);
            if (st[1]) guard = 3000;                     // done
        end
        status = st;
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

reg [7:0]  st;
reg [7:0]  d_lo, d_hi;
reg [63:0] word;
integer    burst_errors;

initial begin
    for (i = 0; i < 1024; i = i + 1) mem[i] = 64'h0;

    repeat (10) @(posedge clk_sys);
    @(negedge clk_sys);
    reset = 1'b0;
    repeat (10) @(posedge clk_sys);

    // ---- 1. write through the probe, inspect the DDR word ------------------
    // Window byte offset 0x0000 -> 64-bit word 0, lane 0.
    do_transfer(16'h0000, 16'hCAFE, 1'b1, st);
    check({24'h0, st}, 32'h00000002, "write retired (done, no timeout)");

    word = mem[0];
    // Documented lane layout: the 16-bit field at lane L is {wdata[7:0], wdata[15:8]}
    check({16'h0, word[15:0]}, 32'h0000FECA,
          "DDR word 0 lane 0 holds the byte-swapped payload");

    // ---- 2. read it back ----------------------------------------------------
    do_transfer(16'h0000, 16'h0000, 1'b0, st);
    check({24'h0, st}, 32'h00000002, "read retired");
    pread(4'hA, d_lo);
    pread(4'hB, d_hi);
    check({16'h0, d_hi, d_lo}, 32'h0000CAFE, "probe read-back of its own write");

    // ---- 3. read a value the "HPS" placed in the window ---------------------
    // HPS writes 0xCAFEBABE at window offset 0x108C (the signature slot).
    // lane = byte_addr[2:1] -> 0x108C picks lane 2, i.e. bits [47:32]
    mem[16'h108C >> 3][47:32] = 16'hFECA;
    do_transfer(16'h108C, 16'h0000, 1'b0, st);
    pread(4'hA, d_lo);
    pread(4'hB, d_hi);
    check({16'h0, d_hi, d_lo}, 32'h0000CAFE,
          "probe reads an HPS-written word at window offset 0x108C");

    // ---- 4. priority master must not be corrupted --------------------------
    mem[100] = 64'h0123456789ABCDEF;
    burst_errors = 0;
    fork
        begin : m0_traffic
            integer k;
            for (k = 0; k < 6; k = k + 1) begin
                @(negedge clk_avl);
                m0_address = WINDOW_WORD_BASE + 29'd100;
                m0_read = 1'b1;
                @(posedge clk_avl);
                while (m0_waitrequest) @(posedge clk_avl);
                @(negedge clk_avl);
                m0_read = 1'b0;
                while (!m0_readdatavalid) @(posedge clk_avl);
                if (m0_readdata !== 64'h0123456789ABCDEF) burst_errors = burst_errors + 1;
            end
        end
        begin : probe_traffic
            do_transfer(16'h0010, 16'h1234, 1'b1, st);
            do_transfer(16'h0018, 16'h5678, 1'b1, st);
        end
    join
    check(burst_errors, 32'h0, "priority master reads uncorrupted during probe traffic");

    // ---- 5. stalled transport must time out, not hang ----------------------
    stall_transport = 1'b1;
    do_transfer(16'h0020, 16'hDEAD, 1'b1, st);
    check({24'h0, st}, 32'h00000006, "stalled transport retires with timeout bit");
    stall_transport = 1'b0;

    if (errors == 0) $display("PASS: tb_ne2000_shm_probe");
    else             $display("FAIL: tb_ne2000_shm_probe (%0d error(s))", errors);
    $finish;
end

endmodule
