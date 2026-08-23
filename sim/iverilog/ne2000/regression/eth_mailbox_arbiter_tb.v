// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_mailbox_arbiter_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

`timescale 1ns / 1ps
//
// eth_mailbox_arbiter_tb.v
//
// Verifies the A2065-style NE2000 ethernet DDR3 mailbox transport:
//   ne2000_ddr_mailbox  (clk_sys 16-bit eth_dma  ->  clk_avl 64-bit Avalon)
//   ne2000_avalon_arbiter (m0 = ddr_svc burst reads, m1 = mailbox, shared slave)
//
// Checks:
//   1. eth writes land at the correct f2sdram word address, lane, byte order
//      (matching sim/eth_dma_lane_tb.v and the HPS byte view).
//   2. eth reads return the correct Amiga-oriented value (round trip + a value
//      "written by the HPS" placed directly in DDR).
//   3. m0 burst reads return uncorrupted data while m1 mailbox traffic
//      interleaves through the arbiter.
//
// Uses two asynchronous clocks to exercise the clk_sys<->clk_avl CDC.
//

module eth_mailbox_arbiter_tb;

    localparam [28:0] BASE_WORD = 29'h03FE0000;   // 0x1FF00000 >> 3

    // ---- clocks ----
    reg clk_sys = 0;
    reg clk_avl = 0;
    always #17 clk_sys = ~clk_sys;   // ~29.4 MHz
    always #21 clk_avl = ~clk_avl;   // ~23.8 MHz (async to clk_sys)

    reg reset_sys = 1;
    reg reset_avl = 1;

    // ---- eth_dma interface (clk_sys) ----
    reg         eth_dma_req   = 0;
    reg         eth_dma_write = 0;
    reg  [15:1] eth_dma_addr  = 0;
    reg  [15:0] eth_dma_wdata = 0;
    reg         eth_dma_uds   = 1;
    reg         eth_dma_lds   = 1;
    wire        eth_dma_ready;
    wire [15:0] eth_dma_rdata;

    // ---- mailbox Avalon master (clk_avl) ----
    wire [28:0] mbx_address;
    wire [ 7:0] mbx_burstcount;
    wire [ 7:0] mbx_byteenable;
    wire [63:0] mbx_writedata;
    wire        mbx_read;
    wire        mbx_write;
    wire        mbx_waitrequest;
    wire [63:0] mbx_readdata;
    wire        mbx_readdatavalid;

    // ---- m0 (ddr_svc emulation) Avalon master (clk_avl) ----
    reg  [28:0] m0_address    = 0;
    reg  [ 7:0] m0_burstcount = 1;
    reg         m0_read       = 0;
    wire        m0_waitrequest;
    wire [63:0] m0_readdata;
    wire        m0_readdatavalid;

    // ---- shared slave (clk_avl) ----
    wire [28:0] s_address;
    wire [ 7:0] s_burstcount;
    wire [ 7:0] s_byteenable;
    wire [63:0] s_writedata;
    wire        s_read;
    wire        s_write;
    wire        s_waitrequest;
    wire [63:0] s_readdata;
    wire        s_readdatavalid;

    integer errors = 0;

    // ================================================================
    // DUTs
    // ================================================================
    ne2000_ddr_mailbox mailbox
    (
        .clk_sys(clk_sys), .reset_sys(reset_sys),
        .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
        .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
        .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
        .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
        .eth_dma_wide(1'b0),
        .eth_dma_wdata64(64'd0),
        .eth_dma_rdata64(),

        .clk_avl(clk_avl), .reset_avl(reset_avl),
        .avl_address(mbx_address), .avl_burstcount(mbx_burstcount),
        .avl_byteenable(mbx_byteenable), .avl_writedata(mbx_writedata),
        .avl_read(mbx_read), .avl_write(mbx_write),
        .avl_waitrequest(mbx_waitrequest), .avl_readdata(mbx_readdata),
        .avl_readdatavalid(mbx_readdatavalid)
    );

    ne2000_avalon_arbiter arbiter
    (
        .clk(clk_avl), .reset(reset_avl),
        // m0 = ddr_svc
        .m0_address(m0_address), .m0_burstcount(m0_burstcount),
        .m0_byteenable(8'hFF), .m0_writedata(64'd0),
        .m0_read(m0_read), .m0_write(1'b0),
        .m0_waitrequest(m0_waitrequest), .m0_readdata(m0_readdata),
        .m0_readdatavalid(m0_readdatavalid),
        // m1 = mailbox
        .m1_address(mbx_address), .m1_burstcount(mbx_burstcount),
        .m1_byteenable(mbx_byteenable), .m1_writedata(mbx_writedata),
        .m1_read(mbx_read), .m1_write(mbx_write),
        .m1_waitrequest(mbx_waitrequest), .m1_readdata(mbx_readdata),
        .m1_readdatavalid(mbx_readdatavalid),
        // slave
        .s_address(s_address), .s_burstcount(s_burstcount),
        .s_byteenable(s_byteenable), .s_writedata(s_writedata),
        .s_read(s_read), .s_write(s_write),
        .s_waitrequest(s_waitrequest), .s_readdata(s_readdata),
        .s_readdatavalid(s_readdatavalid)
    );

    // ================================================================
    // Behavioral f2sdram slave (64-bit, single outstanding, read latency)
    //   index = s_address[13:0]
    // ================================================================
    localparam ACCEPT_DELAY = 2;   // waitrequest cycles before accept
    localparam READ_LAT     = 3;   // cycles from accept to first readdatavalid

    reg [63:0] mem [0:16383];

    localparam SS_IDLE = 2'd0, SS_LAT = 2'd1, SS_EMIT = 2'd2;
    reg [1:0]  ss_state = SS_IDLE;
    reg [3:0]  acc_cnt  = 0;
    reg [3:0]  lat_cnt  = 0;
    reg [8:0]  beats    = 0;
    reg [13:0] r_index  = 0;
    reg        is_busy  = 0;

    // waitrequest: stall while counting accept delay or while busy with a burst
    wire cmd_present = s_read | s_write;
    assign s_waitrequest = is_busy ? 1'b1 :
                           (cmd_present ? (acc_cnt < ACCEPT_DELAY) : 1'b0);

    wire cmd_accept = cmd_present & ~s_waitrequest;

    reg        rdv;
    reg [63:0] rdo;
    assign s_readdatavalid = rdv;
    assign s_readdata      = rdo;

    always @(posedge clk_avl) begin
        if (reset_avl) begin
            ss_state <= SS_IDLE; acc_cnt <= 0; lat_cnt <= 0; beats <= 0;
            is_busy <= 0; rdv <= 0; rdo <= 0;
        end else begin
            rdv <= 0;

            // accept-delay counter
            if (cmd_present && s_waitrequest && !is_busy)
                acc_cnt <= acc_cnt + 1'b1;
            else if (!cmd_present)
                acc_cnt <= 0;

            // accept a command
            if (cmd_accept) begin
                acc_cnt <= 0;
                if (s_write) begin
                    // apply byte enables to the 64-bit word
                    if (s_byteenable[0]) mem[s_address[13:0]][ 7: 0] <= s_writedata[ 7: 0];
                    if (s_byteenable[1]) mem[s_address[13:0]][15: 8] <= s_writedata[15: 8];
                    if (s_byteenable[2]) mem[s_address[13:0]][23:16] <= s_writedata[23:16];
                    if (s_byteenable[3]) mem[s_address[13:0]][31:24] <= s_writedata[31:24];
                    if (s_byteenable[4]) mem[s_address[13:0]][39:32] <= s_writedata[39:32];
                    if (s_byteenable[5]) mem[s_address[13:0]][47:40] <= s_writedata[47:40];
                    if (s_byteenable[6]) mem[s_address[13:0]][55:48] <= s_writedata[55:48];
                    if (s_byteenable[7]) mem[s_address[13:0]][63:56] <= s_writedata[63:56];
                end else begin
                    // schedule a burst read response
                    r_index <= s_address[13:0];
                    beats   <= {1'b0, s_burstcount};
                    lat_cnt <= READ_LAT;
                    is_busy <= 1'b1;
                    ss_state<= SS_LAT;
                end
            end

            // read response engine
            case (ss_state)
                SS_LAT: begin
                    if (lat_cnt == 0) ss_state <= SS_EMIT;
                    else lat_cnt <= lat_cnt - 1'b1;
                end
                SS_EMIT: begin
                    rdv     <= 1'b1;
                    rdo     <= mem[r_index];
                    r_index <= r_index + 1'b1;
                    beats   <= beats - 1'b1;
                    if (beats == 1) begin
                        is_busy  <= 1'b0;
                        ss_state <= SS_IDLE;
                    end
                end
                default: ;
            endcase
        end
    end

    // ================================================================
    // eth_dma access tasks (clk_sys domain)
    // ================================================================
    task eth_access;
        input        wr;
        input [15:1] addr;
        input [15:0] wdata;
        input        uds;     // active low
        input        lds;     // active low
        output [15:0] rdata;
        begin
            @(posedge clk_sys);
            eth_dma_write <= wr;
            eth_dma_addr  <= addr;
            eth_dma_wdata <= wdata;
            eth_dma_uds   <= uds;
            eth_dma_lds   <= lds;
            eth_dma_req   <= 1'b1;
            @(posedge clk_sys);
            while (!eth_dma_ready) @(posedge clk_sys);
            rdata = eth_dma_rdata;
            eth_dma_req <= 1'b0;
            @(posedge clk_sys);
            @(posedge clk_sys);
        end
    endtask

    // expected slave mem index for a 16-bit-word window offset
    function [13:0] idx_of;
        input [15:1] addr;
        idx_of = (BASE_WORD + {16'd0, addr[15:3]}) & 14'h3FFF;
    endfunction

    function [1:0] lane_of;
        input [15:1] addr;
        lane_of = addr[2:1];
    endfunction

    reg [15:0] rd;
    reg [13:0] ix;
    integer    L;
    reg [63:0] w64;

    // ---- m0 concurrent burst driver control ----
    reg run_m0 = 0;
    reg m0_done = 0;

    initial begin : m0_proc
        integer got;
        integer base;
        integer b;
        m0_read <= 0;
        wait (run_m0);
        for (b = 0; b < 40; b = b + 1) begin
            base = 14'h2000 + (b & 14'h0FFF);   // m0 region, distinct from mailbox
            @(posedge clk_avl);
            m0_address    <= base;
            m0_burstcount <= 8'd4;
            m0_read       <= 1'b1;
            @(posedge clk_avl);
            while (m0_waitrequest) @(posedge clk_avl);
            m0_read <= 1'b0;                      // single command accepted
            got = 0;
            while (got < 4) begin
                @(posedge clk_avl);
                if (m0_readdatavalid) begin
                    if (m0_readdata !== mem[(base + got) & 14'h3FFF]) begin
                        $display("FAIL: m0 burst beat %0d addr %0h got %h exp %h",
                                 got, base+got, m0_readdata, mem[(base+got)&14'h3FFF]);
                        errors = errors + 1;
                    end
                    got = got + 1;
                end
            end
            repeat (2) @(posedge clk_avl);
        end
        m0_done <= 1;
    end

    // ================================================================
    // Main test
    // ================================================================
    integer i;
    initial begin
        // init memory
        for (i = 0; i < 16384; i = i + 1) mem[i] = 64'd0;
        // m0 region pattern
        for (i = 14'h2000; i < 14'h3000; i = i + 1)
            mem[i] = {32'hA5A50000 + i, 16'hBEEF, i[15:0]};

        repeat (5) @(posedge clk_avl);
        reset_sys <= 0;
        reset_avl <= 0;
        repeat (5) @(posedge clk_sys);

        // ---- Phase 1: write/read lane + byte order ----
        // Word write at offset 0x1052 (lane 1): wdata 0x4865, both bytes.
        eth_access(1'b1, 15'h0829, 16'h4865, 1'b0, 1'b0, rd);   // addr 0x1052>>1=0x829
        ix = idx_of(15'h0829); L = lane_of(15'h0829);
        // lane 1 -> bytes [2],[3]; byte[2]=upper(0x48), byte[3]=lower(0x65)
        if (mem[ix][8*(2*L) +: 8] !== 8'h48 || mem[ix][8*(2*L+1) +: 8] !== 8'h65) begin
            $display("FAIL: word write byte layout idx %0h lane %0d got %02h %02h",
                     ix, L, mem[ix][8*(2*L) +: 8], mem[ix][8*(2*L+1) +: 8]);
            errors = errors + 1;
        end
        // read it back, expect Amiga-oriented 0x4865
        eth_access(1'b0, 15'h0829, 16'h0000, 1'b0, 1'b0, rd);
        if (rd !== 16'h4865) begin
            $display("FAIL: word read back got %04h exp 4865", rd); errors = errors + 1;
        end

        // Even-byte-only write (uds active, lds inactive) at lane 0, offset 0x2000
        eth_access(1'b1, 15'h1000, 16'h4800, 1'b0, 1'b1, rd);   // 0x2000>>1
        ix = idx_of(15'h1000); L = lane_of(15'h1000);
        if (mem[ix][8*(2*L) +: 8] !== 8'h48) begin
            $display("FAIL: even-byte write byte[2L] got %02h exp 48",
                     mem[ix][8*(2*L) +: 8]); errors = errors + 1;
        end

        // Odd-byte-only write (lds active, uds inactive) at lane 3
        // choose addr with lane 3: addr[2:1]=3 -> addr bits 2,1 =1,1 ; offset byte = 6 within word
        eth_access(1'b1, 15'h1003, 16'h0065, 1'b1, 1'b0, rd);   // addr[2:1]=3
        ix = idx_of(15'h1003); L = lane_of(15'h1003);
        if (mem[ix][8*(2*L+1) +: 8] !== 8'h65) begin
            $display("FAIL: odd-byte write byte[2L+1] got %02h exp 65",
                     mem[ix][8*(2*L+1) +: 8]); errors = errors + 1;
        end

        // ---- HPS-written value read by FPGA ----
        // HPS writes little-endian uint16 0xCAFE at window offset 0x108C lane.
        // Place bytes directly: byte[2L]=0xFE (LE low), byte[2L+1]=0xCA.
        ix = idx_of(15'h0846); L = lane_of(15'h0846);   // 0x108C>>1 = 0x846
        mem[ix][8*(2*L)   +: 8] = 8'hFE;
        mem[ix][8*(2*L+1) +: 8] = 8'hCA;
        eth_access(1'b0, 15'h0846, 16'h0000, 1'b0, 1'b0, rd);
        // ethernet.v applies hps_u16_from_dma() = swap to recover 0xCAFE; the
        // mailbox returns the pre-swap value swap(0xCAFE)=0xFECA.
        if (rd !== 16'hFECA) begin
            $display("FAIL: HPS-written read got %04h exp FECA (pre hps_u16 swap)", rd);
            errors = errors + 1;
        end

        // ---- Phase 3: concurrent m0 bursts + m1 mailbox traffic ----
        run_m0 <= 1;
        for (i = 0; i < 32; i = i + 1) begin
            eth_access(1'b1, 15'h0900 + i[14:0], 16'h1000 + i[15:0], 1'b0, 1'b0, rd);
            eth_access(1'b0, 15'h0900 + i[14:0], 16'h0000, 1'b0, 1'b0, rd);
            if (rd !== (16'h1000 + i[15:0])) begin
                $display("FAIL: concurrent rw mismatch i=%0d got %04h exp %04h",
                         i, rd, 16'h1000 + i[15:0]);
                errors = errors + 1;
            end
        end
        wait (m0_done);

        if (errors == 0)
            $display("PASS: eth_mailbox_arbiter_tb completed (all checks)");
        else
            $display("FAIL: eth_mailbox_arbiter_tb completed with %0d errors", errors);
        $finish;
    end

    // global timeout
    initial begin
        #2000000;
        $display("FAIL: eth_mailbox_arbiter_tb TIMEOUT");
        $finish;
    end

endmodule
