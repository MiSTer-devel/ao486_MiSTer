// ne2000_core.v -- NE2000 / RTL8019AS device model, bus-agnostic.
//
// Extracted in Phase 2 of NE2000_AO486_PLAN.md from the Minimig-AGA
// `ethernet_interface` module (apolkosnik/Minimig-AGA_MiSTer, branch
// Ethernet_shmem2, commit 9598b936; GPL).  The extraction is a pure
// identifier rename: the Amiga-specific bus signals became a generic host port,
// and no behaviour was changed.  Equivalence against the original is proven by
// running the vendored bench suite through ne2000_amiga_glue.v
// (`make -C sim/iverilog/ne2000 equiv`).
//
// ---------------------------------------------------------------------------
// Host port contract
// ---------------------------------------------------------------------------
//
//   host_addr[15:1]  word address of the access, inside the canonical device
//                    offset map below (byte offset = host_addr << 1)
//   host_sel         the access targets this device
//   host_sel_priv    the access falls in the private HPS-mailbox offsets; the
//                    device terminates it but performs no register action
//   host_rd          read strobe (level, held for the cycle)
//   host_wr_hi/lo    write strobe per byte lane (D[15:8] / D[7:0])
//   host_cyc_n       active-low "bus cycle is still selected".  Frames data-port
//                    side effects so exactly one transfer happens per host
//                    cycle, even if host_rd/host_wr glitch inside it.
//   host_be_hi_n     active-low byte enable for D[15:8]
//   host_be_lo_n     active-low byte enable for D[7:0]
//   host_wdata/rdata 16-bit data.  Register reads are placed on the enabled
//                    lane(s); when both lanes are enabled the byte is mirrored.
//   host_ack_n       active-low transfer acknowledge (0 = data valid / accepted)
//   irq              level interrupt request, = |(ISR & IMR)
//
// A 68k host maps AS/UDS/LDS/DTACK straight onto host_cyc_n / host_be_*_n /
// host_ack_n (see ne2000_amiga_glue.v).  An ISA/x86 host synthesises them from
// the I/O cycle (see ne2000_isa.v, Phase 3) and drives one lane per byte port.
//
// Canonical device offset map (byte offsets, as decoded below):
//   0x0C00-0x0C3F  DP8390 registers, 4 bytes per register
//   0x0C40-0x0C5B  remote-DMA data port
//   0x0C5C-0x0C5F  link/media status
//   0x0C60-0x0C7B  debug snapshot registers
//   0x0C7C-0x0C7F  reset port
//   0x0C80/0x8880/0x8C80  wide data-port aliases (X-Surf driver paths)
//   0x1000-0xFFFF  private HPS mailbox offsets (host_sel_priv)
// A non-Amiga host does not have to expose this map; its glue synthesises these
// offsets from whatever addressing the host bus uses.
//
// Byte order: DCR.BOS (bit 1) is honoured -- it drives the data-port swap on
// packet-RAM writes, packet-RAM reads and PROM reads (see dcr_byte_swap and
// maybe_swap_word below), XORed with the 32-bit port accesses, which swap
// independently.
//
// BUT the polarity as vendored is INVERTED with respect to a real DP8390.
// Measured by sim/iverilog/ne2000/tb_ne2000_bos.v (test T2.2), with the first
// wire byte at the even packet-RAM address:
//
//     BOS=0 -> first byte in D[15:8]   (a real NE2000 puts it in D[7:0])
//     BOS=1 -> first byte in D[7:0]    (a real NE2000 puts it in D[15:8])
//
// x86 guests program BOS=0 and expect low-byte-first, so they would see every
// frame byte-swapped. The BOS_INVERT parameter selects which convention this
// instance uses; the Amiga glue keeps 0 (vendored behaviour), ne2000_isa.v
// uses 1 (standard DP8390 behaviour).


/* verilator lint_off DECLFILENAME */
module ne2000_core
#(
    // Data-port byte order.
    //
    // 1 = standard DP8390 semantics (the default, and what ao486 needs):
    //     BOS=0 is 8086 order -- the first packet-RAM byte arrives in D[7:0] --
    //     and BOS=1 is 68000 order.  x86 guests program BOS=0.
    // 0 = the polarity as vendored from Minimig, which is inverted with respect
    //     to a real DP8390.  Kept only so the imported behaviour is still
    //     reachable and documented; nothing in the ao486 build uses it.
    //
    // Measured, not assumed -- see sim/iverilog/ne2000/tb_ne2000_bos.v (T2.2).
    parameter BOS_INVERT = 1'b1
)
(
    input wire clk,
    input wire reset,

    // Generic host bus interface (see contract above)
    input  wire [15:1] host_addr,
    input  wire [15:0] host_wdata,
    output reg  [15:0] host_rdata,
    input  wire        host_rd,
    input  wire        host_wr_hi,
    input  wire        host_wr_lo,
    input  wire        host_cyc_n,
    input  wire        host_be_hi_n,
    input  wire        host_be_lo_n,

    // Access falls in the private HPS mailbox window (terminate, no action)
    input  wire        host_sel_priv,

    // Device select
    input  wire        host_sel,

    // External shared-memory DMA path
    input  wire        eth_dma_ready,
    input  wire [15:0] eth_dma_rdata,
    input  wire [63:0] eth_dma_rdata64,
    output reg         eth_dma_req,
    output reg         eth_dma_write,
    output reg  [15:1] eth_dma_addr,
    output reg  [15:0] eth_dma_wdata,
    output reg         eth_dma_wide,
    output reg  [63:0] eth_dma_wdata64,
    output reg         eth_dma_uds,
    output reg         eth_dma_lds,

    // Level interrupt request, |(ISR & IMR)
    output reg         irq,

    // Active-low transfer acknowledge for host register/data-port accesses
    output reg         host_ack_n
);

//   Ethernet Controller Memory Map
// #define ETH_SHMEM_ADDR   0x1FF00000 // HPS physical address for the FPGA/HPS mailbox

//   Base Address: 0xEA0000 (configurable via autoconfig)

//   Register Space (0xEA0000 - 0xEA0FFF) - local Amiga CPU I/O aperture

//   NE2000 Registers (0xEA0C00 - 0xEA0C3F) - Simplified Implementation

//   - 0xEA0C00-0xEA0C3C: NE2000 registers with 4-byte spacing
//     - 0xEA0C00: CR (Command Register)
//     - 0xEA0C04: CLDA0/PSTART (Current Local DMA Address 0 / Page Start)
//     - 0xEA0C08: CLDA1/PSTOP (Current Local DMA Address 1 / Page Stop)
//     - 0xEA0C0C: BNRY (Boundary Register)
//     - 0xEA0C10: TSR/TPSR (Transmit Status / Transmit Page Start)
//     - 0xEA0C14: NCR/TBCR0 (Number of Collisions / Transmit Byte Count 0)
//     - 0xEA0C18: FIFO/TBCR1 (FIFO / Transmit Byte Count 1)
//     - 0xEA0C1C: ISR (Interrupt Status Register)
//     - 0xEA0C20: CRDA0/RSAR0 (Current Remote DMA Address 0 / Remote Start Address 0)
//     - 0xEA0C24: CRDA1/RSAR1 (Current Remote DMA Address 1 / Remote Start Address 1)
//     - 0xEA0C28: 8019ID0/RBCR0 (RTL8019 ID0 / Remote Byte Count 0)
//     - 0xEA0C2C: 8019ID1/RBCR1 (RTL8019 ID1 / Remote Byte Count 1)
//     - 0xEA0C30: RSR (Receive Status Register)
//     - 0xEA0C34: CNTR0 (Tally Counter 0)
//     - 0xEA0C38: CNTR1 (Tally Counter 1)
//     - 0xEA0C3C: CNTR2 (Tally Counter 2)
//   - 0xEA0C40: Data Port (Remote DMA port)
//   - 0xEA0C60-0xEA0C78: Debug snapshot registers
//     - 0xEA0C60: Remote DMA address low
//     - 0xEA0C64: Remote DMA address high
//     - 0xEA0C68: Remote byte count low
//     - 0xEA0C6C: Remote byte count high
//     - 0xEA0C70: DMA/data-port status bits
//     - 0xEA0C74: HPS communication status word
//     - 0xEA0C78: Last sampled HPS heartbeat low word
//   - 0xEA0C7C: Reset Port

//   FPGA/HPS Mailbox Space (0xEA1000 - 0xEAFFFF)
//
//   This is not exposed as an Amiga CPU memory target. cpu_wrapper exports
//   host_sel_priv only as a marker for the top-level DTACK mux and for
//   diagnostics. The live transport below is accessed by HPS at 0x1FF00000
//   and by this module through the private eth_dma_* master path.

//   Control Structure (0xEA1000 - 0xEA1FFF)

//   - 0xEA1000: ETH_SHM_CTRL_FLAGS (4 bytes) - Control flags
//   - 0xEA1004: ETH_SHM_CTRL_REGS (72 bytes) - NE2000 registers (all pages + extra) - START HERE
//   - 0xEA104C: ETH_SHM_CTRL_MAC (6 bytes) - MAC address  
//   - 0xEA1052: ETH_SHM_CTRL_STATUS (2 bytes) - Status
//   - 0xEA1054: ETH_SHM_CTRL_STATS (52 bytes) - Packet statistics
//   - 0xEA1088: ETH_SHM_HPS_HEARTBEAT (4 bytes) - HPS heartbeat
//   - 0xEA108C: ETH_SHM_HPS_SIGNATURE (4 bytes) - Signature (0xCAFEBABE)

//   Packet Buffers (0xEA2000 - 0xEA2FFF)

//   - 0xEA2000: ETH_SHM_TX_BUFFER (1500 bytes) - TX packet buffer
//   - 0xEA2600: ETH_SHM_RX_BUFFER (1500 bytes) - RX packet buffer
//   - 0xEA2C00: ETH_SHM_PACKET_INFO (512 bytes) - Packet metadata
//     - +0x0000: TX packet length (HPS debug/bridge)
//     - +0x0002: staged RX packet length
//     - +0x0004: staged RX status byte (NE2000 RSR-compatible)

//   Legacy NE2000 Memory Mirror (0xEA3000 - 0xEA6FFF)

//   - 0xEA3000: ETH_SHM_NE_MEMORY (16KB) - legacy/debug mirror region.
//     The authoritative RTL8019 packet RAM now lives locally in this module.
//     - Remote DMA addresses below 0x0020 are handled locally as PROM/shadow RAM.
//     - Remote DMA addresses 0x4000-0x7FFF are handled locally through packet_ram[].
//     - Remote DMA addresses 0x0020-0x3FFF and 0x8000+ are unmapped and read as 0xFF.

//   Reserved / Debug / Future Use (0xEA7000 - 0xEAFFFF)

//   - 0xEAB000: ETH_SHM_DEBUG_INFO (4KB) - Debug information
//   - 0xEAC000: ETH_SHM_FUTURE_USE (16KB) - Reserved for expansion

//   Access Methods

//   1. Register I/O (0xEA0000-0xEA0FFF):
//     - Direct CPU read/write to NE2000 registers
//     - Data port access for packet data via Remote DMA
//   2. FPGA/HPS mailbox (0xEA1000-0xEAFFFF logical offsets):
//     - Used by HPS for packet data transfer and status updates
//     - Used by this module through eth_dma_* background transfers
//     - Amiga CPU accesses are deliberately not routed into this DDR window

//   Address Decoding Logic

//   host_sel selects the full configured 64KB card aperture. Only
//   0xEA0C00-0xEA0C7F has RTL8019 behavior; unused and mailbox offsets are
//   acknowledged as harmless dummy cycles so CPU probes cannot hang the bus.
//   host_sel_priv marks 0xEA1000-0xEAFFFF for diagnostics and HPS/FPGA
//   mailbox separation.
//   
//   This keeps the RTL8019 CPU-visible device small while still retaining the
//   64KB HPS transport ABI.

localparam [15:0] ETH_SHM_CTRL_FLAGS  = 16'h1000;
localparam [15:0] ETH_SHM_CTRL_REGS   = 16'h1004;
localparam [15:0] ETH_SHM_CTRL_MAC    = 16'h104C;
localparam [15:0] ETH_SHM_CTRL_STATUS = 16'h1052;
localparam [15:0] ETH_SHM_HPS_HEARTBEAT = 16'h1088;
localparam [15:0] ETH_SHM_HPS_SIGNATURE = 16'h108C;
localparam [15:0] ETH_RTL8019_STATE   = 16'h1100;
localparam [15:0] ETH_PACKET_BUFFER_SIZE = 16'h0600;
localparam [15:0] ETH_SHM_TX_BUFFER   = 16'h2000;
localparam [15:0] ETH_SHM_RX_BUFFER   = 16'h2600;
localparam [15:0] ETH_SHM_PACKET_INFO = 16'h2C00;
localparam [15:0] ETH_SHM_TX_REQUEST_ADDR = 16'h2C00;
localparam [15:0] ETH_SHM_TX_REQUEST_LEN  = 16'h2C02;
localparam [15:0] ETH_SHM_RX_QUEUE_HEAD   = 16'h2C04;
localparam [15:0] ETH_SHM_RX_QUEUE_TAIL   = 16'h2C06;
localparam [15:0] ETH_SHM_TX_REQUEST_SEQ  = 16'h2C08;
localparam [15:0] ETH_SHM_TX_COMPLETE_SEQ = 16'h2C0A;
localparam [15:0] ETH_SHM_RX_QUEUE_LEN    = 16'h2C20;
localparam [15:0] ETH_SHM_RX_QUEUE_DATA   = 16'h9000;
localparam [15:0] ETH_RX_QUEUE_SLOTS      = 16'h0010;
// TX ring (Fix B): the guest stages each transmit into a per-seq slot so a
// download's ACK storm cannot overwrite the single buffer before the daemon
// sends it. slot = TX_REQUEST_SEQ % 8. PTX is reported after staging (not at
// command time, not after the daemon ack) so page 0x40 is safe to reuse and RX
// is not starved. Slots (8 x 1536) sit in the free window region above the
// control block and below the RX data; the per-slot length array follows the RX
// length array.
localparam [15:0] ETH_SHM_TX_SLOT_LEN     = 16'h2C40;   // 8 x u16
localparam [15:0] ETH_SHM_TX_SLOT_DATA    = 16'h3000;   // 8 x 1536
localparam [15:0] ETH_TX_SLOT_BYTES       = 16'h0600;   // 1536
localparam integer ETH_TX_SLOTS_LOG2      = 3;          // 8 slots
localparam [15:0] ETH_FLAG_TX_REQ     = 16'h0200;   // FPGA-owned (high byte)
localparam [15:0] ETH_FLAG_RX_AVAIL   = 16'h0004;
localparam [15:0] ETH_FLAG_IRQ        = 16'h0800;   // FPGA-owned (high byte)
localparam [15:0] ETH_FLAG_ENABLED    = 16'h2000;   // FPGA-owned (high byte)
localparam [15:0] ETH_STATUS_FPGA_SAMPLED    = 16'h0100;
localparam [15:0] ETH_STATUS_FPGA_SIGNATURE  = 16'h0200;
localparam [15:0] ETH_STATUS_FPGA_HEARTBEAT  = 16'h0400;
localparam [15:0] ETH_STATUS_FPGA_HB_CHANGED = 16'h0800;
localparam [15:0] ETH_STATUS_FPGA_COMM_OK    = 16'h1000;
localparam [15:0] ETH_STATUS_FPGA_RX_ACTIVE  = 16'h2000;
localparam [15:0] ETH_STATUS_FPGA_TX_PENDING = 16'h4000;
localparam [15:0] NE_PMEM_START       = 16'h4000;
localparam [15:0] NE_PMEM_END         = 16'h8000;
localparam [7:0]  NE_PAGE_BASE = 8'h40;
localparam [7:0]  DEFAULT_TX_PAGE = 8'h40;
localparam [7:0]  DEFAULT_RX_START_PAGE = 8'h46;
localparam [7:0]  DEFAULT_RX_STOP_PAGE = 8'h80;
localparam [7:0]  BG_POLL_RELOAD = 8'd63;
localparam [9:0]  ETH_DMA_TIMEOUT_CYCLES = 10'd511;
localparam [9:0]  DATA_PORT_TIMEOUT_CYCLES = 10'd511;
localparam [7:0]  DEFAULT_MAC0 = 8'h52;
localparam [7:0]  DEFAULT_MAC1 = 8'h54;
localparam [7:0]  DEFAULT_MAC2 = 8'h05;
localparam [7:0]  DEFAULT_MAC3 = 8'h04;
localparam [7:0]  DEFAULT_MAC4 = 8'h03;
localparam [7:0]  DEFAULT_MAC5 = 8'h02;
localparam [7:0]  HPS_POLL_RELOAD = 8'hFF;
localparam [15:0] ETH_SHM_HPS_HEARTBEAT_HI = ETH_SHM_HPS_HEARTBEAT + 16'h0002;
localparam [15:0] ETH_SHM_HPS_SIGNATURE_HI = ETH_SHM_HPS_SIGNATURE + 16'h0002;
localparam [15:0] ETH_RX_QUEUE_INDEX_MASK = ETH_RX_QUEUE_SLOTS - 16'h0001;

reg [7:0]  cr_register;
wire [1:0] current_page = cr_register[7:6];

wire       host_wr = host_wr_lo | host_wr_hi;
wire [7:0] host_write_byte = ~host_be_hi_n ? host_wdata[15:8] : host_wdata[7:0];
wire       is_data_port_access;
wire       is_register_access;
wire       is_debug_port_access;
wire       is_reset_port_access;

reg [15:0] remote_dma_addr;
reg [15:0] remote_byte_count;
reg        data_port_read_pending;
reg        data_port_write_pending;
reg        data_port_transfer_done;
reg        data_port_cycle_active;
reg        data_port_bus_active_prev;
reg [15:0] data_port_read_data;
reg [15:0] data_port_byte_addr;
reg        data_port_word_mode;
reg        tx_complete_pending;
reg        tx_abort_pending;    // BF-7: transmit issued with no live transport

// NE2000 Interrupt handling - proper implementation
reg [7:0]  isr_register;       // Interrupt Status Register (0x07)
reg [7:0]  imr_register;       // Interrupt Mask Register (0x0F)
reg [7:0]  dcr_register;

// Effective data-port byte swap.  See the BOS_INVERT parameter: the vendored
// Minimig behaviour is swap == DCR.BOS, which is the OPPOSITE of a real DP8390.
// BOS_INVERT=1 restores standard semantics for little-endian hosts.
wire       dcr_byte_swap = dcr_register[1] ^ BOS_INVERT[0];
reg [7:0]  pstart_register;
reg [7:0]  pstop_register;
reg [7:0]  bnry_register;
reg [7:0]  tpsr_register;
reg [15:0] tbcr_register;
reg [7:0]  tsr_register;
reg [7:0]  rsr_register;
reg [7:0]  cntr0_register;
reg [7:0]  cntr1_register;
reg [7:0]  cntr2_register;
reg [7:0]  curr_register;
reg [7:0]  tcr_register;
reg [7:0]  rcr_register;
reg [7:0]  rtl8019_config0;
reg [7:0]  rtl8019_config1;
reg [7:0]  rtl8019_config2;
reg [7:0]  rtl8019_config3;
reg [7:0]  rtl8019_e9346cr;
reg        rx_poll_enabled;
reg        shm_sync_enabled;
reg        tx_request_pending;
reg [15:0] tx_stage_addr;
reg [15:0] tx_stage_len;
reg [15:0] tx_request_seq;
reg [15:0] mirrored_fpga_flags;
reg [7:0]  par_registers [0:5];
reg [7:0]  mar_registers [0:7];
reg [7:0]  reset_port_latch;
reg [5:0]  bg_state;
reg [7:0]  bg_poll_counter;
reg [7:0]  hps_poll_counter;
reg        bg_dma_inflight;
reg [15:0] bg_flags_word;
reg [15:0] bg_rx_queue_head;
reg [15:0] bg_rx_head_seen_shm;  // what the window claims; diagnostics only
reg        queue_init_done;      // RX head published once after reset
reg  [1:0] mac_word_idx;         // which of the three MAC words is in flight
reg [47:0] mac_from_host;        // assembled host-provisioned MAC
reg [15:0] bg_rx_queue_tail;
reg [15:0] bg_rx_queue_next_head;
reg [15:0] bg_rx_total_length;
reg [15:0] bg_rx_src_offset;
reg [15:0] bg_rx_dst_offset;
reg [15:0] bg_rx_bytes_remaining;
// Integrity probe: running 16-bit byte-sum of every RX PAYLOAD byte the bg writes
// into the ring (the bytes it actually read from shm via the mailbox). Exposed
// through sync slot 40 (shm ETH_RTL8019_STATE+0x0A); the daemon keeps the same
// running sum of frame bytes it enqueued and compares at quiescence. A divergence
// means a frame was corrupted in shm->bg (mailbox/CDC) -- it does NOT see
// ring->Amiga (data-port read) corruption, which is checked separately.
// Integrity probe: count of RX frames fully written to the ring. Published
// (slot 41) alongside bg_rx_csum_run (slot 40) so the daemon can compare the
// two running byte-sums ONLY at a matched frame count (bg caught up to what the
// daemon enqueued) -- the count makes a "sums match" verdict trustworthy
// instead of being confounded by an unknown origin offset.
// Read-side integrity probe: ring_wr_csum sums EVERY byte the bg WRITES into the
// ring (port A, header+payload); dp_rd_csum sums EVERY byte the CPU data-port
// READ hands the 68k (port B). At a ring drain (68k caught up) they match iff the
// 68k reads the ring intact -- this splits a data-port READ corruption (RTL-
// fixable) from an Amiga-side drop. Published slots 42/43 (0x110E/0x1110).
// PER-FRAME read-corruption probe (definitive, no peek confound): the bg stores
// each RX frame's PAYLOAD checksum keyed by its ring start page as it writes it
// (frame_wr_csum[page] <= bg_rx_csum_frame). When the 68k issues the PAYLOAD read
// (the large remote-DMA burst, distinguished from the 4-byte header peeks by
// count>8), the FPGA re-sums exactly the bytes it hands over and compares to the
// stored value; a mismatch (rd_corrupt++) proves the data-port READ corrupted the
// frame. Published slot 44 (0x1112).
// Keep this diagnostic table as deterministic logic, not inferred MLAB RAM.
// The bg writes it when a frame is committed while the CPU side may read another
// page's checksum when arming a remote-DMA payload read. Hardware MLAB read/write
// behavior under that mixed access is not a trustworthy probe source; if this
// table is unstable, rdCorrupt can become a false positive even when packet RAM
// itself is fine.
reg        dp_rd_in_payload;   // a payload read burst is in progress
reg [7:0]  bg_rx_next_page;
reg [7:0]  bg_rx_status;
reg [15:0] bg_source_word;
// 64-bit "wide" packing buffer for the payload copy: holds four 16-bit words
// (lane0=[15:0]..lane3=[63:48]) moved per single mailbox transfer; bg_wide_idx
// walks the four words during the local packet-RAM read/write half-cycles.
reg [63:0] bg_wide_buf;
reg [1:0]  bg_wide_idx;
wire [15:0] bg_source_word_sum = {8'h0, bg_source_word[7:0]} + {8'h0, bg_source_word[15:8]};
wire [15:0] bg_source_tail_sum = {8'h0, bg_source_word[15:8]};
reg [5:0]  bg_sync_slot;
// Incremental register-mirror sync: the FPGA exclusively writes the synced
// CTRL_REGS/MAC/STATE slots (the daemon only reads them, and writes only the
// disjoint trailing stats), so a slot whose value is unchanged since the last
// sync is already correct in shm and need not be re-written.  sync_shadow holds
// the last value written per slot; only changed slots cost a mailbox round-trip.
// shadow_valid marks slots whose shadow has been populated at least once; an
// unvalidated slot is always written (and validated) the first time it is seen,
// so coverage does not depend on any single sync pass running 0..40 to
// completion (re-arming resets the slot index, which would otherwise restart a
// pass-based "force full" indefinitely under steady traffic).
// Keep this as logic registers (not an inferred block RAM): the FSM reads a slot
// combinationally in the same cycle it may write it, and the compare must see the
// OLD value -- forcing ramstyle=logic guarantees synthesis matches the simulated
// (combinational-read, non-blocking-write) behavior.
(* ramstyle = "logic" *) reg [15:0] sync_shadow [0:49];
reg [49:0] shadow_valid;
reg        bg_polling_rx_flags;
reg        bg_clear_rx_avail;
// TCR.LB=01 internal-loopback local copy (see BG_LOOP_* above).
// loop_copy_pending: set by the TX-complete handler, consumed once from
// BG_IDLE (mirrors tx_stage_pending/tx_request_pending's own pending flags).
// bg_loop_copy: true for the duration of the copy itself; read at the three
// branch points inside BG_WRITE_HDR1_REQ/BG_WRITE_PAYLOAD_REQ so they source
// the next word locally (BG_LOOP_READ_REQ) instead of from the HPS mailbox
// (BG_READ_PAYLOAD_REQ) and skip the HPS ring-head publish on completion.
reg        loop_copy_pending;
reg        bg_loop_copy;
reg [7:0]  prom_shadow [0:31];
// Port A -- background FSM (RX ring write / TX buffer read)
reg [12:0]  pmem_addr_a;
reg [15:0]  pmem_wdata_a;
reg [1:0]   pmem_byteena_a;
reg         pmem_wren_a;
wire [15:0] pmem_q_a;
// Port B -- CPU data-port (RX ring read / TX buffer write)
reg [12:0]  pmem_addr_b;
reg [15:0]  pmem_wdata_b;
reg [1:0]   pmem_byteena_b;
reg         pmem_wren_b;
wire [15:0] pmem_q_b;
// FPGA debug disabled to reduce Quartus build time.
// reg [15:0] debug_heartbeat;
// reg [15:0] debug_local_wait_cycles;
// reg [15:0] debug_dma_wait_cycles;
// reg [14:0] debug_sticky_flags_lo;
reg        debug_dma_timeout_sticky;
reg [9:0]  eth_dma_wait_counter;
reg [9:0]  data_port_wait_counter;
reg        tx_stage_pending;
reg [15:0] bg_tx_src_offset;
reg [15:0] bg_tx_bytes_remaining;
reg        local_pmem_read_wait;
reg        data_port_dport32;   // latched: this deferred pmem read is via a 32-bit port (needs per-word swap)
reg [15:0] bg_hps_heartbeat_lo;
reg [15:0] bg_hps_signature_lo;
reg [31:0] hps_heartbeat_seen;
reg [31:0] hps_signature_seen;
reg        hps_status_sampled;
reg        hps_heartbeat_change_seen;
integer    i;

// NE2000 DCR bit definitions
// Bit 0: WTS (Word Transfer Select) - 0=byte DMA, 1=word DMA
// Bit 1: BOS (Byte Order Select) - 0=MSB first, 1=LSB first (8086 mode)
// Bit 2: LAS (Long Address Select) - 0=dual 16-bit DMA, 1=single 32-bit DMA
// Bit 3: LS (Loopback Select) - 0=normal, 1=loopback
// Bit 4: ARM (Auto-initialize Remote) - 0=manual, 1=auto-init remote DMA
// Bit 5: FT0 (FIFO Threshold Select 0)
// Bit 6: FT1 (FIFO Threshold Select 1)
// Bit 7: Reserved

// NE2000 ISR bit definitions
localparam ISR_PRX = 8'h01;     // Bit 0: Packet received
localparam ISR_PTX = 8'h02;     // Bit 1: Packet transmitted
localparam ISR_OVW = 8'h10;     // Bit 4: Receive ring overrun
localparam ISR_RDC = 8'h40;     // Bit 6: Remote DMA Complete
localparam ISR_RST = 8'h80;     // Bit 7: Reset status
localparam ISR_TXE = 8'h08;     // Bit 3: Transmit error
localparam TSR_ABT = 8'h08;     // Bit 3: Transmission aborted
localparam TSR_PTX = 8'h01;     // Bit 0: Packet transmitted without error
localparam RSR_PRX = 8'h01;     // Bit 0: Packet received without error
localparam RSR_MPA = 8'h10;     // Bit 4: Missed packet
localparam RSR_PHY = 8'h20;     // Bit 5: Physical/multicast address match

localparam [5:0] BG_IDLE                = 6'd0;
localparam [5:0] BG_READ_FLAGS_REQ      = 6'd1;
localparam [5:0] BG_READ_FLAGS_WAIT     = 6'd2;
localparam [5:0] BG_READ_RX_LEN_REQ     = 6'd3;
localparam [5:0] BG_READ_RX_LEN_WAIT    = 6'd4;
localparam [5:0] BG_WRITE_HDR0_REQ      = 6'd7;
localparam [5:0] BG_WRITE_HDR1_REQ      = 6'd9;
localparam [5:0] BG_READ_PAYLOAD_REQ    = 6'd11;
localparam [5:0] BG_READ_PAYLOAD_WAIT   = 6'd12;
localparam [5:0] BG_WRITE_PAYLOAD_REQ   = 6'd13;
localparam [5:0] BG_CLEAR_FLAG_REQ      = 6'd15;
localparam [5:0] BG_CLEAR_FLAG_WAIT     = 6'd16;
localparam [5:0] BG_SYNC_WORD_REQ       = 6'd17;
localparam [5:0] BG_SYNC_WORD_WAIT      = 6'd18;
localparam [5:0] BG_WRITE_TX_LEN_REQ    = 6'd19;
localparam [5:0] BG_WRITE_TX_LEN_WAIT   = 6'd20;
localparam [5:0] BG_WRITE_TX_BUF_REQ    = 6'd21;
localparam [5:0] BG_WRITE_TX_BUF_WAIT   = 6'd22;
localparam [5:0] BG_READ_HPS_HB_LO_REQ  = 6'd23;
localparam [5:0] BG_READ_HPS_HB_LO_WAIT = 6'd24;
localparam [5:0] BG_READ_HPS_HB_HI_REQ  = 6'd25;
localparam [5:0] BG_READ_HPS_HB_HI_WAIT = 6'd26;
localparam [5:0] BG_READ_HPS_SIG_LO_REQ = 6'd27;
localparam [5:0] BG_READ_HPS_SIG_LO_WAIT= 6'd28;
localparam [5:0] BG_READ_HPS_SIG_HI_REQ = 6'd29;
localparam [5:0] BG_READ_HPS_SIG_HI_WAIT= 6'd30;
localparam [5:0] BG_WRITE_STATUS_REQ    = 6'd31;
localparam [5:0] BG_WRITE_STATUS_WAIT   = 6'd32;
localparam [5:0] BG_READ_TX_BUF_REQ     = 6'd33;
localparam [5:0] BG_READ_TX_BUF_WAIT1   = 6'd34;
localparam [5:0] BG_READ_TX_BUF_WAIT2   = 6'd35;
localparam [5:0] BG_WRITE_TX_ADDR_REQ   = 6'd36;
localparam [5:0] BG_WRITE_TX_ADDR_WAIT  = 6'd37;
localparam [5:0] BG_WRITE_TX_SEQ_REQ    = 6'd38;
localparam [5:0] BG_WRITE_TX_SEQ_WAIT   = 6'd39;
localparam [5:0] BG_READ_TX_DONE_REQ    = 6'd40;
localparam [5:0] BG_READ_TX_DONE_WAIT   = 6'd41;
localparam [5:0] BG_READ_RX_HEAD_REQ    = 6'd42;
localparam [5:0] BG_READ_RX_HEAD_WAIT   = 6'd43;
localparam [5:0] BG_READ_RX_TAIL_REQ    = 6'd44;
localparam [5:0] BG_READ_RX_TAIL_WAIT   = 6'd45;
localparam [5:0] BG_WRITE_RX_HEAD_REQ   = 6'd46;
localparam [5:0] BG_WRITE_RX_HEAD_WAIT  = 6'd47;
// 64-bit "wide" packing states: move 4 payload words (one full DDR word) per
// mailbox round-trip instead of one 16-bit word, cutting RX/TX copy round-trips
// ~4x.  Used only for the aligned bulk (>= 8 bytes left); the final <=8 bytes
// fall back to the proven narrow states so byte-order / odd-byte behaviour is
// byte-identical to before.
// RX payload DDR read width. 0 = word/narrow (correct on hardware), 1 = 64-bit
// wide burst (faster, but reads back as zeros on real DDR -- see BG_WRITE_HDR1_REQ).
localparam RX_WIDE_READ = 1'b1;   // wide RX (fast). BF-9 root cause was a missing
                                  // eth_dma_rdata64 wire in ao486.sv/system.v.
localparam [5:0] BG_READ_PAYLOAD_WIDE_REQ  = 6'd48;
localparam [5:0] BG_READ_PAYLOAD_WIDE_WAIT = 6'd49;
localparam [5:0] BG_WRITE_PAYLOAD_WIDE     = 6'd50;
localparam [5:0] BG_READ_TX_WIDE_REQ       = 6'd51;
localparam [5:0] BG_READ_TX_WIDE_WAIT1     = 6'd52;
localparam [5:0] BG_READ_TX_WIDE_WAIT2     = 6'd53;
localparam [5:0] BG_WRITE_TX_WIDE_REQ      = 6'd54;
localparam [5:0] BG_WRITE_TX_WIDE_WAIT     = 6'd55;
// Step 3: one-shot publish of the RX consumer index after reset. Dedicated
// states rather than reusing BG_WRITE_RX_HEAD_*, whose completion path assumes
// it is mid-drain and would try to consume a frame that does not exist.
localparam [5:0] BG_INIT_HEAD_REQ          = 6'd56;
localparam [5:0] BG_INIT_HEAD_WAIT         = 6'd57;
// Step 5: fetch the station MAC the host provisioned, once, at init.
localparam [5:0] BG_INIT_MAC_REQ           = 6'd58;
localparam [5:0] BG_INIT_MAC_WAIT          = 6'd59;

// TCR.LB=01 (NIC/internal loopback): copy the just-transmitted frame straight
// from the TX page into the next RX ring page over packet-RAM port A, no HPS
// mailbox involved -- matches a real DP8390, which loops the frame inside the
// chip and still drives it through the genuine receive datapath (see
// NE2000_AO486_PLAN.md addendum). Read side only; the write side reuses
// BG_WRITE_HDR0_REQ/BG_WRITE_HDR1_REQ/BG_WRITE_PAYLOAD_REQ unchanged (they
// already just consume bg_source_word/bg_rx_* regardless of where the word
// came from), gated by bg_loop_copy at their three continue/finalize branch
// points so the proven HPS-fed path is untouched when bg_loop_copy is 0.
localparam [5:0] BG_LOOP_READ_REQ          = 6'd60;
localparam [5:0] BG_LOOP_READ_WAIT1        = 6'd61;
localparam [5:0] BG_LOOP_READ_WAIT2        = 6'd62;

wire [7:0] cr_write_value = host_write_byte;
wire       rtl8019_config_write_enable = (rtl8019_e9346cr[7:6] == 2'b11);
wire [2:0] cr_remote_dma_cmd = cr_register[5:3];
wire [2:0] cr_write_remote_dma_cmd = cr_write_value[5:3];
wire       cr_remote_dma_read = (cr_remote_dma_cmd == 3'b001);
wire       cr_remote_dma_write = (cr_remote_dma_cmd == 3'b010);
wire       cr_write_remote_dma_read = (cr_write_remote_dma_cmd == 3'b001);
wire       cr_write_remote_dma_write = (cr_write_remote_dma_cmd == 3'b010);
wire       cr_write_remote_dma_abort = (cr_write_remote_dma_cmd == 3'b100);

task automatic apply_nic_reset;
    begin
        cr_register <= 8'h21;
        remote_dma_addr <= 16'h0000;
        remote_byte_count <= 16'h0000;
        data_port_read_pending <= 1'b0;
        data_port_write_pending <= 1'b0;
        data_port_transfer_done <= 1'b0;
        data_port_cycle_active <= 1'b0;
        data_port_bus_active_prev <= 1'b0;
        data_port_read_data <= 16'h0000;
        local_pmem_read_wait <= 1'b0;
        data_port_byte_addr <= 16'h0000;
        data_port_word_mode <= 1'b0;
        tx_complete_pending <= 1'b0;
        tx_abort_pending <= 1'b0;
        isr_register <= ISR_RST;
        imr_register <= 8'h00;
        dcr_register <= 8'h80;
        pstart_register <= DEFAULT_RX_START_PAGE;
        pstop_register <= DEFAULT_RX_STOP_PAGE;
        bnry_register <= DEFAULT_RX_START_PAGE;
        tpsr_register <= DEFAULT_TX_PAGE;
        tbcr_register <= 16'h0000;
        tsr_register <= 8'h00;
        rsr_register <= 8'h00;
        cntr0_register <= 8'h00;
        cntr1_register <= 8'h00;
        cntr2_register <= 8'h00;
        curr_register <= DEFAULT_RX_START_PAGE + 8'h01;
        tcr_register <= 8'h00;
        rcr_register <= 8'h00;
        rtl8019_config0 <= 8'h00;
        rtl8019_config1 <= 8'h80;
        rtl8019_config2 <= 8'h40;
        rtl8019_config3 <= 8'h40;
        rtl8019_e9346cr <= 8'h00;
        rx_poll_enabled <= 1'b0;
        shm_sync_enabled <= 1'b1;
        tx_request_pending <= 1'b0;
        tx_stage_addr <= {DEFAULT_TX_PAGE, 8'h00};
        tx_stage_len <= 16'h0000;
        // NB: tx_request_seq is NOT cleared here. It is a transport-lifetime
        // counter the HPS daemon tracks for edge detection; a guest NIC soft
        // reset (reset-port read) calls apply_nic_reset() every transmit run,
        // and zeroing the seq made every run restart at 1, colliding with the
        // daemon's last-seen value so only the first frame after a restart was
        // ever sent. Cleared only on hard core reset (see the `if (reset)`
        // branch), which also clears the shared window.
        mirrored_fpga_flags <= 16'h0000;
        bg_state <= BG_IDLE;
        bg_poll_counter <= 8'h00;
        hps_poll_counter <= 8'h00;
        bg_dma_inflight <= 1'b0;
        bg_flags_word <= 16'h0000;
        bg_rx_queue_head <= 16'h0000;
        bg_rx_head_seen_shm <= 16'h0000;
        queue_init_done <= 1'b0;
        mac_word_idx <= 2'd0;
        mac_from_host <= 48'h000000000000;
        bg_rx_queue_tail <= 16'h0000;
        bg_rx_queue_next_head <= 16'h0000;
        bg_rx_total_length <= 16'h0000;
        bg_rx_src_offset <= 16'h0000;
        dp_rd_in_payload <= 1'b0;
        bg_rx_dst_offset <= 16'h0000;
        bg_rx_bytes_remaining <= 16'h0000;
        bg_rx_next_page <= 8'h00;
        bg_rx_status <= 8'h00;
        bg_source_word <= 16'h0000;
        bg_sync_slot <= 6'd0;
        shadow_valid <= 50'b0;     // force every slot to be written once after reset
        bg_polling_rx_flags <= 1'b0;
        bg_clear_rx_avail <= 1'b0;
        loop_copy_pending <= 1'b0;
        bg_loop_copy <= 1'b0;
        tx_stage_pending <= 1'b0;
        bg_tx_src_offset <= 16'h0000;
        bg_tx_bytes_remaining <= 16'h0000;
        bg_hps_heartbeat_lo <= 16'h0000;
        bg_hps_signature_lo <= 16'h0000;
        hps_heartbeat_seen <= 32'h00000000;
        hps_signature_seen <= 32'h00000000;
        hps_status_sampled <= 1'b0;
        hps_heartbeat_change_seen <= 1'b0;
        eth_dma_req <= 1'b0;
        eth_dma_write <= 1'b0;
        eth_dma_addr <= 15'h0000;
        eth_dma_wdata <= 16'h0000;
        eth_dma_wide <= 1'b0;
        eth_dma_wdata64 <= 64'h0;
        eth_dma_uds <= 1'b1;
        eth_dma_lds <= 1'b1;
        bg_wide_buf <= 64'h0;
        bg_wide_idx <= 2'd0;
        irq <= 1'b0;
        eth_dma_wait_counter <= 10'd0;
        data_port_wait_counter <= 10'd0;
        par_registers[0] <= DEFAULT_MAC0;
        par_registers[1] <= DEFAULT_MAC1;
        par_registers[2] <= DEFAULT_MAC2;
        par_registers[3] <= DEFAULT_MAC3;
        par_registers[4] <= DEFAULT_MAC4;
        par_registers[5] <= DEFAULT_MAC5;
        for (i = 0; i < 8; i = i + 1) begin
            mar_registers[i] <= 8'h00;
        end
        prom_shadow[0] <= DEFAULT_MAC0;
        prom_shadow[1] <= DEFAULT_MAC0;
        prom_shadow[2] <= DEFAULT_MAC1;
        prom_shadow[3] <= DEFAULT_MAC1;
        prom_shadow[4] <= DEFAULT_MAC2;
        prom_shadow[5] <= DEFAULT_MAC2;
        prom_shadow[6] <= DEFAULT_MAC3;
        prom_shadow[7] <= DEFAULT_MAC3;
        prom_shadow[8] <= DEFAULT_MAC4;
        prom_shadow[9] <= DEFAULT_MAC4;
        prom_shadow[10] <= DEFAULT_MAC5;
        prom_shadow[11] <= DEFAULT_MAC5;
        prom_shadow[12] <= 8'h00;
        prom_shadow[13] <= 8'h00;
        prom_shadow[14] <= 8'h00;
        prom_shadow[15] <= 8'h00;
        prom_shadow[16] <= 8'h00;
        prom_shadow[17] <= 8'h00;
        prom_shadow[18] <= 8'h00;
        prom_shadow[19] <= 8'h00;
        prom_shadow[20] <= 8'h00;
        prom_shadow[21] <= 8'h00;
        prom_shadow[22] <= 8'h00;
        prom_shadow[23] <= 8'h00;
        prom_shadow[24] <= 8'h00;
        prom_shadow[25] <= 8'h00;
        prom_shadow[26] <= 8'h00;
        prom_shadow[27] <= 8'h00;
        prom_shadow[28] <= 8'h57;
        prom_shadow[29] <= 8'h57;
        prom_shadow[30] <= 8'h57;
        prom_shadow[31] <= 8'h57;
    end
endtask

task automatic complete_data_port_transfer;
    input [15:0] dma_read_word;
    reg [15:0] read_word;
    begin
        // DCR.BOS applies to 16-bit transfers only. On a real DP8390 an 8-bit
        // transfer has no byte order, and this path picks its byte out of
        // read_word by address AFTER the swap -- so swapping in byte mode
        // returns the neighbouring byte. Hardware 2026-07-28: AA,BB written to
        // 0x4000 read back as BB,AA. data_port_word_mode is the mode latched
        // when the transfer was armed, which is what the byte select below uses.
        read_word = maybe_swap_word(dma_read_word,
                                    (dcr_byte_swap & data_port_word_mode) ^ data_port_dport32);

        // Capture the read result for data-port READ completions. This used to
        // gate on !eth_dma_write back when the data port itself drove eth_dma,
        // but eth_dma_write now belongs to the background FSM and is frequently
        // left high after a bg mailbox write. Gating on it caused data-port
        // reads that completed while the bg was active to skip capturing pmem_q,
        // returning stale 0x0000 (xsurftest "Testing 16bit memory" read back all
        // zeros). Use the data-port's own direction instead.
        if (!data_port_write_pending) begin
            if (data_port_word_mode) begin
                data_port_read_data <= read_word;
            end else begin
                // Mirror byte reads onto both lanes so either UDS or LDS byte access works.
                data_port_read_data <= data_port_byte_addr[0] ?
                    {read_word[7:0], read_word[7:0]} :
                    {read_word[15:8], read_word[15:8]};
            end
        end

        if (data_port_word_mode) begin
            remote_dma_addr <= ring_wrap_addr(data_port_byte_addr + 16'h0002,
                                              pstart_register, pstop_register);
            if (remote_byte_count > 16'h0002) begin
                remote_byte_count <= remote_byte_count - 16'h0002;
            end else begin
                remote_byte_count <= 16'h0000;
                isr_register <= isr_register | ISR_RDC;
                shm_sync_enabled <= 1'b1;
                bg_sync_slot <= 6'd0;
            end
        end else begin
            remote_dma_addr <= ring_wrap_addr(data_port_byte_addr + 16'h0001,
                                              pstart_register, pstop_register);
            if (remote_byte_count > 16'h0001) begin
                remote_byte_count <= remote_byte_count - 16'h0001;
            end else begin
                remote_byte_count <= 16'h0000;
                isr_register <= isr_register | ISR_RDC;
                shm_sync_enabled <= 1'b1;
                bg_sync_slot <= 6'd0;
            end
        end

        // Data port is local (packet RAM/PROM) and does not own eth_dma; only
        // release eth_dma_req if a background mailbox transfer isn't using it,
        // else this completion stomps the bg (ISSP: bg *_WAIT inflight=1 req=0,
        // hb frozen -> CPU remote DMA blocked -> driver spins on CR/ISR -> lockup).
        if (!bg_dma_inflight) eth_dma_req <= 1'b0;
        data_port_read_pending <= 1'b0;
        data_port_write_pending <= 1'b0;
        local_pmem_read_wait <= 1'b0;
        data_port_transfer_done <= 1'b1;
    end
endtask

function [7:0] sanitize_ring_page;
    input [7:0] page;
    input [7:0] pstart;
    input [7:0] pstop;
    begin
        if ((page < pstart) || (page >= pstop)) begin
            sanitize_ring_page = pstart;
        end else begin
            sanitize_ring_page = page;
        end
    end
endfunction

function [15:0] maybe_swap_word;
    input [15:0] word_value;
    input        swap_bytes;
    begin
        maybe_swap_word = swap_bytes ? {word_value[7:0], word_value[15:8]} : word_value;
    end
endfunction

function [7:0] wrap_ring_page_add;
    input [7:0] page;
    input [7:0] pages;
    input [7:0] pstart;
    input [7:0] pstop;
    reg [8:0] next_page;
    reg [7:0] wrapped_page;
    begin
        next_page = {1'b0, page} + {1'b0, pages};
        if (next_page >= {1'b0, pstop}) begin
            wrapped_page = pstart + next_page[7:0] - pstop;
            wrap_ring_page_add = wrapped_page;
        end else begin
            wrap_ring_page_add = next_page[7:0];
        end
    end
endfunction

function [7:0] ring_page_distance;
    input [7:0] from_page;
    input [7:0] to_page;
    input [7:0] pstart;
    input [7:0] pstop;
    reg [8:0] ring_pages;
    begin
        ring_pages = {1'b0, pstop} - {1'b0, pstart};
        if ((ring_pages == 9'd0) ||
            (from_page < pstart) || (from_page >= pstop) ||
            (to_page < pstart) || (to_page >= pstop)) begin
            ring_page_distance = 8'h00;
        end else if (to_page >= from_page) begin
            ring_page_distance = to_page - from_page;
        end else begin
            ring_page_distance = ring_pages[7:0] - (from_page - to_page);
        end
    end
endfunction

function [15:0] ring_page_byte_offset;
    input [7:0] page;
    begin
        ring_page_byte_offset = {page - NE_PAGE_BASE, 8'h00};
    end
endfunction

// Fold an NE packet-RAM byte address back into the receive ring [pstart, pstop)
// when it runs off PSTOP. A real RTL8019 wraps both the receive write pointer
// and the remote-DMA pointer at PSTOP -> PSTART. Without this, a frame whose
// data crosses PSTOP runs linearly past NE_PMEM_END: the write masks back into
// the TX buffer (pages < PSTART) corrupting a staged ACK, and the read leaves
// the packet region entirely -> the Amiga receives a corrupt frame, drops it on
// checksum, and the server retransmits (observed as ETHPERF retx with every
// drop counter at zero). A single frame is far smaller than the ring, so it can
// straddle PSTOP at most once -> one conditional fold-back is exact.
function [15:0] ring_wrap_addr;
    input [15:0] ne_addr;
    input [7:0]  pstart;
    input [7:0]  pstop;
    begin
        if (ne_addr >= {pstop, 8'h00})
            ring_wrap_addr = ne_addr - ({pstop, 8'h00} - {pstart, 8'h00});
        else
            ring_wrap_addr = ne_addr;
    end
endfunction

function [15:0] hps_u16_from_dma;
    input [15:0] data;
    begin
        hps_u16_from_dma = {data[7:0], data[15:8]};
    end
endfunction

function [7:0] hps_u8_from_dma;
    input [7:0] data;
    begin
        hps_u8_from_dma = data;
    end
endfunction

function [15:0] build_hps_status_word;
    input sampled;
    input signature_valid_in;
    input hb_nonzero;
    input hb_changed;
    input rx_active;
    input tx_pending;
    begin
        build_hps_status_word =
            (sampled ? ETH_STATUS_FPGA_SAMPLED : 16'h0000) |
            (signature_valid_in ? ETH_STATUS_FPGA_SIGNATURE : 16'h0000) |
            (hb_nonzero ? ETH_STATUS_FPGA_HEARTBEAT : 16'h0000) |
            (hb_changed ? ETH_STATUS_FPGA_HB_CHANGED : 16'h0000) |
            ((sampled && signature_valid_in && hb_changed) ? ETH_STATUS_FPGA_COMM_OK : 16'h0000) |
            (rx_active ? ETH_STATUS_FPGA_RX_ACTIVE : 16'h0000) |
            (tx_pending ? ETH_STATUS_FPGA_TX_PENDING : 16'h0000);
    end
endfunction

function [15:0] build_hps_status_dma_word;
    input sampled;
    input signature_valid_in;
    input hb_nonzero;
    input hb_changed;
    input rx_active;
    input tx_pending;
    reg [15:0] status_word;
    begin
        status_word = build_hps_status_word(sampled, signature_valid_in, hb_nonzero, hb_changed, rx_active, tx_pending);
        build_hps_status_dma_word = {status_word[7:0], status_word[15:8]};
    end
endfunction

function packet_ram_addr_valid;
    input [15:0] ne_addr;
    begin
        packet_ram_addr_valid = (ne_addr >= NE_PMEM_START) && (ne_addr < NE_PMEM_END);
    end
endfunction

/* verilator lint_off UNUSEDSIGNAL */
function [12:0] packet_ram_word_addr;
    input [15:0] ne_addr;
    reg [15:0] pmem_byte_addr;
    begin
        pmem_byte_addr = ne_addr - NE_PMEM_START;
        packet_ram_word_addr = pmem_byte_addr[13:1];
    end
endfunction
/* verilator lint_on UNUSEDSIGNAL */

function [1:0] packet_ram_byteena_for_byte;
    input        addr_lsb;
    begin
        packet_ram_byteena_for_byte = addr_lsb ? 2'b01 : 2'b10;
    end
endfunction

function [15:0] packet_ram_wdata_for_byte;
    input        addr_lsb;
    input [7:0]  value;
    begin
        packet_ram_wdata_for_byte = addr_lsb ? {8'h00, value} : {value, 8'h00};
    end
endfunction

function [15:0] format_reg_read_data;
    input [7:0] value;
    input       uds_n;
    input       lds_n;
    begin
        if (!uds_n && lds_n) begin
            format_reg_read_data = {value, 8'h00};
        end else if (uds_n && !lds_n) begin
            format_reg_read_data = {8'h00, value};
        end else begin
            // Mirror register bytes on word/unspecified reads so monitor and
            // driver code that samples either lane still sees the value.
            format_reg_read_data = {value, value};
        end
    end
endfunction

/* verilator lint_off UNUSEDSIGNAL */
function [7:0] rx_page_count_for_length;
    input [15:0] length;
    reg [15:0] rounded_length;
    begin
        rounded_length = length + 16'h0103;
        rx_page_count_for_length = rounded_length[15:8];
    end
endfunction
/* verilator lint_on UNUSEDSIGNAL */

localparam [15:0] ETH_FPGA_FLAG_MASK = ETH_FLAG_TX_REQ | ETH_FLAG_IRQ | ETH_FLAG_ENABLED;
localparam [15:0] ETH_HPS_FLAG_MASK = ETH_FLAG_RX_AVAIL;

function [7:0] shm_ctrl_reg_value;
    input [4:0] slot;
    begin
        case (slot)
            5'h00: shm_ctrl_reg_value = cr_register;
            5'h01: shm_ctrl_reg_value = pstart_register;
            5'h02: shm_ctrl_reg_value = pstop_register;
            5'h03: shm_ctrl_reg_value = bnry_register;
            5'h04: shm_ctrl_reg_value = tpsr_register;
            5'h05: shm_ctrl_reg_value = tbcr_register[7:0];
            5'h06: shm_ctrl_reg_value = tbcr_register[15:8];
            5'h07: shm_ctrl_reg_value = isr_register;
            5'h08: shm_ctrl_reg_value = remote_dma_addr[7:0];
            5'h09: shm_ctrl_reg_value = remote_dma_addr[15:8];
            5'h0A: shm_ctrl_reg_value = remote_byte_count[7:0];
            5'h0B: shm_ctrl_reg_value = remote_byte_count[15:8];
            5'h0C: shm_ctrl_reg_value = rcr_register;
            5'h0D: shm_ctrl_reg_value = tcr_register;
            5'h0E: shm_ctrl_reg_value = dcr_register;
            5'h0F: shm_ctrl_reg_value = imr_register;
            5'h11: shm_ctrl_reg_value = par_registers[0];
            5'h12: shm_ctrl_reg_value = par_registers[1];
            5'h13: shm_ctrl_reg_value = par_registers[2];
            5'h14: shm_ctrl_reg_value = par_registers[3];
            5'h15: shm_ctrl_reg_value = par_registers[4];
            5'h16: shm_ctrl_reg_value = par_registers[5];
            5'h17: shm_ctrl_reg_value = curr_register;
            5'h18: shm_ctrl_reg_value = mar_registers[0];
            5'h19: shm_ctrl_reg_value = mar_registers[1];
            5'h1A: shm_ctrl_reg_value = mar_registers[2];
            5'h1B: shm_ctrl_reg_value = mar_registers[3];
            5'h1C: shm_ctrl_reg_value = mar_registers[4];
            5'h1D: shm_ctrl_reg_value = mar_registers[5];
            5'h1E: shm_ctrl_reg_value = mar_registers[6];
            5'h1F: shm_ctrl_reg_value = mar_registers[7];
            default: shm_ctrl_reg_value = 8'h00;
        endcase
    end
endfunction

/* verilator lint_off UNUSEDSIGNAL */
function [14:0] sync_slot_word_addr;
    input [5:0] slot;
    reg [15:0] byte_addr;
    begin
        case (slot)
            6'd0, 6'd1, 6'd2, 6'd3, 6'd4, 6'd5, 6'd6, 6'd7,
            6'd8, 6'd9, 6'd10, 6'd11, 6'd12, 6'd13, 6'd14, 6'd15,
            6'd16, 6'd17, 6'd18, 6'd19, 6'd20, 6'd21, 6'd22, 6'd23,
            6'd24, 6'd25, 6'd26, 6'd27, 6'd28, 6'd29, 6'd30, 6'd31:
                byte_addr = ETH_SHM_CTRL_REGS + {9'b000000000, slot[4:0], 2'b00};
            6'd32: byte_addr = ETH_SHM_CTRL_MAC + 16'h0000;
            6'd33: byte_addr = ETH_SHM_CTRL_MAC + 16'h0002;
            6'd34: byte_addr = ETH_SHM_CTRL_MAC + 16'h0004;
            6'd35: byte_addr = ETH_RTL8019_STATE + 16'h0000;
            6'd36: byte_addr = ETH_RTL8019_STATE + 16'h0002;
            6'd37: byte_addr = ETH_RTL8019_STATE + 16'h0004;
            6'd38: byte_addr = ETH_RTL8019_STATE + 16'h0006;
            6'd39: byte_addr = ETH_RTL8019_STATE + 16'h0008;
            6'd40: byte_addr = ETH_RTL8019_STATE + 16'h000A;
            6'd41: byte_addr = ETH_RTL8019_STATE + 16'h000C;
            6'd42: byte_addr = ETH_RTL8019_STATE + 16'h000E;
            6'd43: byte_addr = ETH_RTL8019_STATE + 16'h0010;
            6'd44: byte_addr = ETH_RTL8019_STATE + 16'h0012;
            6'd45: byte_addr = ETH_RTL8019_STATE + 16'h0014;
            6'd46: byte_addr = ETH_RTL8019_STATE + 16'h0016;
            6'd47: byte_addr = ETH_RTL8019_STATE + 16'h0018;
            6'd48: byte_addr = ETH_RTL8019_STATE + 16'h001A;
            6'd49: byte_addr = ETH_RTL8019_STATE + 16'h001C;
            default: byte_addr = ETH_SHM_CTRL_REGS;
        endcase
        sync_slot_word_addr = byte_addr[15:1];
    end
endfunction
/* verilator lint_on UNUSEDSIGNAL */

function [15:0] sync_slot_wdata;
    input [5:0] slot;
    reg [7:0] state_page_byte;
    reg [7:0] state_enabled_byte;
    begin
        state_page_byte = {6'b000000, current_page};
        state_enabled_byte = cr_register[1] ? 8'h01 : 8'h00;
        case (slot)
            6'd0, 6'd1, 6'd2, 6'd3, 6'd4, 6'd5, 6'd6, 6'd7,
            6'd8, 6'd9, 6'd10, 6'd11, 6'd12, 6'd13, 6'd14, 6'd15,
            6'd16, 6'd17, 6'd18, 6'd19, 6'd20, 6'd21, 6'd22, 6'd23,
            6'd24, 6'd25, 6'd26, 6'd27, 6'd28, 6'd29, 6'd30, 6'd31:
                sync_slot_wdata = {8'h00, shm_ctrl_reg_value(slot[4:0])};
            // ETH_CTRL_MAC mirror (0x104C). The mailbox byte-swaps each 16-bit
            // word on the way to DDR, so emit the pair as {byte_n, byte_n+1} to
            // make the daemon read the 6 MAC bytes in order (mac[0..5] =
            // par_registers[0..5]). Previously emitted {par[1],par[0]} etc.,
            // which landed pair-swapped (54:52:04:05:02:03) so the daemon
            // filtered unicast RX for the wrong address and dropped ping/ARP
            // replies. The Amiga-side station PROM already reads 52:54:... ; this
            // makes the daemon view agree.
            6'd32: sync_slot_wdata = {par_registers[0], par_registers[1]};
            6'd33: sync_slot_wdata = {par_registers[2], par_registers[3]};
            6'd34: sync_slot_wdata = {par_registers[4], par_registers[5]};
            6'd35: sync_slot_wdata = {par_registers[0], state_page_byte};
            6'd36: sync_slot_wdata = {par_registers[2], par_registers[1]};
            6'd37: sync_slot_wdata = {par_registers[4], par_registers[3]};
            6'd38: sync_slot_wdata = {8'h01, par_registers[5]};
            6'd39: sync_slot_wdata = {8'h00, state_enabled_byte};
            6'd40: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486     // integrity probe: bg RX running byte-sum
            6'd41: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486  // integrity probe: bg RX frames delivered (count tag)
            6'd42: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486       // read-side probe: bytes bg WROTE into the ring
            6'd43: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486         // read-side probe: bytes 68k READ via the data port
            6'd44: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486         // per-frame read probe: payload-read mismatches
            6'd45: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486         // per-frame read probe: payload reads compared (0 => not armed)
            6'd46: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486        // per-frame read probe: last mismatch page
            6'd47: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486         // per-frame read probe: last mismatch RBCR byte count
            6'd48: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486      // per-frame read probe: last expected payload csum
            6'd49: sync_slot_wdata = 16'h0000;   // diagnostic probe removed for ao486      // per-frame read probe: last actual payload csum
            default: sync_slot_wdata = 16'h0000;
        endcase
    end
endfunction

wire [1:0]  tcr_loopback_mode = tcr_register[2:1];
wire        rcr_monitor_mode = rcr_register[5];
wire        dcr_word_mode = dcr_register[0];
// The X-Surf-100 32-bit DMA ports (board 0x8880 read / 0x8C80 write; host_addr
// 0x4440 / 0x4640) are accessed by the driver with MOVE.L/MOVEM.L in CardType=2
// mode. On the Amiga 68020 the 32-bit access delivers each 16-bit word's two
// bytes in the OPPOSITE order from a normal 16-bit (MOVE.W) port access, so the
// transmitted frame came out byte-swapped per word (HW: ARP/DHCP went out as
// e.g. 54 52 04 05.. instead of 52 54 05 04..). Apply an extra per-word byte
// swap for these two windows so the on-wire bytes are correct. (The 16-bit port
// 0xC80 is unaffected. The station-MAC read via 0x8880 was swap-invariant
// because the PROM duplicates each MAC byte, which is why it looked fine.)
wire        is_dport32_access = ((host_addr >= 15'h4440) && (host_addr <= 15'h444F)) ||
                                ((host_addr >= 15'h4640) && (host_addr <= 15'h464F));
wire        remote_dma_prom_region = (remote_dma_addr < 16'h0020);
wire        remote_dma_pmem_region = (remote_dma_addr >= NE_PMEM_START) && (remote_dma_addr < NE_PMEM_END);
wire        irq_pending = |(isr_register & imr_register);
wire [15:0] fpga_owned_flags =
    (tx_request_pending ? ETH_FLAG_TX_REQ : 16'h0000) |
    (irq_pending ? ETH_FLAG_IRQ : 16'h0000) |
    (cr_register[1] ? ETH_FLAG_ENABLED : 16'h0000);
wire        receiver_active = rx_poll_enabled && cr_register[1] && !rcr_monitor_mode;

ne2000_packet_ram packet_ram_inst (
    .clk(clk),
    .addr_a(pmem_addr_a),     .wren_a(pmem_wren_a),
    .byteena_a(pmem_byteena_a), .wdata_a(pmem_wdata_a), .q_a(pmem_q_a),
    .addr_b(pmem_addr_b),     .wren_b(pmem_wren_b),
    .byteena_b(pmem_byteena_b), .wdata_b(pmem_wdata_b), .q_b(pmem_q_b)
);

// FPGA debug disabled to reduce Quartus build time.
// localparam USE_DEBUG_ISSP = 1'b1;

// ISSP source bits:
//   [0] inhibit background Ethernet DMA/sync engine
//   [1] synchronous clear for debug counters and sticky flags
// wire [1:0]  debug_source;
wire        debug_bg_disable = 1'b0;
wire        debug_clear = 1'b0;
// Step 4 (owner-specific slots): this used to be
//     (bg_flags_word & ETH_HPS_FLAG_MASK) | fpga_owned_flags
// i.e. a read-modify-write of a word both sides write. Anything the HPS set
// between our read and our write was silently clobbered. The flag word is now
// split by byte lane -- FPGA bits in the high byte, HPS bits in the low byte --
// and each side writes only its own lane, so no read is involved and there is
// nothing to race. Clearing the HPS's RX_AVAIL is no longer our business; RX
// discovery uses the head/tail indices, not that hint.
wire [15:0] bg_flags_write_word = fpga_owned_flags;
wire        hps_signature_valid = (hps_signature_seen == 32'hCAFEBABE);


// BF-7 gate. "Complete-on-command" below reports PTX as soon as the transmit is
// issued, because waiting for the frame to stage through the mailbox overran
// real drivers' transmit timeouts. That is fine while a daemon is actually
// there to pick the frame up -- and a lie when there is not: with no host the
// guest was told every frame went out clean while they silently vanished.
// A transmit is only claimed successful if the HPS end has actually published
// itself: signature present AND a non-zero heartbeat.
//
// Deliberately NOT requiring the heartbeat to have been seen to *advance*: that
// makes every transmit in the first poll window fail, and it wrongly fails a
// host that is present but between ticks. Signature + non-zero heartbeat is the
// difference between "nobody is there" (a zeroed window) and "somebody is".
//
// Known gap: a daemon that dies leaving its signature behind still looks alive.
// Startup clears the window (plan item 4.4), and catching a *stopped* host needs
// heartbeat-staleness tracking over time -- worth adding when the daemon lands.
wire        transport_alive = hps_signature_valid && (hps_heartbeat_seen != 32'h00000000);
wire [15:0] hps_comm_status_word = build_hps_status_word(
    hps_status_sampled,
    hps_signature_valid,
    (hps_heartbeat_seen != 32'h00000000),
    hps_heartbeat_change_seen,
    receiver_active,
    tx_request_pending
);
wire        data_port_dma_complete_now = eth_dma_req && eth_dma_ready && !bg_dma_inflight;
wire        data_port_dma_timeout_now =
    eth_dma_req && !eth_dma_ready &&
    (eth_dma_wait_counter == ETH_DMA_TIMEOUT_CYCLES) &&
    (data_port_read_pending || data_port_write_pending ||
     (host_sel && is_data_port_access && (host_rd || host_wr)));
wire        local_remote_dma_active =
    (((cr_remote_dma_read || cr_remote_dma_write) &&
      ((remote_byte_count != 16'h0000) ||
       data_port_read_pending || data_port_write_pending || eth_dma_req || data_port_cycle_active))) ||
    data_port_read_pending || data_port_write_pending;
wire [15:0] bg_dma_hps_word = hps_u16_from_dma(eth_dma_rdata);

// Step 5: MAC word currently on the bus, and the full address including it --
// the third word is only latched this cycle, so the validity test cannot use
// mac_from_host alone.
// bg_dma_hps_word has ALREADY been through hps_u16_from_dma, so it is in host
// order: MAC[2N] sits in [7:0] and MAC[2N+1] in [15:8]. Swapping again here put
// MAC[1] where MAC[0] belongs, and the address was then correctly rejected for
// not being locally administered.
wire [15:0] mac_word_now  = bg_dma_hps_word;
wire [47:0] mac_host_full = {mac_word_now, mac_from_host[31:0]};
wire [15:0] bg_rx_length_from_dma = hps_u16_from_dma(eth_dma_rdata);
wire [4:0]  prom_byte_index = remote_dma_addr[4:0];
wire [4:0]  prom_word_index = {remote_dma_addr[4:1], 1'b0};
wire [15:0] prom_read_word = {prom_shadow[prom_word_index], prom_shadow[prom_word_index + 5'd1]};
wire [7:0]  prom_read_byte = prom_shadow[prom_byte_index];
wire [7:0]  bg_rx_page_start_calc =
    sanitize_ring_page(curr_register, pstart_register, pstop_register);
wire [15:0] bg_rx_dst_offset_calc = ring_page_byte_offset(bg_rx_page_start_calc);
wire [7:0]  bg_rx_page_count_calc = rx_page_count_for_length(bg_rx_length_from_dma);
wire [7:0]  bg_rx_next_page_calc =
    wrap_ring_page_add(bg_rx_page_start_calc, bg_rx_page_count_calc, pstart_register, pstop_register);
wire [7:0]  bg_rx_free_pages_calc =
    ring_page_distance(bg_rx_page_start_calc, bnry_register, pstart_register, pstop_register);
wire        bg_rx_ring_full_calc = (bg_rx_page_count_calc >= bg_rx_free_pages_calc);
// TCR.LB=01 loopback ring bookkeeping: bg_rx_page_start_calc/bg_rx_dst_offset_calc/
// bg_rx_free_pages_calc are already length-independent (pure functions of
// curr_register/bnry_register/pstart/pstop) so they're shared as-is; only the
// page count depends on the frame length, which here is tbcr_register (the
// TX byte count) instead of a length read from the HPS mailbox.
wire [7:0]  loop_page_count_calc = rx_page_count_for_length(tbcr_register);
wire [7:0]  loop_next_page_calc =
    wrap_ring_page_add(bg_rx_page_start_calc, loop_page_count_calc, pstart_register, pstop_register);
wire        loop_ring_full_calc = (loop_page_count_calc >= bg_rx_free_pages_calc);
wire [3:0]  bg_rx_slot = bg_rx_queue_head[3:0];
wire [3:0]  bg_rx_next_slot = bg_rx_slot + 4'd1;
wire [15:0] bg_rx_slot_offset =
    {2'b00, bg_rx_slot, 10'b0000000000} + {3'b000, bg_rx_slot, 9'b000000000};
wire [15:0] bg_rx_slot_data_base =
    ETH_SHM_RX_QUEUE_DATA + bg_rx_slot_offset;
wire [15:0] tx_next_request_seq =
    (tx_request_seq == 16'hFFFF) ? 16'h0001 : (tx_request_seq + 16'h0001);
// Fix B: the frame being staged gets seq = tx_next_request_seq, so it lands in
// slot (seq % 8). slot*1536 mirrors the RX slot-offset trick (x1024 + x512).
wire [2:0]  tx_slot = tx_next_request_seq[2:0];
wire [15:0] tx_slot_offset = {3'b000, tx_slot, 10'b0} + {4'b0000, tx_slot, 9'b0};
/* verilator lint_off UNUSEDSIGNAL */
wire [15:0] bg_rx_head_byte_addr = ETH_SHM_RX_QUEUE_HEAD;
wire [15:0] bg_rx_tail_byte_addr = ETH_SHM_RX_QUEUE_TAIL;
wire [15:0] bg_rx_len_byte_addr = ETH_SHM_RX_QUEUE_LEN + {11'h000, bg_rx_slot, 1'b0};
wire [15:0] bg_payload_src_byte_addr = bg_rx_slot_data_base + bg_rx_src_offset;
wire [15:0] bg_tx_addr_byte_addr = ETH_SHM_TX_REQUEST_ADDR;
wire [15:0] bg_tx_len_byte_addr = ETH_SHM_TX_SLOT_LEN + {12'h000, tx_slot, 1'b0};
wire [15:0] bg_tx_seq_byte_addr = ETH_SHM_TX_REQUEST_SEQ;
wire [15:0] bg_tx_complete_seq_byte_addr = ETH_SHM_TX_COMPLETE_SEQ;
wire [15:0] bg_tx_dst_byte_addr = ETH_SHM_TX_SLOT_DATA + tx_slot_offset + bg_tx_src_offset;
/* verilator lint_on UNUSEDSIGNAL */
wire [15:0] bg_sync_wd        = sync_slot_wdata(bg_sync_slot);
wire [14:0] bg_flags_word_addr = ETH_SHM_CTRL_FLAGS[15:1];
wire [14:0] bg_status_word_addr = ETH_SHM_CTRL_STATUS[15:1];
wire [14:0] bg_rx_head_word_addr = bg_rx_head_byte_addr[15:1];
wire [14:0] bg_rx_tail_word_addr = bg_rx_tail_byte_addr[15:1];
wire [14:0] bg_rx_len_word_addr = bg_rx_len_byte_addr[15:1];
wire [14:0] bg_payload_src_word_addr = bg_payload_src_byte_addr[15:1];
wire [14:0] bg_tx_addr_word_addr = bg_tx_addr_byte_addr[15:1];
wire [14:0] bg_tx_len_word_addr = bg_tx_len_byte_addr[15:1];
wire [14:0] bg_tx_seq_word_addr = bg_tx_seq_byte_addr[15:1];
wire [14:0] bg_tx_complete_seq_word_addr = bg_tx_complete_seq_byte_addr[15:1];
wire [14:0] bg_tx_dst_word_addr = bg_tx_dst_byte_addr[15:1];
wire [14:0] bg_hps_hb_lo_word_addr = ETH_SHM_HPS_HEARTBEAT[15:1];
wire [14:0] bg_hps_hb_hi_word_addr = ETH_SHM_HPS_HEARTBEAT_HI[15:1];
wire [14:0] bg_hps_sig_lo_word_addr = ETH_SHM_HPS_SIGNATURE[15:1];
wire [14:0] bg_hps_sig_hi_word_addr = ETH_SHM_HPS_SIGNATURE_HI[15:1];
wire        data_port_select_active =
    host_sel && !host_sel_priv && is_data_port_access &&
    !host_cyc_n;
wire        data_port_bus_active = data_port_select_active && (host_rd || host_wr);
wire        data_port_pmem_busy =
    data_port_bus_active || data_port_cycle_active ||
    data_port_read_pending || data_port_write_pending;
wire        data_port_cycle_start =
    data_port_bus_active && !data_port_bus_active_prev && !data_port_cycle_active;
wire        data_port_cycle_end = !data_port_select_active && data_port_cycle_active;
wire        data_port_cycle_timeout_now =
    data_port_cycle_active && !data_port_transfer_done &&
    (data_port_wait_counter == DATA_PORT_TIMEOUT_CYCLES);
// The background FSM contends with the CPU data-port ONLY for the shared
// single-port packet RAM, which it drives solely in the RX header/payload
// write states and the TX-buffer read states.  Its HPS-poll and mailbox
// traffic use eth_dma (DDR) and never touch packet RAM, so the CPU data-port
// must NOT be gated on general eth_dma_req activity -- only on actual bg
// packet-RAM access.  (Gating on eth_dma_req stalled the CPU during the now-
// active HPS poll and broke xsurftest's 16-bit memory test.  bg cannot enter
// these states while a data-port cycle is pending -- the bg request block is
// gated by !local_remote_dma_active -- so there is no RAM-port collision.)
// (Historical: bg_pmem_active / bg_releasable_pmem tracked which bg states held
// the shared single-port packet RAM, so the CPU data-port read could re-arm and
// wait for a bg-idle cycle, and so those states could be released from the
// data-port freeze to avoid a mutual deadlock.  The packet RAM is now TRUE
// DUAL-PORT -- the bg owns port A, the CPU owns port B -- so the CPU never sees
// the bg's writes and none of that mux/re-arm/release bookkeeping is needed.
// Both wires and their gate term have been removed.)
wire        data_port_cycle_launch_ok =
    (data_port_cycle_start || data_port_cycle_active) &&
    !data_port_transfer_done &&
    !data_port_cycle_timeout_now &&
    !data_port_dma_complete_now && !data_port_dma_timeout_now &&
    // No !bg_pmem_active term: the CPU drives the dedicated packet-RAM port B,
    // so it never has to wait for the bg's port-A activity (dual-port RAM).
    !data_port_write_pending && !data_port_read_pending;
wire [7:0]  debug_status_byte = {
    debug_dma_timeout_sticky,
    bg_dma_inflight,
    data_port_cycle_active,
    data_port_transfer_done,
    data_port_write_pending,
    data_port_read_pending,
    eth_dma_req,
    local_remote_dma_active
};

// ---------------------------------------------------------------------------
// Live ISSP debug instance (In-System Sources & Probes over JTAG).
// Focused on the HPS<->FPGA mailbox round trip so we can confirm, without the
// HPS daemon log, whether the FPGA actually sees what the HPS writes to the
// 0x1FF00000 mailbox.
//
// eth_dbg_probe (128 bits), MSB..LSB:
//   [127:120] debug_status_byte  (timeout_sticky, bg_dma_inflight,
//                                 dp_cycle_active, dp_transfer_done,
//                                 dp_write_pending, dp_read_pending,
//                                 eth_dma_req, local_remote_dma_active)
//   [119:114] bg_state           (background mailbox FSM state)
//   [113]     hps_signature_valid (hps_signature_seen == 0xCAFEBABE)
//   [112]     hps_heartbeat_change_seen
//   [111:104] isr_register  (ISR)  | irq = |(isr & imr); stuck nonzero => IRQ storm
//   [103:96]  imr_register  (IMR mask)
//   [95:80]   tx_request_seq
//   [79:64]   hps_comm_status_word
//   [63:32]   hps_heartbeat_seen   <- advancing => FPGA reads HPS via mailbox
//   [31:16]   dbg_last_acc_addr     <- last CPU aperture offset
//   [15:12]   dbg_last_acc_flags    <- {host_sel, is_data_port_access, host_rd, host_wr}
//   [11:0]    live CPU/data-port flags
//
// Key check: read instance "ETHDBG"; if [113]==1 and [63:32] advances between
// reads, the f2sdram2 mailbox round trip is healthy on hardware.
// ---------------------------------------------------------------------------
/* verilator lint_off UNUSEDSIGNAL */
// Diagnostic: latch the last CPU access to the ethernet aperture so an ISSP
// read during an Amiga lockup shows exactly which X-Surf offset the CPU is
// stuck/spinning on (e.g. PHY/config 0x0406/0x04F2 returning open-bus). Latch
// on any host_rd/host_wr; byte_addr is the aperture offset (host_addr<<1).
reg [15:0] dbg_last_acc_addr = 16'h0000;
reg [3:0]  dbg_last_acc_flags = 4'h0;   // {host_sel, is_data_port_access, host_rd, host_wr} at that access
always @(posedge clk) begin
    if (reset) begin
        dbg_last_acc_addr  <= 16'h0000;
        dbg_last_acc_flags <= 4'h0;
    end else if (host_rd || host_wr) begin
        dbg_last_acc_addr  <= {host_addr, 1'b0};   // aperture byte offset (host_addr<<1)
        dbg_last_acc_flags <= {host_sel, is_data_port_access, host_rd, host_wr};
    end
end

// Diagnostic: capture what the FPGA returns for the driver's station-MAC read
// (remote-DMA read of the PROM region, remote_dma_addr 0..0x1F, via the 0xC80
// data port). dbg_prom_rd_first latches the value returned for the FIRST PROM
// word (addr 0) -- should be 0x5252 (DEFAULT_MAC0 duplicated) if the read is
// healthy; 0xFFFF/0x0000 means the PROM read is broken. dbg_prom_rd_cnt counts
// PROM-region reads so we can confirm the MAC read actually happened. Persists
// across reset so the one-shot MAC read at device open stays visible to JTAG.
reg [15:0] dbg_prom_rd_first = 16'h0000;
reg [7:0]  dbg_prom_rd_cnt   = 8'h00;

// Diagnostic event counters for the RX-interrupt path (why the driver receives
// into the ring -- CURR advances -- but never gets an IRQ -- ISR reads 0x00).
//   prx_set: bg delivered an RX frame and set ISR.PRX
//   ptx_set: a TX completed and set ISR.PTX
//   isr_clr: the CPU wrote ISR (write-1-to-clear)
//   ethirq:  irq rising edges (|(isr&imr) went 0->1) = interrupts raised to INT2
// If prx_set climbs but ethirq stays ~0 -> ISR.PRX is being cleared before irq
// can assert (or it's never really set); if ethirq climbs but the Amiga doesn't
// react -> the INT2/handler side. These persist across reset to accumulate.
reg [7:0]  dbg_prx_set_cnt = 8'h00;
reg [7:0]  dbg_ptx_set_cnt = 8'h00;
reg [7:0]  dbg_isr_clr_cnt = 8'h00;
reg [7:0]  dbg_ethirq_cnt  = 8'h00;

wire [127:0] eth_dbg_probe = {
    debug_status_byte,            // [127:120]
    bg_state,                     // [119:114]
    hps_signature_valid,          // [113]
    hps_heartbeat_change_seen,    // [112]
    isr_register,                 // [111:104] ISR (interrupt status)
    imr_register,                 // [103:96]  IMR (mask); irq = |(isr & imr)
    dbg_prom_rd_first,            // [95:80]  first station-PROM read word (expect 0x5252)
    hps_comm_status_word,         // [79:64]
    // [63:32] repurposed for RX-interrupt event counters (hb liveness still
    // visible via bg_state cycling + hps_heartbeat_change_seen [112]).
    dbg_prx_set_cnt,              // [63:56] bg set ISR.PRX (RX delivered)
    dbg_ptx_set_cnt,              // [55:48] TX completed -> ISR.PTX
    dbg_isr_clr_cnt,              // [47:40] CPU wrote/cleared ISR
    dbg_ethirq_cnt,               // [39:32] irq rising edges -> INT2
    // [31:0] repurposed for the live CPU-access diagnostic (signature already
    // confirmed CAFEBABE via hps_signature_valid [113]).
    dbg_last_acc_addr,            // [31:16] last aperture offset accessed
    dbg_last_acc_flags,           // [15:12] {sel_eth,is_dport,rd,wr} at that access
    host_sel,                 // [11] live
    host_ack_n,                    // [10] live (1=not acked -> CPU waiting)
    host_rd,                       // [9]  live
    host_wr,                       // [8]  live
    data_port_cycle_active,       // [7]
    data_port_transfer_done,      // [6]
    dbg_prom_rd_cnt[5:0]          // [5:0] count of station-PROM reads (>0 = MAC read happened)
};
wire [1:0] eth_dbg_source;        // JTAG-driven source (reserved; observe-only)
/* verilator lint_on UNUSEDSIGNAL */

// Bring-up JTAG ISSP probe -- DISABLED for production. It (plus the sld_hub JTAG
// fabric it pulls in and the dbg_* counters that feed it) consumes logic that
// congests the fitter and was pushing the marginal Minimig cpu_cache->cpu_dat_r
// setup path negative after the data-port-read race fix. With the probe removed,
// eth_dbg_probe and every dbg_* counter become dead and are stripped by synthesis,
// freeing that logic so timing closes. Define ETH_DEBUG_ISSP to bring it back for
// JTAG debugging. (HW diagnosis now uses the daemon ETHPERF counters, not JTAG.)
`ifdef ETH_DEBUG_ISSP
ethernet_issp #(
    .PROBE_WIDTH(128),
    .SOURCE_WIDTH(2),
    .INSTANCE_ID("ETHDBG")
) eth_debug_issp (
    .clk(clk),
    .probe(eth_dbg_probe),
    .source(eth_dbg_source)
);
`endif


// ISSP probe map:
// [127:112] remote_dma_addr
// [111:96]  remote_byte_count
// [95:80]   sticky flags
// [79:65]   eth_dma_addr
// [64:50]   host_addr
// [49:42]   CR
// [41:34]   ISR
// [33:26]   IMR
// [25:18]   CURR
// [17:13]   bg_state
// [12:0]    live flags
// wire [15:0] debug_sticky_flags = {debug_dma_timeout_sticky, debug_sticky_flags_lo};

// /* verilator lint_off UNUSEDSIGNAL */
// wire [127:0] debug_probe = {
//     remote_dma_addr,
//     remote_byte_count,
//     debug_sticky_flags,
//     eth_dma_addr,
//     host_addr,
//     cr_register,
//     isr_register,
//     imr_register,
//     curr_register,
//     bg_state[4:0],
//     host_rd,
//     host_wr,
//     host_sel,
//     host_sel_priv,
//     is_data_port_access,
//     host_ack_n,
//     irq,
//     eth_dma_req,
//     eth_dma_ready,
//     eth_dma_write,
//     bg_dma_inflight,
//     data_port_read_pending,
//     data_port_write_pending
// };
// /* verilator lint_on UNUSEDSIGNAL */

// generate
// if (USE_DEBUG_ISSP) begin : gen_eth_debug_issp
//     ethernet_issp #(
//         .PROBE_WIDTH(128),
//         .SOURCE_WIDTH(2),
//         .INSTANCE_ID("ETHDBG")
//     ) eth_debug_issp (
//         .clk(clk),
//         .probe(debug_probe),
//         .source(debug_source)
//     );
// end else begin : gen_eth_debug_issp_tieoff
//     assign debug_source = 2'b00;
// end
// endgenerate

// always @(posedge clk) begin
//     if (reset || debug_clear) begin
//         debug_heartbeat <= 16'h0000;
//         debug_local_wait_cycles <= 16'h0000;
//         debug_dma_wait_cycles <= 16'h0000;
//         debug_sticky_flags_lo <= 15'h0000;
//     end else begin
//         debug_heartbeat <= debug_heartbeat + 16'h0001;
//
//         if (host_sel && !host_sel_priv && (host_rd || host_wr) && host_ack_n &&
//             (debug_local_wait_cycles != 16'hFFFF)) begin
//             debug_local_wait_cycles <= debug_local_wait_cycles + 16'h0001;
//         end
//
//         if (eth_dma_req && !eth_dma_ready && (debug_dma_wait_cycles != 16'hFFFF)) begin
//             debug_dma_wait_cycles <= debug_dma_wait_cycles + 16'h0001;
//         end
//
//         if (host_sel && !host_sel_priv && (host_rd || host_wr) && host_ack_n) begin
//             debug_sticky_flags_lo[0] <= 1'b1;
//         end
//         if (eth_dma_req && !eth_dma_ready) begin
//             debug_sticky_flags_lo[1] <= 1'b1;
//         end
//         if (host_sel && host_sel_priv) begin
//             debug_sticky_flags_lo[2] <= 1'b1;
//         end
//         if (host_sel && host_wr && is_register_access) begin
//             debug_sticky_flags_lo[3] <= 1'b1;
//         end
//         if (host_sel && (host_rd || host_wr) && is_data_port_access) begin
//             debug_sticky_flags_lo[4] <= 1'b1;
//         end
//         if (eth_dma_req && host_sel && is_data_port_access && (host_rd || host_wr)) begin
//             debug_sticky_flags_lo[5] <= 1'b1;
//         end
//         if (bg_polling_rx_flags) begin
//             debug_sticky_flags_lo[6] <= 1'b1;
//         end
//         if (shm_sync_enabled) begin
//             debug_sticky_flags_lo[7] <= 1'b1;
//         end
//         if (tx_request_pending) begin
//             debug_sticky_flags_lo[8] <= 1'b1;
//         end
//         if (irq) begin
//             debug_sticky_flags_lo[9] <= 1'b1;
//         end
//         if (isr_register[6]) begin
//             debug_sticky_flags_lo[10] <= 1'b1;
//         end
//         if (isr_register[4]) begin
//             debug_sticky_flags_lo[11] <= 1'b1;
//         end
//         if (isr_register[0]) begin
//             debug_sticky_flags_lo[12] <= 1'b1;
//         end
//         if (isr_register[1]) begin
//             debug_sticky_flags_lo[13] <= 1'b1;
//         end
//         if (debug_bg_disable) begin
//             debug_sticky_flags_lo[14] <= 1'b1;
//         end
//     end
// end

// ---- Packet-RAM PORT A: background FSM (RX ring write / TX buffer read) ----
always @* begin
    pmem_addr_a    = 13'h0000;
    pmem_wdata_a   = 16'h0000;
    pmem_byteena_a = 2'b00;
    pmem_wren_a    = 1'b0;

    if (!data_port_pmem_busy && (bg_state == BG_WRITE_HDR0_REQ)) begin
        pmem_addr_a = packet_ram_word_addr(NE_PMEM_START + bg_rx_dst_offset);
        pmem_wdata_a = {bg_rx_status, bg_rx_next_page};
        pmem_byteena_a = 2'b11;
        pmem_wren_a = 1'b1;
    end else if (!data_port_pmem_busy && (bg_state == BG_WRITE_HDR1_REQ)) begin
        pmem_addr_a = packet_ram_word_addr(NE_PMEM_START + bg_rx_dst_offset + 16'h0002);
        pmem_wdata_a = {bg_rx_total_length[7:0], bg_rx_total_length[15:8]};
        pmem_byteena_a = 2'b11;
        pmem_wren_a = 1'b1;
    end else if (!data_port_pmem_busy &&
                 (bg_state == BG_WRITE_PAYLOAD_REQ) &&
                 (bg_rx_bytes_remaining != 16'h0000)) begin
        pmem_addr_a = packet_ram_word_addr(ring_wrap_addr(
            NE_PMEM_START + bg_rx_dst_offset + 16'h0004 + bg_rx_src_offset,
            pstart_register, pstop_register));
        if (bg_rx_bytes_remaining > 16'h0001) begin
            pmem_wdata_a = bg_source_word;
            pmem_byteena_a = 2'b11;
        end else begin
            pmem_wdata_a = {bg_source_word[15:8], 8'h00};
            pmem_byteena_a = 2'b10;
        end
        pmem_wren_a = 1'b1;
    end else if (!data_port_pmem_busy && (bg_state == BG_WRITE_PAYLOAD_WIDE)) begin
        // One of the four words of the wide-read 64-bit line; bg_wide_idx walks
        // 0..3, each a full word (the aligned bulk never has an odd tail byte).
        pmem_addr_a = packet_ram_word_addr(ring_wrap_addr(
            NE_PMEM_START + bg_rx_dst_offset + 16'h0004 +
            bg_rx_src_offset + {13'd0, bg_wide_idx, 1'b0},
            pstart_register, pstop_register));
        pmem_wdata_a = bg_wide_buf[{bg_wide_idx, 4'd0} +: 16];
        pmem_byteena_a = 2'b11;
        pmem_wren_a = 1'b1;
    end else if (!data_port_pmem_busy &&
                 ((bg_state == BG_READ_TX_BUF_REQ) || (bg_state == BG_READ_TX_BUF_WAIT1) ||
                  (bg_state == BG_READ_TX_BUF_WAIT2))) begin
        pmem_addr_a = packet_ram_word_addr(tx_stage_addr + bg_tx_src_offset);
    end else if (!data_port_pmem_busy &&
                 ((bg_state == BG_READ_TX_WIDE_REQ) || (bg_state == BG_READ_TX_WIDE_WAIT1) ||
                  (bg_state == BG_READ_TX_WIDE_WAIT2))) begin
        pmem_addr_a = packet_ram_word_addr(tx_stage_addr + bg_tx_src_offset +
                                           {13'd0, bg_wide_idx, 1'b0});
    end else if (!data_port_pmem_busy &&
                 ((bg_state == BG_LOOP_READ_REQ) || (bg_state == BG_LOOP_READ_WAIT1) ||
                  (bg_state == BG_LOOP_READ_WAIT2))) begin
        // TCR.LB=01 internal loopback: read the next payload word straight
        // from the TX page (tpsr_register), not tx_stage_addr -- that reg is
        // only ever set on the normal (non-loopback) TX path. bg_rx_src_offset
        // is the running frame offset shared with the write side below.
        pmem_addr_a = packet_ram_word_addr({tpsr_register, 8'h00} + bg_rx_src_offset);
    end
end

// ---- Packet-RAM PORT B: CPU data-port (RX ring read / TX buffer write) ----
always @* begin
    pmem_addr_b    = 13'h0000;
    pmem_wdata_b   = 16'h0000;
    pmem_byteena_b = 2'b00;
    pmem_wren_b    = 1'b0;

    if (data_port_cycle_launch_ok && host_wr && remote_dma_pmem_region &&
        (~host_be_hi_n || ~host_be_lo_n)) begin
        pmem_addr_b = packet_ram_word_addr(remote_dma_addr);
        if (dcr_word_mode) begin
            pmem_wdata_b = (dcr_byte_swap ^ is_dport32_access) ? {host_wdata[7:0], host_wdata[15:8]} : host_wdata;
            pmem_byteena_b = 2'b11;
        end else begin
            pmem_wdata_b = packet_ram_wdata_for_byte(remote_dma_addr[0], host_write_byte);
            pmem_byteena_b = packet_ram_byteena_for_byte(remote_dma_addr[0]);
        end
        pmem_wren_b = 1'b1;
    end else if (data_port_read_pending) begin
        pmem_addr_b = packet_ram_word_addr(data_port_byte_addr);
    end else if (data_port_cycle_launch_ok && host_rd && remote_dma_pmem_region) begin
        pmem_addr_b = packet_ram_word_addr(remote_dma_addr);
    end
end

// Address decode
wire [4:0]  register_select;
always @(posedge clk) begin
    if (reset) begin
        apply_nic_reset();
        tx_request_seq <= 16'h0000;   // transport-lifetime counter: hard reset only
        reset_port_latch <= 8'h00;
        debug_dma_timeout_sticky <= 1'b0;
        host_ack_n <= 1'b1;
    end else begin
        data_port_bus_active_prev <= data_port_bus_active;

        if (debug_clear) begin
            debug_dma_timeout_sticky <= 1'b0;
        end

        if (host_sel && (host_rd || host_wr)) begin
            if (is_data_port_access && !host_sel_priv) begin
                host_ack_n <= (data_port_cycle_active && data_port_transfer_done) ? 1'b0 : 1'b1;
            end else begin
                host_ack_n <= 1'b0;
            end
        end else begin
            host_ack_n <= 1'b1;
        end

        if (data_port_cycle_start) begin
            data_port_cycle_active <= 1'b1;
            data_port_transfer_done <= 1'b0;
            data_port_wait_counter <= 10'd0;
            data_port_word_mode <= dcr_word_mode;
            data_port_byte_addr <= remote_dma_addr;
        end else if (data_port_cycle_end ||
                     (data_port_cycle_active &&
                      (!host_sel || host_sel_priv || !is_data_port_access))) begin
            data_port_cycle_active <= 1'b0;
            data_port_transfer_done <= 1'b0;
            data_port_wait_counter <= 10'd0;
        end else if (data_port_cycle_active && !data_port_transfer_done) begin
            if (data_port_wait_counter != DATA_PORT_TIMEOUT_CYCLES) begin
                data_port_wait_counter <= data_port_wait_counter + 10'd1;
            end
        end else begin
            data_port_wait_counter <= 10'd0;
        end

        if (data_port_cycle_timeout_now) begin
            debug_dma_timeout_sticky <= 1'b1;
            data_port_read_data <= 16'hFFFF;
            data_port_read_pending <= 1'b0;
            data_port_write_pending <= 1'b0;
            local_pmem_read_wait <= 1'b0;
            data_port_transfer_done <= 1'b1;
            if (!bg_dma_inflight) begin
                eth_dma_req <= 1'b0;
                eth_dma_write <= 1'b0;
                eth_dma_uds <= 1'b1;
                eth_dma_lds <= 1'b1;
            end
        end

        if (host_sel && host_wr && is_reset_port_access && (!host_be_hi_n || !host_be_lo_n)) begin
            reset_port_latch <= host_write_byte;
        end else if (host_sel && host_wr && is_register_access &&
                     (!host_be_hi_n || !host_be_lo_n)) begin
            case (register_select[4:0])
                5'h00: begin
                    cr_register <= cr_write_value;
                    // per-frame read probe: arm on a PAYLOAD remote-read (RD2:0=001,
                    // RSAR at a frame's payload offset 0x04, count>8 -- distinguishes
                    // it from the 4-byte header peeks at offset 0x00). Latch the
                    // frame's start page, snapshot the expected (bg-written) payload
                    // csum, and reset the read accumulator.
                    if (cr_write_remote_dma_read &&
                        (remote_dma_addr[7:0] == 8'h04) &&
                        (remote_byte_count > 16'd8) &&
                        (remote_byte_count[0] == 1'b0)) begin
                        dp_rd_in_payload  <= 1'b1;
                    end
                    if (cr_write_value[0]) begin
                        isr_register <= isr_register | ISR_RST;
                    end else begin
                        isr_register <= isr_register & ~ISR_RST;
                    end
                    if (cr_write_remote_dma_abort) begin
                        data_port_read_pending <= 1'b0;
                        data_port_write_pending <= 1'b0;
                        data_port_transfer_done <= 1'b0;
                        data_port_cycle_active <= 1'b0;
                        local_pmem_read_wait <= 1'b0;
                        // Abort the CPU's remote DMA, but NEVER stomp the shared
                        // eth_dma master while a background mailbox transfer owns
                        // it (bg_dma_inflight). The data port is local (packet
                        // RAM / PROM) and does not use eth_dma, so eth_dma_req is
                        // only ever the bg's; clearing it mid-transfer leaves
                        // bg_dma_inflight stuck with eth_dma_req=0, wedging the bg
                        // (ISSP: bg in *_WAIT, req=0, hb frozen) which then blocks
                        // CPU remote DMA -> ISR.RDC never sets -> the driver spins
                        // on CR/ISR forever and the Amiga locks up. The earlier
                        // guard also cleared on data_port_*_pending, which fires
                        // constantly now that the data port runs concurrently with
                        // the bg -> that re-opened the stomp. Gate purely on
                        // bg ownership; the data-port state is cleared above
                        // regardless, so the CPU's abort still takes effect.
                        if (!bg_dma_inflight) begin
                            eth_dma_req <= 1'b0;
                            eth_dma_write <= 1'b0;
                            eth_dma_uds <= 1'b1;
                            eth_dma_lds <= 1'b1;
                            eth_dma_wait_counter <= 10'd0;
                        end
                        // Only assert ISR.RDC (remote DMA complete) when the
                        // abort actually terminates an in-flight remote DMA. The
                        // driver writes CR=0x22 (STA + RD2:0=100 abort/complete)
                        // on EVERY interrupt-handler entry and exit as its idle
                        // command; unconditionally setting RDC here re-armed
                        // ISR.RDC every iteration, so if IMR.RDC is enabled
                        // (ISR & IMR) never cleared, irq/irq_pending stuck
                        // high -> the handler re-entered forever reading CR/ISR
                        // (ISSP: CPU spinning 0x0C00/0x0C1C, no data-port access,
                        // bg healthy). On real NE2000 RDC is set by the DMA byte
                        // count reaching 0 (complete_data_port_transfer already
                        // does that), not by an abort with no DMA pending.
                        isr_register <= (cr_write_value[0] ? (isr_register | ISR_RST)
                                                          : (isr_register & ~ISR_RST))
                                        | ((data_port_read_pending || data_port_write_pending ||
                                            (remote_byte_count != 16'h0000)) ? ISR_RDC : 8'h00);
                    end else if ((cr_write_remote_dma_read || cr_write_remote_dma_write) &&
                                 (remote_byte_count == 16'h0000)) begin
                        isr_register <= (cr_write_value[0] ? (isr_register | ISR_RST)
                                                          : (isr_register & ~ISR_RST)) | ISR_RDC;
                    end
                    // TPSR (transmit page) is independent of the RX ring; on a
                    // standard NE2000 the TX buffer (page 0x40) sits BELOW
                    // PSTART (0x46). Bound the transmit by the physical packet
                    // RAM page range [NE_PAGE_BASE, NE_PMEM_END>>8), not by the
                    // RX ring [PSTART, PSTOP) -- the latter wrongly dropped a
                    // transmit from page 0x40 (TSR/ISR.PTX never set).
                    if (cr_write_value[2] &&
                        (tbcr_register != 16'h0000) &&
                        (tpsr_register >= NE_PAGE_BASE) &&
                        (tpsr_register < NE_PMEM_END[15:8])) begin
                        tsr_register <= 8'h00;
                        // TCR.LB=01 is NIC (internal) loopback -- on a real DP8390
                        // this never leaves the chip, so it must not depend on the
                        // HPS/daemon either. Modes 10/11 (external/SNI loopback) DO
                        // leave the chip on real hardware, out through the
                        // transceiver interface; here that's the host NIC, so they
                        // fall into the same HPS-staging path as a normal transmit
                        // and rely on the daemon's own --loopback echo, exactly as
                        // external loopback needs a physical loopback plug on a
                        // real card.
                        if (tcr_loopback_mode == 2'b01) begin
                            tx_complete_pending <= 1'b1;
                            tx_stage_pending <= 1'b0;
                            tx_request_pending <= 1'b0;
                        end else begin
                            // Complete-on-command: report PTX immediately when the
                            // transmit is issued, exactly like a real NE2000
                            // accepting the frame. The packet still stages to the
                            // HPS mailbox in the background (tx_stage_pending), but
                            // Amiga-side TX completion does not wait on the slow
                            // word-by-word mailbox copy (a 1500-byte frame is
                            // hundreds of eth_dma round trips) -- which otherwise
                            // overran the driver's transmit timeout ("No IRQ
                            // received / Transmit timeout"). The HPS picks up the
                            // published TX_REQUEST_SEQ once staging finishes.
                            // Only claim success if there is a live host to
                            // hand the frame to (see transport_alive above).
                            // Fix B: PTX is raised AFTER the frame is staged into
                            // its window TX slot (BG_WRITE_TX_SEQ_WAIT), not here.
                            // Command-time PTX (complete-on-command) let the driver
                            // reuse packet-RAM page 0x40 before the core copied it
                            // out -> under a download's ACK storm the single buffer
                            // was overwritten and ~90% of guest transmits were lost.
                            // Staging is bounded and already blocks RX for the same
                            // duration as today, so this does not add starvation
                            // (unlike waiting for the daemon's ack). No host -> abort.
                            tx_complete_pending <= 1'b0;
                            tx_abort_pending    <= ~transport_alive;
                            tx_stage_pending <= transport_alive;
                            tx_request_pending <= 1'b0;
                            tx_stage_addr <= {tpsr_register, 8'h00};
                            tx_stage_len <= tbcr_register;
                            bg_tx_src_offset <= 16'h0000;
                            bg_tx_bytes_remaining <= tbcr_register;
                        end
                    end
                end
                5'h01: begin
                    case (current_page)
                        2'b00: pstart_register <= host_write_byte;
                        2'b01: par_registers[0] <= host_write_byte;
                        2'b11: rtl8019_e9346cr <= {host_write_byte[7:1], rtl8019_e9346cr[0]};
                        default: begin
                        end
                    endcase
                end
                5'h02: begin
                    case (current_page)
                        2'b00: pstop_register <= host_write_byte;
                        2'b01: par_registers[1] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h03: begin
                    case (current_page)
                        2'b00: bnry_register <= host_write_byte;
                        2'b01: par_registers[2] <= host_write_byte;
                        2'b11: if (rtl8019_config_write_enable) begin
                            rtl8019_config0 <= {host_write_byte[7:6], rtl8019_config0[5:0]};
                        end
                        default: begin
                        end
                    endcase
                end
                5'h04: begin
                    case (current_page)
                        2'b00: tpsr_register <= host_write_byte;
                        2'b01: par_registers[3] <= host_write_byte;
                        2'b11: if (rtl8019_config_write_enable) begin
                            rtl8019_config1 <= {host_write_byte[7], rtl8019_config1[6:0]};
                        end
                        default: begin
                        end
                    endcase
                end
                5'h05: begin
                    case (current_page)
                        2'b00: tbcr_register[7:0] <= host_write_byte;
                        2'b01: par_registers[4] <= host_write_byte;
                        2'b11: if (rtl8019_config_write_enable) begin
                            rtl8019_config2 <= {host_write_byte[7:5], rtl8019_config2[4:0]};
                        end
                        default: begin
                        end
                    endcase
                end
                5'h06: begin
                    case (current_page)
                        2'b00: tbcr_register[15:8] <= host_write_byte;
                        2'b01: par_registers[5] <= host_write_byte;
                        2'b11: if (rtl8019_config_write_enable) begin
                            rtl8019_config3 <= {rtl8019_config3[7:3], host_write_byte[2:1], rtl8019_config3[0]};
                        end
                        default: begin
                        end
                    endcase
                end
                5'h07: begin
                    case (current_page)
                        2'b00: begin isr_register <= isr_register & ~host_write_byte; dbg_isr_clr_cnt <= dbg_isr_clr_cnt + 8'd1; end
                        2'b01: curr_register <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h08: begin
                    case (current_page)
                        2'b00: remote_dma_addr[7:0] <= host_write_byte;
                        2'b01: mar_registers[0] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h09: begin
                    case (current_page)
                        2'b00: remote_dma_addr[15:8] <= host_write_byte;
                        2'b01: mar_registers[1] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h0A: begin
                    case (current_page)
                        2'b00: remote_byte_count[7:0] <= host_write_byte;
                        2'b01: mar_registers[2] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h0B: begin
                    case (current_page)
                        2'b00: remote_byte_count[15:8] <= host_write_byte;
                        2'b01: mar_registers[3] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h0C: begin
                    case (current_page)
                        2'b00: begin
                            rcr_register <= host_write_byte;
                            rx_poll_enabled <= 1'b1;
                        end
                        2'b01: mar_registers[4] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h0D: begin
                    case (current_page)
                        2'b00: tcr_register <= host_write_byte;
                        2'b01: mar_registers[5] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h0E: begin
                    case (current_page)
                        2'b00: dcr_register <= {1'b1, host_write_byte[6:0]};
                        2'b01: mar_registers[6] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                5'h0F: begin
                    case (current_page)
                        2'b00: imr_register <= host_write_byte;
                        2'b01: mar_registers[7] <= host_write_byte;
                        default: begin
                        end
                    endcase
                end
                default: begin
                end
            endcase

            shm_sync_enabled <= 1'b1;
            bg_sync_slot <= 6'd0;
        end

        if (host_sel && host_rd && is_reset_port_access && !host_sel_priv) begin
            apply_nic_reset();
        end

        if (tx_abort_pending) begin
            // No live transport: report a genuine transmit failure. A driver
            // sees TSR.ABT / ISR.TXE and can retry or report a dead link,
            // instead of believing a frame was sent that never left the FPGA.
            tx_abort_pending <= 1'b0;
            cr_register <= {cr_register[7:3], 1'b0, cr_register[1:0]};
            tsr_register <= TSR_ABT;
            isr_register <= isr_register | ISR_TXE;
        end

        if (tx_complete_pending) begin
            tx_complete_pending <= 1'b0;
            cr_register <= {cr_register[7:3], 1'b0, cr_register[1:0]};
            tsr_register <= TSR_PTX;
            isr_register <= isr_register | ISR_PTX;
            dbg_ptx_set_cnt <= dbg_ptx_set_cnt + 8'd1;   // diagnostic
            if ((tcr_loopback_mode == 2'b01) && receiver_active) begin
                // Kick off the local packet-RAM copy (BG_IDLE dispatch below).
                // RSR_PRX/ISR_PRX are set when that copy actually finishes
                // writing the frame into the ring, not here -- matching how a
                // genuinely received frame's status is only valid once its
                // bytes have landed, not at the moment TX completes.
                loop_copy_pending <= 1'b1;
            end
            shm_sync_enabled <= 1'b1;
            bg_sync_slot <= 6'd0;
        end

        // Data-port (Amiga PIO) read of packet RAM via the DEDICATED CPU port B.
        // Port B always drives data_port_byte_addr while data_port_read_pending,
        // independent of the bg's port A, so the old "wait for a bg-idle cycle"
        // re-arm (which existed only because the single port could return the bg's
        // write-address data) is gone: just wait one cycle for the registered q_b
        // to settle, then capture it.  No bg_pmem_active gating, no corruption --
        // the bg writes/reads port A, the CPU reads port B.
        if (data_port_read_pending && local_pmem_read_wait) begin
            local_pmem_read_wait <= 1'b0;
        end else if (data_port_read_pending && remote_dma_pmem_region) begin
            // (The Minimig-era read-corruption probes that lived here were removed
            // for ao486 -- see the Phase 4 instrumentation cleanup in the plan.)
            complete_data_port_transfer(pmem_q_b);
        end

        // The CPU-facing data-port path keeps a bounded eth_dma timeout so the
        // 68k can never hang. The background mailbox DMA (bg_dma_inflight, no
        // data-port access) has NO timeout: it simply waits for the mailbox to
        // complete. Abandoning + re-issuing a background transfer here used to
        // race the clk_audio mailbox FSM (which only samples a new request while
        // idle) and permanently desync the clk_sys<->clk_audio handshake, which
        // ISSP showed as bg_dma_inflight stuck with eth_dma_req low.
        if (eth_dma_req && !eth_dma_ready &&
            (data_port_read_pending || data_port_write_pending ||
             (host_sel && is_data_port_access && (host_rd || host_wr)))) begin
            if (eth_dma_wait_counter != ETH_DMA_TIMEOUT_CYCLES) begin
                eth_dma_wait_counter <= eth_dma_wait_counter + 10'd1;
            end else begin
                eth_dma_wait_counter <= 10'd0;
                debug_dma_timeout_sticky <= 1'b1;
                if (bg_dma_inflight) begin
                    bg_dma_inflight <= 1'b0;
                    eth_dma_wide <= 1'b0;   // never leave a stale wide flag on abort
                    bg_state <= BG_IDLE;
                    bg_polling_rx_flags <= 1'b0;
                    bg_clear_rx_avail <= 1'b0;
                    bg_poll_counter <= BG_POLL_RELOAD;
                end
                complete_data_port_transfer(16'hFFFF);
            end
        end else begin
            eth_dma_wait_counter <= 10'd0;
        end

        if (eth_dma_req && eth_dma_ready) begin
            if (bg_dma_inflight) begin
                bg_dma_inflight <= 1'b0;
                eth_dma_req <= 1'b0;
                // Clear the wide flag on every completion so a stale wide=1 from
                // a payload burst can never be reinterpreted by the mailbox as a
                // 64-bit transfer on the next (narrow) request.
                eth_dma_wide <= 1'b0;

                case (bg_state)
                    BG_READ_FLAGS_WAIT: begin
                        bg_flags_word <= bg_dma_hps_word;
                        if (bg_polling_rx_flags) begin
                            bg_state <= BG_READ_RX_HEAD_REQ;
                        end else if ((bg_dma_hps_word & ETH_FPGA_FLAG_MASK) != fpga_owned_flags) begin
                            bg_clear_rx_avail <= 1'b0;
                            bg_state <= BG_CLEAR_FLAG_REQ;
                        end else begin
                            mirrored_fpga_flags <= bg_dma_hps_word & ETH_FPGA_FLAG_MASK;
                            bg_state <= BG_IDLE;
                            bg_poll_counter <= BG_POLL_RELOAD;
                        end
                    end

                    BG_READ_RX_HEAD_WAIT: begin
                        // Step 3 (publish, do not adopt): RX_QUEUE_HEAD is the
                        // FPGA's own consumer index. It used to be re-adopted from
                        // the window on every poll, which meant any stale or wrong
                        // content there could move our read pointer -- and the
                        // window really does come up as uninitialised DDR (observed
                        // as random bytes before the first clear). The local value
                        // stays authoritative; the read is kept only so the DMA
                        // sequence the HPS sees is unchanged, and its value is now
                        // recorded for diagnostics only.
                        bg_rx_head_seen_shm <= bg_dma_hps_word & ETH_RX_QUEUE_INDEX_MASK;
                        bg_state <= BG_READ_RX_TAIL_REQ;
                    end

                    BG_READ_RX_TAIL_WAIT: begin
                        bg_rx_queue_tail <= bg_dma_hps_word & ETH_RX_QUEUE_INDEX_MASK;
                        if (bg_rx_queue_head[3:0] == bg_dma_hps_word[3:0]) begin
                            bg_polling_rx_flags <= 1'b0;
                            bg_clear_rx_avail <= (bg_flags_word & ETH_FLAG_RX_AVAIL) != 16'h0000;
                            if ((bg_flags_word & ETH_FLAG_RX_AVAIL) != 16'h0000) begin
                                bg_state <= BG_CLEAR_FLAG_REQ;
                            end else begin
                                bg_state <= BG_IDLE;
                                bg_poll_counter <= BG_POLL_RELOAD;
                            end
                        end else begin
                            bg_state <= BG_READ_RX_LEN_REQ;
                        end
                    end

                    BG_READ_RX_LEN_WAIT: begin
                        // RTL8029/NE2000-compatible RX headers report count
                        // including the 4-byte ring header. The driver reads
                        // the header, then subtracts 4 before remote-DMA-reading
                        // the payload.
                        bg_rx_total_length <= bg_rx_length_from_dma + 16'h0004;
                        bg_rx_src_offset <= 16'h0000;
                        bg_rx_bytes_remaining <= bg_rx_length_from_dma;
                        bg_rx_dst_offset <= bg_rx_dst_offset_calc;
                        // per-frame read probe: start this frame's payload checksum,
                        // keyed by its ring start page.
                        bg_rx_next_page <= bg_rx_next_page_calc;
                        bg_rx_queue_next_head <= {12'h000, bg_rx_next_slot};
                        bg_rx_status <= RSR_PRX | RSR_PHY;
                        bg_clear_rx_avail <= (bg_rx_next_slot == bg_rx_queue_tail[3:0]);

                        if (bg_rx_length_from_dma == 16'h0000) begin
                            bg_state <= BG_WRITE_RX_HEAD_REQ;
                        end else if (bg_rx_ring_full_calc) begin
                            rsr_register <= RSR_MPA;
                            isr_register <= isr_register | ISR_OVW;
                            cntr2_register <= cntr2_register + 8'h01;
                            shm_sync_enabled <= 1'b1;
                            bg_sync_slot <= 6'd0;
                            bg_state <= BG_WRITE_RX_HEAD_REQ;
                        end else begin
                            bg_state <= BG_WRITE_HDR0_REQ;
                        end
                    end

                    BG_READ_PAYLOAD_WAIT: begin
                        bg_source_word <= eth_dma_rdata;
                        bg_state <= BG_WRITE_PAYLOAD_REQ;
                    end

                    BG_READ_PAYLOAD_WIDE_WAIT: begin
                        // Whole 64-bit line landed; replay it into packet RAM as
                        // four word writes (bg_wide_idx 0..3).
                        bg_wide_buf <= eth_dma_rdata64;
                        bg_wide_idx <= 2'd0;
                        bg_state    <= BG_WRITE_PAYLOAD_WIDE;
                    end

                    BG_WRITE_TX_LEN_WAIT: begin
                        if (bg_tx_bytes_remaining > 16'h0008) begin
                            bg_wide_idx <= 2'd0;
                            bg_state <= BG_READ_TX_WIDE_REQ;
                        end else if (bg_tx_bytes_remaining != 16'h0000) begin
                            bg_state <= BG_READ_TX_BUF_REQ;
                        end else begin
                            bg_state <= BG_WRITE_TX_SEQ_REQ;
                        end
                    end

                    BG_WRITE_TX_WIDE_WAIT: begin
                        // One 64-bit line published to the HPS TX buffer.  Switch
                        // to the narrow path for the final <=8 bytes so the odd
                        // tail byte is handled exactly as before.
                        bg_tx_src_offset      <= bg_tx_src_offset + 16'h0008;
                        bg_tx_bytes_remaining <= bg_tx_bytes_remaining - 16'h0008;
                        if ((bg_tx_bytes_remaining - 16'h0008) > 16'h0008) begin
                            bg_wide_idx <= 2'd0;
                            bg_state <= BG_READ_TX_WIDE_REQ;
                        end else begin
                            bg_state <= BG_READ_TX_BUF_REQ;
                        end
                    end

                    BG_WRITE_TX_BUF_WAIT: begin
                        if (bg_tx_bytes_remaining > 16'h0002) begin
                            bg_tx_src_offset <= bg_tx_src_offset + 16'h0002;
                            bg_tx_bytes_remaining <= bg_tx_bytes_remaining - 16'h0002;
                            bg_state <= BG_READ_TX_BUF_REQ;
                        end else begin
                            bg_tx_src_offset <= bg_tx_src_offset + bg_tx_bytes_remaining;
                            bg_tx_bytes_remaining <= 16'h0000;
                            bg_state <= BG_WRITE_TX_SEQ_REQ;
                        end
                    end

                    BG_WRITE_TX_ADDR_WAIT: begin
                        bg_state <= BG_WRITE_TX_LEN_REQ;
                    end

                    BG_WRITE_TX_SEQ_WAIT: begin
                        // Background staging finished: the frame is now fully
                        // published to the HPS mailbox (addr/len/payload/seq) and
                        // the HPS can pick up TX_REQUEST_SEQ and transmit. PTX was
                        // already reported at command time (complete-on-command),
                        // so just clear the staging state here.
                        tx_request_seq <= tx_next_request_seq;
                        tx_stage_pending <= 1'b0;
                        tx_request_pending <= 1'b0;
                        // Fix B: the frame is now safely in its window TX slot, so
                        // page 0x40 can be reused -- raise PTX here (staged), not at
                        // command time. The daemon drains the TX ring at its own
                        // pace (every seq, slot = seq % 8) without blocking us.
                        tx_complete_pending <= 1'b1;
                        bg_polling_rx_flags <= 1'b0;
                        bg_clear_rx_avail <= 1'b0;
                        bg_state <= BG_READ_FLAGS_REQ;
                    end

                    BG_READ_TX_DONE_WAIT: begin
                        if ((tx_request_seq != 16'h0000) &&
                            (hps_u16_from_dma(eth_dma_rdata) == tx_request_seq)) begin
                            tx_stage_pending <= 1'b0;
                            tx_request_pending <= 1'b0;
                            tx_complete_pending <= 1'b1;
                            bg_polling_rx_flags <= 1'b0;
                            bg_clear_rx_avail <= 1'b0;
                            bg_state <= BG_READ_FLAGS_REQ;
                        end else begin
                            bg_state <= BG_IDLE;
                        end
                    end

                    BG_CLEAR_FLAG_WAIT: begin
                        mirrored_fpga_flags <= fpga_owned_flags;
                        bg_clear_rx_avail <= 1'b0;
                        bg_state <= BG_IDLE;
                        bg_poll_counter <= BG_POLL_RELOAD;
                    end

                    BG_SYNC_WORD_WAIT: begin
                        if (bg_sync_slot == 6'd49) begin
                            bg_sync_slot <= 6'd0;
                            shm_sync_enabled <= 1'b0;
                        end else begin
                            bg_sync_slot <= bg_sync_slot + 6'd1;
                        end
                        bg_state <= BG_IDLE;
                    end

                    BG_READ_HPS_HB_LO_WAIT: begin
                        bg_hps_heartbeat_lo <= hps_u16_from_dma(eth_dma_rdata);
                        bg_state <= BG_READ_HPS_HB_HI_REQ;
                    end

                    BG_READ_HPS_HB_HI_WAIT: begin
                        if (hps_status_sampled &&
                            ({hps_u16_from_dma(eth_dma_rdata), bg_hps_heartbeat_lo} != hps_heartbeat_seen)) begin
                            hps_heartbeat_change_seen <= 1'b1;
                        end
                        hps_heartbeat_seen <= {hps_u16_from_dma(eth_dma_rdata), bg_hps_heartbeat_lo};
                        hps_status_sampled <= 1'b1;
                        bg_state <= BG_READ_HPS_SIG_LO_REQ;
                    end

                    BG_READ_HPS_SIG_LO_WAIT: begin
                        bg_hps_signature_lo <= hps_u16_from_dma(eth_dma_rdata);
                        bg_state <= BG_READ_HPS_SIG_HI_REQ;
                    end

                    BG_READ_HPS_SIG_HI_WAIT: begin
                        // Latch the signature read result, then issue the status
                        // write through the dedicated BG_WRITE_STATUS_REQ state.
                        // Do NOT assert eth_dma_req inline here.  This block runs in
                        // the same cycle the previous (read) transfer completed, and
                        // line ~1470 is deasserting eth_dma_req.  Re-asserting it in
                        // the same cycle keeps eth_dma_req continuously high, so the
                        // clk_audio mailbox never sees the rising edge it needs to
                        // flip req_toggle (eth_ddr3_mailbox.v: "if (eth_dma_req &&
                        // !req_d)") -> the write is silently dropped and the FSM
                        // deadlocks (ISSP: bg stuck at BG_WRITE_STATUS_WAIT, MBOX
                        // state=idle, wr_acc=0).  Routing through the _REQ block
                        // (guarded by !eth_dma_req && !bg_dma_inflight) guarantees
                        // the same req-low gap every read transaction gets.
                        hps_signature_seen <= {hps_u16_from_dma(eth_dma_rdata), bg_hps_signature_lo};
                        bg_state <= BG_WRITE_STATUS_REQ;
                    end

                    BG_WRITE_STATUS_WAIT: begin
                        hps_poll_counter <= HPS_POLL_RELOAD;
                        bg_state <= BG_IDLE;
                    end

                    BG_INIT_HEAD_WAIT: begin
                        // Published. From here the FPGA owns the consumer index
                        // and never adopts it back from the window.
                        mac_word_idx <= 2'd0;
                        bg_state <= BG_INIT_MAC_REQ;
                    end

                    BG_INIT_MAC_WAIT: begin
                        // Window byte +0 is the logical low byte (measured, see
                        // tb_ne2000_flag_owner), so word N carries MAC[2N] in
                        // bits [7:0] and MAC[2N+1] in bits [15:8].
                        case (mac_word_idx)
                            2'd0: mac_from_host[15:0]  <= mac_word_now;
                            2'd1: mac_from_host[31:16] <= mac_word_now;
                            default: mac_from_host[47:32] <= mac_word_now;
                        endcase

                        if (mac_word_idx == 2'd2) begin
                            // Adopt only a sane address: non-zero, unicast
                            // (bit0 of byte 0 clear) and locally administered
                            // (bit1 set). A zeroed or uninitialised window
                            // fails all three and leaves the built-in default,
                            // so the card still works with no host.
                            if ((mac_host_full != 48'h000000000000) &&
                                !mac_host_full[0] && mac_host_full[1]) begin
                                par_registers[0] <= mac_host_full[7:0];
                                par_registers[1] <= mac_host_full[15:8];
                                par_registers[2] <= mac_host_full[23:16];
                                par_registers[3] <= mac_host_full[31:24];
                                par_registers[4] <= mac_host_full[39:32];
                                par_registers[5] <= mac_host_full[47:40];
                                prom_shadow[0]  <= mac_host_full[7:0];
                                prom_shadow[1]  <= mac_host_full[7:0];
                                prom_shadow[2]  <= mac_host_full[15:8];
                                prom_shadow[3]  <= mac_host_full[15:8];
                                prom_shadow[4]  <= mac_host_full[23:16];
                                prom_shadow[5]  <= mac_host_full[23:16];
                                prom_shadow[6]  <= mac_host_full[31:24];
                                prom_shadow[7]  <= mac_host_full[31:24];
                                prom_shadow[8]  <= mac_host_full[39:32];
                                prom_shadow[9]  <= mac_host_full[39:32];
                                prom_shadow[10] <= mac_host_full[47:40];
                                prom_shadow[11] <= mac_host_full[47:40];
                            end
                            queue_init_done <= 1'b1;
                            bg_state <= BG_IDLE;
                            bg_poll_counter <= BG_POLL_RELOAD;
                        end else begin
                            mac_word_idx <= mac_word_idx + 2'd1;
                            bg_state <= BG_INIT_MAC_REQ;
                        end
                    end

                    BG_WRITE_RX_HEAD_WAIT: begin
                        // RX head write completed.  Advance the LOCAL head (the shm
                        // copy was already written by BG_WRITE_RX_HEAD_REQ) and, if
                        // more frames are already queued (bg_clear_rx_avail==0 means
                        // bg_rx_next_slot != cached tail), drain the next slot
                        // BACK-TO-BACK -- go straight to BG_READ_RX_LEN_REQ instead of
                        // the default IDLE + 63-tick poll + FLAGS/HEAD/TAIL re-read.
                        // bg_rx_queue_head advances this cycle so bg_rx_slot (LEN/data
                        // addrs) and the curr-based ring dst point at the next slot.
                        // The per-frame shm register-sync only runs from BG_IDLE, so
                        // it coalesces to one pass after the whole batch (the Amiga
                        // reads ISR/CURR from local regs, not the deferred shm mirror).
                        // The LAST frame falls through to the original IDLE+re-poll
                        // path, which clears RX_AVAIL and re-reads the tail to pick up
                        // anything the daemon enqueued during the batch.
                        //
                        // ACK INTERLEAVE: a pending Amiga transmit (tx_stage_pending --
                        // almost always a TCP ACK during a download) takes priority over
                        // continuing the back-to-back RX drain.  Without this the ACK is
                        // only serviced at the BG_IDLE dispatch, which the batch loop
                        // bypasses, so the ACK waits until the WHOLE remaining batch
                        // drains (proven in eth_ack_starvation_tb: issued at head=2,
                        // staged at head=8).  The server, seeing no ACK, RTO-retransmits
                        // -> retxDat climbs with dupAck~0 (the daemon's "ACKs aren't
                        // reaching the server" signature) and the download stalls.
                        // Staging it here, between frames, gets the ACK to the HPS
                        // promptly; the RX batch resumes from the persisted
                        // bg_rx_queue_head via the normal flags re-poll after staging
                        // (no frames are lost -- the shm head/tail are re-read).
                        bg_rx_queue_head <= bg_rx_queue_next_head;
                        bg_polling_rx_flags <= 1'b0;
                        if (tx_stage_pending) begin
                            bg_state <= BG_WRITE_TX_ADDR_REQ;
                        end else if (!bg_clear_rx_avail) begin
                            bg_state <= BG_READ_RX_LEN_REQ;
                        end else begin
                            bg_state <= BG_IDLE;
                            bg_poll_counter <= BG_POLL_RELOAD;
                        end
                    end

                    default: begin
                        bg_state <= BG_IDLE;
                        bg_poll_counter <= BG_POLL_RELOAD;
                    end
                endcase
            end else begin
                complete_data_port_transfer(eth_dma_rdata);
            end
        end

        if (data_port_cycle_launch_ok && host_wr) begin
            if (~host_be_hi_n || ~host_be_lo_n) begin
                if (remote_dma_prom_region) begin
                    data_port_transfer_done <= 1'b1;
                    if (dcr_word_mode) begin
                        if (dcr_byte_swap) begin
                            if (!host_be_hi_n) prom_shadow[{remote_dma_addr[4:1], 1'b0}] <= host_wdata[7:0];
                            if (!host_be_lo_n) prom_shadow[{remote_dma_addr[4:1], 1'b1}] <= host_wdata[15:8];
                        end else begin
                            if (!host_be_hi_n) prom_shadow[{remote_dma_addr[4:1], 1'b0}] <= host_wdata[15:8];
                            if (!host_be_lo_n) prom_shadow[{remote_dma_addr[4:1], 1'b1}] <= host_wdata[7:0];
                        end
                    end else if (!remote_dma_addr[0]) begin
                        prom_shadow[remote_dma_addr[4:0]] <= host_write_byte;
                    end else begin
                        prom_shadow[remote_dma_addr[4:0]] <= host_write_byte;
                    end
                    data_port_word_mode <= dcr_word_mode;
                    data_port_byte_addr <= remote_dma_addr;
                    // Local PROM write: never stomp the bg's eth_dma (see complete_data_port_transfer).
                    if (!bg_dma_inflight) eth_dma_req <= 1'b0;
                    eth_dma_write <= 1'b0;
                    eth_dma_uds <= 1'b1;
                    eth_dma_lds <= 1'b1;
                    if (dcr_word_mode) begin
                        remote_dma_addr <= remote_dma_addr + 16'h0002;
                        if (remote_byte_count > 16'h0002) begin
                            remote_byte_count <= remote_byte_count - 16'h0002;
                        end else begin
                            remote_byte_count <= 16'h0000;
                            isr_register <= isr_register | ISR_RDC;
                            shm_sync_enabled <= 1'b1;
                            bg_sync_slot <= 6'd0;
                        end
                    end else begin
                        remote_dma_addr <= remote_dma_addr + 16'h0001;
                        if (remote_byte_count > 16'h0001) begin
                            remote_byte_count <= remote_byte_count - 16'h0001;
                        end else begin
                            remote_byte_count <= 16'h0000;
                            isr_register <= isr_register | ISR_RDC;
                            shm_sync_enabled <= 1'b1;
                            bg_sync_slot <= 6'd0;
                        end
                    end
                end else if (remote_dma_pmem_region) begin
                    data_port_transfer_done <= 1'b1;
                    data_port_word_mode <= dcr_word_mode;
                    data_port_byte_addr <= remote_dma_addr;
                    if (dcr_word_mode) begin
                        remote_dma_addr <= remote_dma_addr + 16'h0002;
                        if (remote_byte_count > 16'h0002) begin
                            remote_byte_count <= remote_byte_count - 16'h0002;
                        end else begin
                            remote_byte_count <= 16'h0000;
                            isr_register <= isr_register | ISR_RDC;
                            shm_sync_enabled <= 1'b1;
                            bg_sync_slot <= 6'd0;
                        end
                    end else begin
                        remote_dma_addr <= remote_dma_addr + 16'h0001;
                        if (remote_byte_count > 16'h0001) begin
                            remote_byte_count <= remote_byte_count - 16'h0001;
                        end else begin
                            remote_byte_count <= 16'h0000;
                            isr_register <= isr_register | ISR_RDC;
                            shm_sync_enabled <= 1'b1;
                            bg_sync_slot <= 6'd0;
                        end
                    end
                end else begin
                    data_port_transfer_done <= 1'b1;
                    data_port_word_mode <= dcr_word_mode;
                    data_port_byte_addr <= remote_dma_addr;
                    // Local unmapped-region access: never stomp the bg's eth_dma.
                    if (!bg_dma_inflight) eth_dma_req <= 1'b0;
                    eth_dma_write <= 1'b0;
                    eth_dma_uds <= 1'b1;
                    eth_dma_lds <= 1'b1;
                    if (dcr_word_mode) begin
                        remote_dma_addr <= remote_dma_addr + 16'h0002;
                        if (remote_byte_count > 16'h0002) begin
                            remote_byte_count <= remote_byte_count - 16'h0002;
                        end else begin
                            remote_byte_count <= 16'h0000;
                            isr_register <= isr_register | ISR_RDC;
                            shm_sync_enabled <= 1'b1;
                            bg_sync_slot <= 6'd0;
                        end
                    end else begin
                        remote_dma_addr <= remote_dma_addr + 16'h0001;
                        if (remote_byte_count > 16'h0001) begin
                            remote_byte_count <= remote_byte_count - 16'h0001;
                        end else begin
                            remote_byte_count <= 16'h0000;
                            isr_register <= isr_register | ISR_RDC;
                            shm_sync_enabled <= 1'b1;
                            bg_sync_slot <= 6'd0;
                        end
                    end
                end
            end
        end else if (data_port_cycle_launch_ok && host_rd) begin
            if (remote_dma_prom_region) begin
                data_port_transfer_done <= 1'b1;
                dbg_prom_rd_cnt <= dbg_prom_rd_cnt + 8'd1;   // diagnostic: count PROM reads
                if (remote_dma_addr == 16'h0000)             // diagnostic: capture first MAC word
                    dbg_prom_rd_first <= dcr_word_mode
                        ? maybe_swap_word(prom_read_word, dcr_byte_swap)
                        : {prom_read_byte, prom_read_byte};
                if (dcr_word_mode) begin
                    data_port_read_data <= maybe_swap_word(prom_read_word, dcr_byte_swap ^ is_dport32_access);
                    remote_dma_addr <= remote_dma_addr + 16'h0002;
                    if (remote_byte_count > 16'h0002) begin
                        remote_byte_count <= remote_byte_count - 16'h0002;
                    end else begin
                        remote_byte_count <= 16'h0000;
                        isr_register <= isr_register | ISR_RDC;
                        shm_sync_enabled <= 1'b1;
                        bg_sync_slot <= 6'd0;
                    end
                end else begin
                    data_port_read_data <= {prom_read_byte, prom_read_byte};
                    remote_dma_addr <= remote_dma_addr + 16'h0001;
                    if (remote_byte_count > 16'h0001) begin
                        remote_byte_count <= remote_byte_count - 16'h0001;
                    end else begin
                        remote_byte_count <= 16'h0000;
                        isr_register <= isr_register | ISR_RDC;
                        shm_sync_enabled <= 1'b1;
                        bg_sync_slot <= 6'd0;
                    end
                end
            end else if (remote_dma_pmem_region) begin
                data_port_word_mode <= dcr_word_mode;
                data_port_byte_addr <= remote_dma_addr;
                data_port_dport32 <= is_dport32_access;   // remember 32-bit-port swap for the deferred read
                local_pmem_read_wait <= 1'b1;
                data_port_read_pending <= 1'b1;
            end else begin
                data_port_transfer_done <= 1'b1;
                if (dcr_word_mode) begin
                    data_port_read_data <= 16'hFFFF;
                    remote_dma_addr <= remote_dma_addr + 16'h0002;
                    if (remote_byte_count > 16'h0002) begin
                        remote_byte_count <= remote_byte_count - 16'h0002;
                    end else begin
                        remote_byte_count <= 16'h0000;
                        isr_register <= isr_register | ISR_RDC;
                        shm_sync_enabled <= 1'b1;
                        bg_sync_slot <= 6'd0;
                    end
                end else begin
                    data_port_read_data <= 16'hFFFF;
                    remote_dma_addr <= remote_dma_addr + 16'h0001;
                    if (remote_byte_count > 16'h0001) begin
                        remote_byte_count <= remote_byte_count - 16'h0001;
                    end else begin
                        remote_byte_count <= 16'h0000;
                        isr_register <= isr_register | ISR_RDC;
                        shm_sync_enabled <= 1'b1;
                        bg_sync_slot <= 6'd0;
                    end
                end
            end
        end

        // Keep data-port pending state alive until the DMA side completes or
        // times out. Real bus strobes can drop before the async memory path
        // answers, and clearing these flags early loses RDC completion.

        if (bg_state == BG_IDLE) begin
            if (!debug_bg_disable && receiver_active && (bg_poll_counter != 8'h00)) begin
                bg_poll_counter <= bg_poll_counter - 8'h01;
            end
            if (!debug_bg_disable && (hps_poll_counter != 8'h00)) begin
                hps_poll_counter <= hps_poll_counter - 8'h01;
            end
            if (!debug_bg_disable &&
                !eth_dma_req &&
                !local_remote_dma_active &&
                !(host_sel && is_data_port_access && (host_rd || host_wr))) begin
                if (!queue_init_done) begin
                    // Step 3: publish our RX consumer index once, before consuming
                    // anything. The daemon reads this to know what we have taken;
                    // if the core reloads while the daemon keeps running, whatever
                    // index was left in the window is stale and would mislead it.
                    // Publishing 0 first makes the FPGA the source of truth from
                    // the moment it comes up.
                    bg_state <= BG_INIT_HEAD_REQ;
                end else if (bg_clear_rx_avail) begin
                    bg_state <= BG_CLEAR_FLAG_REQ;
                end else if (loop_copy_pending) begin
                    // TCR.LB=01: local-only copy, no mailbox round trip, so it
                    // can start the moment the bg is free instead of queuing
                    // behind the HPS-poll cadence below -- the guest is
                    // spinning on ISR waiting for it.
                    loop_copy_pending <= 1'b0;
                    bg_rx_total_length   <= tbcr_register + 16'h0004;
                    bg_rx_src_offset     <= 16'h0000;
                    bg_rx_bytes_remaining <= tbcr_register;
                    bg_rx_dst_offset     <= bg_rx_dst_offset_calc;
                    bg_rx_next_page      <= loop_next_page_calc;
                    bg_rx_status         <= RSR_PRX | RSR_PHY;
                    if (loop_ring_full_calc) begin
                        // No room in the ring: report overrun exactly like the
                        // HPS-fed path does, and skip the copy -- no header,
                        // no payload, same as a real DP8390 dropping a
                        // received frame with nowhere to put it.
                        rsr_register <= RSR_MPA;
                        isr_register <= isr_register | ISR_OVW;
                        cntr2_register <= cntr2_register + 8'h01;
                    end else begin
                        bg_loop_copy <= 1'b1;
                        bg_state <= BG_WRITE_HDR0_REQ;
                    end
                end else if (tx_stage_pending) begin
                    bg_state <= BG_WRITE_TX_ADDR_REQ;
                end else if (tx_request_pending &&
                             ((mirrored_fpga_flags & ETH_FLAG_TX_REQ) != 16'h0000)) begin
                    bg_state <= BG_READ_TX_DONE_REQ;
                end else if (((shm_sync_enabled || tx_request_pending) &&
                     (mirrored_fpga_flags != fpga_owned_flags)) ||
                    (receiver_active && (bg_poll_counter == 8'h00) &&
                     (tcr_loopback_mode == 2'b00))) begin
                    // A real DP8390 in loopback mode disconnects the receiver
                    // from the wire -- the A2065 project hit exactly this the
                    // other way round ("live segment traffic would otherwise
                    // flood the ring") and gates its own loopback path on it.
                    // Without this, the HPS-fed RX-fill poll keeps draining
                    // real incoming LAN frames into the SAME ring the
                    // BG_LOOP_* copy is using, racing it: on real hardware
                    // with live traffic, an ARP/broadcast frame lands in the
                    // ring between the loopback write and readback, so the
                    // guest reads back real wire traffic instead of its own
                    // loopback frame. Neither testbench caught this because
                    // simulation has no live LAN feeding the normal RX path.
                    bg_polling_rx_flags <= receiver_active && (bg_poll_counter == 8'h00) &&
                                           (tcr_loopback_mode == 2'b00);
                    bg_clear_rx_avail <= 1'b0;
                    bg_state <= BG_READ_FLAGS_REQ;
                end else if (hps_poll_counter == 8'h00) begin
                    bg_state <= BG_READ_HPS_HB_LO_REQ;
                end else if (shm_sync_enabled) begin
                    bg_state <= BG_SYNC_WORD_REQ;
                end
            end
        end else if (debug_bg_disable && !eth_dma_req && !bg_dma_inflight &&
                     !local_remote_dma_active &&
                     !(host_sel && is_data_port_access && (host_rd || host_wr))) begin
            bg_state <= BG_IDLE;
            bg_polling_rx_flags <= 1'b0;
            bg_clear_rx_avail <= 1'b0;
            bg_poll_counter <= BG_POLL_RELOAD;
        end else if (!eth_dma_req && !bg_dma_inflight &&
                      // The packet RAM is true dual-port, but hardware captures
                      // showed data-port read checksum mismatches under concurrent
                      // Amiga PIO reads and bg port-A traffic.  Keep mailbox
                      // ownership independent, but do not advance bg states while
                      // the CPU is actively using the packet-RAM data port.
                      !data_port_pmem_busy &&
                      (!local_remote_dma_active || remote_dma_pmem_region) &&
                      !(host_sel && is_data_port_access && (host_rd || host_wr) &&
                        !remote_dma_pmem_region)) begin
            case (bg_state)
                BG_READ_FLAGS_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_flags_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_FLAGS_WAIT;
                end

                BG_READ_RX_HEAD_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_rx_head_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_RX_HEAD_WAIT;
                end

                BG_READ_RX_TAIL_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_rx_tail_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_RX_TAIL_WAIT;
                end

                BG_READ_RX_LEN_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_rx_len_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_RX_LEN_WAIT;
                end

                BG_WRITE_HDR0_REQ: begin
                    bg_state <= BG_WRITE_HDR1_REQ;
                end

                    BG_WRITE_HDR1_REQ: begin
                        // RX payload uses the WORD (narrow) DDR read path. The
                        // 64-bit wide read (eth_dma_rdata64 / avl burst) reads back
                        // as zeros on real hardware -- the header (local regs) and
                        // narrow DDR reads (heartbeat/signature/RX length) are all
                        // correct, only the wide DDR READ fails, so a received frame
                        // landed in packet RAM with a valid header but a zeroed
                        // payload (DHCP OFFER never seen; NE2KMEM packet-RAM
                        // round-trip and NE2KLOOP header both fine, payload all 00).
                        // Narrow reads are slower but correct; RX_WIDE_READ can be
                        // re-enabled once the mailbox 64-bit read path is fixed.
                        //
                        // bg_loop_copy (TCR.LB=01) always takes the narrow-style
                        // local path -- RX_WIDE_READ is an eth_dma (mailbox)
                        // mechanism and the loopback copy never touches the
                        // mailbox -- and finalizes locally (BG_IDLE) instead of
                        // publishing an RX-head update the HPS never asked for.
                        if (bg_loop_copy) begin
                            if (bg_rx_bytes_remaining != 16'h0000) begin
                                bg_state <= BG_LOOP_READ_REQ;
                            end else begin
                                rsr_register <= bg_rx_status;
                                isr_register <= isr_register | ISR_PRX;
                                dbg_prx_set_cnt <= dbg_prx_set_cnt + 8'd1;
                                curr_register <= bg_rx_next_page;
                                bg_loop_copy <= 1'b0;
                                bg_state <= BG_IDLE;
                            end
                        end else if (RX_WIDE_READ && bg_rx_bytes_remaining > 16'h0008) begin
                            bg_state <= BG_READ_PAYLOAD_WIDE_REQ;
                        end else if (bg_rx_bytes_remaining != 16'h0000) begin
                            bg_state <= BG_READ_PAYLOAD_REQ;
                        end else begin
                            rsr_register <= bg_rx_status;
                            isr_register <= isr_register | ISR_PRX;
                            dbg_prx_set_cnt <= dbg_prx_set_cnt + 8'd1;
                            curr_register <= bg_rx_next_page;
                            shm_sync_enabled <= 1'b1;
                            bg_sync_slot <= 6'd0;
                            bg_state <= BG_WRITE_RX_HEAD_REQ;
                        end
                    end

                BG_READ_PAYLOAD_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_payload_src_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_PAYLOAD_WAIT;
                end

                BG_READ_PAYLOAD_WIDE_REQ: begin
                    // Read a full 64-bit line (4 payload words) in one round-trip.
                    // bg_payload_src_word_addr is 64-bit aligned here because the
                    // slot base and bg_rx_src_offset are both multiples of 8.
                    eth_dma_req   <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_wide  <= 1'b1;
                    eth_dma_addr  <= bg_payload_src_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds   <= 1'b0;
                    eth_dma_lds   <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_PAYLOAD_WIDE_WAIT;
                end

                BG_WRITE_PAYLOAD_WIDE: begin
                    // Four local packet-RAM writes (combinational pmem write uses
                    // bg_wide_idx); no mailbox traffic.  After the 4th, advance by
                    // 8 and either keep packing or hand the <=8-byte tail to the
                    // proven narrow path.
                    // Integrity probe: sum this line's 8 payload bytes once (idx 0).
                    if (bg_wide_idx == 2'd3) begin
                        bg_rx_src_offset <= bg_rx_src_offset + 16'h0008;
                        bg_rx_bytes_remaining <= bg_rx_bytes_remaining - 16'h0008;
                        bg_state <= ((bg_rx_bytes_remaining - 16'h0008) > 16'h0008)
                                    ? BG_READ_PAYLOAD_WIDE_REQ
                                    : BG_READ_PAYLOAD_REQ;
                    end else begin
                        bg_wide_idx <= bg_wide_idx + 2'd1;
                        bg_state <= BG_WRITE_PAYLOAD_WIDE;
                    end
                end

                    BG_WRITE_PAYLOAD_REQ: begin
                        if (bg_rx_bytes_remaining > 16'h0001) begin
                            // Integrity probe: both payload bytes of this word.
                            if (bg_rx_bytes_remaining > 16'h0002) begin
                                bg_rx_src_offset <= bg_rx_src_offset + 16'h0002;
                                bg_rx_bytes_remaining <= bg_rx_bytes_remaining - 16'h0002;
                                bg_state <= bg_loop_copy ? BG_LOOP_READ_REQ : BG_READ_PAYLOAD_REQ;
                            end else begin
                                // Last even word. Finalize here; do not issue a
                                // bogus extra read/write for a non-existent odd tail.
                                bg_rx_src_offset <= bg_rx_src_offset + 16'h0002;
                                bg_rx_bytes_remaining <= 16'h0000;
                                rsr_register <= bg_rx_status;
                                isr_register <= isr_register | ISR_PRX;
                                dbg_prx_set_cnt <= dbg_prx_set_cnt + 8'd1;
                                curr_register <= bg_rx_next_page;
                                if (bg_loop_copy) begin
                                    bg_loop_copy <= 1'b0;
                                    bg_state <= BG_IDLE;
                                end else begin
                                    shm_sync_enabled <= 1'b1;
                                    bg_sync_slot <= 6'd0;
                                    bg_state <= BG_WRITE_RX_HEAD_REQ;
                                end
                            end
                        end else begin
                            // Integrity probe: the single odd tail byte actually written.
                            // per-frame probe: finalize this frame's payload sum (incl the
                            // tail byte) and store it keyed by the frame's ring start page.
                            bg_rx_src_offset <= bg_rx_src_offset + bg_rx_bytes_remaining;
                            bg_rx_bytes_remaining <= 16'h0000;
                            rsr_register <= bg_rx_status;
                            isr_register <= isr_register | ISR_PRX;
                            dbg_prx_set_cnt <= dbg_prx_set_cnt + 8'd1;
                            curr_register <= bg_rx_next_page;
                            if (bg_loop_copy) begin
                                bg_loop_copy <= 1'b0;
                                bg_state <= BG_IDLE;
                            end else begin
                                shm_sync_enabled <= 1'b1;
                                bg_sync_slot <= 6'd0;
                                bg_state <= BG_WRITE_RX_HEAD_REQ;
                            end
                        end
                    end

                    // (BG_WRITE_RX_HEAD_WAIT is a dma-completion wait -- handled in
                    //  the eth_dma_ready case where the back-to-back drain lives.)

                BG_WRITE_TX_LEN_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b1;
                    eth_dma_addr <= bg_tx_len_word_addr;
                    eth_dma_wdata <= {tx_stage_len[7:0], tx_stage_len[15:8]};
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_WRITE_TX_LEN_WAIT;
                end

                BG_WRITE_TX_ADDR_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b1;
                    eth_dma_addr <= bg_tx_addr_word_addr;
                    eth_dma_wdata <= {tx_stage_addr[7:0], tx_stage_addr[15:8]};
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_WRITE_TX_ADDR_WAIT;
                end

                BG_READ_TX_BUF_REQ: begin
                    bg_state <= BG_READ_TX_BUF_WAIT1;
                end

                BG_READ_TX_BUF_WAIT1: begin
                    bg_state <= BG_READ_TX_BUF_WAIT2;
                end

                BG_READ_TX_BUF_WAIT2: begin
                    bg_source_word <= pmem_q_a;
                    bg_state <= BG_WRITE_TX_BUF_REQ;
                end

                // TCR.LB=01 local loopback copy: same 2-cycle BRAM-latency read
                // shape as BG_READ_TX_BUF_*, but the captured word feeds back
                // into BG_WRITE_PAYLOAD_REQ (the existing RX-ring write state)
                // instead of BG_WRITE_TX_BUF_REQ (the HPS mailbox write state).
                BG_LOOP_READ_REQ: begin
                    bg_state <= BG_LOOP_READ_WAIT1;
                end

                BG_LOOP_READ_WAIT1: begin
                    bg_state <= BG_LOOP_READ_WAIT2;
                end

                BG_LOOP_READ_WAIT2: begin
                    bg_source_word <= pmem_q_a;
                    bg_state <= BG_WRITE_PAYLOAD_REQ;
                end

                BG_WRITE_TX_BUF_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b1;
                    eth_dma_addr <= bg_tx_dst_word_addr;
                    if (bg_tx_bytes_remaining > 16'h0001) begin
                        eth_dma_wdata <= bg_source_word;
                        eth_dma_uds <= 1'b0;
                        eth_dma_lds <= 1'b0;
                    end else begin
                        eth_dma_wdata <= {bg_source_word[15:8], 8'h00};
                        eth_dma_uds <= 1'b0;
                        eth_dma_lds <= 1'b1;
                    end
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_WRITE_TX_BUF_WAIT;
                end

                BG_READ_TX_WIDE_REQ: begin
                    // Local packet-RAM read of word bg_wide_idx (combinational
                    // pmem_addr); same 2-cycle BRAM latency as the narrow path.
                    bg_state <= BG_READ_TX_WIDE_WAIT1;
                end

                BG_READ_TX_WIDE_WAIT1: begin
                    bg_state <= BG_READ_TX_WIDE_WAIT2;
                end

                BG_READ_TX_WIDE_WAIT2: begin
                    bg_wide_buf[{bg_wide_idx, 4'd0} +: 16] <= pmem_q_a;
                    if (bg_wide_idx == 2'd3) begin
                        bg_wide_idx <= 2'd0;
                        bg_state <= BG_WRITE_TX_WIDE_REQ;
                    end else begin
                        bg_wide_idx <= bg_wide_idx + 2'd1;
                        bg_state <= BG_READ_TX_WIDE_REQ;
                    end
                end

                BG_WRITE_TX_WIDE_REQ: begin
                    // Publish the packed 64-bit line to the HPS TX buffer in one
                    // round-trip.  bg_tx_dst_word_addr is 64-bit aligned (TX
                    // buffer base and bg_tx_src_offset are multiples of 8).
                    eth_dma_req     <= 1'b1;
                    eth_dma_write   <= 1'b1;
                    eth_dma_wide    <= 1'b1;
                    eth_dma_addr    <= bg_tx_dst_word_addr;
                    eth_dma_wdata64 <= bg_wide_buf;
                    eth_dma_uds     <= 1'b0;
                    eth_dma_lds     <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_WRITE_TX_WIDE_WAIT;
                end

                BG_INIT_MAC_REQ: begin
                    // Read the station MAC the host provisioned at
                    // ETH_SHM_CTRL_MAC (three 16-bit words).
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= (ETH_SHM_CTRL_MAC[15:1] + {13'd0, mac_word_idx});
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_INIT_MAC_WAIT;
                end


                BG_INIT_HEAD_REQ: begin
                    // Step 3: publish head = 0 once, before consuming anything,
                    // so a core reload cannot leave a running daemon reading a
                    // stale consumer index.
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b1;
                    eth_dma_addr <= bg_rx_head_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_INIT_HEAD_WAIT;
                end


                BG_WRITE_RX_HEAD_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b1;
                    eth_dma_addr <= bg_rx_head_word_addr;
                    eth_dma_wdata <= {bg_rx_queue_next_head[7:0], bg_rx_queue_next_head[15:8]};
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_WRITE_RX_HEAD_WAIT;
                end

                BG_WRITE_TX_SEQ_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b1;
                    eth_dma_addr <= bg_tx_seq_word_addr;
                    eth_dma_wdata <= {tx_next_request_seq[7:0], tx_next_request_seq[15:8]};
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_WRITE_TX_SEQ_WAIT;
                end

                BG_READ_TX_DONE_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_tx_complete_seq_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_TX_DONE_WAIT;
                end

                BG_CLEAR_FLAG_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b1;
                    eth_dma_addr <= bg_flags_word_addr;
                    eth_dma_wdata <= {bg_flags_write_word[7:0], bg_flags_write_word[15:8]};
                    // The word is stored big-endian in the window, so the swap
                    // above puts our logical HIGH byte into wdata[7:0], which is
                    // the lane lds selects. Enable that lane only: the low byte
                    // belongs to the HPS and must survive untouched.
                    eth_dma_uds <= 1'b1;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_CLEAR_FLAG_WAIT;
                end

                BG_SYNC_WORD_REQ: begin
                    if (!shadow_valid[bg_sync_slot] || (bg_sync_wd != sync_shadow[bg_sync_slot])) begin
                        // First time seen, or value changed: write it and record
                        // the new shadow value.
                        eth_dma_req <= 1'b1;
                        eth_dma_write <= 1'b1;
                        eth_dma_addr <= sync_slot_word_addr(bg_sync_slot);
                        eth_dma_wdata <= bg_sync_wd;
                        eth_dma_uds <= 1'b0;
                        eth_dma_lds <= 1'b0;
                        bg_dma_inflight <= 1'b1;
                        sync_shadow[bg_sync_slot] <= bg_sync_wd;
                        shadow_valid[bg_sync_slot] <= 1'b1;
                        bg_state <= BG_SYNC_WORD_WAIT;
                    end else if (bg_sync_slot == 6'd49) begin
                        // Unchanged and last slot: sync done, no round-trip.
                        bg_sync_slot <= 6'd0;
                        shm_sync_enabled <= 1'b0;
                        bg_state <= BG_IDLE;
                    end else begin
                        // Unchanged: skip to the next slot without a round-trip.
                        bg_sync_slot <= bg_sync_slot + 6'd1;
                    end
                end

                BG_READ_HPS_HB_LO_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_hps_hb_lo_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_HPS_HB_LO_WAIT;
                end

                BG_READ_HPS_HB_HI_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_hps_hb_hi_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_HPS_HB_HI_WAIT;
                end

                BG_READ_HPS_SIG_LO_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_hps_sig_lo_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_HPS_SIG_LO_WAIT;
                end

                BG_READ_HPS_SIG_HI_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b0;
                    eth_dma_addr <= bg_hps_sig_hi_word_addr;
                    eth_dma_wdata <= 16'h0000;
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_READ_HPS_SIG_HI_WAIT;
                end

                BG_WRITE_STATUS_REQ: begin
                    eth_dma_req <= 1'b1;
                    eth_dma_write <= 1'b1;
                    eth_dma_addr <= bg_status_word_addr;
                    eth_dma_wdata <= build_hps_status_dma_word(
                        hps_status_sampled,
                        hps_signature_valid,
                        (hps_heartbeat_seen != 32'h00000000),
                        hps_heartbeat_change_seen,
                        receiver_active,
                        tx_request_pending
                    );
                    eth_dma_uds <= 1'b0;
                    eth_dma_lds <= 1'b0;
                    bg_dma_inflight <= 1'b1;
                    bg_state <= BG_WRITE_STATUS_WAIT;
                end

                default: begin
                    bg_state <= BG_IDLE;
                    bg_poll_counter <= BG_POLL_RELOAD;
                end
            endcase
        end

        if ((|(isr_register & imr_register)) && !irq) dbg_ethirq_cnt <= dbg_ethirq_cnt + 8'd1; // diagnostic: irq rising edges
        irq <= |(isr_register & imr_register);
    end
end

// Address decode logic for the local 64KB ethernet aperture.
wire [15:0] effective_addr;
wire [15:0] byte_addr;

assign effective_addr = {1'b0, host_addr};
assign byte_addr = effective_addr << 1;  // Convert to byte address


// The RTL8019 data port aliases over its register block so longword monitor
// reads can hit the second word within that slot. Reg 0x17 (0xEA0C5C) is carved
// out below as the link/media-status register, so the alias stops at 0xC5B.
//
// X-Surf 16-bit data port at NIC+0x80 (0xEA0C80): the x-surf-100.device driver
// does ALL bulk remote-DMA transfers (the open-time memory test, MAC/PROM read,
// and packet TX/RX) through a wide data port at board+0xC80, NOT the 8-bit
// reg-0x10 window at 0xC40 (see lbC002690/lbC00279E: "MOVE.W ...,($0080,A2)").
// Without decoding it, the driver's memory test reads back open-bus garbage and
// OpenDevice fails -> "AddNetInterface: ... (Input/output error)". The transfer
// itself still targets remote_dma_addr (set via RSAR), so routing this window to
// the same data-port logic is correct; the driver sets DCR.WTS=1 (word mode)
// before using it. xsurftest uses the 0xC40 port, which is why it worked.
// The X-Surf-100 driver detects the card via autoconfig (manuf 0x1212, product
// 0x64) and HARDCODES CardType=2 = 32-bit data-port mode (lbC000656). In that
// mode it does NOT use the 16-bit port at 0xC80; instead it bulk-transfers via
// dedicated 32-bit DMA ports at board offsets 0x8880 (READ, lbC0002D4 MOVE.L)
// and 0x8C80 (WRITE, lbC000226 MOVEM.L). The 68k presents these as 16-bit half
// cycles (0x8880/0x8882, 0x8C80/0x8C82); each must hit the remote-DMA logic and
// advance remote_dma_addr exactly like the 0xC80 port. Without this the driver's
// internal memtest reads back garbage, reports "Datacache is enabled", and skips
// the station-MAC read entirely -> MAC=FF:FF:FF:FF:FF:FF and the stack locks up.
// (These offsets are inside the HPS shm window 0x1000-0xFFFF, so cpu_wrapper.v
// also excludes them from host_sel_priv for the Amiga so they route here.)
assign is_data_port_access =
    ((byte_addr >= 16'h0C40) && (byte_addr <= 16'h0C5B)) ||
    ((byte_addr >= 16'h0C80) && (byte_addr <= 16'h0C9F)) ||
    ((byte_addr >= 16'h8880) && (byte_addr <= 16'h889F)) ||   // 32-bit DMA read port
    ((byte_addr >= 16'h8C80) && (byte_addr <= 16'h8C9F));     // 32-bit DMA write port

// RTL8019/X-Surf link/media-status register at reg 0x17 (0xEA0C5C). The X-Surf
// TestPrg reads it after a transmit: bit0 = link up, bits[2:1] = speed/duplex
// (00=10H, 01=10F, 10=100H, 11=100F). It must NOT be treated as remote-DMA data
// (which read 0 -> "link down!") and must have no data-port side effects.
wire is_link_status = (byte_addr >= 16'h0C5C) && (byte_addr <= 16'h0C5F);
assign is_debug_port_access = (byte_addr >= 16'h0C60) && (byte_addr <= 16'h0C7B);
assign is_reset_port_access = (byte_addr >= 16'h0C7C) && (byte_addr <= 16'h0C7F);

// X-Surf card-level interrupt-status register at board offset 0x40 (0xEA0040).
// The X-Surf TestPrg and the Roadshow driver read this byte; bit 7 reflects the
// NIC interrupt-request line. Without this the offset read open-bus 0xFF, whose
// bit 7 made the test report "Interrupt Bit ist schon gesetzt / Falsche Karte".
wire is_xsurf_int_status = (byte_addr == 16'h0040) || (byte_addr == 16'h0041);

// Register access detection: Only 0xEA1C00-0xEA1C3F range (byte addresses)
// Removed 0xEA1600 range for simplification
assign is_register_access = ((byte_addr >= 16'h0C00) && (byte_addr <= 16'h0C3F));

// Convert word offset to register number for 0xC00 range only
reg [4:0] reg_index_0c00;

always @(*) begin
    reg_index_0c00 = byte_addr[6:2];
end

assign register_select = is_data_port_access ? 5'd16 :                // Data port
                         (is_register_access || is_debug_port_access || is_reset_port_access) ? reg_index_0c00 :  // Register/debug/reset index
                         5'd31;  // Invalid

// Output logic - immediate response with full register set support
always @(*) begin
    // Default outputs
    host_rdata = 16'h0000;

    // Handle the whole configured Ethernet card aperture. Only the RTL8019
    // register/data/debug/reset block has behavior; all other card offsets
    // read as open-bus 0xFFFF but still terminate the CPU cycle.
    if (host_sel && host_rd) begin
        host_rdata = 16'hFFFF;

        if (!host_sel_priv && is_xsurf_int_status) begin
            // bit 7 of each byte lane = NIC interrupt-request line state.
            host_rdata = irq_pending ? 16'h8080 : 16'h0000;
        end
        else if (!host_sel_priv && is_link_status) begin
            // bit0 = link up, bits[2:1] = 01 -> 10 Mbit/s full duplex.
            host_rdata = 16'h0303;
        end
        else if (!host_sel_priv && is_data_port_access) begin
            host_rdata = data_port_read_data;
        end
        else if (!host_sel_priv &&
                 (is_register_access || is_debug_port_access || is_reset_port_access)) begin
            // Register reads - always handle register reads regardless of address translation
                // Return register data - each register gets individual 4-byte space
                // Register values in MSB (high byte) for Amiga bus compatibility
                case (register_select[4:0])
                    // Register 0x00: CR - Command Register
                    5'h00: begin
                        host_rdata = format_reg_read_data(cr_register, host_be_hi_n, host_be_lo_n);
                    end

                    // Register 0x01: CLDA0/PAR0 - Current Local DMA Address 0 or Physical Address Register 0
                    5'h01: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(8'h00, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(par_registers[0], host_be_hi_n, host_be_lo_n);
                            2'b10: host_rdata = format_reg_read_data(pstart_register, host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(rtl8019_e9346cr, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(8'h00, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x02: CLDA1/PAR1 - Current Local DMA Address 1 or Physical Address Register 1
                    5'h02: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(8'h00, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(par_registers[1], host_be_hi_n, host_be_lo_n);
                            2'b10: host_rdata = format_reg_read_data(pstop_register, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(8'h00, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x03: BNRY/PAR2 - Boundary Pointer or Physical Address Register 2
                    5'h03: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(bnry_register, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(par_registers[2], host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(rtl8019_config0, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(bnry_register, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x04: TSR/PAR3 - Transmit Status Register or Physical Address Register 3
                    5'h04: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(tsr_register, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(par_registers[3], host_be_hi_n, host_be_lo_n);
                            2'b10: host_rdata = format_reg_read_data(tpsr_register, host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(rtl8019_config1, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(tsr_register, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x05: NCR/PAR4 - Number of Collisions Register or Physical Address Register 4
                    5'h05: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(8'h00, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(par_registers[4], host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(rtl8019_config2, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(8'h00, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x06: FIFO/PAR5 - FIFO Register or Physical Address Register 5
                    5'h06: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(8'h00, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(par_registers[5], host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(rtl8019_config3, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(8'h00, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x07: ISR/CURR - Interrupt Status Register or Current Page Register
                    5'h07: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(isr_register, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(curr_register, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(isr_register, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x08: CRDA0/MAR0 - Current Remote DMA Address 0 or Multicast Address Register 0
                    5'h08: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(remote_dma_addr[7:0], host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(mar_registers[0], host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(remote_dma_addr[7:0], host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x09: CRDA1/MAR1 - Current Remote DMA Address 1 or Multicast Address Register 1
                    5'h09: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(remote_dma_addr[15:8], host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(mar_registers[1], host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(remote_dma_addr[15:8], host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x0A: 8019ID0/MAR2 - RTL8019AS ID0 or Multicast Address Register 2
                    5'h0A: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(8'h50, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(mar_registers[2], host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(8'h50, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = 16'h0000;
                        endcase
                    end

                    // Register 0x0B: 8019ID1/MAR3 - RTL8019AS ID1 or Multicast Address Register 3
                    5'h0B: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(8'h70, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(mar_registers[3], host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(8'h70, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = 16'h0000;
                        endcase
                    end

                    // Register 0x0C: RSR/MAR4 - Receive Status Register or Multicast Address Register 4
                    5'h0C: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(rsr_register, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(mar_registers[4], host_be_hi_n, host_be_lo_n);
                            2'b10: host_rdata = format_reg_read_data(rcr_register, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(rsr_register, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x0D: CNTR0/MAR5 - Tally Counter 0 or Multicast Address Register 5
                    5'h0D: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(cntr0_register, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(mar_registers[5], host_be_hi_n, host_be_lo_n);
                            2'b10: host_rdata = format_reg_read_data(tcr_register, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(cntr0_register, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x0E: CNTR1/MAR6 - Tally Counter 1 or Multicast Address Register 6
                    5'h0E: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(cntr1_register, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(mar_registers[6], host_be_hi_n, host_be_lo_n);
                            2'b10: host_rdata = format_reg_read_data(dcr_register, host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(8'h50, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(cntr1_register, host_be_hi_n, host_be_lo_n);
                        endcase
                    end

                    // Register 0x0F: CNTR2/IMR/MAR7 - Tally Counter 2, Interrupt Mask Register or MAR7
                    5'h0F: begin
                        case (current_page)
                            2'b00: host_rdata = format_reg_read_data(cntr2_register, host_be_hi_n, host_be_lo_n);
                            2'b01: host_rdata = format_reg_read_data(mar_registers[7], host_be_hi_n, host_be_lo_n);
                            2'b10: host_rdata = format_reg_read_data(imr_register, host_be_hi_n, host_be_lo_n);
                            2'b11: host_rdata = format_reg_read_data(8'h70, host_be_hi_n, host_be_lo_n);
                            default: host_rdata = format_reg_read_data(cntr2_register, host_be_hi_n, host_be_lo_n);
                        endcase
                    end
                    5'h18: begin
                        host_rdata = format_reg_read_data(remote_dma_addr[7:0], host_be_hi_n, host_be_lo_n);
                    end
                    5'h19: begin
                        host_rdata = format_reg_read_data(remote_dma_addr[15:8], host_be_hi_n, host_be_lo_n);
                    end
                    5'h1A: begin
                        host_rdata = format_reg_read_data(remote_byte_count[7:0], host_be_hi_n, host_be_lo_n);
                    end
                    5'h1B: begin
                        host_rdata = format_reg_read_data(remote_byte_count[15:8], host_be_hi_n, host_be_lo_n);
                    end
                    5'h1C: begin
                        host_rdata = format_reg_read_data(debug_status_byte, host_be_hi_n, host_be_lo_n);
                    end
                    5'h1D: begin
                        host_rdata = hps_comm_status_word;
                    end
                    5'h1E: begin
                        host_rdata = hps_heartbeat_seen[15:0];
                    end
                    5'h1F: begin
                        host_rdata = format_reg_read_data(reset_port_latch, host_be_hi_n, host_be_lo_n);
                    end

                    default: host_rdata = 16'h0000;  // Invalid register
                endcase
            end
        end
end

endmodule
/* verilator lint_on DECLFILENAME */
