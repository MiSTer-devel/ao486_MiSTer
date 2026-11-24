// Ported for the ao486 NE2000 (Phase 1 of NE2000_AO486_PLAN.md) from the
// Minimig-AGA Ethernet_shmem2 branch, commit 9598b936
// (apolkosnik/Minimig-AGA_MiSTer, GPL). Module renamed; logic unchanged.
//
//
// ne2000_avalon_arbiter.v
//
// Two-master Avalon-MM arbiter for the f2sdram2 (ram2) port shared between the
// existing audio/PAL DDR service (ddr_svc) and the NE2000 ethernet DDR3 mailbox.
//
// This mirrors the A2065 transport structure (dedicated f2sdram2 master sharing
// the port with the core's DDR service through an arbiter) while keeping the
// NE2000/RTL8019 device model intact.
//
// Arbitration policy: ROUND-ROBIN (fair).  When both masters request, the next
// free slot alternates between them; otherwise the sole requester wins.  Grant
// is held for the duration of a burst/outstanding reads.  This bounds the
// mailbox's worst-case wait to ~one ddr_svc burst, so the low-rate mailbox is
// never starved by a busy ddr_svc/PAL display load.  (Strict ddr_svc priority
// was tried first but starved the mailbox under display DMA, tripping the
// background DMA timeout and desyncing the clk_sys<->clk_audio handshake.)
// ddr_svc's audio/PAL FIFOs tolerate the at-most-one-beat insertion of a
// single-beat mailbox access between their bursts.
//
// Contract:
//   - m0 (ddr_svc) is read-only with bursts (assign ram_writedata=0 in ddr_svc).
//   - m1 (mailbox) issues only single-beat transfers (burstcount==1), one
//     outstanding at a time.
//   - Standard Avalon-MM: master holds command stable while waitrequest is high;
//     read responses (readdatavalid) return in order after an accepted read.
//
// Grant is held (cannot switch master) whenever a command is mid-handshake or
// any read responses are still pending, so readdatavalid is always routed to the
// master that issued the read.  This is the explicit, documented version of the
// "stuck grant" behaviour the A2065 mailbox depended on implicitly.
//

module ne2000_avalon_arbiter
(
    input         clk,
    input         reset,         // synchronous, active high

    // Master 0 = ddr_svc (audio/PAL).  Priority.
    input  [28:0] m0_address,
    input  [ 7:0] m0_burstcount,
    input  [ 7:0] m0_byteenable,
    input  [63:0] m0_writedata,
    input         m0_read,
    input         m0_write,
    output        m0_waitrequest,
    output [63:0] m0_readdata,
    output        m0_readdatavalid,

    // Master 1 = NE2000 ethernet mailbox.  Single-beat read/write.
    input  [28:0] m1_address,
    input  [ 7:0] m1_burstcount,
    input  [ 7:0] m1_byteenable,
    input  [63:0] m1_writedata,
    input         m1_read,
    input         m1_write,
    output        m1_waitrequest,
    output [63:0] m1_readdata,
    output        m1_readdatavalid,

    // Shared slave = ram2 / f2sdram2 (clk_audio domain).
    output [28:0] s_address,
    output [ 7:0] s_burstcount,
    output [ 7:0] s_byteenable,
    output [63:0] s_writedata,
    output        s_read,
    output        s_write,
    input         s_waitrequest,
    input  [63:0] s_readdata,
    input         s_readdatavalid
);

    // grant: 0 -> m0 (priority), 1 -> m1
    reg        grant    = 1'b0;
    // outstanding read-response beats owed to the current grant master
    reg [9:0]  rpending = 10'd0;

    wire m0_req = m0_read | m0_write;
    wire m1_req = m1_read | m1_write;

    // last master that was actually granted a command (for round-robin).
    reg        last = 1'b0;

    // A command is presented to the slave but not yet accepted.
    wire cmd_inflight = (s_read | s_write) & s_waitrequest;
    // A read command is accepted this cycle (response will land later).
    wire read_accept  = s_read & ~s_waitrequest;
    // Any command accepted this cycle.
    wire cmd_accept   = (s_read | s_write) & ~s_waitrequest;

    // Grant must not change while a command is mid-handshake or read responses
    // are still owed.  read_accept keeps the lock continuous into the cycle when
    // rpending becomes non-zero (no one-cycle gap).
    wire lock = (rpending != 10'd0) | cmd_inflight | read_accept;

    always @(posedge clk) begin
        if (reset) begin
            grant    <= 1'b0;
            last     <= 1'b0;
            rpending <= 10'd0;
        end else begin
            // outstanding read-beat accounting (burst-aware)
            case ({read_accept, s_readdatavalid})
                2'b10: rpending <= rpending + {2'd0, s_burstcount};
                2'b01: rpending <= rpending - 10'd1;
                2'b11: rpending <= rpending + {2'd0, s_burstcount} - 10'd1;
                default: ;
            endcase

            // Remember who was last served so the next free slot goes to the
            // other master (fairness -> the mailbox cannot be starved by a busy
            // ddr_svc/PAL display load, which previously tripped the background
            // DMA timeout and desynced the clk_sys<->clk_audio handshake).
            if (cmd_accept) last <= grant;

            // Re-arbitrate only when it is safe to switch master. Round-robin:
            // if both request, grant the one that did NOT go last.
            if (!lock) begin
                if (m0_req && m1_req) grant <= ~last;
                else if (m0_req)      grant <= 1'b0;
                else if (m1_req)      grant <= 1'b1;
            end
        end
    end

    // Command mux: the granted master drives the slave.
    assign s_address    = grant ? m1_address    : m0_address;
    assign s_burstcount = grant ? m1_burstcount  : m0_burstcount;
    assign s_byteenable = grant ? m1_byteenable  : m0_byteenable;
    assign s_writedata  = grant ? m1_writedata   : m0_writedata;
    assign s_read       = grant ? m1_read        : m0_read;
    assign s_write      = grant ? m1_write       : m0_write;

    // Backpressure: only the granted master sees the real waitrequest.
    assign m0_waitrequest = grant ? 1'b1 : s_waitrequest;
    assign m1_waitrequest = grant ? s_waitrequest : 1'b1;

    // Read responses route to the granted master (grant is held until drained).
    assign m0_readdata      = s_readdata;
    assign m1_readdata      = s_readdata;
    assign m0_readdatavalid = s_readdatavalid & ~grant;
    assign m1_readdatavalid = s_readdatavalid &  grant;

endmodule
