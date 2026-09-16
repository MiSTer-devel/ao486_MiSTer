// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_ack_starvation_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_ack_starvation_tb.v
//
// Proves (and then guards the fix for) the DOWNLOAD ACK-egress stall.
//
// During a download the bg drains a queued batch of RX frames back-to-back
// (BG_WRITE_RX_HEAD_WAIT -> BG_READ_RX_LEN_REQ, ethernet.v) WITHOUT passing
// through BG_IDLE. But the Amiga's outgoing ACKs are only serviced at the
// BG_IDLE dispatch (tx_stage_pending -> BG_WRITE_TX_ADDR_REQ, ethernet.v:2174).
// So an ACK the Amiga issues mid-drain is not staged to the HPS mailbox until
// the ENTIRE remaining batch has drained. The server, not seeing the ACK,
// RTO-retransmits -> the daemon's retxDat climbs with dupAck~0 (its own
// classifier: "the Amiga's ACKs aren't reaching the server"), the download
// collapses to ~40 KB/s and aborts.
//
// This TB injects a batch of RX frames (a download), waits until the bg is
// draining mid-batch, then issues a REAL Amiga transmit (TPSR/TBCR/CR.TXP,
// exactly as the x-surf-100.device sends an ACK) and measures how many RX
// frames the bg drains between tx_stage_pending asserting and clearing
// (i.e. before the ACK is actually staged for the HPS to send).
//
//   delta_head >= 3  -> the ACK waited behind the rest of the batch (STARVED)
//   delta_head <= 2  -> the ACK was interleaved into the drain promptly (FIXED)
//
// No fake logic: real ethernet_interface + real ne2000_ddr_mailbox, frames
// injected exactly like the HPS daemon, TX issued over the real CPU bus.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_ack_starvation_tb;

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
    localparam integer NFRAMES  = 8;
    localparam integer FLEN     = 64;       // 64B payload -> 1 ring page each
    localparam integer ACK_AT   = 2;        // issue the Amiga ACK once 2 frames drained
    integer fi;

    task automatic inject_frame;
        input integer slot;
        input integer flen;
        integer b;
        reg [15:0] data_base;
        begin
            data_base = OFF_RX_DATA + slot*16'd1536;
            for (b = 0; b < flen; b = b + 1)
                ddr_write_byte(data_base + b[15:0],
                               (b == 0) ? (8'hA0 + slot[7:0]) :
                               (b == 1) ? (8'hC0 + slot[7:0]) :
                               (8'h40 + b[5:0]));
            ddr_write_u16(OFF_RX_LEN + slot*16'd2, flen[15:0]);
        end
    endtask

    // Issue a REAL Amiga transmit (an ACK): point TPSR at the TX page, set the
    // byte count, then write CR with TXP -> the FSM latches tx_stage_pending=1
    // (complete-on-command), exactly the x-surf-100.device ACK path.
    task automatic issue_ack_tx;
        begin
            write_high_reg(15'h0608, 8'h40);   // TPSR  (reg 4) = 0x40 (TX page)
            write_high_reg(15'h060A, 8'h40);   // TBCR0 (reg 5) = 64
            write_high_reg(15'h060C, 8'h00);   // TBCR1 (reg 6) = 0
            write_high_reg(15'h0600, 8'h26);   // CR    (reg 0) = STA | TXP
        end
    endtask

    // ---- monitor: capture bg_rx_queue_head at the tx_stage_pending edges ----
    reg        prev_tx_stage = 1'b0;
    reg        ack_set_seen  = 1'b0;
    reg        ack_clr_seen  = 1'b0;
    integer    head_at_set   = 0;
    integer    head_at_clr   = 0;
    integer    cyc           = 0;
    integer    cyc_at_set    = 0;
    integer    cyc_at_clr    = 0;
    always @(posedge clk_sys) begin
        cyc <= cyc + 1;
        if (!reset_sys) begin
            if (dut.tx_stage_pending && !prev_tx_stage && !ack_set_seen) begin
                ack_set_seen <= 1'b1;
                head_at_set  <= dut.bg_rx_queue_head;
                cyc_at_set   <= cyc;
            end
            if (!dut.tx_stage_pending && prev_tx_stage && ack_set_seen && !ack_clr_seen) begin
                ack_clr_seen <= 1'b1;
                head_at_clr  <= dut.bg_rx_queue_head;
                cyc_at_clr   <= cyc;
            end
            prev_tx_stage <= dut.tx_stage_pending;
        end
    end

    integer delta_head;

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

        // ---- queue the whole batch (a download burst) and start it draining ----
        for (fi = 0; fi < NFRAMES; fi = fi + 1) inject_frame(fi, FLEN);
        ddr_write_u16(OFF_RX_TAIL, NFRAMES[15:0]);
        ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);

        // ---- wait until the bg is mid-drain (ACK_AT frames consumed) ----
        begin : wait_mid
            integer g;
            for (g = 0; g < 300000; g = g + 1) begin
                @(posedge clk_sys);
                if (dut.bg_rx_queue_head >= ACK_AT[15:0]) disable wait_mid;
            end
        end

        // ---- the Amiga sends an ACK right now, mid-download ----
        issue_ack_tx;

        // ---- wait until that ACK is actually staged (tx_stage_pending clears) ----
        begin : wait_ack
            integer g;
            for (g = 0; g < 400000 && !ack_clr_seen; g = g + 1) @(posedge clk_sys);
        end
        @(posedge clk_sys);

        if (!ack_set_seen) begin
            $display("FAIL: tx_stage_pending never asserted -- the Amiga TX (ACK) was not accepted");
            errors = errors + 1;
        end
        if (!ack_clr_seen) begin
            $display("FAIL: tx_stage_pending never cleared -- the ACK was never staged for the HPS (hard stall)");
            errors = errors + 1;
        end

        delta_head = head_at_clr - head_at_set;
        $display("ACK issued at rx_head=%0d (cyc %0d); ACK staged at rx_head=%0d (cyc %0d)",
                 head_at_set, cyc_at_set, head_at_clr, cyc_at_clr);
        $display("RX frames drained while the ACK waited = %0d ; stage latency = %0d cycles",
                 delta_head, cyc_at_clr - cyc_at_set);

        if (ack_set_seen && ack_clr_seen) begin
            if (delta_head >= 3) begin
                $display("FAIL: ACK STARVED -- it waited behind %0d more RX frames before being staged (download ACK-egress stall reproduced).", delta_head);
                errors = errors + 1;
            end else begin
                $display("INFO: ACK interleaved promptly -- only %0d RX frame(s) drained before it was staged.", delta_head);
            end
        end

        // ---- DEADLOCK CHECK: RX must keep draining while a TX ack is OUTSTANDING.
        // This TB never writes TX_COMPLETE_SEQ, so once the ACK stages,
        // tx_request_pending stays asserted (the HPS "hasn't acked"). If the
        // TX-ack poll is given absolute priority it starves RX and
        // bg_rx_queue_head freezes -- the exact bring-up deadlock (the FPGA cannot
        // deliver the DHCP OFFER while a TX ack is pending). Require all NFRAMES to
        // drain DESPITE the stuck TX.
        begin : wait_drain
            integer g;
            for (g = 0; g < 300000 && (dut.bg_rx_queue_head < NFRAMES[15:0]); g = g + 1)
                @(posedge clk_sys);
        end
        $display("After ACK: tx_request_pending=%0b, RX drained=%0d/%0d",
                 dut.tx_request_pending, dut.bg_rx_queue_head, NFRAMES);
        if (dut.bg_rx_queue_head < NFRAMES[15:0]) begin
            $display("FAIL: RX STARVED by a pending TX ack -- only %0d/%0d frames drained while tx_request_pending stuck (bring-up deadlock).",
                     dut.bg_rx_queue_head, NFRAMES);
            errors = errors + 1;
        end else begin
            $display("INFO: all %0d RX frames drained with the TX ack still outstanding -- RX not starved by the TX-ack poll.", NFRAMES);
        end

        if (errors == 0)
            $display("PASS: eth_ack_starvation_tb (ACK staged within %0d RX frame(s); RX not starved by a pending TX ack)", delta_head);
        else
            $display("FAILED: eth_ack_starvation_tb with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #40000000;
        $display("FAIL: eth_ack_starvation_tb global timeout");
        $finish;
    end

endmodule
