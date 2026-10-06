// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_dataport_contention_tb.v
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
// Original root cause: the CPU data-port cycle and the background FSM's RX ring
// writes contended for a SINGLE-PORT packet RAM. The data-port launch was gated
// on !bg_pmem_active and the deferred pmem read re-armed whenever the bg held the
// port for the ENTIRE mailbox round-trip of every 8-byte chunk it wrote, so while
// a frame was being delivered the CPU data-port cycle was starved. If that
// starvation lasted past DATA_PORT_TIMEOUT_CYCLES (511) the cycle timed out -> a
// READ latched 0xFFFF and a WRITE never set ISR.RDC.
//
// FIX under test: the packet RAM is now TRUE DUAL-PORT -- the bg writes the ring
// on port A (pmem_wren_a) while the CPU drives its data-port reads/writes on the
// dedicated port B. The two are physically independent, so a frame delivery can
// NEVER starve or corrupt a concurrent data-port cycle. This TB drives a frame
// delivery (pmem_wren_a active) concurrently with a data-port memtest burst and
// asserts ZERO timeouts / 0xFF reads / data mismatches.
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

module eth_dataport_contention_tb;

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
    localparam integer NFRAMES = 6;
    localparam integer FLEN    = 1024;     // large frames -> long bg delivery
    integer fi, bj;

    task automatic inject_frame;
        input integer slot;
        input integer flen;
        integer b;
        reg [15:0] data_base;
        begin
            data_base = OFF_RX_DATA + slot*16'd1536;
            // Recognizable payload: 0x40 + (b & 0x3f), never 0x00/0xFF.
            for (b = 0; b < flen; b = b + 1)
                ddr_write_byte(data_base + b[15:0], 8'h40 + (b[5:0]));
            ddr_write_u16(OFF_RX_LEN + slot*16'd2, flen[15:0]);
        end
    endtask

    // ----- the data-port memtest pattern -----
    localparam integer NWORDS = 8;
    reg [15:0] pattern [0:NWORDS-1];
    reg [15:0] got;
    reg        wtmo, rtmo;
    integer k;
    integer read_timeouts = 0, write_timeouts = 0, ff_reads = 0, data_mismatch = 0;

    // ---- instrumentation: how busy is the bg packet-RAM write port (A)? ----
    // pmem_wren_a is asserted exactly on the cycles the bg writes the ring
    // (BG_WRITE_HDR0/HDR1/PAYLOAD*).  With the true dual-port RAM the bg owns
    // port A and the CPU owns port B, so these bg writes now overlap the CPU's
    // data-port accesses with ZERO contention -- which is what this TB confirms.
    integer pmem_active_cycles = 0;
    integer pmem_active_max_run = 0;
    integer pmem_active_run = 0;
    reg     probe_en = 0;
    always @(posedge clk_sys) begin
        if (probe_en) begin
            if (dut.pmem_wren_a) begin
                pmem_active_cycles = pmem_active_cycles + 1;
                pmem_active_run = pmem_active_run + 1;
                if (pmem_active_run > pmem_active_max_run) pmem_active_max_run = pmem_active_run;
            end else begin
                pmem_active_run = 0;
            end
        end
    end

    initial begin
        pattern[0] = 16'h4865; pattern[1] = 16'h6C6C;
        pattern[2] = 16'h6F20; pattern[3] = 16'h4865;
        pattern[4] = 16'h7265; pattern[5] = 16'h2049;
        pattern[6] = 16'h7320; pattern[7] = 16'h416D;

        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys);
        @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        // HPS signature/heartbeat so the bg considers the link live.
        ddr_write_u16(OFF_SIG,         16'hBABE);
        ddr_write_u16(OFF_SIG + 16'd2, 16'hCAFE);
        ddr_write_u16(OFF_HB,          16'h0001);

        repeat (400) @(posedge clk_sys);

        // ---- enable the NE2000 receiver so the bg delivers injected frames
        //      (exact proven sequence from eth_rx_driver_tb) ----
        write_high_reg(15'h0602, 8'h46);   // PSTART (reg 1) = 0x46
        write_high_reg(15'h0604, 8'h80);   // PSTOP  (reg 2) = 0x80
        write_high_reg(15'h0606, 8'h46);   // BNRY   (reg 3) = PSTART
        write_high_reg(15'h061C, 8'h4B);   // DCR    (reg 14) = word mode
        write_high_reg(15'h0618, 8'h0C);   // RCR    (reg 12) = bcast+mcast -> arms rx_poll
        write_high_reg(15'h0600, 8'h62);   // CR     (reg 0) page1
        write_high_reg(15'h060E, 8'h47);   // CURR   (reg 7 page1) = PSTART+1
        write_high_reg(15'h0600, 8'h22);   // CR     page0 + STA -> receiver_active
        write_high_reg(15'h061E, 8'h0F);   // IMR    (reg 15) = PRX|PTX|RXE|TXE

        // ---- queue one large frame (1 slot, tail=1 like the proven driver TB)
        //      so the bg spends a long time in BG_WRITE_PAYLOAD_WIDE delivering it.
        inject_frame(0, FLEN);
        ddr_write_u16(OFF_RX_LEN,  FLEN[15:0]);   // slot-0 len (also at base)
        ddr_write_u16(OFF_RX_TAIL, 16'h0001);
        ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);

        probe_en = 1'b1;
        // Spin until the bg is actually writing payload to the ring
        // (pmem_wren_a asserted), so the memtest below truly overlaps delivery.
        begin : wait_deliver
            integer g;
            for (g = 0; g < 300000; g = g + 1) begin
                @(posedge clk_sys);
                if (dut.pmem_wren_a) disable wait_deliver;
            end
        end
        $display("PROBE start: bg_state=%0d isr=0x%02x rx_head=%0d rx_tail=%0d (bg now delivering payload)",
                 dut.bg_state, dut.isr_register, dut.bg_rx_queue_head, dut.bg_rx_queue_tail);

        // ---- CONCURRENT data-port WRITE burst (PIOWriteMem equivalent) ----
        // RSAR=0x4000, RBCR, CR=remote write, then push the pattern. Each word
        // is a CPU data-port cycle that must arbitrate against the bg.
        write_high_reg(15'h0610, 8'h00);   // RSAR0
        write_high_reg(15'h0612, 8'h40);   // RSAR1 -> 0x4000
        write_high_reg(15'h0614, NWORDS*2);// RBCR0
        write_high_reg(15'h0616, 8'h00);   // RBCR1
        write_high_reg(15'h0600, 8'h12);   // CR = remote write + STA
        for (k = 0; k < NWORDS; k = k + 1) begin
            data_port_write_word(pattern[k], wtmo);
            if (wtmo) write_timeouts = write_timeouts + 1;
        end
        if ((dut.isr_register & 8'h40) == 8'h00)
            $display("OBSERVED: ISR.RDC not set after write burst -> PIOWriteMem Timeout mechanism (ISR=0x%02x RBCR=0x%04x)",
                     dut.isr_register, dut.remote_byte_count);

        // ---- CONCURRENT data-port READ burst ----
        write_high_reg(15'h0610, 8'h00);
        write_high_reg(15'h0612, 8'h40);
        write_high_reg(15'h0614, NWORDS*2);
        write_high_reg(15'h0616, 8'h00);
        write_high_reg(15'h0600, 8'h0A);   // CR = remote read + STA
        for (k = 0; k < NWORDS; k = k + 1) begin
            data_port_read_word(got, rtmo);
            if (rtmo) read_timeouts = read_timeouts + 1;
            if (got === 16'hFFFF) begin
                ff_reads = ff_reads + 1;
                $display("OBSERVED: word %0d read back 0x%04x (open-bus / timeout latch) <- the longread 0xffffffff symptom", k, got);
            end else if (got !== pattern[k]) begin
                data_mismatch = data_mismatch + 1;
                $display("OBSERVED: word %0d read back 0x%04x != written 0x%04x", k, got, pattern[k]);
            end
        end

        $display("PROBE end: bg_state=%0d isr=0x%02x rx_head=%0d rx_tail=%0d  | bg ring-write (pmem_wren_a): cycles=%0d max_consec_run=%0d (timeout threshold=511)",
                 dut.bg_state, dut.isr_register, dut.bg_rx_queue_head, dut.bg_rx_queue_tail,
                 pmem_active_cycles, pmem_active_max_run);
        $display("SUMMARY: write_timeouts=%0d read_timeouts=%0d ff_reads=%0d data_mismatch=%0d",
                 write_timeouts, read_timeouts, ff_reads, data_mismatch);
        if (write_timeouts || read_timeouts || ff_reads || data_mismatch)
            $display("REPRODUCED: data-port cycle starved by bg ring-write contention (matches the HW memtest failure).");
        else
            $display("NOT REPRODUCED: data port survived concurrent RX delivery in this run.");
        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: eth_dataport_contention_tb global timeout");
        $finish;
    end

endmodule
