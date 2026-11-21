// Ported for the ao486 NE2000 (Phase 1 of NE2000_AO486_PLAN.md) from the
// Minimig-AGA Ethernet_shmem2 branch, commit 9598b936
// (apolkosnik/Minimig-AGA_MiSTer, GPL). Module renamed; logic unchanged.
//
//
// ne2000_dma_addr_map.v
//
// Single source of truth (RTL side) for the NE2000 ethernet DDR3 mailbox base.
//
// Maps a 16-bit-word offset inside the 64KB shared window to the absolute
// f2sdram2 (ram2) Avalon word address.  The f2sdram2 port is 64-bit, so the
// Avalon word address is the HPS physical byte address >> 3.
//
//   HPS physical base  : 0x1FF00000   (reserved high DDR; matches A2065 and the
//                                       HPS mmap in extra/minimig_eth.h)
//   f2sdram2 word base : 0x1FF00000 >> 3 = 0x03FE0000
//
// local_word_addr[15:1] is a 16-bit-word offset; the 64-bit word index within
// the window is local_word_addr[15:3] (drop the low 3 byte/lane bits, which the
// mailbox handles via byteenable and lane placement).
//
// This module is instantiated by rtl/eth_ddr3_mailbox.v so the base lives in
// exactly one place.  extra/minimig_eth.h must keep ETH_SHMEM_ADDR == base<<3.
//
module ne2000_dma_addr_map
(
    input  wire [15:1] local_word_addr,
    output wire [28:0] ddr_word_addr
);

localparam [28:0] ETH_F2SDRAM_BASE_WORD = 29'h03FE0000;   // 0x1FF00000 >> 3

assign ddr_word_addr = ETH_F2SDRAM_BASE_WORD + {16'd0, local_word_addr[15:3]};

endmodule
