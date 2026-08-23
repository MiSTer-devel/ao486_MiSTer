// tb_ne2000_isa_rx.v -- multi-page RX read-out THROUGH the ao486 ISA glue.
//
// tb_ne2000_rx_multipage reads a 2-page frame back correctly, but it drives
// ne2000_core directly. On hardware the guest goes through ne2000_isa (the
// iobus latch/hold/ack glue), and a 300-byte loopback frame reads back almost
// entirely corrupt (NE2KLOOP: ~295/300 bytes wrong, header fine). This bench
// puts the ISA glue in the path -- the full shipped chain -- injects a 300-byte
// pattern frame the way the daemon does, and reads the whole payload back
// through the 16-bit ISA data port (offset 0x10, io_32), byte-for-byte.

`timescale 1ns / 1ps

module tb_ne2000_isa_rx;

    localparam [15:0] OFF_FLAGS   = 16'h1000;
    localparam [15:0] OFF_HB      = 16'h1088;
    localparam [15:0] OFF_SIG     = 16'h108C;
    localparam [15:0] OFF_RX_TAIL = 16'h2C06;
    localparam [15:0] OFF_RX_LEN  = 16'h2C20;
    localparam [15:0] OFF_RX_DATA = 16'h9000;
    localparam [15:0] FLAG_RX_AVAIL = 16'h0004;

    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    integer errors = 0;

    // ISA guest side
    reg  [5:0]  io_address = 0;
    reg         io_read = 0, io_write = 0;
    reg  [31:0] io_writedata = 0;
    reg         io_32 = 0;
    wire [31:0] io_readdata;
    wire        io_wait, irq;

    wire        c_req, c_write, c_wide, c_uds, c_lds;
    wire [15:1] c_addr;
    wire [15:0] c_wdata;
    wire [63:0] c_wdata64;
    wire        c_ready;
    wire [15:0] c_rdata;
    wire [63:0] c_rdata64;

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
    wire [15:1] d_addr;
    wire [15:0] d_wdata;
    wire [63:0] d_wdata64;
    wire        d_ready;
    wire [15:0] d_rdata;
    wire [63:0] d_rdata64;

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

    wire [28:0] m1_address;
    wire  [7:0] m1_burstcount, m1_byteenable;
    wire [63:0] m1_writedata;
    wire        m1_read, m1_write, m1_waitrequest;
    wire [63:0] m1_readdata;
    wire        m1_readdatavalid;

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

    wire [28:0] s_address;
    wire  [7:0] s_burstcount, s_byteenable;
    wire [63:0] s_writedata;
    wire        s_read, s_write;
    wire [63:0] s_readdata;
    wire        s_readdatavalid;

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

    // byte-addressable DDR window
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

    // ---- ISA guest helpers -------------------------------------------------
    integer lat;
    task automatic io_out;         // byte register write
        input [5:0] port; input [7:0] value;
        begin
            @(negedge clk);
            io_address = port; io_writedata = {24'h0, value}; io_32 = 0; io_write = 1;
            @(negedge clk); io_write = 0;
            lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
        end
    endtask
    task automatic io_in;          // byte register read
        input [5:0] port; output [7:0] value;
        begin
            @(negedge clk);
            io_address = port; io_32 = 0; io_read = 1;
            @(negedge clk); io_read = 0;
            lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
            value = io_readdata[7:0];
        end
    endtask
    task automatic io_inw;         // 16-bit data-port read (io_32)
        output [15:0] value;
        begin
            @(negedge clk);
            io_address = 6'h10; io_32 = 1; io_read = 1;
            @(negedge clk); io_read = 0;
            lat = 0; while (io_wait && lat < 5000) begin @(negedge clk); lat = lat + 1; end
            value = io_readdata[15:0];
        end
    endtask

    localparam integer FRAME_LEN = 300;      // 2 pages incl 4-byte header
    localparam [7:0]   EXP_NEXT  = 8'h49;
    reg [7:0] b, curr_v, st_v, next_v, lenlo_v, lenhi_v;
    reg [15:0] got, expw, hdr0, hdr1;
    integer k, mism;

    function [7:0] pat; input integer idx; begin pat = (idx * 7 + 8'h11) & 8'hFF; end endfunction

    initial begin
        for (i = 0; i < 65536; i = i + 1) win[i] = 8'h00;
        repeat (8) @(posedge clk);
        @(negedge clk); reset = 0;
        repeat (20) @(posedge clk);

        // live host
        win[16'h108C]=8'hBE; win[16'h108D]=8'hBA; win[16'h108E]=8'hFE; win[16'h108F]=8'hCA;
        win[16'h1088]=8'h01; win[16'h1089]=8'h00;
        repeat (20) @(posedge clk);

        // init NIC for RX (word mode)
        io_in (6'h18, b);            // reset port
        io_out(6'h07, 8'hFF);        // clear ISR
        io_out(6'h00, 8'h21);        // stop
        io_out(6'h0E, 8'h01);        // DCR word
        io_out(6'h0C, 8'h0C);        // RCR bcast+mcast
        io_out(6'h0D, 8'h00);        // TCR
        io_out(6'h01, 8'h46);        // PSTART
        io_out(6'h02, 8'h80);        // PSTOP
        io_out(6'h03, 8'h46);        // BNRY
        io_out(6'h00, 8'h61);        // page1
        io_out(6'h07, 8'h47);        // CURR
        io_out(6'h00, 8'h22);        // page0 start
        io_out(6'h0F, 8'h0F);        // IMR

        // inject a 300-byte pattern frame
        for (k = 0; k < FRAME_LEN; k = k + 1) win[OFF_RX_DATA + k[15:0]] = pat(k);
        win[OFF_RX_LEN]   = FRAME_LEN[7:0]; win[OFF_RX_LEN+1] = FRAME_LEN[15:8];
        win[OFF_RX_TAIL]  = 8'h01;          win[OFF_RX_TAIL+1] = 8'h00;
        win[OFF_FLAGS]    = FLAG_RX_AVAIL[7:0];

        // wait ISR.PRX
        begin : wp
            integer g;
            for (g = 0; g < 200000; g = g + 1) begin
                @(posedge clk);
                if ((dut.u_core.isr_register & 8'h01) != 8'h00) disable wp;
            end
        end
        if ((dut.u_core.isr_register & 8'h01) == 8'h00) begin
            $display("FAIL: ISR.PRX never set (curr=0x%02x)", dut.u_core.curr_register);
            errors = errors + 1;
        end

        io_out(6'h00, 8'h62); io_in(6'h07, curr_v); io_out(6'h00, 8'h22);
        $display("INFO: CURR=0x%02x (expect 0x%02x)", curr_v, EXP_NEXT);
        if (curr_v !== EXP_NEXT) errors = errors + 1;

        // header via data port
        io_out(6'h0A, 8'h04); io_out(6'h0B, 8'h00);
        io_out(6'h08, 8'h00); io_out(6'h09, 8'h47);
        io_out(6'h00, 8'h0A);
        io_inw(hdr0); io_inw(hdr1);
        st_v = hdr0[7:0]; next_v = hdr0[15:8]; lenlo_v = hdr1[7:0]; lenhi_v = hdr1[15:8];
        $display("INFO: header status=0x%02x next=0x%02x len=0x%02x%02x", st_v, next_v, lenhi_v, lenlo_v);
        if (next_v !== EXP_NEXT) errors = errors + 1;
        if ({lenhi_v,lenlo_v} !== FRAME_LEN[15:0] + 16'h0004) errors = errors + 1;

        // payload via data port, full frame
        io_out(6'h0A, FRAME_LEN[7:0]); io_out(6'h0B, FRAME_LEN[15:8]);
        io_out(6'h08, 8'h04); io_out(6'h09, 8'h47);
        io_out(6'h00, 8'h0A);
        mism = 0;
        for (k = 0; k < FRAME_LEN; k = k + 2) begin
            io_inw(got);
            expw = {pat(k+1), pat(k)};
            if (got !== expw) begin
                if (mism < 16)
                    $display("FAIL: payload word %0d (byte %0d) = 0x%04x, expected 0x%04x",
                             k/2, k, got, expw);
                mism = mism + 1; errors = errors + 1;
            end
        end
        if (mism == 0) $display("INFO: all %0d payload bytes correct", FRAME_LEN);
        else $display("DIAG: %0d/%0d payload words mismatched (first at/after word %0d)",
                      mism, FRAME_LEN/2, 0);

        if (errors == 0) $display("PASS: tb_ne2000_isa_rx");
        else             $display("FAIL: tb_ne2000_isa_rx (%0d error(s))", errors);
        $finish;
    end

    initial begin #20000000; $display("FAIL: global timeout"); $finish; end

endmodule
