// tb_ne2000_no_host.v -- Phase 4 step 2: the guest must never wait on the host.
//
// A2065's hard-won rule: back-pressure on FPGA-internal capacity is safe;
// back-pressure that waits for host software deadlocks. They hit it as a
// circular wait -- the Amiga on a stretched DTACK waiting for Main, Main in its
// IDE handler waiting for the Amiga.
//
// This bench builds the shipped chain
//
//   ne2000_isa -> ne2000_dma_mux -> ne2000_ddr_mailbox -> ne2000_ddram_arbiter
//                                                      -> DDR slave model
//
// and runs a realistic guest sequence in two hostile conditions:
//
//   A. DDR works, but NO host ever touches the window (daemon not running).
//   B. DDR is dead: waitrequest stuck high forever.
//
// In both, every single ISA access must retire. The bench records the worst
// access latency it sees, so a regression that turns a bounded wait into an
// unbounded one shows up as a timeout rather than a hang.

`timescale 1ns / 1ps

module tb_ne2000_no_host;

reg clk = 1'b0;
reg reset = 1'b1;
always #5 clk = ~clk;

integer errors = 0;
integer worst_latency = 0;

// ---- guest side ------------------------------------------------------------
reg  [5:0] io_address = 6'h00;
reg        io_read = 1'b0, io_write = 1'b0;
reg [31:0] io_writedata = 32'h0;
reg        io_32 = 1'b0;
wire [31:0] io_readdata;
wire       io_wait;
wire       irq;

// ---- transport -------------------------------------------------------------
wire        c_req, c_write, c_wide, c_uds, c_lds;
wire [15:1] c_addr;
wire [15:0] c_wdata;
wire [63:0] c_wdata64;
wire        c_ready;
wire [15:0] c_rdata;
wire [63:0] c_rdata64;

ne2000_isa dut
(
    .clk(clk), .reset(reset),
    .io_address(io_address), .io_read(io_read), .io_write(io_write),
    .io_writedata(io_writedata), .io_32(io_32),
    .io_readdata(io_readdata), .io_wait(io_wait), .irq(irq),
    .eth_dma_ready(c_ready), .eth_dma_rdata(c_rdata), .eth_dma_rdata64(c_rdata64),
    .eth_dma_req(c_req), .eth_dma_write(c_write), .eth_dma_addr(c_addr),
    .eth_dma_wdata(c_wdata), .eth_dma_wide(c_wide), .eth_dma_wdata64(c_wdata64),
    .eth_dma_uds(c_uds), .eth_dma_lds(c_lds)
);

wire        d_req, d_write, d_wide, d_uds, d_lds;
wire [15:1] d_addr;
wire [15:0] d_wdata;
wire [63:0] d_wdata64;
wire        d_ready;
wire [15:0] d_rdata;
wire [63:0] d_rdata64;

ne2000_dma_mux mux
(
    .clk(clk), .reset(reset),
    .m0_req(c_req), .m0_write(c_write), .m0_addr(c_addr), .m0_wdata(c_wdata),
    .m0_wide(c_wide), .m0_wdata64(c_wdata64), .m0_uds(c_uds), .m0_lds(c_lds),
    .m0_ready(c_ready), .m0_rdata(c_rdata), .m0_rdata64(c_rdata64),
    .m1_req(1'b0), .m1_write(1'b0), .m1_addr(15'h0), .m1_wdata(16'h0),
    .m1_wide(1'b0), .m1_wdata64(64'h0), .m1_uds(1'b1), .m1_lds(1'b1),
    .m1_ready(), .m1_rdata(), .m1_rdata64(),
    .eth_dma_req(d_req), .eth_dma_write(d_write), .eth_dma_addr(d_addr),
    .eth_dma_wdata(d_wdata), .eth_dma_wide(d_wide), .eth_dma_wdata64(d_wdata64),
    .eth_dma_uds(d_uds), .eth_dma_lds(d_lds),
    .eth_dma_ready(d_ready), .eth_dma_rdata(d_rdata), .eth_dma_rdata64(d_rdata64)
);

wire [28:0] m1_address;
wire  [7:0] m1_burstcount, m1_byteenable;
wire [63:0] m1_writedata;
wire        m1_read, m1_write, m1_waitrequest;
wire [63:0] m1_readdata;
wire        m1_readdatavalid;

ne2000_ddr_mailbox mbx
(
    .clk_sys(clk), .reset_sys(reset),
    .eth_dma_req(d_req), .eth_dma_write(d_write), .eth_dma_addr(d_addr),
    .eth_dma_wdata(d_wdata), .eth_dma_uds(d_uds), .eth_dma_lds(d_lds),
    .eth_dma_wide(d_wide), .eth_dma_wdata64(d_wdata64),
    .eth_dma_ready(d_ready), .eth_dma_rdata(d_rdata), .eth_dma_rdata64(d_rdata64),
    .clk_avl(clk), .reset_avl(reset),
    .avl_address(m1_address), .avl_burstcount(m1_burstcount),
    .avl_byteenable(m1_byteenable), .avl_writedata(m1_writedata),
    .avl_read(m1_read), .avl_write(m1_write),
    .avl_waitrequest(m1_waitrequest), .avl_readdata(m1_readdata),
    .avl_readdatavalid(m1_readdatavalid), .dbg()
);

wire [28:0] s_address;
wire  [7:0] s_burstcount, s_byteenable;
wire [63:0] s_writedata;
wire        s_read, s_write, s_waitrequest;
wire [63:0] s_readdata;
wire        s_readdatavalid;

ne2000_ddram_arbiter arb
(
    .clk(clk), .rst(reset),
    .m0_address(29'h0), .m0_burstcount(8'd1), .m0_read(1'b0), .m0_readdata(),
    .m0_readdatavalid(), .m0_writedata(64'h0), .m0_byteenable(8'h0),
    .m0_write(1'b0), .m0_waitrequest(),
    .m1_address(m1_address), .m1_burstcount(m1_burstcount), .m1_read(m1_read),
    .m1_readdata(m1_readdata), .m1_readdatavalid(m1_readdatavalid),
    .m1_writedata(m1_writedata), .m1_byteenable(m1_byteenable),
    .m1_write(m1_write), .m1_waitrequest(m1_waitrequest),
    .s_address(s_address), .s_burstcount(s_burstcount), .s_byteenable(s_byteenable),
    .s_writedata(s_writedata), .s_read(s_read), .s_write(s_write),
    .s_waitrequest(s_waitrequest), .s_readdata(s_readdata),
    .s_readdatavalid(s_readdatavalid)
);

// ---- DDR slave. `ddr_dead` models the port never accepting anything --------
localparam [28:0] WINDOW_WORD_BASE = 29'h03FE0000;
reg         ddr_dead = 1'b0;
reg [63:0]  mem [0:2047];
integer     i;
reg         rd_pending = 1'b0;
reg [63:0]  rd_data = 64'h0;
reg  [1:0]  rd_delay = 2'd0;

assign s_waitrequest = ddr_dead;

always @(posedge clk) begin
    if (reset) rd_pending <= 1'b0;
    else if (!ddr_dead) begin
        if (s_write) begin
            for (i = 0; i < 8; i = i + 1)
                if (s_byteenable[i])
                    mem[(s_address - WINDOW_WORD_BASE) & 11'h7FF][i*8 +: 8] <=
                        s_writedata[i*8 +: 8];
        end
        if (s_read) begin
            rd_data    <= mem[(s_address - WINDOW_WORD_BASE) & 11'h7FF];
            rd_pending <= 1'b1;
            rd_delay   <= 2'd2;
        end
        else if (rd_pending) begin
            if (rd_delay != 0) rd_delay <= rd_delay - 2'd1;
            else rd_pending <= 1'b0;
        end
    end
end
assign s_readdata      = rd_data;
assign s_readdatavalid = rd_pending && (rd_delay == 0) && !ddr_dead;

// ---- guest access helpers, with latency measurement ------------------------
integer lat;
reg [7:0] isr_after_tx;
reg [7:0] tsr_after_tx;

task automatic io_out;
    input [5:0] port;
    input [7:0] value;
    begin
        @(negedge clk);
        io_address = port; io_writedata = {24'h0, value}; io_32 = 0; io_write = 1;
        @(negedge clk);
        io_write = 0;
        lat = 0;
        while (io_wait && lat < 100000) begin @(negedge clk); lat = lat + 1; end
        if (lat > worst_latency) worst_latency = lat;
        if (lat >= 100000) begin
            $display("FAIL: OUT to port %02x never retired", port);
            errors = errors + 1;
        end
    end
endtask

task automatic io_in;
    input  [5:0] port;
    output [7:0] value;
    begin
        @(negedge clk);
        io_address = port; io_32 = 0; io_read = 1;
        @(negedge clk);
        io_read = 0;
        lat = 0;
        while (io_wait && lat < 100000) begin @(negedge clk); lat = lat + 1; end
        if (lat > worst_latency) worst_latency = lat;
        if (lat >= 100000) begin
            $display("FAIL: IN from port %02x never retired", port);
            errors = errors + 1;
        end
        value = io_readdata[7:0];
    end
endtask

task automatic io_outw;
    input [5:0] port;
    input [15:0] value;
    begin
        @(negedge clk);
        io_address = port; io_writedata = {16'h0, value}; io_32 = 1; io_write = 1;
        @(negedge clk);
        io_write = 0;
        lat = 0;
        while (io_wait && lat < 100000) begin @(negedge clk); lat = lat + 1; end
        if (lat > worst_latency) worst_latency = lat;
        if (lat >= 100000) begin
            $display("FAIL: OUTW to port %02x never retired", port);
            errors = errors + 1;
        end
    end
endtask

// A full, realistic driver sequence: probe, reset, program the ring, move data.
task automatic guest_sequence;
    input [255:0] label;
    reg [7:0] b;
    begin
        $display("  -- %0s --", label);
        io_in (6'h18, b);                    // reset port
        io_out(6'h07, 8'hFF);                // clear ISR
        io_out(6'h00, 8'h21);                // CR: stop
        io_in (6'h0A, b);
        if (b !== 8'h50) begin
            $display("FAIL: %0s RTL8019 ID0 = %02x", label, b);
            errors = errors + 1;
        end
        io_out(6'h0E, 8'h01);                // DCR word mode
        io_out(6'h01, 8'h46);                // PSTART
        io_out(6'h02, 8'h80);                // PSTOP
        io_out(6'h03, 8'h46);                // BNRY
        io_out(6'h0F, 8'h1F);                // IMR: all
        io_out(6'h0C, 8'h04);                // RCR
        io_out(6'h0D, 8'h00);                // TCR
        io_out(6'h00, 8'h22);                // CR: start

        // remote DMA write into packet RAM, then a transmit trigger
        io_out(6'h0A, 8'h04);
        io_out(6'h0B, 8'h00);
        io_out(6'h08, 8'h00);
        io_out(6'h09, 8'h40);
        io_out(6'h00, 8'h12);
        io_outw(6'h10, 16'hAA55);
        io_outw(6'h10, 16'h1234);

        io_out(6'h04, 8'h40);                // TPSR
        io_out(6'h05, 8'h3C);                // TBCR0
        io_out(6'h06, 8'h00);                // TBCR1
        io_out(6'h00, 8'h26);                // CR: TXP -- needs the host to finish

        // keep hammering registers while the background engine runs, exactly
        // as a driver waiting for transmit completion does
        repeat (200) begin
            io_in(6'h07, b);                 // ISR poll, as a driver would
            io_in(6'h03, b);                 // BNRY
        end
        // BF-7: with no live host a transmit must be reported as a failure,
        // never as success -- TSR.ABT + ISR.TXE, not TSR.PTX.
        io_in(6'h07, b); isr_after_tx = b;
        io_in(6'h04, b); tsr_after_tx = b;
        if (tsr_after_tx[0] || isr_after_tx[1]) begin
            $display("FAIL: transmit claimed success with no host (TSR=%02x ISR=%02x)",
                     tsr_after_tx, isr_after_tx);
            errors = errors + 1;
        end else if (tsr_after_tx[3] && isr_after_tx[3]) begin
            $display("     ok: transmit honestly aborted (TSR=%02x ISR=%02x)",
                     tsr_after_tx, isr_after_tx);
        end else begin
            $display("FAIL: transmit neither completed nor aborted (TSR=%02x ISR=%02x)",
                     tsr_after_tx, isr_after_tx);
            errors = errors + 1;
        end
    end
endtask

reg [7:0] b;

initial begin
    for (i = 0; i < 2048; i = i + 1) mem[i] = 64'h0;

    repeat (8) @(posedge clk);
    @(negedge clk); reset = 1'b0;
    repeat (20) @(posedge clk);

    // ---- A. transport alive, no host software anywhere ---------------------
    guest_sequence("A: DDR works, no host daemon");

    // ---- B. DDR port completely dead ---------------------------------------
    ddr_dead = 1'b1;
    repeat (50) @(posedge clk);
    guest_sequence("B: DDR port dead (waitrequest stuck)");
    ddr_dead = 1'b0;

    $display("");
    $display("worst guest access latency: %0d cycles", worst_latency);
    if (worst_latency > 4000) begin
        $display("FAIL: an access took longer than the watchdog bound");
        errors = errors + 1;
    end

    if (errors == 0) $display("PASS: tb_ne2000_no_host");
    else             $display("FAIL: tb_ne2000_no_host (%0d error(s))", errors);
    $finish;
end

endmodule
