// tb_ne2000_iobus_rx.v -- multi-page RX read-out through the REAL iobus.
//
// tb_ne2000_isa_rx drives ne2000_isa's io_* port directly and passes. On
// hardware a 300-byte loopback frame reads back as: 2 words correct, then all
// zeros (daemon log: 21 49 30 01 00 00 ...). The only thing between the CPU and
// ne2000_isa on hardware that the isa_rx bench omits is rtl/soc/iobus.v -- the
// FSM that pulses bus_read for one cycle and captures bus_readdata on ~bus_wait,
// completing a 16-bit (bus_io32) access in a single accepted beat. This bench
// puts iobus in the path and reads a 2-page frame back exactly as the guest
// does, to reproduce the "2 words then zeros" corruption.

`timescale 1ns / 1ps

module tb_ne2000_iobus_rx;

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

    // ---- CPU <-> iobus ----
    reg         cpu_read_do = 0, cpu_write_do = 0;
    reg  [15:0] cpu_addr = 0;
    reg  [2:0]  cpu_len = 1;
    reg  [31:0] cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire        cpu_read_done, cpu_write_done;

    // ---- iobus <-> device bus ----
    wire [15:0] bus_address;
    wire        bus_write, bus_read;
    wire [2:0]  bus_datasize;
    wire [31:0] bus_writedata;
    wire [31:0] bus_readdata;
    wire        bus_wait;

    // NE2000 decode (mirrors system.v): base 0x300, data port at 0x310-0x317.
    wire        ne2k_cs       = ({bus_address[15:6]} == 10'h00C) && (bus_address[5:4] != 2'b11);
    wire        ne2k_dataport = (bus_address[5:3] == 3'b010);
    wire        ne2k_io32     = ne2k_cs & ne2k_dataport & (bus_datasize != 3'd1);

    wire [31:0] ne2k_readdata;
    wire        ne2k_wait;

    assign bus_readdata = ne2k_cs ? ne2k_readdata : 32'hFFFFFFFF;
    assign bus_wait     = ne2k_wait;
    wire        bus_io32 = ne2k_io32;

    iobus u_iobus (
        .clk(clk), .reset(reset),
        .cpu_read_do(cpu_read_do), .cpu_read_address(cpu_addr), .cpu_read_length(cpu_len),
        .cpu_read_data(cpu_rdata), .cpu_read_done(cpu_read_done),
        .cpu_write_do(cpu_write_do), .cpu_write_address(cpu_addr), .cpu_write_length(cpu_len),
        .cpu_write_data(cpu_wdata), .cpu_write_done(cpu_write_done),
        .bus_address(bus_address), .bus_write(bus_write), .bus_read(bus_read),
        .bus_io32(bus_io32), .bus_datasize(bus_datasize),
        .bus_writedata(bus_writedata), .bus_readdata(bus_readdata), .bus_wait(bus_wait)
    );

    // ---- ne2000_isa + transport chain ----
    wire        c_req, c_write, c_wide, c_uds, c_lds;
    wire [15:1] c_addr;  wire [15:0] c_wdata;  wire [63:0] c_wdata64;
    wire        c_ready; wire [15:0] c_rdata;  wire [63:0] c_rdata64;

    ne2000_isa dut (
        .clk(clk), .reset(reset),
        .io_address(bus_address[5:0]),
        .io_read(bus_read & ne2k_cs), .io_write(bus_write & ne2k_cs),
        .io_writedata(bus_writedata), .io_32(ne2k_io32),
        .io_readdata(ne2k_readdata), .io_wait(ne2k_wait), .irq(),
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

    // ---- CPU-model helpers (drive iobus like the ao486 core) ----
    integer w;
    task automatic cpu_out8;       // byte write to a register
        input [15:0] addr; input [7:0] val;
        begin
            @(negedge clk);
            cpu_addr = addr; cpu_wdata = {24'h0, val}; cpu_len = 3'd1; cpu_write_do = 1;
            @(negedge clk); cpu_write_do = 0;
            w = 0; while (!cpu_write_done && w < 200) begin @(negedge clk); w = w + 1; end
        end
    endtask
    task automatic cpu_in8;        // byte read of a register
        input [15:0] addr; output [7:0] val;
        begin
            @(negedge clk);
            cpu_addr = addr; cpu_len = 3'd1; cpu_read_do = 1;
            @(negedge clk); cpu_read_do = 0;
            w = 0; while (!cpu_read_done && w < 200) begin @(negedge clk); w = w + 1; end
            val = cpu_rdata[7:0];
        end
    endtask
    task automatic cpu_inw;        // 16-bit data-port read (bus_io32)
        input [15:0] addr; output [15:0] val;
        begin
            @(negedge clk);
            cpu_addr = addr; cpu_len = 3'd2; cpu_read_do = 1;
            @(negedge clk); cpu_read_do = 0;
            w = 0; while (!cpu_read_done && w < 200) begin @(negedge clk); w = w + 1; end
            val = cpu_rdata[15:0];
        end
    endtask

    // NE2000 port addresses at base 0x300
    localparam [15:0] P_CR    = 16'h0300;
    localparam [15:0] P_PSTART= 16'h0301;
    localparam [15:0] P_PSTOP = 16'h0302;
    localparam [15:0] P_BNRY  = 16'h0303;
    localparam [15:0] P_ISR   = 16'h0307;
    localparam [15:0] P_RSAR0 = 16'h0308;
    localparam [15:0] P_RSAR1 = 16'h0309;
    localparam [15:0] P_RBCR0 = 16'h030A;
    localparam [15:0] P_RBCR1 = 16'h030B;
    localparam [15:0] P_RCR   = 16'h030C;
    localparam [15:0] P_TCR   = 16'h030D;
    localparam [15:0] P_DCR   = 16'h030E;
    localparam [15:0] P_IMR   = 16'h030F;
    localparam [15:0] P_DATA  = 16'h0310;
    localparam [15:0] P_RESET = 16'h0318;

    localparam integer FRAME_LEN = 300;
    reg [7:0] b, curr_v;
    reg [15:0] got, expw;
    integer k, mism;
    function [7:0] pat; input integer idx; begin pat = (idx * 7 + 8'h11) & 8'hFF; end endfunction

    initial begin
        for (i = 0; i < 65536; i = i + 1) win[i] = 8'h00;
        repeat (8) @(posedge clk);
        @(negedge clk); reset = 0;
        repeat (20) @(posedge clk);

        win[16'h108C]=8'hBE; win[16'h108D]=8'hBA; win[16'h108E]=8'hFE; win[16'h108F]=8'hCA;
        win[16'h1088]=8'h01; win[16'h1089]=8'h00;
        repeat (20) @(posedge clk);

        cpu_in8 (P_RESET, b);
        cpu_out8(P_ISR, 8'hFF);
        cpu_out8(P_CR, 8'h21);
        cpu_out8(P_DCR, 8'h01);
        cpu_out8(P_RCR, 8'h0C);
        cpu_out8(P_TCR, 8'h00);
        cpu_out8(P_PSTART, 8'h46);
        cpu_out8(P_PSTOP, 8'h80);
        cpu_out8(P_BNRY, 8'h46);
        cpu_out8(P_CR, 8'h61);
        cpu_out8(P_ISR, 8'h47);          // CURR (page1 reg7)
        cpu_out8(P_CR, 8'h22);
        cpu_out8(P_IMR, 8'h0F);

        for (k = 0; k < FRAME_LEN; k = k + 1) win[OFF_RX_DATA + k[15:0]] = pat(k);
        win[OFF_RX_LEN]=FRAME_LEN[7:0]; win[OFF_RX_LEN+1]=FRAME_LEN[15:8];
        win[OFF_RX_TAIL]=8'h01; win[OFF_RX_TAIL+1]=8'h00;
        win[OFF_FLAGS]=FLAG_RX_AVAIL[7:0];

        begin : wp
            integer g;
            for (g = 0; g < 300000; g = g + 1) begin
                @(posedge clk);
                if ((dut.u_core.isr_register & 8'h01) != 8'h00) disable wp;
            end
        end
        if ((dut.u_core.isr_register & 8'h01) == 8'h00) begin
            $display("FAIL: ISR.PRX never set"); errors = errors + 1;
        end

        // SINGLE remote read from page start: header(4) + payload, like NE2KLOOP.
        cpu_out8(P_RBCR0, 8'd52); cpu_out8(P_RBCR1, 8'h00);
        cpu_out8(P_RSAR0, 8'h00); cpu_out8(P_RSAR1, 8'h47);
        cpu_out8(P_CR,    8'h0A);
        mism = 0;
        for (k = 0; k < 24; k = k + 1) begin
            cpu_inw(P_DATA, got);
            if (k == 0)      expw = 16'h4921;             // {next,status}
            else if (k == 1) expw = FRAME_LEN[15:0] + 16'h0004;   // length
            else             expw = {pat(2*(k-2)+1), pat(2*(k-2))};  // payload words
            if (got !== expw) begin
                if (mism < 12) $display("FAIL: word %0d = 0x%04x, expected 0x%04x", k, got, expw);
                mism = mism + 1; errors = errors + 1;
            end else if (k < 6) begin
                $display("INFO: word %0d = 0x%04x OK", k, got);
            end
        end
        if (mism == 0) $display("INFO: single-read header+payload all correct");
        else $display("DIAG: %0d/24 words mismatched", mism);

        if (errors == 0) $display("PASS: tb_ne2000_iobus_rx");
        else             $display("FAIL: tb_ne2000_iobus_rx (%0d error(s))", errors);
        $finish;
    end

    initial begin #30000000; $display("FAIL: global timeout"); $finish; end

endmodule
