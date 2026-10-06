// tb_ne2000_dma_mux.v -- Phase 4: the core and the probe share one transport.
//
// The failure this guards against is a completion delivered to the wrong
// master: eth_dma_ready is a single pulse, so if the loser sees it, it retires
// a transfer it never issued and reads someone else's data.

`timescale 1ns / 1ps

module tb_ne2000_dma_mux;

reg clk = 1'b0;
reg reset = 1'b1;
always #5 clk = ~clk;

integer errors = 0;

reg        m0_req = 0, m0_write = 0;
reg [15:1] m0_addr = 0;
reg [15:0] m0_wdata = 0;
wire       m0_ready;
wire [15:0] m0_rdata;

reg        m1_req = 0, m1_write = 0;
reg [15:1] m1_addr = 0;
reg [15:0] m1_wdata = 0;
wire       m1_ready;
wire [15:0] m1_rdata;

wire        d_req, d_write, d_wide, d_uds, d_lds;
wire [15:1] d_addr;
wire [15:0] d_wdata;
wire [63:0] d_wdata64;
reg         d_ready = 0;
reg  [15:0] d_rdata = 0;

ne2000_dma_mux dut
(
    .clk(clk), .reset(reset),
    .m0_req(m0_req), .m0_write(m0_write), .m0_addr(m0_addr), .m0_wdata(m0_wdata),
    .m0_wide(1'b0), .m0_wdata64(64'h0), .m0_uds(1'b0), .m0_lds(1'b0),
    .m0_ready(m0_ready), .m0_rdata(m0_rdata), .m0_rdata64(),
    .m1_req(m1_req), .m1_write(m1_write), .m1_addr(m1_addr), .m1_wdata(m1_wdata),
    .m1_wide(1'b0), .m1_wdata64(64'h0), .m1_uds(1'b0), .m1_lds(1'b0),
    .m1_ready(m1_ready), .m1_rdata(m1_rdata), .m1_rdata64(),
    .eth_dma_req(d_req), .eth_dma_write(d_write), .eth_dma_addr(d_addr),
    .eth_dma_wdata(d_wdata), .eth_dma_wide(d_wide), .eth_dma_wdata64(d_wdata64),
    .eth_dma_uds(d_uds), .eth_dma_lds(d_lds),
    .eth_dma_ready(d_ready), .eth_dma_rdata(d_rdata), .eth_dma_rdata64(64'h0)
);

// Mailbox stand-in: 3 cycles of work, then a single-cycle ready pulse.
reg [2:0] lat = 0;
always @(posedge clk) begin
    d_ready <= 1'b0;
    if (reset) lat <= 0;
    else if (d_req && !d_ready) begin
        if (lat == 3) begin
            d_ready <= 1'b1;
            d_rdata <= {8'hA0, d_addr[8:1]};   // echo something address-derived
            lat     <= 0;
        end else lat <= lat + 1'b1;
    end
end

task automatic check;
    input [31:0] got, expected;
    input [511:0] label;
    begin
        if (got !== expected) begin
            $display("FAIL: %0s expected 0x%0x got 0x%0x", label, expected, got);
            errors = errors + 1;
        end else $display("ok:   %0s", label);
    end
endtask

integer m0_completions = 0;
integer m1_completions = 0;
integer guard;
reg     saw_m1_during_m0;

// Sample completions once per cycle, after the clock edge has settled, so the
// count can never race the checks that read it.
always @(posedge clk) begin
    #1;
    if (!reset) begin
        if (m0_ready) m0_completions = m0_completions + 1;
        if (m1_ready) m1_completions = m1_completions + 1;
    end
end

// Drive one transfer for a master and wait for its own completion.
task automatic run_m0;
    begin
        @(negedge clk); m0_req = 1;
        guard = 0;
        while (!m0_ready && guard < 60) begin @(posedge clk); #2; guard = guard + 1; end
        @(negedge clk); m0_req = 0;
        @(negedge clk);
    end
endtask

task automatic run_m1;
    begin
        @(negedge clk); m1_req = 1;
        guard = 0;
        while (!m1_ready && guard < 60) begin @(posedge clk); #2; guard = guard + 1; end
        @(negedge clk); m1_req = 0;
        @(negedge clk);
    end
endtask

initial begin
    repeat (4) @(posedge clk);
    @(negedge clk); reset = 1'b0;
    repeat (4) @(posedge clk);

    // ---- 1. each master alone completes, and only it -----------------------
    m0_addr = 15'h0100;
    run_m0();
    check(m0_completions, 1, "core transfer completed");
    check(m1_completions, 0, "probe saw no completion of the core's transfer");

    m1_addr = 15'h0200;
    run_m1();
    check(m1_completions, 1, "probe transfer completed");
    check(m0_completions, 1, "core saw no completion of the probe's transfer");

    // ---- 2. contention: the core wins, the probe still gets served ---------
    saw_m1_during_m0 = 1'b0;
    fork
        begin : core_traffic
            m0_addr = 15'h0300;
            run_m0();
        end
        begin : probe_traffic
            m1_addr = 15'h0400;
            @(negedge clk); m1_req = 1;
            guard = 0;
            while (!m1_ready && guard < 200) begin
                @(posedge clk); #2;
                if (dut.busy && dut.owner == 1'b0 && m1_ready) saw_m1_during_m0 = 1'b1;
                guard = guard + 1;
            end
            @(negedge clk); m1_req = 0;
        end
    join
    check(m0_completions, 2, "core completed under contention");
    check(m1_completions, 2, "probe eventually completed too");
    check(saw_m1_during_m0, 1'b0, "probe never got a completion while the core owned the bus");

    // ---- 3. an in-flight probe transfer is not pre-empted ------------------
    @(negedge clk); m1_addr = 15'h0500; m1_req = 1;
    repeat (2) @(posedge clk);            // probe takes the grant
    @(negedge clk); m0_req = 1;           // core arrives late
    guard = 0;
    while (!m1_ready && guard < 60) begin @(posedge clk); #2; guard = guard + 1; end
    check(m1_completions, 3, "probe kept its grant to completion");
    check(m0_completions, 2, "core did not steal the in-flight transfer");
    @(negedge clk); m1_req = 0;
    guard = 0;
    while (!m0_ready && guard < 60) begin @(posedge clk); #2; guard = guard + 1; end
    check(m0_completions, 3, "core served straight after the probe finished");
    @(negedge clk); m0_req = 0;

    if (errors == 0) $display("PASS: tb_ne2000_dma_mux");
    else             $display("FAIL: tb_ne2000_dma_mux (%0d error(s))", errors);
    $finish;
end

endmodule
