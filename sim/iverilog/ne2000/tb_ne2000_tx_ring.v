// tb_ne2000_tx_ring.v -- Fix B: the TX ring keeps back-to-back transmits from
// overwriting each other.
//
// Before Fix B the core staged every transmit into a single window buffer
// (0x2000) and reported PTX at command time, so a driver that issued frames
// faster than the daemon drained overwrote the buffer -- under a download's ACK
// storm ~90% of guest transmits were lost (tx_frames << TX_REQUEST_SEQ). Now the
// core stages frame N into slot (N % 8) at 0x3000 + slot*1536 and raises PTX only
// after staging, so several frames coexist in the ring for the daemon to drain.
//
// This bench issues 6 back-to-back transmits WITHOUT any daemon draining them,
// each with a distinct marker byte, and checks every frame is present in its own
// slot -- i.e. none was overwritten.

`timescale 1ns / 1ps

module tb_ne2000_tx_ring;

    localparam [15:0] OFF_HB   = 16'h1088;
    localparam [15:0] OFF_SIG  = 16'h108C;
    localparam [15:0] OFF_TX_SLOT_DATA = 16'h3000;
    localparam [15:0] OFF_TX_REQ_SEQ   = 16'h2C08;

    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    integer errors = 0;

    reg  [5:0]  io_address = 0;
    reg         io_read = 0, io_write = 0;
    reg  [31:0] io_writedata = 0;
    reg         io_32 = 0;
    wire [31:0] io_readdata;
    wire        io_wait, irq;

    wire        c_req, c_write, c_wide, c_uds, c_lds;
    wire [15:1] c_addr;  wire [15:0] c_wdata;  wire [63:0] c_wdata64;
    wire        c_ready; wire [15:0] c_rdata;  wire [63:0] c_rdata64;

    ne2000_isa dut (
        .clk(clk), .reset(reset),
        .io_address(io_address), .io_read(io_read), .io_write(io_write),
        .io_writedata(io_writedata), .io_32(io_32),
        .io_readdata(io_readdata), .io_wait(io_wait), .irq(irq),
        .eth_dma_ready(c_ready), .eth_dma_rdata(c_rdata), .eth_dma_rdata64(c_rdata64),
        .eth_dma_req(c_req), .eth_dma_write(c_write), .eth_dma_addr(c_addr),
        .eth_dma_wdata(c_wdata), .eth_dma_wide(c_wide), .eth_dma_wdata64(c_wdata64),
        .eth_dma_uds(c_uds), .eth_dma_lds(c_lds)
    );

    wire        d_req, d_write, d_wide, d_uds, d_lds;
    wire [15:1] d_addr;  wire [15:0] d_wdata;  wire [63:0] d_wdata64;
    wire        d_ready; wire [15:0] d_rdata;  wire [63:0] d_rdata64;

    ne2000_dma_mux mux (
        .clk(clk), .reset(reset),
        .m0_req(c_req), .m0_write(c_write), .m0_addr(c_addr), .m0_wdata(c_wdata),
        .m0_wide(c_wide), .m0_wdata64(c_wdata64), .m0_uds(c_uds), .m0_lds(c_lds),
        .m0_ready(c_ready), .m0_rdata(c_rdata), .m0_rdata64(c_rdata64),
        .m1_req(1'b0), .m1_write(1'b0), .m1_addr(15'h0), .m1_wdata(16'h0),
        .m1_wide(1'b0), .m1_wdata64(64'h0), .m1_uds(1'b1), .m1_lds(1'b1),
        .m1_ready(), .m1_rdata(), .m1_rdata64(),
        .eth_dma_req(d_req), .eth_dma_write(d_write), .eth_dma_addr(d_addr),
        .eth_dma_wdata(d_wdata), .eth_dma_wide(d_wide), .eth_dma_wdata64(d_wdata64),
        .eth_dma_uds(d_uds), .eth_dma_lds(d_lds),
        .eth_dma_ready(d_ready), .eth_dma_rdata(d_rdata), .eth_dma_rdata64(d_rdata64)
    );

    wire [28:0] m1_address; wire [7:0] m1_burstcount, m1_byteenable;
    wire [63:0] m1_writedata; wire m1_read, m1_write, m1_waitrequest;
    wire [63:0] m1_readdata; wire m1_readdatavalid;

    ne2000_ddr_mailbox mbx (
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

    wire [28:0] s_address; wire [7:0] s_burstcount, s_byteenable;
    wire [63:0] s_writedata; wire s_read, s_write;
    wire [63:0] s_readdata; wire s_readdatavalid;

    ne2000_ddram_arbiter arb (
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

    localparam [28:0] WINDOW_WORD_BASE = 29'h03FE0000;
    reg [7:0] win [0:65535];
    integer i;
    reg rd_pending = 0; reg [63:0] rd_data = 0;
    always @(posedge clk) begin
        rd_pending <= 1'b0;
        if (s_write) for (i = 0; i < 8; i = i + 1)
            if (s_byteenable[i]) win[((s_address - WINDOW_WORD_BASE) << 3) + i] <= s_writedata[i*8 +: 8];
        if (s_read) begin
            for (i = 0; i < 8; i = i + 1)
                rd_data[i*8 +: 8] <= win[((s_address - WINDOW_WORD_BASE) << 3) + i];
            rd_pending <= 1'b1;
        end
    end
    assign s_readdata = rd_data;
    assign s_readdatavalid = rd_pending;

    integer lat;
    task automatic io_out; input [5:0] port; input [7:0] value; begin
        @(negedge clk); io_address = port; io_writedata = {24'h0, value}; io_32 = 0; io_write = 1;
        @(negedge clk); io_write = 0;
        lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
    end endtask
    task automatic io_in; input [5:0] port; output [7:0] value; begin
        @(negedge clk); io_address = port; io_32 = 0; io_read = 1;
        @(negedge clk); io_read = 0;
        lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
        value = io_readdata[7:0];
    end endtask
    task automatic io_outw; input [5:0] port; input [15:0] value; begin
        @(negedge clk); io_address = port; io_writedata = {16'h0, value}; io_32 = 1; io_write = 1;
        @(negedge clk); io_write = 0;
        lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
    end endtask

    localparam integer FRAME_LEN = 60;
    reg [7:0] b;
    integer k, w;

    // Transmit one frame whose bytes are all `marker`, via remote-DMA write to
    // page 0x40 then TXP; wait for ISR.PTX (staged).
    task automatic transmit_marked; input [7:0] marker; begin
        io_out(6'h0A, FRAME_LEN);          // RBCR0
        io_out(6'h0B, 8'h00);
        io_out(6'h08, 8'h00);              // RSAR0
        io_out(6'h09, 8'h40);              // RSAR1 -> 0x4000
        io_out(6'h00, 8'h12);              // remote write
        for (w = 0; w < FRAME_LEN/2; w = w + 1) io_outw(6'h10, {marker, marker});
        io_out(6'h04, 8'h40);              // TPSR
        io_out(6'h05, FRAME_LEN);          // TBCR0
        io_out(6'h06, 8'h00);
        io_out(6'h07, 8'hFF);              // clear ISR
        io_out(6'h00, 8'h26);              // STA | TXP
        begin : wptx
            integer g;
            for (g = 0; g < 40000; g = g + 1) begin
                @(posedge clk);
                if ((dut.u_core.isr_register & 8'h02) != 8'h00) disable wptx;
            end
        end
        if ((dut.u_core.isr_register & 8'h02) == 8'h00) begin
            $display("FAIL: PTX never set for marker 0x%02x (bg_state=%0d)", marker, dut.u_core.bg_state);
            errors = errors + 1;
        end
    end endtask

    initial begin
        for (i = 0; i < 65536; i = i + 1) win[i] = 8'h00;
        repeat (8) @(posedge clk);
        @(negedge clk); reset = 0;
        repeat (20) @(posedge clk);

        // live host
        win[16'h108C]=8'hBE; win[16'h108D]=8'hBA; win[16'h108E]=8'hFE; win[16'h108F]=8'hCA;
        win[16'h1088]=8'h01; win[16'h1089]=8'h00;
        repeat (20) @(posedge clk);

        io_in (6'h18, b);            // reset
        io_out(6'h07, 8'hFF);
        io_out(6'h00, 8'h21);
        io_out(6'h0E, 8'h01);        // DCR word
        io_out(6'h0D, 8'h00);        // TCR
        io_out(6'h00, 8'h22);        // start

        // Wait for the bg to have read the seeded signature/heartbeat so
        // transport_alive is set -- else the first transmit takes the honest
        // abort path (BF-7) instead of staging.
        begin : wait_alive
            integer g;
            for (g = 0; g < 20000; g = g + 1) begin
                @(posedge clk);
                if (dut.u_core.transport_alive) disable wait_alive;
            end
        end

        // 6 back-to-back transmits, markers 0xA1..0xA6, NO daemon draining
        for (k = 1; k <= 6; k = k + 1) transmit_marked(8'hA0 + k[7:0]);

        // TX_REQUEST_SEQ must have reached 6
        if ({win[OFF_TX_REQ_SEQ+1], win[OFF_TX_REQ_SEQ]} !== 16'd6) begin
            $display("FAIL: TX_REQUEST_SEQ=%0d, expected 6",
                     {win[OFF_TX_REQ_SEQ+1], win[OFF_TX_REQ_SEQ]});
            errors = errors + 1;
        end

        // Each frame must still be in its own slot (seq % 8), byte 0 = its marker.
        // With the old single buffer, only the last frame (0xA6) would survive.
        for (k = 1; k <= 6; k = k + 1) begin
            b = win[16'h3000 + ((k % 8) * 16'h0600)];
            if (b !== (8'hA0 + k[7:0])) begin
                $display("FAIL: slot %0d (seq %0d) byte0 = 0x%02x, expected 0x%02x -- frame overwritten",
                         k % 8, k, b, 8'hA0 + k[7:0]);
                errors = errors + 1;
            end else
                $display("ok:   seq %0d -> slot %0d holds 0x%02x", k, k % 8, b);
        end

        if (errors == 0) $display("PASS: tb_ne2000_tx_ring");
        else             $display("FAIL: tb_ne2000_tx_ring (%0d error(s))", errors);
        $finish;
    end

    initial begin #30000000; $display("FAIL: global timeout"); $finish; end

endmodule
