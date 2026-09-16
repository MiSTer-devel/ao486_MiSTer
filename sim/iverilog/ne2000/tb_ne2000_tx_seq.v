// tb_ne2000_tx_seq.v -- TX_REQUEST_SEQ must survive a guest NIC soft reset.
//
// Regression for the seq-collision bug found on hardware 2026-08-03:
//
//   Every NE2KSEND run begins with a reset-port read (the standard NE2000 soft
//   reset). apply_nic_reset() zeroed tx_request_seq, so the first transmit after
//   a reset always published seq=1. The HPS daemon tracks the last seq it sent
//   and only transmits on a change, so the SECOND and every later run collided
//   at seq=1 and the daemon dropped the frame -- while the BF-7 fast path still
//   reported TSR.PTX "SENT". A dead-silent lost transmit.
//
// Fix: tx_request_seq is a transport-lifetime counter. It is cleared only on a
// hard core reset (which also clears the shared window), never on a guest soft
// reset. So back-to-back transmits separated by a reset-port read must publish
// strictly increasing seq values.
//
// The window is seeded with a live host (signature + heartbeat) so transport is
// "alive" and the core actually stages the frame and publishes the seq. The
// core writes seq little-endian into the window: window byte +0 = seq[7:0].

`timescale 1ns / 1ps

module tb_ne2000_tx_seq;

reg clk = 1'b0;
reg reset = 1'b1;
always #5 clk = ~clk;

integer errors = 0;

reg  [15:1] host_addr = 15'h0000;
reg  [15:0] host_wdata = 16'h0000;
wire [15:0] host_rdata;
reg host_rd = 0, host_wr_hi = 0, host_wr_lo = 0;
reg host_cyc_n = 1, host_be_hi_n = 1, host_be_lo_n = 1;
reg host_sel = 0;

wire        d_req, d_write, d_wide, d_uds, d_lds;
wire [15:1] d_addr;
wire [15:0] d_wdata;
wire [63:0] d_wdata64;
wire        d_ready;
wire [15:0] d_rdata;
wire [63:0] d_rdata64;
wire        irq, host_ack_n;

ne2000_core dut
(
    .clk(clk), .reset(reset),
    .host_addr(host_addr), .host_wdata(host_wdata), .host_rdata(host_rdata),
    .host_rd(host_rd), .host_wr_hi(host_wr_hi), .host_wr_lo(host_wr_lo),
    .host_cyc_n(host_cyc_n),
    .host_be_hi_n(host_be_hi_n), .host_be_lo_n(host_be_lo_n),
    .host_sel_priv(1'b0), .host_sel(host_sel),
    .eth_dma_ready(d_ready), .eth_dma_rdata(d_rdata), .eth_dma_rdata64(d_rdata64),
    .eth_dma_req(d_req), .eth_dma_write(d_write), .eth_dma_addr(d_addr),
    .eth_dma_wdata(d_wdata), .eth_dma_wide(d_wide), .eth_dma_wdata64(d_wdata64),
    .eth_dma_uds(d_uds), .eth_dma_lds(d_lds),
    .irq(irq), .host_ack_n(host_ack_n)
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
wire        s_read, s_write;
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
    .s_waitrequest(1'b0), .s_readdata(s_readdata),
    .s_readdatavalid(s_readdatavalid)
);

// ---- window model, byte addressable ----------------------------------------
localparam [28:0] WINDOW_WORD_BASE = 29'h03FE0000;
reg [7:0] win [0:65535];
integer i;
reg        rd_pending = 0;
reg [63:0] rd_data = 0;

always @(posedge clk) begin
    rd_pending <= 1'b0;
    if (s_write) begin
        for (i = 0; i < 8; i = i + 1)
            if (s_byteenable[i])
                win[((s_address - WINDOW_WORD_BASE) << 3) + i] <= s_writedata[i*8 +: 8];
    end
    if (s_read) begin
        for (i = 0; i < 8; i = i + 1)
            rd_data[i*8 +: 8] <= win[((s_address - WINDOW_WORD_BASE) << 3) + i];
        rd_pending <= 1'b1;
    end
end
assign s_readdata = rd_data;
assign s_readdatavalid = rd_pending;

// ---- host register access (generic port, low byte lane like the ISA glue) --
task automatic write_reg;
    input [4:0] index;
    input [7:0] value;
    begin
        @(negedge clk);
        host_addr = 15'h0600 + {9'h000, index, 1'b0};
        host_wdata = {8'h00, value};
        host_sel = 1; host_wr_lo = 1; host_cyc_n = 0; host_be_lo_n = 0;
        @(posedge clk); @(negedge clk);
        host_sel = 0; host_wr_lo = 0; host_cyc_n = 1; host_be_lo_n = 1;
    end
endtask

// A reset-port read: byte 0x0C7C (word 0x063E) -> apply_nic_reset(), the exact
// soft reset NE2KSEND does at the top of every run.
task automatic pulse_reset_port;
    begin
        @(negedge clk);
        host_addr = 15'h063E;
        host_sel = 1; host_rd = 1; host_cyc_n = 0; host_be_lo_n = 0;
        @(posedge clk); @(negedge clk);
        host_sel = 0; host_rd = 0; host_cyc_n = 1; host_be_lo_n = 1;
    end
endtask

// Wait (bounded) for the background FSM to have read the seeded signature and
// heartbeat so transport_alive is asserted.
task automatic wait_transport_alive;
    integer guard;
    begin
        guard = 0;
        while (!dut.transport_alive && guard < 20000) begin
            @(posedge clk); guard = guard + 1;
        end
        if (!dut.transport_alive) begin
            $display("FAIL: transport never went alive (signature seeding wrong?)");
            errors = errors + 1;
        end
    end
endtask

// Program the ring and fire one transmit (TPSR=0x40, 60 bytes). The frame
// contents do not matter here -- only that the TX background FSM runs and
// publishes TX_REQUEST_SEQ.
task automatic transmit_once;
    begin
        pulse_reset_port();               // soft reset, as every real run begins
        write_reg(5'h07, 8'hFF);          // clear ISR
        write_reg(5'h00, 8'h21);          // CR: stop, page 0
        write_reg(5'h0E, 8'h01);          // DCR: word mode
        write_reg(5'h01, 8'h46);          // PSTART
        write_reg(5'h02, 8'h80);          // PSTOP
        write_reg(5'h03, 8'h46);          // BNRY
        write_reg(5'h0D, 8'h00);          // TCR: normal (no loopback)
        write_reg(5'h0C, 8'h04);          // RCR: broadcast
        write_reg(5'h00, 8'h22);          // CR: start
        write_reg(5'h04, 8'h40);          // TPSR = page 0x40
        write_reg(5'h05, 8'h3C);          // TBCR0 = 60
        write_reg(5'h06, 8'h00);          // TBCR1
        // The background FSM discovers the host by polling the window; TXP must
        // see transport_alive or it takes the honest-abort path (BF-7) and never
        // stages, so wait for the poll to land before firing.
        wait_transport_alive();
        write_reg(5'h00, 8'h26);          // CR: STA | TXP
        repeat (6000) @(posedge clk);     // let the background FSM publish the seq
    end
endtask

// TX_REQUEST_SEQ lives at window byte 0x2C08, little-endian.
function [15:0] published_seq;
    input dummy;
    begin
        published_seq = {win[16'h2C09], win[16'h2C08]};
    end
endfunction

reg [15:0] seq_a, seq_b;

initial begin
    for (i = 0; i < 65536; i = i + 1) win[i] = 8'h00;

    repeat (8) @(posedge clk);
    @(negedge clk); reset = 1'b0;
    repeat (10) @(posedge clk);

    // A live host: signature 0xCAFEBABE + a non-zero heartbeat, written with the
    // daemon's proven convention -- 32-bit slots low-half-first, each 16-bit half
    // little-endian. The core reads word@off then word@off+2 and swaps each with
    // hps_u16_from_dma, so hps_signature_seen assembles back to 0xCAFEBABE only
    // for this byte order (flag_owner's big-endian seed never gets validated
    // because that bench does not gate on transport_alive).
    //   sig  lo half 0xBABE @0x108C, hi half 0xCAFE @0x108E
    win[16'h108C] = 8'hBE; win[16'h108D] = 8'hBA;
    win[16'h108E] = 8'hFE; win[16'h108F] = 8'hCA;
    //   heartbeat lo half 0x0001 @0x1088, hi half 0x0000 @0x108A
    win[16'h1088] = 8'h01; win[16'h1089] = 8'h00;
    win[16'h108A] = 8'h00; win[16'h108B] = 8'h00;
    repeat (10) @(posedge clk);

    if (published_seq(0) !== 16'h0000) begin
        $display("FAIL: seq nonzero before any transmit (0x%04x)", published_seq(0));
        errors = errors + 1;
    end

    // First run: soft reset then transmit. seq must become 1.
    transmit_once();
    seq_a = published_seq(0);
    $display("run 1: published TX_REQUEST_SEQ = %0d", seq_a);
    if (seq_a !== 16'h0001) begin
        $display("FAIL: first transmit did not publish seq=1 (got %0d)", seq_a);
        errors = errors + 1;
    end

    // Second run: the guest soft-resets again (as NE2KSEND does) then transmits.
    // The bug made this republish seq=1; the fix makes it 2.
    transmit_once();
    seq_b = published_seq(0);
    $display("run 2: published TX_REQUEST_SEQ = %0d", seq_b);
    if (seq_b === seq_a) begin
        $display("FAIL: seq did NOT advance across a soft reset (both %0d) -- the", seq_b);
        $display("      daemon would drop this frame as a duplicate. seq-collision bug.");
        errors = errors + 1;
    end else if (seq_b !== 16'h0002) begin
        $display("FAIL: second transmit published seq=%0d, expected 2", seq_b);
        errors = errors + 1;
    end else begin
        $display("ok:   seq advanced 1 -> 2 across a guest soft reset");
    end

    if (errors == 0) $display("PASS: tb_ne2000_tx_seq");
    else             $display("FAIL: tb_ne2000_tx_seq (%0d error(s))", errors);
    $finish;
end

endmodule
