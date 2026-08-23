// tb_ne2000_flag_owner.v -- Phase 4 step 4: the shared flag word is split by
// owner, so neither side can clobber the other.
//
// Before: the FPGA published its flags with
//     (bg_flags_word & ETH_HPS_FLAG_MASK) | fpga_owned_flags
// a read-modify-write of a word both sides write. Anything the HPS set between
// the FPGA's read and its write was lost.
//
// After: FPGA bits live in the logical high byte, HPS bits in the low byte, and
// each side writes only its own byte lane.
//
// Lane mapping, measured rather than assumed: the core pre-swaps before handing
// the word to the mailbox, which swaps again, so a core-logical word lands in
// the window LOW byte first. Window byte 0x1000 is therefore the logical LOW
// byte (HPS-owned) and 0x1001 the logical HIGH byte (FPGA-owned).

`timescale 1ns / 1ps

module tb_ne2000_flag_owner;

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

// ---- window model, byte addressable for the test ---------------------------
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

// ---- host register access (generic port, byte lane like the ISA glue) ------
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

task automatic check8;
    input [7:0] got, expected;
    input [511:0] label;
    begin
        if (got !== expected) begin
            $display("FAIL: %0s expected 0x%02x got 0x%02x", label, expected, got);
            errors = errors + 1;
        end else $display("ok:   %0s = 0x%02x", label, got);
    end
endtask

initial begin
    for (i = 0; i < 65536; i = i + 1) win[i] = 8'h00;

    repeat (8) @(posedge clk);
    @(negedge clk); reset = 1'b0;
    repeat (10) @(posedge clk);

    // A host is present: signature + heartbeat, stored big-endian.
    win[16'h108C] = 8'hCA; win[16'h108D] = 8'hFE;
    win[16'h108E] = 8'hBA; win[16'h108F] = 8'hBE;
    win[16'h1088] = 8'h00; win[16'h1089] = 8'h01;

    // The daemon raises RX_AVAIL (0x0004) in ITS byte -- the logical low byte,
    // which is window byte 0x1000.
    win[16'h1000] = 8'h04;
    win[16'h1001] = 8'h00;

    // Now make the FPGA publish its own flags: starting the NIC sets ENABLED,
    // so its mirror differs from the window and it writes its lane.
    write_reg(5'h00, 8'h21);          // CR: stop
    write_reg(5'h0F, 8'h1F);          // IMR
    write_reg(5'h00, 8'h22);          // CR: start -> ENABLED
    repeat (4000) @(posedge clk);     // let the background engine publish

    $display("window flags: [0x1000]=%02x (HPS lane)  [0x1001]=%02x (FPGA lane)",
             win[16'h1000], win[16'h1001]);

    // The HPS's bit must be untouched. Before the split this read back 0x00,
    // because the FPGA's read-modify-write wrote back a stale copy.
    check8(win[16'h1000], 8'h04, "HPS RX_AVAIL survived the FPGA publishing flags");

    // And the FPGA's own lane must carry ENABLED (0x2000 -> high byte 0x20).
    if (win[16'h1001] & 8'h20)
        $display("ok:   FPGA published ENABLED in its own lane");
    else begin
        $display("FAIL: FPGA lane does not show ENABLED (got 0x%02x)", win[16'h1001]);
        errors = errors + 1;
    end

    if (errors == 0) $display("PASS: tb_ne2000_flag_owner");
    else             $display("FAIL: tb_ne2000_flag_owner (%0d error(s))", errors);
    $finish;
end

endmodule
