// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_dma_lane_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

`timescale 1ns / 1ps

module eth_dma_lane_tb;

reg  [15:0] eth_dma_wdata;
reg         eth_dma_uds;
reg         eth_dma_lds;
reg  [1:0] word_lane;

wire [15:0] eth_dma_ddr_wdata = eth_dma_wdata;
wire        eth_dma_ddr_u = eth_dma_uds;
wire        eth_dma_ddr_l = eth_dma_lds;

// This mirrors the ramshared byte swap and byte-enable generation in ddram_ctrl.
// f2sdram sees this 64-bit byte-enable mask directly for partial writes.
wire [15:0] raw_write_dat = {eth_dma_ddr_wdata[7:0], eth_dma_ddr_wdata[15:8]};
wire [1:0]  raw_write_be  = ~{eth_dma_ddr_l, eth_dma_ddr_u};
wire [7:0]  ddram_be      = {6'b000000, raw_write_be} << {word_lane, 1'b0};

function [15:0] hps_u16_from_dma;
    input [15:0] data;
    begin
        hps_u16_from_dma = {data[7:0], data[15:8]};
    end
endfunction

task check_write_lane;
    input [1:0]  lane;
    input [15:0] wdata;
    input        uds_n;
    input        lds_n;
    input [15:0] expected_raw;
    input [7:0]  expected_be;
    input [255:0] label;
    begin
        word_lane = lane;
        eth_dma_wdata = wdata;
        eth_dma_uds = uds_n;
        eth_dma_lds = lds_n;
        #1;
        if (raw_write_dat !== expected_raw || ddram_be !== expected_be) begin
            $display("FAIL: %0s expected raw/be 0x%04x/0x%02x, got 0x%04x/0x%02x",
                     label, expected_raw, expected_be, raw_write_dat, ddram_be);
            $fatal(1);
        end
    end
endtask

task check_hps_bytes_for_write;
    input [15:0] wdata;
    input [7:0]  expected_byte0;
    input [7:0]  expected_byte1;
    input [255:0] label;
    begin
        word_lane = 2'd0;
        eth_dma_wdata = wdata;
        eth_dma_uds = 1'b0;
        eth_dma_lds = 1'b0;
        #1;
        if (raw_write_dat[7:0] !== expected_byte0 ||
            raw_write_dat[15:8] !== expected_byte1) begin
            $display("FAIL: %0s expected HPS bytes %02x %02x, got %02x %02x",
                     label, expected_byte0, expected_byte1,
                     raw_write_dat[7:0], raw_write_dat[15:8]);
            $fatal(1);
        end
    end
endtask

initial begin
    word_lane = 2'd0;

    // Even-byte write: Amiga upper byte should land in the raw low byte.
    check_write_lane(2'd0, 16'h4800, 1'b0, 1'b1, 16'h0048, 8'b00000001,
                     "even byte lane 0");
    check_write_lane(2'd2, 16'h4800, 1'b0, 1'b1, 16'h0048, 8'b00010000,
                     "even byte lane 2");

    // Odd-byte write: Amiga lower byte should land in the raw high byte.
    check_write_lane(2'd0, 16'h0065, 1'b1, 1'b0, 16'h6500, 8'b00000010,
                     "odd byte lane 0");
    check_write_lane(2'd3, 16'h0065, 1'b1, 1'b0, 16'h6500, 8'b10000000,
                     "odd byte lane 3");

    // Word write: Amiga big-endian word should be stored little-endian in raw DDR.
    check_write_lane(2'd0, 16'h4865, 1'b0, 1'b0, 16'h6548, 8'b00000011,
                     "word write lane 0");
    check_write_lane(2'd1, 16'h4865, 1'b0, 1'b0, 16'h6548, 8'b00001100,
                     "word write lane 1");
    check_write_lane(2'd2, 16'h4865, 1'b0, 1'b0, 16'h6548, 8'b00110000,
                     "word write lane 2");
    check_write_lane(2'd3, 16'h4865, 1'b0, 1'b0, 16'h6548, 8'b11000000,
                     "word write lane 3");

    // Packet payload writes preserve wire-order bytes in the HPS byte view.
    check_hps_bytes_for_write(16'hC3D4, 8'hC3, 8'hD4,
                              "TX staging byte order used for HPS-visible C3 D4");
    check_hps_bytes_for_write(16'hD4C3, 8'hD4, 8'hC3,
                              "alternate payload word byte order");

    // Mailbox uint16 fields are read by ethernet.v through hps_u16_from_dma.
    if (hps_u16_from_dma(16'h0200) !== 16'h0002) begin
        $display("FAIL: HPS uint16 length read expected 0x0002");
        $fatal(1);
    end
    if (hps_u16_from_dma(16'h2400) !== 16'h0024) begin
        $display("FAIL: HPS uint16 flag read expected 0x0024");
        $fatal(1);
    end

    $display("PASS: eth_dma_lane_tb completed");
    $finish;
end

endmodule
