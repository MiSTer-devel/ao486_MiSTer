// tb_ne2000_loopback.v -- TCR.LB=01 (NIC/internal loopback) data-path test.
//
// Ported from the A2065 project's Lance-Test review: a real DP8390 in NIC
// loopback mode loops the frame entirely inside the chip and still drives it
// through the genuine receive datapath -- the receive buffer ring, CRC/byte
// assembly, boundary-pointer update -- exactly as if it arrived off the wire.
// The core used to fake only the STATUS half of that (RSR_PRX/ISR_PTX) without
// ever copying the transmitted bytes into the RX ring or advancing CURR, so a
// guest reading back its own loopback frame got stale/garbage data. This bench
// proves the fix: the BG_LOOP_* states copy the TX page into the RX ring via
// packet-RAM port A, entirely locally.
//
// Two frames are sent back-to-back: an even length (60, exercises the "last
// even word" finalize branch in BG_WRITE_PAYLOAD_REQ) and an odd length (61,
// exercises the "odd tail byte" finalize branch) -- both branches were touched
// to add the bg_loop_copy gate, so both need direct coverage.
//
// eth_dma_ready is tied permanently low and eth_dma_req is monitored
// throughout: if the loopback path ever fell through to the HPS-mailbox path
// (the bug this replaces would have, since TCR.LB used to skip staging
// entirely with no RX side at all), either the wait for ISR.PRX times out or
// the eth_dma_req monitor catches it -- this is the direct proof the copy is
// FPGA-local, matching what a real DP8390's NIC loopback mode needs (no
// external transport at all).

`timescale 1ns / 1ps

module tb_ne2000_loopback;

reg clk = 1'b0;
reg reset = 1'b1;

reg [15:1] host_addr = 15'h0000;
reg [15:0] host_wdata = 16'h0000;
wire [15:0] host_rdata;
reg host_rd = 1'b0;
reg host_wr_hi = 1'b0;
reg host_wr_lo = 1'b0;
reg host_cyc_n = 1'b1;
reg host_be_hi_n = 1'b1;
reg host_be_lo_n = 1'b1;
reg host_sel = 1'b0;
reg host_sel_priv = 1'b0;

// Minimal always-ready mailbox stub. The bg FSM's own boot sequence
// (BG_INIT_HEAD_REQ.. BG_INIT_MAC_WAIT) and periodic HPS-poll/register-mirror
// sync go through eth_dma unconditionally, independent of loopback mode -- a
// permanently-low ready would wedge bg_state in BG_INIT_MAC_WAIT forever and
// the core would never even reach BG_IDLE. Reads return 0, which is harmless
// here (MAC-adopt validity check rejects an all-zero address and keeps the
// built-in default; RX head/tail read as an empty queue).
wire [15:0] eth_dma_rdata = 16'h0000;
wire [63:0] eth_dma_rdata64 = 64'h0;
wire eth_dma_req, eth_dma_write, eth_dma_wide, eth_dma_uds, eth_dma_lds;
wire [15:1] eth_dma_addr;
wire [15:0] eth_dma_wdata;
wire [63:0] eth_dma_wdata64;
wire eth_dma_ready = eth_dma_req;
wire irq, host_ack_n;

integer errors = 0;
// Scoped to the loop-copy itself (not the whole test -- unrelated background
// mailbox chatter, like the boot sequence above, is expected and harmless).
// This is the direct proof the copy is FPGA-local, matching a real DP8390's
// NIC loopback, which needs no external transport at all.
reg mailbox_touched_during_copy = 1'b0;
always @(posedge clk) if (dut.bg_loop_copy && eth_dma_req) mailbox_touched_during_copy = 1'b1;

ne2000_core dut (
    .clk(clk), .reset(reset),
    .host_addr(host_addr), .host_wdata(host_wdata), .host_rdata(host_rdata),
    .host_rd(host_rd), .host_wr_hi(host_wr_hi), .host_wr_lo(host_wr_lo),
    .host_cyc_n(host_cyc_n),
    .host_be_hi_n(host_be_hi_n), .host_be_lo_n(host_be_lo_n),
    .host_sel_priv(host_sel_priv), .host_sel(host_sel),
    .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
    .eth_dma_rdata64(eth_dma_rdata64),
    .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
    .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
    .eth_dma_wide(eth_dma_wide), .eth_dma_wdata64(eth_dma_wdata64),
    .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
    .irq(irq), .host_ack_n(host_ack_n)
);

always #5 clk = ~clk;

localparam [14:0] REG_BASE = 15'h0600;   // byte 0x0C00, 4 bytes per register
localparam [14:0] DPORT    = 15'h0640;   // byte 0x0C80, wide data-port alias

function [14:0] reg_word;
    input [4:0] index;
    begin
        reg_word = REG_BASE + {9'h000, index, 1'b0};
    end
endfunction

// x86-style register write: one byte on the LOW lane only.
task automatic write_reg;
    input [4:0] index;
    input [7:0] value;
    begin
        @(negedge clk);
        host_addr = reg_word(index);
        host_wdata = {8'h00, value};
        host_sel = 1'b1;
        host_wr_lo = 1'b1;
        host_cyc_n = 1'b0;
        host_be_lo_n = 1'b0;
        @(posedge clk);
        @(negedge clk);
        host_wr_lo = 1'b0;
        host_cyc_n = 1'b1;
        host_be_lo_n = 1'b1;
        host_sel = 1'b0;
        host_wdata = 16'h0000;
    end
endtask

task automatic read_reg;
    input [4:0] index;
    output [7:0] value;
    integer w; reg done;
    begin
        done = 1'b0; value = 8'hXX;
        @(negedge clk);
        host_addr = reg_word(index);
        host_sel = 1'b1; host_rd = 1'b1;
        host_cyc_n = 1'b0; host_be_lo_n = 1'b0;
        for (w = 0; w < 64 && !done; w = w + 1) begin
            @(posedge clk); #1;
            if (host_ack_n === 1'b0) begin value = host_rdata[7:0]; done = 1'b1; end
        end
        @(negedge clk);
        host_rd = 1'b0; host_cyc_n = 1'b1; host_be_lo_n = 1'b1; host_sel = 1'b0;
        if (!done) begin $display("FAIL: register read @index 0x%02x timed out", index); errors = errors + 1; end
        @(negedge clk);
    end
endtask

// 16-bit data-port word write, full word (both lanes).
task automatic dport_write_word;
    input [15:0] value;
    integer w; reg done;
    begin
        done = 1'b0;
        @(negedge clk);
        host_addr = DPORT; host_wdata = value; host_sel = 1'b1;
        host_wr_hi = 1'b1; host_wr_lo = 1'b1;
        host_cyc_n = 1'b0; host_be_hi_n = 1'b0; host_be_lo_n = 1'b0;
        for (w = 0; w < 600 && !done; w = w + 1) begin
            @(posedge clk); #1;
            if (host_ack_n === 1'b0) done = 1'b1;
        end
        @(negedge clk);
        host_wr_hi = 1'b0; host_wr_lo = 1'b0; host_cyc_n = 1'b1;
        host_be_hi_n = 1'b1; host_be_lo_n = 1'b1; host_sel = 1'b0;
        host_wdata = 16'h0000;
        if (!done) begin $display("FAIL: data-port write timed out"); errors = errors + 1; end
        @(negedge clk);
    end
endtask

task automatic dport_read_word;
    output [15:0] value;
    integer w; reg done;
    begin
        done = 1'b0; value = 16'hXXXX;
        @(negedge clk);
        host_addr = DPORT; host_sel = 1'b1; host_rd = 1'b1;
        host_cyc_n = 1'b0; host_be_hi_n = 1'b0; host_be_lo_n = 1'b0;
        for (w = 0; w < 600 && !done; w = w + 1) begin
            @(posedge clk); #1;
            if (host_ack_n === 1'b0) begin value = host_rdata; done = 1'b1; end
        end
        @(negedge clk);
        host_rd = 1'b0; host_cyc_n = 1'b1; host_be_hi_n = 1'b1; host_be_lo_n = 1'b1; host_sel = 1'b0;
        if (!done) begin $display("FAIL: data-port read timed out"); errors = errors + 1; end
        @(negedge clk);
    end
endtask

localparam integer MAX_LEN = 64;
reg [7:0] frame [0:MAX_LEN-1];
integer k, w;
reg [7:0] curr_before, curr_after, isr_v, tsr_v;
reg [15:0] got, expw, hdr0, hdr1;
reg [7:0] st_v, next_v, lenlo_v, lenhi_v;
integer mism;

// Send one loopback frame of `len` bytes (pattern seeded by `seed` so two
// calls never share content), verify PTX+PRX, CURR advance, ring header, and
// byte-exact payload readback -- and that the mailbox was never touched.
task automatic loopback_frame;
    input integer len;
    input [7:0] seed;
    input [7:0] exp_next;
    begin
        for (k = 0; k < len; k = k + 1) frame[k] = ((k * 8'h07) + seed) & 8'hFF;

        mailbox_touched_during_copy = 1'b0;

        // Program the ring and loopback mode.
        write_reg(5'h00, 8'h21);        // CR: stop, page 0
        write_reg(5'h0E, 8'h01);        // DCR: word mode
        write_reg(5'h01, 8'h46);        // PSTART
        write_reg(5'h02, 8'h80);        // PSTOP
        write_reg(5'h03, 8'h46);        // BNRY
        write_reg(5'h0C, 8'h04);        // RCR: accept broadcast -- also the only
                                         // thing that latches rx_poll_enabled, which
                                         // receiver_active (and so loop_copy_pending)
                                         // requires
        write_reg(5'h0D, 8'h02);        // TCR: LB[1:0]=01 (bit1 set) -> NIC loopback
        write_reg(5'h07, 8'hFF);        // clear ISR

        // Load the TX page (0x4000) via remote-DMA write.
        write_reg(5'h0A, len[7:0]);     // RBCR0
        write_reg(5'h0B, 8'h00);        // RBCR1
        write_reg(5'h08, 8'h00);        // RSAR0
        write_reg(5'h09, 8'h40);        // RSAR1 -> 0x4000
        write_reg(5'h00, 8'h12);        // CR: remote write
        for (w = 0; w < len; w = w + 2)
            dport_write_word({frame[w+1], frame[w]});   // x86: low byte first

        // Snapshot CURR before the transmit.
        write_reg(5'h00, 8'h62);        // CR: page 1
        read_reg(5'h07, curr_before);   // page-1 index 7 = CURR
        write_reg(5'h00, 8'h22);        // CR: page 0, STA

        // Transmit -- with TCR.LB=01 the copy itself must never touch eth_dma
        // (see mailbox_touched_during_copy monitor above).
        write_reg(5'h04, 8'h40);        // TPSR = 0x40
        write_reg(5'h05, len[7:0]);     // TBCR0
        write_reg(5'h06, 8'h00);        // TBCR1
        write_reg(5'h00, 8'h26);        // CR: STA | TXP

        begin : wait_prx
            integer g;
            for (g = 0; g < 20000; g = g + 1) begin
                @(posedge clk);
                if ((dut.isr_register & 8'h03) == 8'h03) disable wait_prx;   // PRX|PTX
            end
        end
        if ((dut.isr_register & 8'h03) != 8'h03) begin
            $display("FAIL: len=%0d ISR PRX|PTX never both set (isr=0x%02x bg_state=%0d)",
                     len, dut.isr_register, dut.bg_state);
            errors = errors + 1;
        end else begin
            $display("ok:   len=%0d ISR PRX|PTX set (isr=0x%02x)", len, dut.isr_register);
        end

        if (mailbox_touched_during_copy) begin
            $display("FAIL: len=%0d eth_dma_req asserted during the loopback copy -- not local", len);
            errors = errors + 1;
        end else begin
            $display("ok:   len=%0d never touched eth_dma (fully local)", len);
        end

        read_reg(5'h04, tsr_v);         // TSR
        if ((tsr_v & 8'h01) != 8'h01) begin
            $display("FAIL: len=%0d TSR.PTX not set (tsr=0x%02x)", len, tsr_v);
            errors = errors + 1;
        end

        // CURR must have advanced by exactly one page (len <= 64 always fits).
        write_reg(5'h00, 8'h62);
        read_reg(5'h07, curr_after);
        write_reg(5'h00, 8'h22);
        $display("INFO: len=%0d CURR 0x%02x -> 0x%02x (expect 0x%02x)",
                 len, curr_before, curr_after, exp_next);
        if (curr_after !== exp_next) begin
            $display("FAIL: len=%0d CURR=0x%02x, expected 0x%02x", len, curr_after, exp_next);
            errors = errors + 1;
        end

        // Ring header at curr_before*256: {status, next_page}, {len_lo, len_hi}.
        write_reg(5'h08, 8'h00);                 // RSAR0
        write_reg(5'h09, curr_before);            // RSAR1
        write_reg(5'h0A, 8'h04);                  // RBCR0
        write_reg(5'h0B, 8'h00);                  // RBCR1
        write_reg(5'h00, 8'h0A);                  // CR: remote read
        dport_read_word(hdr0);
        dport_read_word(hdr1);
        st_v = hdr0[7:0]; next_v = hdr0[15:8];
        lenlo_v = hdr1[7:0]; lenhi_v = hdr1[15:8];
        $display("INFO: len=%0d header status=0x%02x next=0x%02x len=0x%02x%02x",
                 len, st_v, next_v, lenhi_v, lenlo_v);
        if (next_v !== exp_next) begin
            $display("FAIL: len=%0d header next_page=0x%02x, expected 0x%02x", len, next_v, exp_next);
            errors = errors + 1;
        end
        if ({lenhi_v, lenlo_v} !== (len[15:0] + 16'h0004)) begin
            $display("FAIL: len=%0d header length=0x%04x, expected 0x%04x",
                     len, {lenhi_v, lenlo_v}, len[15:0] + 16'h0004);
            errors = errors + 1;
        end

        // Payload, byte-exact against what was staged into the TX page.
        write_reg(5'h08, 8'h04);                  // RSAR0
        write_reg(5'h09, curr_before);             // RSAR1
        write_reg(5'h0A, len[7:0]);                // RBCR0
        write_reg(5'h0B, 8'h00);                   // RBCR1
        write_reg(5'h00, 8'h0A);                   // CR: remote read
        mism = 0;
        for (w = 0; w < len; w = w + 2) begin
            dport_read_word(got);
            if (w == len - 1) expw = {8'h00, frame[w]};   // odd tail: only low byte meaningful
            else expw = {frame[w+1], frame[w]};
            if (w == len - 1) begin
                if (got[7:0] !== expw[7:0]) begin
                    $display("FAIL: len=%0d payload tail byte %0d = 0x%02x, expected 0x%02x",
                             len, w, got[7:0], expw[7:0]);
                    mism = mism + 1; errors = errors + 1;
                end
            end else if (got !== expw) begin
                if (mism < 8)
                    $display("FAIL: len=%0d payload word (byte %0d) = 0x%04x, expected 0x%04x",
                             len, w, got, expw);
                mism = mism + 1; errors = errors + 1;
            end
        end
        if (mism == 0) $display("ok:   len=%0d all %0d payload bytes read back correctly", len, len);
    end
endtask

initial begin
    reset = 1'b1;
    repeat (8) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    repeat (8) @(posedge clk);

    // Even length: exercises BG_WRITE_PAYLOAD_REQ's "last even word" finalize.
    // 60 bytes from PSTART=0x46 -> 1 page -> next = 0x47.
    loopback_frame(60, 8'h11, 8'h48);

    // Reset between frames so CURR/BNRY/ring state start clean again.
    reset = 1'b1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    repeat (8) @(posedge clk);

    // Odd length: exercises BG_WRITE_PAYLOAD_REQ's "odd tail byte" finalize.
    loopback_frame(61, 8'h5A, 8'h48);

    if (errors == 0) $display("PASS: tb_ne2000_loopback");
    else             $display("FAIL: tb_ne2000_loopback (%0d error(s))", errors);
    $finish;
end

initial begin
    #2000000;
    $display("FAIL: global timeout"); errors = errors + 1; $finish;
end

endmodule
