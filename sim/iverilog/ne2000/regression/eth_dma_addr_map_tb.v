// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_dma_addr_map_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

`timescale 1ns / 1ps
//
// eth_dma_addr_map_tb.v
//
// Verifies the f2sdram2 address mapping (A2065-style dedicated mailbox).
// The HPS physical byte address recovered from the Avalon word address plus the
// 16-bit lane within the 64-bit DDR word must equal ETH_SHMEM_ADDR + window
// byte offset, proving the FPGA and the ARM mmap touch the same bytes.
//
module eth_dma_addr_map_tb;

reg  [15:1] local_word_addr;
wire [28:0] ddr_word_addr;

ne2000_dma_addr_map dut (
    .local_word_addr(local_word_addr),
    .ddr_word_addr(ddr_word_addr)
);

localparam [31:0] ETH_SHMEM_PHYS       = 32'h1FF00000;   // HPS mmap base
localparam [28:0] ETH_F2SDRAM_BASE_WORD = 29'h03FE0000;  // ETH_SHMEM_PHYS >> 3

// Recover the HPS physical byte address: 64-bit Avalon word << 3, plus the
// 16-bit lane (local_word_addr[2:1]) inside that word.
function [31:0] hps_phys_from_ddr_word_addr;
    input [28:0] word_addr;
    input [15:1] local_addr;
    begin
        hps_phys_from_ddr_word_addr =
            {word_addr, 3'b000} + {29'b0, local_addr[2:1], 1'b0};
    end
endfunction

task check_map;
    input [15:1] local_addr;
    reg   [28:0] expected;
    reg   [31:0] expected_phys;
    reg   [31:0] actual_phys;
    begin
        local_word_addr = local_addr;
        #1;
        expected      = ETH_F2SDRAM_BASE_WORD + {16'd0, local_addr[15:3]};
        expected_phys = ETH_SHMEM_PHYS + {16'h0000, local_addr, 1'b0};
        actual_phys   = hps_phys_from_ddr_word_addr(ddr_word_addr, local_addr);
        if (ddr_word_addr !== expected) begin
            $display("FAIL: local=%04x expected_word=%08x got_word=%08x",
                     {local_addr, 1'b0}, expected, ddr_word_addr);
            $finish(1);
        end
        if (actual_phys !== expected_phys) begin
            $display("FAIL: local=%04x expected_phys=%08x got_phys=%08x",
                     {local_addr, 1'b0}, expected_phys, actual_phys);
            $finish(1);
        end
    end
endtask

initial begin
    check_map(15'h0000);   // window byte 0x0000 -> 0x1FF00000
    check_map(15'h0800);   // window byte 0x1000 -> 0x1FF01000 (ETH_CTRL_FLAGS)
    check_map(15'h0829);   // window byte 0x1052 -> 0x1FF01052 (ETH_CTRL_STATUS, lane 1)
    check_map(15'h1000);   // window byte 0x2000 -> 0x1FF02000 (ETH_TX_BUFFER)
    check_map(15'h1003);   // lane 3
    check_map(15'h1800);   // window byte 0x3000 -> 0x1FF03000 (ETH_NE_MEMORY)
    check_map(15'h7FFF);   // top of window

    $display("PASS: eth_dma_addr_map_tb completed");
    $finish;
end

endmodule
