// tb_ne2000_loop_vs_realtraffic.v -- regression for the race found on real
// hardware 2026-08-10: a real DP8390 in loopback mode disconnects the
// receiver from the wire, but ne2000_core's HPS-fed RX-fill poll
// (receiver_active && bg_poll_counter==0) never checked TCR.LB. On a MiSTer
// connected to a live LAN, real broadcast/ARP traffic kept landing in the
// ring concurrently with the TCR.LB=01 loopback copy -- NE2KDIAG's internal
// loopback test read back a genuine ARP request off the wire instead of its
// own loopback frame (the actual captured bytes decoded as a real "who-has
// 192.168.1.1" ARP request). Fixed by gating that trigger on
// tcr_loopback_mode==0.
//
// This bench seeds a real pending frame in the daemon's RX queue (exactly
// like a live LAN would) BEFORE engaging loopback, and checks:
//   1. the loopback readback returns the loopback content, not the queued
//      real frame, while TCR.LB=01;
//   2. normal draining isn't just broken -- the real frame is still there
//      and gets consumed correctly once TCR returns to 0.
//
// Caveat, recorded rather than hidden: this bench does NOT reproduce the
// hardware race itself. bg_polling_rx_flags (the flag that actually gates a
// real-frame drain) only went high once across a 6000-cycle deliberate wait
// with the guard removed, and that one time was AFTER TCR returned to
// normal -- shm_sync_enabled's own dispatch traffic from this bench's ~20
// register writes appears to dominate BG_IDLE's priority chain long enough
// that the counter-driven RX-poll never got a synchronous-sim turn during
// the loopback window. The real race depends on wall-clock timing ratios
// between actual DOS/x86 instruction execution and the FPGA's poll counter
// that a clocked, task-driven testbench doesn't naturally reproduce. What
// this bench DOES verify -- correctly, and worth keeping -- is that the fix
// causes no regression to either loopback correctness or normal drain
// resumption. The authoritative confirmation is NE2KDIAG re-run on real
// hardware, on a live LAN, which is what exposed this in the first place.
//
// Harness (ne2000_isa + mux + mailbox + arbiter + behavioral DDR window) is
// tb_ne2000_loopback_isa.v's; frame injection is tb_ne2000_rx_multipage.v's.

`timescale 1ns / 1ps

module tb_ne2000_loop_vs_realtraffic;

    localparam [15:0] OFF_HB      = 16'h1088;
    localparam [15:0] OFF_SIG     = 16'h108C;
    localparam [15:0] OFF_RX_TAIL = 16'h2C06;
    localparam [15:0] OFF_RX_LEN  = 16'h2C20;
    localparam [15:0] OFF_RX_DATA = 16'h9000;
    localparam [15:0] OFF_FLAGS   = 16'h1000;
    localparam [15:0] FLAG_RX_AVAIL = 16'h0004;

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

    task automatic ddr_write_byte;
        input [15:0] byte_off; input [7:0] val;
        begin win[byte_off] = val; end
    endtask
    task automatic ddr_write_u16;
        input [15:0] byte_off; input [15:0] val;
        begin ddr_write_byte(byte_off, val[7:0]); ddr_write_byte(byte_off + 16'd1, val[15:8]); end
    endtask

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
    localparam integer REAL_LEN = 64;
    reg [7:0] loop_frame [0:LOOP_LEN-1];
    reg [7:0] real_frame [0:REAL_LEN-1];
    integer k, w, mism;
    reg [7:0] curr0, curr1, curr2;
    reg [15:0] got;

    initial begin
        for (i = 0; i < 65536; i = i + 1) win[i] = 8'h00;
        for (k = 0; k < LOOP_LEN; k = k + 1) loop_frame[k] = (k[7:0] + 8'h11) ^ 8'h5A;
        // A plausible-looking real frame, same shape as the ARP request that
        // exposed this on hardware: broadcast dest, some source MAC, then
        // arbitrary payload -- content doesn't matter, only that it's
        // distinguishable from loop_frame.
        real_frame[0]=8'hFF; real_frame[1]=8'hFF; real_frame[2]=8'hFF;
        real_frame[3]=8'hFF; real_frame[4]=8'hFF; real_frame[5]=8'hFF;
        real_frame[6]=8'hA0; real_frame[7]=8'hB5; real_frame[8]=8'h3C;
        real_frame[9]=8'h0A; real_frame[10]=8'h70; real_frame[11]=8'h03;
        for (k = 12; k < REAL_LEN; k = k + 1) real_frame[k] = k[7:0];

        repeat (8) @(posedge clk);
        @(negedge clk); reset = 0;
        repeat (20) @(posedge clk);

        win[16'h108C]=8'hBE; win[16'h108D]=8'hBA; win[16'h108E]=8'hFE; win[16'h108F]=8'hCA;
        win[16'h1088]=8'h01; win[16'h1089]=8'h00;
        repeat (20) @(posedge clk);

        io_in(6'h18, curr0);        // reset port
        io_out(6'h07, 8'hFF);

        // Program the ring and start the receiver -- same as a guest driver
        // would before anything else runs.
        io_out(6'h00, 8'h21);       // CR: stop
        io_out(6'h0C, 8'h04);       // RCR: enable (latches rx_poll_enabled)
        io_out(6'h01, 8'h46);       // PSTART
        io_out(6'h02, 8'h80);       // PSTOP
        io_out(6'h03, 8'h46);       // BNRY
        io_out(6'h0D, 8'h00);       // TCR: normal (not loopback yet)
        io_out(6'h00, 8'h22);       // CR: STA, page0
        repeat (200) @(posedge clk);   // let queue_init_done / early polling settle

        // Seed ONE real frame in the daemon's queue, exactly as a live LAN
        // would -- this is what a router's ARP broadcast looks like from the
        // FPGA's side, sitting there waiting to be drained.
        for (k = 0; k < REAL_LEN; k = k + 1) ddr_write_byte(OFF_RX_DATA + k[15:0], real_frame[k]);
        ddr_write_u16(OFF_RX_LEN, REAL_LEN[15:0]);
        ddr_write_u16(OFF_RX_TAIL, 16'h0001);
        ddr_write_u16(OFF_FLAGS, FLAG_RX_AVAIL);

        // Engage loopback, then snapshot CURR -- the real frame is sitting
        // in the queue RIGHT NOW. The wait stands in for real elapsed DOS/x86
        // time before TXP fires (see the file header for why this alone
        // doesn't reliably reproduce the race in this harness).
        io_out(6'h0D, 8'h02);       // TCR: LB=01
        begin : loop_wait
            integer lw;
            for (lw = 0; lw < 6000 && dut.u_core.curr_register == 8'h47; lw = lw + 1) begin
                @(posedge clk);
            end
        end
        io_out(6'h00, 8'h62); io_in(6'h07, curr0); io_out(6'h00, 8'h22);

        io_out(6'h0E, 8'h01);       // DCR: word mode
        io_out(6'h0A, LOOP_LEN[7:0]); io_out(6'h0B, 8'h00);
        io_out(6'h08, 8'h00); io_out(6'h09, 8'h40);
        io_out(6'h00, 8'h12);
        for (w = 0; w < LOOP_LEN; w = w + 2)
            io_outw(6'h10, {loop_frame[w+1], loop_frame[w]});

        io_out(6'h04, 8'h40);
        io_out(6'h05, LOOP_LEN[7:0]); io_out(6'h06, 8'h00);
        io_out(6'h00, 8'h26);       // CR: STA | TXP

        begin : wp
            integer g;
            for (g = 0; g < 40000; g = g + 1) begin
                @(posedge clk);
                if ((dut.u_core.isr_register & 8'h03) == 8'h03) disable wp;
            end
        end
        if ((dut.u_core.isr_register & 8'h03) != 8'h03) begin
            $display("FAIL: loopback ISR PRX|PTX never both set (isr=0x%02x)", dut.u_core.isr_register);
            errors = errors + 1;
        end

        io_out(6'h00, 8'h62); io_in(6'h07, curr1); io_out(6'h00, 8'h22);
        $display("INFO: CURR 0x%02x -> 0x%02x after loopback frame", curr0, curr1);

        io_out(6'h0E, 8'h01);
        io_out(6'h08, 8'h04); io_out(6'h09, curr0);
        io_out(6'h0A, LOOP_LEN[7:0]); io_out(6'h0B, 8'h00);
        io_out(6'h00, 8'h0A);
        mism = 0;
        for (w = 0; w < LOOP_LEN; w = w + 2) begin
            io_inw(got);
            if (got[7:0] !== loop_frame[w] || got[15:8] !== loop_frame[w+1]) begin
                if (mism < 4)
                    $display("FAIL: byte %0d expected %02x %02x got %02x %02x -- looks like real traffic leaked in",
                             w, loop_frame[w], loop_frame[w+1], got[7:0], got[15:8]);
                mism = mism + 1;
            end
        end
        if (mism == 0) $display("ok:   loopback readback matches the loopback frame, not the queued real one");
        else begin errors = errors + 1; $display("DIAG: %0d/%0d words mismatched", mism, LOOP_LEN/2); end

        // Back to normal mode: the real frame that was sitting in the queue
        // this whole time must now get drained, proving the fix only
        // SUPPRESSES the normal path during loopback, it doesn't break it.
        io_out(6'h0D, 8'h00);       // TCR: normal
        begin : wr
            integer g;
            for (g = 0; g < 40000; g = g + 1) begin
                @(posedge clk);
                io_out(6'h00, 8'h62); io_in(6'h07, curr2); io_out(6'h00, 8'h22);
                if (curr2 !== curr1) disable wr;
            end
        end
        if (curr2 === curr1) begin
            $display("FAIL: real frame never drained after leaving loopback (CURR stuck at 0x%02x)", curr1);
            errors = errors + 1;
        end else begin
            $display("ok:   real frame drained after TCR back to normal (CURR 0x%02x -> 0x%02x)", curr1, curr2);

            io_out(6'h0E, 8'h01);
            io_out(6'h08, 8'h04); io_out(6'h09, curr1);
            io_out(6'h0A, REAL_LEN[7:0]); io_out(6'h0B, 8'h00);
            io_out(6'h00, 8'h0A);
            mism = 0;
            for (w = 0; w < REAL_LEN; w = w + 2) begin
                io_inw(got);
                if (got[7:0] !== real_frame[w] || got[15:8] !== real_frame[w+1]) mism = mism + 1;
            end
            if (mism == 0) $display("ok:   drained frame matches the real one that was queued");
            else begin errors = errors + 1; $display("FAIL: drained frame content wrong, %0d/%0d words mismatched", mism, REAL_LEN/2); end
        end

        if (errors == 0) $display("PASS: tb_ne2000_loop_vs_realtraffic");
        else             $display("FAIL: tb_ne2000_loop_vs_realtraffic (%0d error(s))", errors);
        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: global timeout"); errors = errors + 1; $finish;
    end

endmodule
