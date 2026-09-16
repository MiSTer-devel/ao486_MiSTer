// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_rx_batch_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_dataport_contention_tb.v
//
// Reproduces the X-Surf "Testing 16bit memory" HARDWARE failure (xsurftest4 /
// longread / longwrite, all on the current 16:14 RBF): the data-port memory
// test reads back 0xFF (open bus) and the write reports "PIOWriteMem Timeout".
//
// Root cause under test: the CPU data-port cycle and the background FSM's RX
// ring writes contend for the SINGLE-PORT packet RAM. The data-port launch is
// gated on !bg_pmem_active (ethernet.v:1052) and the deferred pmem read re-arms
// whenever bg_pmem_active (ethernet.v:1699). The bg holds bg_pmem_active for the
// ENTIRE mailbox round-trip of every 8-byte chunk it writes (it only leaves
// BG_WRITE_PAYLOAD_WIDE on eth_dma_ready, ethernet.v:1736), so while a frame is
// being delivered the CPU data-port cycle is starved. If that starvation lasts
// past DATA_PORT_TIMEOUT_CYCLES (511) the cycle times out -> a READ latches
// 0xFFFF (ethernet.v:1413-1415) and a WRITE never sets ISR.RDC.
//
// This is exactly the real condition the open-time memtest hits on a live
// network (broadcast frames being delivered by the bg) and, more importantly,
// the condition a DOWNLOAD hits continuously (the bg streaming RX frames into
// the ring while the driver PIO-reads it).
//
// The f2sdram slave here is deliberately SLOW (mailbox/DDR latency on real
// silicon is tens of clk_sys cycles, not the ~5 my fast model used), which is
// why the earlier fast-slave TBs passed and masked the bug. No fake logic: real
// ethernet_interface + real ne2000_ddr_mailbox, frames injected exactly like the
// HPS daemon, data port driven over the real CPU bus.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

// ===========================================================================
// eth_rx_batch_tb.v
//
// Validates the back-to-back RX queue drain: inject N frames into N consecutive
// shm RX-queue slots AT ONCE (tail jumps to N), then check that (1) the bg
// delivers all N byte-exact into consecutive ring pages, and (2) it drains them
// WITHOUT re-polling FLAGS/HEAD/TAIL per frame (the batch loop in
// BG_WRITE_RX_HEAD_WAIT), i.e. BG_READ_RX_HEAD_REQ is entered exactly once for
// the whole batch instead of once per frame.
// ===========================================================================
module eth_rx_batch_tb;

    // ---- shm offsets (match ethernet.v parameters) ----
    localparam [15:0] OFF_FLAGS      = 16'h1000;
    localparam [15:0] OFF_HB         = 16'h1088;
    localparam [15:0] OFF_SIG        = 16'h108C;
    localparam [15:0] OFF_RX_HEAD    = 16'h2C04;
    localparam [15:0] OFF_RX_TAIL    = 16'h2C06;
    localparam [15:0] OFF_RX_LEN     = 16'h2C20;   // + slot*2
    localparam [15:0] OFF_RX_DATA    = 16'h9000;   // + slot*1536
    localparam [15:0] FLAG_RX_AVAIL  = 16'h0004;

    // ---- clocks ----
    reg clk_sys = 0;
    reg clk_avl = 0;
    always #17 clk_sys = ~clk_sys;   // ~29.4 MHz
    always #21 clk_avl = ~clk_avl;   // ~23.8 MHz (async)

    reg reset_sys = 1;
    reg reset_avl = 1;

    // ---- CPU bus ----
    reg  [15:1] cpu_addr     = 0;
    reg  [15:0] cpu_data_in  = 0;
    wire [15:0] cpu_data_out;
    reg         cpu_rd       = 0;
    reg         cpu_hwr      = 0;
    reg         cpu_lwr      = 0;
    reg         cpu_as       = 1;
    reg         cpu_uds      = 1;
    reg         cpu_lds      = 1;
    reg         sel_ethernet_shm = 0;
    reg         sel_ethernet     = 0;

    // ---- eth_dma between ethernet_interface and mailbox ----
    wire        eth_dma_ready;
    wire [15:0] eth_dma_rdata;
    wire [63:0] eth_dma_rdata64;
    wire        eth_dma_wide;
    wire [63:0] eth_dma_wdata64;
    wire        eth_dma_req;
    wire        eth_dma_write;
    wire [15:1] eth_dma_addr;
    wire [15:0] eth_dma_wdata;
    wire        eth_dma_uds;
    wire        eth_dma_lds;
    wire        eth_irq;
    wire        dtack_eth;

    // ---- mailbox Avalon master -> slave ----
    wire [28:0] avl_address;
    wire [ 7:0] avl_burstcount;
    wire [ 7:0] avl_byteenable;
    wire [63:0] avl_writedata;
    wire        avl_read;
    wire        avl_write;
    wire        avl_waitrequest;
    wire [63:0] avl_readdata;
    wire        avl_readdatavalid;

    integer errors = 0;

    ne2000_core dut (
        .clk(clk_sys), .reset(reset_sys),
        .host_addr(cpu_addr), .host_wdata(cpu_data_in), .host_rdata(cpu_data_out),
        .host_rd(cpu_rd), .host_wr_hi(cpu_hwr), .host_wr_lo(cpu_lwr),
        .host_cyc_n(cpu_as), .host_be_hi_n(cpu_uds), .host_be_lo_n(cpu_lds),
        .host_sel_priv(sel_ethernet_shm), .host_sel(sel_ethernet),
        .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
        .eth_dma_rdata64(eth_dma_rdata64),
        .eth_dma_wide(eth_dma_wide),
        .eth_dma_wdata64(eth_dma_wdata64),
        .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
        .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
        .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
        .irq(eth_irq), .host_ack_n(dtack_eth)
    );

    ne2000_ddr_mailbox mailbox (
        .clk_sys(clk_sys), .reset_sys(reset_sys),
        .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
        .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
        .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
        .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
        .eth_dma_rdata64(eth_dma_rdata64),
        .eth_dma_wide(eth_dma_wide),
        .eth_dma_wdata64(eth_dma_wdata64),
        .clk_avl(clk_avl), .reset_avl(reset_avl),
        .avl_address(avl_address), .avl_burstcount(avl_burstcount),
        .avl_byteenable(avl_byteenable), .avl_writedata(avl_writedata),
        .avl_read(avl_read), .avl_write(avl_write),
        .avl_waitrequest(avl_waitrequest), .avl_readdata(avl_readdata),
        .avl_readdatavalid(avl_readdatavalid),
        .dbg()
    );

    // ---- behavioral 64-bit f2sdram slave: SLOW, to mimic real DDR/mailbox
    //      latency (tens of clk_sys cycles per access, not ~5). ----
    localparam ACCEPT_DELAY = 8;
    localparam READ_LAT     = 24;
    reg [63:0] mem [0:16383];
    localparam SS_IDLE = 2'd0, SS_LAT = 2'd1, SS_EMIT = 2'd2;
    reg [1:0]  ss_state = SS_IDLE;
    reg [5:0]  acc_cnt  = 0;
    reg [5:0]  lat_cnt  = 0;
    reg [8:0]  beats    = 0;
    reg [13:0] r_index  = 0;
    reg        is_busy  = 0;
    wire cmd_present = avl_read | avl_write;
    assign avl_waitrequest = is_busy ? 1'b1 : (cmd_present ? (acc_cnt < ACCEPT_DELAY) : 1'b0);
    wire cmd_accept = cmd_present & ~avl_waitrequest;
    reg        rdv = 0;
    reg [63:0] rdo = 0;
    assign avl_readdatavalid = rdv;
    assign avl_readdata      = rdo;
    integer i;
    initial for (i = 0; i < 16384; i = i + 1) mem[i] = 64'd0;

    always @(posedge clk_avl) begin
        if (reset_avl) begin
            ss_state <= SS_IDLE; acc_cnt <= 0; lat_cnt <= 0; beats <= 0;
            is_busy <= 0; rdv <= 0; rdo <= 0;
        end else begin
            rdv <= 0;
            if (cmd_present && avl_waitrequest && !is_busy) acc_cnt <= acc_cnt + 1'b1;
            else if (!cmd_present) acc_cnt <= 0;
            if (cmd_accept) begin
                acc_cnt <= 0;
                if (avl_write) begin
                    if (avl_byteenable[0]) mem[avl_address[13:0]][ 7: 0] <= avl_writedata[ 7: 0];
                    if (avl_byteenable[1]) mem[avl_address[13:0]][15: 8] <= avl_writedata[15: 8];
                    if (avl_byteenable[2]) mem[avl_address[13:0]][23:16] <= avl_writedata[23:16];
                    if (avl_byteenable[3]) mem[avl_address[13:0]][31:24] <= avl_writedata[31:24];
                    if (avl_byteenable[4]) mem[avl_address[13:0]][39:32] <= avl_writedata[39:32];
                    if (avl_byteenable[5]) mem[avl_address[13:0]][47:40] <= avl_writedata[47:40];
                    if (avl_byteenable[6]) mem[avl_address[13:0]][55:48] <= avl_writedata[55:48];
                    if (avl_byteenable[7]) mem[avl_address[13:0]][63:56] <= avl_writedata[63:56];
                end else begin
                    r_index <= avl_address[13:0]; beats <= {1'b0, avl_burstcount};
                    lat_cnt <= READ_LAT; is_busy <= 1'b1; ss_state <= SS_LAT;
                end
            end
            case (ss_state)
                SS_LAT:  if (lat_cnt == 0) ss_state <= SS_EMIT; else lat_cnt <= lat_cnt - 1'b1;
                SS_EMIT: begin
                    rdv <= 1'b1; rdo <= mem[r_index]; r_index <= r_index + 1'b1; beats <= beats - 1'b1;
                    if (beats == 1) begin is_busy <= 1'b0; ss_state <= SS_IDLE; end
                end
                default: ;
            endcase
        end
    end

    // ----- CPU bus helpers -----
    task automatic write_high_reg;
        input [14:0] word_offset;
        input [7:0]  value;
        begin
            @(negedge clk_sys);
            cpu_addr = word_offset; cpu_data_in = {value, 8'h00};
            sel_ethernet = 1'b1; cpu_hwr = 1'b1; cpu_lwr = 1'b0;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b1;
            @(posedge clk_sys);
            @(negedge clk_sys);
            cpu_hwr = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1;
            sel_ethernet = 1'b0; cpu_data_in = 16'h0000;
        end
    endtask

    // Word write to the X-Surf data port at reg 0x10 (0xEA0C40, cpu_addr 0x620 -
    // the exact port xsurftest uses). Bounded DTACK wait, like the 68k.
    task automatic data_port_write_word;
        input [15:0] value;
        output       timed_out;
        integer w;
        reg done;
        begin
            done = 1'b0; timed_out = 1'b0;
            @(negedge clk_sys);
            cpu_addr = 15'h0620; cpu_data_in = value;
            sel_ethernet = 1'b1; cpu_hwr = 1'b1; cpu_lwr = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 1200 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) done = 1'b1;
            end
            @(negedge clk_sys);
            cpu_hwr = 1'b0; cpu_lwr = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1;
            sel_ethernet = 1'b0; cpu_data_in = 16'h0000;
            if (!done) timed_out = 1'b1;
            @(negedge clk_sys);
        end
    endtask

    task automatic data_port_read_word;
        output [15:0] value;
        output        timed_out;
        integer w;
        reg done;
        begin
            done = 1'b0; value = 16'hXXXX; timed_out = 1'b0;
            @(negedge clk_sys);
            cpu_addr = 15'h0620; sel_ethernet = 1'b1; cpu_rd = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 1200 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) begin value = cpu_data_out; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) timed_out = 1'b1;
            @(negedge clk_sys);
        end
    endtask

    // ----- DDR (shm) write helpers (byte-addressed into the 64-bit slave) -----
    task automatic ddr_write_byte;
        input [15:0] byte_off; input [7:0] val;
        integer widx; integer bsh;
        begin widx = byte_off >> 3; bsh = (byte_off & 7) * 8; mem[widx][bsh +: 8] = val; end
    endtask
    task automatic ddr_write_u16;
        input [15:0] byte_off; input [15:0] val;
        begin ddr_write_byte(byte_off, val[7:0]); ddr_write_byte(byte_off + 16'd1, val[15:8]); end
    endtask

    // ----- frame injection (daemon order) into a queue slot -----
    localparam integer NFRAMES = 8;
    localparam integer FLEN    = 64;       // 64B payload -> 1 ring page each
    integer fi, bj;

    task automatic inject_frame;
        input integer slot;
        input integer flen;
        integer b;
        reg [15:0] data_base;
        begin
            data_base = OFF_RX_DATA + slot*16'd1536;
            // Per-frame marker in the first two payload bytes so each delivered
            // frame is identifiable in the ring; rest is a recognizable ramp.
            for (b = 0; b < flen; b = b + 1)
                ddr_write_byte(data_base + b[15:0],
                               (b == 0) ? (8'hA0 + slot[7:0]) :
                               (b == 1) ? (8'hC0 + slot[7:0]) :
                               (8'h40 + b[5:0]));
            ddr_write_u16(OFF_RX_LEN + slot*16'd2, flen[15:0]);
        end
    endtask

    // ---- monitor: count entries into BG_READ_RX_HEAD_REQ (the per-poll HEAD
    //      re-read).  Back-to-back drain => entered ONCE for the whole batch;
    //      one-frame-per-poll => entered NFRAMES times.
    localparam [5:0] S_READ_RX_HEAD_REQ = 6'd42;
    integer  head_reads = 0;
    reg [5:0] prev_bg_state = 6'h3F;
    reg       monitor_en = 1'b0;
    always @(posedge clk_sys) begin
        if (monitor_en && dut.bg_state == S_READ_RX_HEAD_REQ &&
            prev_bg_state != S_READ_RX_HEAD_REQ)
            head_reads = head_reads + 1;
        prev_bg_state <= dut.bg_state;
    end

    integer wb; reg [7:0] u_byte, l_byte; reg [7:0] exp0, exp1;

    initial begin
        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys);
        @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        ddr_write_u16(OFF_SIG,         16'hBABE);
        ddr_write_u16(OFF_SIG + 16'd2, 16'hCAFE);
        ddr_write_u16(OFF_HB,          16'h0001);
        repeat (400) @(posedge clk_sys);

        // ---- enable the NE2000 receiver (proven sequence) ----
        write_high_reg(15'h0602, 8'h46);   // PSTART = 0x46
        write_high_reg(15'h0604, 8'h80);   // PSTOP  = 0x80
        write_high_reg(15'h0606, 8'h46);   // BNRY   = PSTART
        write_high_reg(15'h061C, 8'h4B);   // DCR    = word mode
        write_high_reg(15'h0618, 8'h0C);   // RCR    = bcast+mcast -> arms rx_poll
        write_high_reg(15'h0600, 8'h62);   // CR page1
        write_high_reg(15'h060E, 8'h47);   // CURR = PSTART+1 = 0x47
        write_high_reg(15'h0600, 8'h22);   // CR page0 + STA
        write_high_reg(15'h061E, 8'h0F);   // IMR

        // ---- queue ALL NFRAMES at once into slots 0..N-1, then advance tail in
        //      one step and raise RX_AVAIL: this is the batch the drain must
        //      handle back-to-back. ----
        for (fi = 0; fi < NFRAMES; fi = fi + 1) inject_frame(fi, FLEN);
        monitor_en = 1'b1;
        ddr_write_u16(OFF_RX_TAIL, NFRAMES[15:0]);
        ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);

        // ---- wait until the bg has consumed all NFRAMES (head reaches N) ----
        begin : wait_drain
            integer g;
            for (g = 0; g < 600000; g = g + 1) begin
                @(posedge clk_sys);
                if (dut.bg_rx_queue_head == NFRAMES[15:0]) disable wait_drain;
            end
        end
        monitor_en = 1'b0;
        @(posedge clk_sys);

        $display("DRAIN done: rx_head=%0d rx_tail=%0d CURR=0x%02x BNRY=0x%02x  head_reads=%0d",
                 dut.bg_rx_queue_head, dut.bg_rx_queue_tail, dut.curr_register, dut.bnry_register, head_reads);

        if (dut.bg_rx_queue_head !== NFRAMES[15:0]) begin
            $display("FAIL: bg drained only head=%0d of %0d frames", dut.bg_rx_queue_head, NFRAMES);
            errors = errors + 1;
        end

        // ---- verify each frame landed in its consecutive ring page (0x47+fi),
        //      payload word 0 = {marker0, marker1}.  packet-RAM word index of a
        //      page's payload = (page-0x40)*128 + 2; page = 0x47 + fi (1 page/frame).
        for (fi = 0; fi < NFRAMES; fi = fi + 1) begin
            wb = (7 + fi) * 128 + 2;
            u_byte = dut.packet_ram_inst.mem_u[wb];
            l_byte = dut.packet_ram_inst.mem_l[wb];
            exp0 = 8'hA0 + fi[7:0];
            exp1 = 8'hC0 + fi[7:0];
            // accept either lane order; what matters is frame fi's markers are at page 0x47+fi
            if (!((u_byte === exp0 && l_byte === exp1) ||
                  (u_byte === exp1 && l_byte === exp0))) begin
                $display("FAIL: frame %0d ring payload @word 0x%04x = u=0x%02x l=0x%02x, expected markers 0x%02x/0x%02x",
                         fi, wb[15:0], u_byte, l_byte, exp0, exp1);
                errors = errors + 1;
            end
        end

        // ---- integrity-probe assertions: the bg's published frame count and
        //      running byte-sum (slots 41/40) must match exactly the frames we
        //      injected -- FLEN payload bytes each, summed mod 65536. This is the
        //      basis of the HW FPGA-vs-Amiga verdict, so it must be byte-exact
        //      (no phantom tail byte on even-length frames, etc.).

        // ---- back-to-back assertion: HEAD/TAIL read exactly once for the batch ----
        if (head_reads != 1) begin
            $display("FAIL: BG_READ_RX_HEAD_REQ entered %0d times for %0d frames -> NOT draining back-to-back (per-frame re-poll)",
                     head_reads, NFRAMES);
            errors = errors + 1;
        end else begin
            $display("INFO: back-to-back drain confirmed -- HEAD/TAIL polled once for all %0d frames", NFRAMES);
        end

        if (errors == 0)
            $display("PASS: eth_rx_batch_tb (%0d frames drained back-to-back, all byte-exact in consecutive ring pages, head_reads=1)", NFRAMES);
        else
            $display("FAILED: eth_rx_batch_tb with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #30000000;
        $display("FAIL: eth_rx_batch_tb global timeout");
        $finish;
    end

endmodule
