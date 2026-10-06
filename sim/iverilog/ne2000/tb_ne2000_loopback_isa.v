// tb_ne2000_loopback_isa.v -- TCR.LB=01 internal loopback through the REAL
// bus stack (ne2000_isa + ne2000_dma_mux + ne2000_ddr_mailbox +
// ne2000_ddram_arbiter + a behavioral DDR window), not the bare ne2000_core
// harness tb_ne2000_loopback.v uses.
//
// Why this exists: tb_ne2000_loopback.v proved the RTL's data path byte-exact
// against ne2000_core directly and passed clean, but on real hardware
// NE2KDIAG's internal-loopback test failed differently across two runs (a
// payload mismatch once, a timeout once) -- a race/hazard signature the bare
// harness's idealized fixed-latency host cycles can't reproduce, since it
// bypasses ne2000_isa/iobus and the mailbox/arbiter entirely. This harness is
// the same shape as tb_ne2000_tx_ring.v (the one bench that already proven-
// exercises the full stack), adapted to drive the loopback path instead.

`timescale 1ns / 1ps

module tb_ne2000_loopback_isa;

    localparam [15:0] OFF_HB   = 16'h1088;
    localparam [15:0] OFF_SIG  = 16'h108C;

    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    integer errors = 0;

    reg  [5:0]  io_address = 0;
    reg         io_read = 0, io_write = 0;
    reg  [31:0] io_writedata = 0;
    reg         io_32 = 0;
    wire [31:0] io_readdata;
    wire        io_wait, irq;

    wire        c_req, c_write, c_wide, c_uds, c_lds;
    wire [15:1] c_addr;  wire [15:0] c_wdata;  wire [63:0] c_wdata64;
    wire        c_ready; wire [15:0] c_rdata;  wire [63:0] c_rdata64;

    ne2000_isa dut (
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
    wire [15:1] d_addr;  wire [15:0] d_wdata;  wire [63:0] d_wdata64;
    wire        d_ready; wire [15:0] d_rdata;  wire [63:0] d_rdata64;

    ne2000_dma_mux mux (
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

    wire [28:0] m1_address; wire [7:0] m1_burstcount, m1_byteenable;
    wire [63:0] m1_writedata; wire m1_read, m1_write, m1_waitrequest;
    wire [63:0] m1_readdata; wire m1_readdatavalid;

    ne2000_ddr_mailbox mbx (
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

    wire [28:0] s_address; wire [7:0] s_burstcount, s_byteenable;
    wire [63:0] s_writedata; wire s_read, s_write;
    wire [63:0] s_readdata; wire s_readdatavalid;

    ne2000_ddram_arbiter arb (
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
        .s_waitrequest(1'b0), .s_readdata(s_readdata),
        .s_readdatavalid(s_readdatavalid)
    );

    localparam [28:0] WINDOW_WORD_BASE = 29'h03FE0000;
    reg [7:0] win [0:65535];
    integer i;
    reg rd_pending = 0; reg [63:0] rd_data = 0;
    always @(posedge clk) begin
        rd_pending <= 1'b0;
        if (s_write) for (i = 0; i < 8; i = i + 1)
            if (s_byteenable[i]) win[((s_address - WINDOW_WORD_BASE) << 3) + i] <= s_writedata[i*8 +: 8];
        if (s_read) begin
            for (i = 0; i < 8; i = i + 1)
                rd_data[i*8 +: 8] <= win[((s_address - WINDOW_WORD_BASE) << 3) + i];
            rd_pending <= 1'b1;
        end
    end
    assign s_readdata = rd_data;
    assign s_readdatavalid = rd_pending;

    integer lat;
    task automatic io_out; input [5:0] port; input [7:0] value; begin
        @(negedge clk); io_address = port; io_writedata = {24'h0, value}; io_32 = 0; io_write = 1;
        @(negedge clk); io_write = 0;
        lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
    end endtask
    task automatic io_in; input [5:0] port; output [7:0] value; begin
        @(negedge clk); io_address = port; io_32 = 0; io_read = 1;
        @(negedge clk); io_read = 0;
        lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
        value = io_readdata[7:0];
    end endtask
    task automatic io_outw; input [5:0] port; input [15:0] value; begin
        @(negedge clk); io_address = port; io_writedata = {16'h0, value}; io_32 = 1; io_write = 1;
        @(negedge clk); io_write = 0;
        lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
    end endtask
    task automatic io_inw; output [15:0] value; begin
        @(negedge clk); io_address = 6'h10; io_32 = 1; io_read = 1;
        @(negedge clk); io_read = 0;
        lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
        value = io_readdata[15:0];
    end endtask

    localparam integer LOOP_LEN = 32;
    reg [7:0] frame [0:LOOP_LEN-1];
    reg [7:0] got_buf [0:LOOP_LEN-1];
    integer k, w, mism, iter;
    reg [7:0] curr_before, curr_after, isr_v, tsr_v;
    reg [15:0] got, hdr0, hdr1;

    // Same shape as NE2KDIAG.ASM's test_loop, one iteration, driven the same
    // way a real x86 CPU would: io_out/io_outw through the actual ISA glue.
    task automatic loopback_frame; input [7:0] seed; begin
        for (k = 0; k < LOOP_LEN; k = k + 1) frame[k] = (k[7:0] + seed) ^ 8'h5A;

        io_out(6'h00, 8'h21);        // CR: stop
        io_out(6'h0C, 8'h04);        // RCR: enable (latches rx_poll_enabled)
        io_out(6'h01, 8'h46);        // PSTART
        io_out(6'h02, 8'h80);        // PSTOP
        io_out(6'h03, 8'h46);        // BNRY
        io_out(6'h0D, 8'h02);        // TCR: LB=01
        io_out(6'h07, 8'hFF);        // clear ISR
        io_out(6'h00, 8'h22);        // CR: STA, page0

        io_out(6'h00, 8'h62);        // CR: page1
        io_in(6'h07, curr_before);   // CURR
        io_out(6'h00, 8'h22);        // CR: page0, STA

        io_out(6'h0E, 8'h01);            // DCR: word mode (arm_dma sets this
                                          // on every call in NE2KDIAG.ASM;
                                          // this harness must too)
        io_out(6'h0A, LOOP_LEN[7:0]);   // RBCR0
        io_out(6'h0B, 8'h00);            // RBCR1
        io_out(6'h08, 8'h00);             // RSAR0
        io_out(6'h09, 8'h40);              // RSAR1 -> 0x4000
        io_out(6'h00, 8'h12);               // CR: remote write
        for (w = 0; w < LOOP_LEN; w = w + 2)
            io_outw(6'h10, {frame[w+1], frame[w]});

        io_out(6'h04, 8'h40);           // TPSR
        io_out(6'h05, LOOP_LEN[7:0]);    // TBCR0
        io_out(6'h06, 8'h00);             // TBCR1
        io_out(6'h00, 8'h26);              // CR: STA | TXP

        begin : wp
            integer g;
            for (g = 0; g < 40000; g = g + 1) begin
                @(posedge clk);
                if ((dut.u_core.isr_register & 8'h03) == 8'h03) disable wp;
            end
        end
        if ((dut.u_core.isr_register & 8'h03) != 8'h03) begin
            $display("FAIL: seed=0x%02x ISR PRX|PTX never both set (isr=0x%02x bg_state=%0d)",
                     seed, dut.u_core.isr_register, dut.u_core.bg_state);
            errors = errors + 1;
        end else begin
            $display("ok:   seed=0x%02x ISR PRX|PTX set (isr=0x%02x) after wait", seed, dut.u_core.isr_register);
        end

        io_out(6'h0E, 8'h01);             // DCR: word mode
        io_out(6'h08, 8'h04);              // RSAR0
        io_out(6'h09, curr_before);         // RSAR1
        io_out(6'h0A, LOOP_LEN[7:0]);        // RBCR0
        io_out(6'h0B, 8'h00);                 // RBCR1
        io_out(6'h00, 8'h0A);                  // CR: remote read
        mism = 0;
        for (w = 0; w < LOOP_LEN; w = w + 2) begin
            io_inw(got);
            got_buf[w] = got[7:0]; got_buf[w+1] = got[15:8];
            if (got[7:0] !== frame[w] || got[15:8] !== frame[w+1]) begin
                if (mism < 8)
                    $display("FAIL: seed=0x%02x byte %0d: expected %02x %02x, got %02x %02x",
                             seed, w, frame[w], frame[w+1], got[7:0], got[15:8]);
                mism = mism + 1;
            end
        end
        if (mism == 0)
            $display("ok:   seed=0x%02x all %0d payload bytes read back correctly (CURR 0x%02x)",
                      seed, LOOP_LEN, curr_before);
        else begin
            errors = errors + 1;
            $display("DIAG: seed=0x%02x %0d/%0d words mismatched", seed, mism, LOOP_LEN/2);
        end

        io_out(6'h0D, 8'h00);            // TCR: normal
    end endtask

    initial begin
        for (i = 0; i < 65536; i = i + 1) win[i] = 8'h00;
        repeat (8) @(posedge clk);
        @(negedge clk); reset = 0;
        repeat (20) @(posedge clk);

        // live host, same as tb_ne2000_tx_ring.v -- lets the bg's init
        // sequence (BG_INIT_HEAD/BG_INIT_MAC) complete against a real
        // mailbox instead of a permanently-ready stub.
        win[16'h108C]=8'hBE; win[16'h108D]=8'hBA; win[16'h108E]=8'hFE; win[16'h108F]=8'hCA;
        win[16'h1088]=8'h01; win[16'h1089]=8'h00;
        repeat (20) @(posedge clk);

        io_in(6'h18, isr_v);        // reset port
        io_out(6'h07, 8'hFF);

        // Run several back-to-back iterations, like NE2KDIAG's LOOP_COUNT,
        // through the real bus stack -- if the flakiness NE2KDIAG hit on
        // hardware is a race this harness's realistic timing can excite, it
        // should show up somewhere in this run, likely not always on the
        // very first one.
        for (iter = 0; iter < 20; iter = iter + 1) loopback_frame(iter[7:0]);

        if (errors == 0) $display("PASS: tb_ne2000_loopback_isa");
        else             $display("FAIL: tb_ne2000_loopback_isa (%0d error(s))", errors);
        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: global timeout"); errors = errors + 1; $finish;
    end

endmodule
