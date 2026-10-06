// ne2000_dma_mux.v -- shares the shared-memory transport between the NE2000
// core and the bring-up probe.
//
// Phase 4 of NE2000_AO486_PLAN.md. The mailbox accepts one outstanding
// eth_dma_* transfer at a time, and both the device model and ne2000_shm_probe
// want it: the core for real traffic, the probe for diagnostics.
//
// Fixed priority, core wins. The probe is a human-driven debug aperture issuing
// a transfer every few milliseconds at most; the core carries packets. A held
// grant means the loser's request simply waits, which is safe here because
// neither master can be *forced* to wait on host software -- that is the
// deadlock rule this phase is built around.
//
// The eth_dma contract: req is held high until ready pulses. So the grant is
// latched when a transfer starts and released on ready, and ready is steered to
// the owner only. The loser never sees a ready it did not earn.

module ne2000_dma_mux
(
    input  wire        clk,
    input  wire        reset,

    // ---- m0: NE2000 core (priority) ----
    input  wire        m0_req,
    input  wire        m0_write,
    input  wire [15:1] m0_addr,
    input  wire [15:0] m0_wdata,
    input  wire        m0_wide,
    input  wire [63:0] m0_wdata64,
    input  wire        m0_uds,
    input  wire        m0_lds,
    output wire        m0_ready,
    output wire [15:0] m0_rdata,
    output wire [63:0] m0_rdata64,

    // ---- m1: shared-window probe ----
    input  wire        m1_req,
    input  wire        m1_write,
    input  wire [15:1] m1_addr,
    input  wire [15:0] m1_wdata,
    input  wire        m1_wide,
    input  wire [63:0] m1_wdata64,
    input  wire        m1_uds,
    input  wire        m1_lds,
    output wire        m1_ready,
    output wire [15:0] m1_rdata,
    output wire [63:0] m1_rdata64,

    // ---- to ne2000_ddr_mailbox ----
    output wire        eth_dma_req,
    output wire        eth_dma_write,
    output wire [15:1] eth_dma_addr,
    output wire [15:0] eth_dma_wdata,
    output wire        eth_dma_wide,
    output wire [63:0] eth_dma_wdata64,
    output wire        eth_dma_uds,
    output wire        eth_dma_lds,
    input  wire        eth_dma_ready,
    input  wire [15:0] eth_dma_rdata,
    input  wire [63:0] eth_dma_rdata64
);

localparam M0 = 1'b0;
localparam M1 = 1'b1;

reg busy;
reg owner;

// While idle the core wins outright; the probe is granted only in the gaps.
wire       start_m0 = !busy && m0_req;
wire       start_m1 = !busy && !m0_req && m1_req;
wire       sel      = busy ? owner : (m0_req ? M0 : M1);

always @(posedge clk) begin
    if (reset) begin
        busy  <= 1'b0;
        owner <= M0;
    end
    else if (!busy) begin
        if (start_m0 || start_m1) begin
            busy  <= 1'b1;
            owner <= start_m0 ? M0 : M1;
        end
    end
    else if (eth_dma_ready) begin
        busy <= 1'b0;
    end
end

wire granted_m0 = busy ? (owner == M0) : start_m0;
wire granted_m1 = busy ? (owner == M1) : start_m1;

assign eth_dma_req     = granted_m0 ? m0_req     : granted_m1 ? m1_req     : 1'b0;
assign eth_dma_write   = (sel == M0) ? m0_write   : m1_write;
assign eth_dma_addr    = (sel == M0) ? m0_addr    : m1_addr;
assign eth_dma_wdata   = (sel == M0) ? m0_wdata   : m1_wdata;
assign eth_dma_wide    = (sel == M0) ? m0_wide    : m1_wide;
assign eth_dma_wdata64 = (sel == M0) ? m0_wdata64 : m1_wdata64;
assign eth_dma_uds     = (sel == M0) ? m0_uds     : m1_uds;
assign eth_dma_lds     = (sel == M0) ? m0_lds     : m1_lds;

// Completion goes only to the master that owns the transfer.
assign m0_ready   = eth_dma_ready & granted_m0;
assign m1_ready   = eth_dma_ready & granted_m1;
assign m0_rdata   = eth_dma_rdata;
assign m1_rdata   = eth_dma_rdata;
assign m0_rdata64 = eth_dma_rdata64;
assign m1_rdata64 = eth_dma_rdata64;

endmodule
