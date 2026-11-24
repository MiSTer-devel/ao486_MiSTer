// ne2000_isa.v -- ISA host glue for ne2000_core on the ao486 core.
//
// Phase 3 of NE2000_AO486_PLAN.md.  Converts ao486 `iobus` I/O cycles into the
// core's generic host port:
//
//   ISA port           core canonical byte offset   host_addr[15:1]
//   base+0x00..0x0F    0x0C00 + reg*4               0x0600 + reg*2
//   base+0x10..0x17    0x0C40 (remote DMA data)     0x0620
//   base+0x18..0x1F    0x0C7C (reset port)          0x063E
//   base+0x20..0x2F    0x0C60 + n*4  (debug)        0x0630 + n*2   [optional]
//
// Byte accesses use the LOW lane only, so a register read comes back in
// io_readdata[7:0].  A 16-bit data-port access (io_32) enables both lanes and
// the core returns the assembled word, byte-ordered per DCR.BOS -- with
// BOS_INVERT=1 (the ne2000_core default) that is standard DP8390 behaviour, so
// an x86 guest programming BOS=0 gets the first packet byte in D[7:0].
//
// Bus handshake: `iobus` pulses bus_read/bus_write for one cycle and then waits
// while bus_wait is high, so this module latches the access and holds the core
// strobes until the core acknowledges (host_ack_n low) -- the same shape as a
// 68k AS/DTACK cycle, which is what the core expects.  Register accesses retire
// in a couple of cycles; a data-port access can take longer while the core
// moves packet RAM.  WATCHDOG_CYCLES bounds every access so a wedged core or a
// dead transport can never hang the CPU (plan item 4.3).


module ne2000_isa
#(
    // Expose the core's debug snapshot registers at base+0x20..0x2F.
    // Non-standard; the guest-visible NE2000 is base+0x00..0x1F either way.
    parameter DEBUG_APERTURE  = 1'b1,
    // Bounded escape for any access the core does not acknowledge.
    parameter WATCHDOG_CYCLES = 12'd2047
)
(
    input  wire        clk,
    input  wire        reset,

    // ao486 iobus side (strobes already qualified with the chip select)
    input  wire  [5:0] io_address,
    input  wire        io_read,
    input  wire        io_write,
    input  wire [31:0] io_writedata,
    input  wire        io_32,          // 16-bit access (data port)
    output reg  [31:0] io_readdata,
    output wire        io_wait,

    output wire        irq,

    // Shared-memory transport (Phase 1/4)
    input  wire        eth_dma_ready,
    input  wire [15:0] eth_dma_rdata,
    input  wire [63:0] eth_dma_rdata64,
    output wire        eth_dma_req,
    output wire        eth_dma_write,
    output wire [15:1] eth_dma_addr,
    output wire [15:0] eth_dma_wdata,
    output wire        eth_dma_wide,
    output wire [63:0] eth_dma_wdata64,
    output wire        eth_dma_uds,
    output wire        eth_dma_lds
);

// ---------------------------------------------------------------------------
// Port decode
// ---------------------------------------------------------------------------

// The core has 7 debug registers (canonical 0x0C60..0x0C78). Index 7 would
// land on 0x0C7C, which is the RESET port -- reading base+0x27 would reset the
// NIC. Only 0..6 are mapped; the rest of the aperture is unmapped open bus.
wire        acc_debug     = DEBUG_APERTURE[0] && io_address[5] && (io_address[2:0] != 3'd7);
wire        acc_register  = !io_address[5] && !io_address[4];
wire        acc_dataport  = !io_address[5] &&  io_address[4] && !io_address[3];
wire        acc_resetport = !io_address[5] &&  io_address[4] &&  io_address[3];

function [14:0] host_word_addr;
    input [5:0] a;
    begin
        if (DEBUG_APERTURE[0] && a[5])
            host_word_addr = 15'h0630 + {11'd0, a[2:0], 1'b0};   // debug regs
        else if (!a[4])
            host_word_addr = 15'h0600 + {10'd0, a[3:0], 1'b0};   // DP8390 regs
        else if (!a[3])
            host_word_addr = 15'h0620;                           // data port
        else
            host_word_addr = 15'h063E;                           // reset port
    end
endfunction

wire acc_mapped   = acc_register | acc_dataport | acc_resetport | acc_debug;
wire access_start = io_read | io_write;

// ---------------------------------------------------------------------------
// Access latch: hold the core strobes until it acknowledges
// ---------------------------------------------------------------------------

reg         busy;
reg         lat_mapped;
reg         lat_rd;
reg         lat_wr;
reg         lat_word;
reg  [14:0] lat_addr;
reg  [15:0] lat_wdata;
reg  [11:0] watchdog;

wire [15:0] core_rdata;
wire        core_ack_n;

always @(posedge clk) begin
    if (reset) begin
        busy      <= 1'b0;
        lat_mapped<= 1'b0;
        lat_rd    <= 1'b0;
        lat_wr    <= 1'b0;
        lat_word  <= 1'b0;
        lat_addr  <= 15'h0000;
        lat_wdata <= 16'h0000;
        watchdog  <= 12'd0;
        io_readdata <= 32'h00000000;
    end
    else if (!busy) begin
        if (access_start) begin
            busy      <= 1'b1;
            lat_mapped<= acc_mapped;
            lat_rd    <= io_read;
            lat_wr    <= io_write;
            lat_word  <= io_32;
            lat_addr  <= host_word_addr(io_address);
            lat_wdata <= io_32 ? io_writedata[15:0] : {8'h00, io_writedata[7:0]};
            watchdog  <= WATCHDOG_CYCLES;
        end
    end
    else if (!lat_mapped) begin
        // Unmapped offset inside the decoded window: terminate as open bus so a
        // guest probe cannot stall, and never let it reach the core.
        io_readdata <= 32'hFFFFFFFF;
        busy   <= 1'b0;
        lat_rd <= 1'b0;
        lat_wr <= 1'b0;
    end
    else begin
        watchdog <= watchdog - 12'd1;

        if (!core_ack_n) begin
            // Byte accesses take the low lane; word data-port accesses take both.
            io_readdata <= lat_word ? {16'h0000, core_rdata}
                                    : {24'h000000, core_rdata[7:0]};
            busy   <= 1'b0;
            lat_rd <= 1'b0;
            lat_wr <= 1'b0;
        end
        else if (watchdog == 12'd0) begin
            // Bounded escape: retire the cycle as open bus rather than hang.
            io_readdata <= 32'hFFFFFFFF;
            busy   <= 1'b0;
            lat_rd <= 1'b0;
            lat_wr <= 1'b0;
        end
    end
end

assign io_wait = busy;

// ---------------------------------------------------------------------------
// Core instance
// ---------------------------------------------------------------------------
//
// host_cyc_n frames the access (68k AS equivalent).  Byte lanes: low only for
// byte accesses, both for 16-bit data-port accesses.

wire access_active = busy & lat_mapped & (lat_rd | lat_wr);

ne2000_core u_core
(
    .clk              (clk),
    .reset            (reset),

    .host_addr        (lat_addr),
    .host_wdata       (lat_wdata),
    .host_rdata       (core_rdata),
    .host_rd          (busy & lat_rd),
    .host_wr_hi       (busy & lat_wr & lat_word),
    .host_wr_lo       (busy & lat_wr),
    .host_cyc_n       (~access_active),
    .host_be_hi_n     (~(access_active & lat_word)),
    .host_be_lo_n     (~access_active),

    .host_sel_priv    (1'b0),          // the HPS mailbox is never CPU-visible here
    .host_sel         (access_active),

    .eth_dma_ready    (eth_dma_ready),
    .eth_dma_rdata    (eth_dma_rdata),
    .eth_dma_rdata64  (eth_dma_rdata64),
    .eth_dma_req      (eth_dma_req),
    .eth_dma_write    (eth_dma_write),
    .eth_dma_addr     (eth_dma_addr),
    .eth_dma_wdata    (eth_dma_wdata),
    .eth_dma_wide     (eth_dma_wide),
    .eth_dma_wdata64  (eth_dma_wdata64),
    .eth_dma_uds      (eth_dma_uds),
    .eth_dma_lds      (eth_dma_lds),

    .irq              (irq),
    .host_ack_n       (core_ack_n)
);

endmodule
