// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_mailbox_wide_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

`timescale 1ns / 1ps
//
// eth_mailbox_wide_tb.v
//
// Verifies the 64-bit "wide" packing path added to ne2000_ddr_mailbox against the
// proven 16-bit per-lane path, using the REAL mailbox and a behavioral 64-bit
// f2sdram slave (same model as eth_mailbox_arbiter_tb.v).
//
// The whole point of wide packing is that a single 64-bit transfer must leave
// DDR byte-for-byte identical to four single-lane 16-bit transfers, so it can
// never change the on-wire frame bytes the HPS sees.  Checks:
//   1. Four NARROW word writes to lanes 0..3 of one 64-bit word, vs. ONE WIDE
//      write of the same four words to a different 64-bit word -> identical DDR.
//   2. WIDE read of the narrow-written word returns the four words in lane order.
//   3. NARROW reads of the wide-written word return each original word.
// The test is non-vacuous: it fails if the wide lane order or per-lane byte
// swap differs from the narrow path in any lane.
//

module eth_mailbox_wide_tb;

    localparam [28:0] BASE_WORD = 29'h03FE0000;   // 0x1FF00000 >> 3

    reg clk_sys = 0;
    reg clk_avl = 0;
    always #17 clk_sys = ~clk_sys;   // ~29.4 MHz
    always #21 clk_avl = ~clk_avl;   // ~23.8 MHz (async)

    reg reset_sys = 1;
    reg reset_avl = 1;

    // ---- eth_dma interface (clk_sys) ----
    reg         eth_dma_req     = 0;
    reg         eth_dma_write   = 0;
    reg  [15:1] eth_dma_addr    = 0;
    reg  [15:0] eth_dma_wdata   = 0;
    reg         eth_dma_wide    = 0;
    reg  [63:0] eth_dma_wdata64 = 0;
    reg         eth_dma_uds     = 1;
    reg         eth_dma_lds     = 1;
    wire        eth_dma_ready;
    wire [15:0] eth_dma_rdata;
    wire [63:0] eth_dma_rdata64;

    // ---- mailbox Avalon master (clk_avl) -> behavioral slave ----
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

    ne2000_ddr_mailbox mailbox
    (
        .clk_sys(clk_sys), .reset_sys(reset_sys),
        .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
        .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
        .eth_dma_wide(eth_dma_wide), .eth_dma_wdata64(eth_dma_wdata64),
        .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
        .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
        .eth_dma_rdata64(eth_dma_rdata64),

        .clk_avl(clk_avl), .reset_avl(reset_avl),
        .avl_address(s_address), .avl_burstcount(s_burstcount),
        .avl_byteenable(s_byteenable), .avl_writedata(s_writedata),
        .avl_read(s_read), .avl_write(s_write),
        .avl_waitrequest(s_waitrequest), .avl_readdata(s_readdata),
        .avl_readdatavalid(s_readdatavalid),
        .dbg()
    );

    // ---- behavioral f2sdram slave (64-bit, single outstanding, read latency) ----
    localparam ACCEPT_DELAY = 2;
    localparam READ_LAT     = 3;

    reg [63:0] mem [0:16383];

    localparam SS_IDLE = 2'd0, SS_LAT = 2'd1, SS_EMIT = 2'd2;
    reg [1:0]  ss_state = SS_IDLE;
    reg [3:0]  acc_cnt  = 0;
    reg [3:0]  lat_cnt  = 0;
    reg [8:0]  beats    = 0;
    reg [13:0] r_index  = 0;
    reg        is_busy  = 0;

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

            if (cmd_present && s_waitrequest && !is_busy)
                acc_cnt <= acc_cnt + 1'b1;
            else if (!cmd_present)
                acc_cnt <= 0;

            if (cmd_accept) begin
                acc_cnt <= 0;
                if (s_write) begin
                    if (s_byteenable[0]) mem[s_address[13:0]][ 7: 0] <= s_writedata[ 7: 0];
                    if (s_byteenable[1]) mem[s_address[13:0]][15: 8] <= s_writedata[15: 8];
                    if (s_byteenable[2]) mem[s_address[13:0]][23:16] <= s_writedata[23:16];
                    if (s_byteenable[3]) mem[s_address[13:0]][31:24] <= s_writedata[31:24];
                    if (s_byteenable[4]) mem[s_address[13:0]][39:32] <= s_writedata[39:32];
                    if (s_byteenable[5]) mem[s_address[13:0]][47:40] <= s_writedata[47:40];
                    if (s_byteenable[6]) mem[s_address[13:0]][55:48] <= s_writedata[55:48];
                    if (s_byteenable[7]) mem[s_address[13:0]][63:56] <= s_writedata[63:56];
                end else begin
                    r_index <= s_address[13:0];
                    beats   <= {1'b0, s_burstcount};
                    lat_cnt <= READ_LAT;
                    is_busy <= 1'b1;
                    ss_state<= SS_LAT;
                end
            end

            case (ss_state)
                SS_LAT:  if (lat_cnt == 0) ss_state <= SS_EMIT; else lat_cnt <= lat_cnt - 1'b1;
                SS_EMIT: begin
                    rdv <= 1'b1; rdo <= mem[r_index];
                    r_index <= r_index + 1'b1; beats <= beats - 1'b1;
                    if (beats == 1) begin is_busy <= 1'b0; ss_state <= SS_IDLE; end
                end
                default: ;
            endcase
        end
    end

    // ---- eth_dma access tasks (clk_sys) ----
    task eth_write16;
        input [15:1] addr;
        input [15:0] wdata;
        input        uds;     // active low
        input        lds;     // active low
        begin
            @(posedge clk_sys);
            eth_dma_write   <= 1'b1;
            eth_dma_wide    <= 1'b0;
            eth_dma_addr    <= addr;
            eth_dma_wdata   <= wdata;
            eth_dma_uds     <= uds;
            eth_dma_lds     <= lds;
            eth_dma_req     <= 1'b1;
            @(posedge clk_sys);
            while (!eth_dma_ready) @(posedge clk_sys);
            eth_dma_req <= 1'b0;
            @(posedge clk_sys); @(posedge clk_sys);
        end
    endtask

    task eth_read16;
        input  [15:1] addr;
        output [15:0] rdata;
        begin
            @(posedge clk_sys);
            eth_dma_write <= 1'b0;
            eth_dma_wide  <= 1'b0;
            eth_dma_addr  <= addr;
            eth_dma_uds   <= 1'b0;
            eth_dma_lds   <= 1'b0;
            eth_dma_req   <= 1'b1;
            @(posedge clk_sys);
            while (!eth_dma_ready) @(posedge clk_sys);
            rdata = eth_dma_rdata;
            eth_dma_req <= 1'b0;
            @(posedge clk_sys); @(posedge clk_sys);
        end
    endtask

    task eth_write64;
        input [15:1] addr;     // must be 64-bit aligned (addr[2:1]==0)
        input [63:0] wdata64;
        begin
            @(posedge clk_sys);
            eth_dma_write   <= 1'b1;
            eth_dma_wide    <= 1'b1;
            eth_dma_addr    <= addr;
            eth_dma_wdata64 <= wdata64;
            eth_dma_uds     <= 1'b0;
            eth_dma_lds     <= 1'b0;
            eth_dma_req     <= 1'b1;
            @(posedge clk_sys);
            while (!eth_dma_ready) @(posedge clk_sys);
            eth_dma_req  <= 1'b0;
            eth_dma_wide <= 1'b0;
            @(posedge clk_sys); @(posedge clk_sys);
        end
    endtask

    task eth_read64;
        input  [15:1] addr;
        output [63:0] rdata64;
        begin
            @(posedge clk_sys);
            eth_dma_write <= 1'b0;
            eth_dma_wide  <= 1'b1;
            eth_dma_addr  <= addr;
            eth_dma_uds   <= 1'b0;
            eth_dma_lds   <= 1'b0;
            eth_dma_req   <= 1'b1;
            @(posedge clk_sys);
            while (!eth_dma_ready) @(posedge clk_sys);
            rdata64 = eth_dma_rdata64;
            eth_dma_req  <= 1'b0;
            eth_dma_wide <= 1'b0;
            @(posedge clk_sys); @(posedge clk_sys);
        end
    endtask

    function [13:0] idx_of;
        input [15:1] addr;
        idx_of = (BASE_WORD + {16'd0, addr[15:3]}) & 14'h3FFF;
    endfunction

    // group A (narrow), group B (wide): two distinct 64-bit words
    localparam [15:1] A0 = 15'h1000;   // byte 0x2000, lane 0
    localparam [15:1] A1 = 15'h1001;   // byte 0x2002, lane 1
    localparam [15:1] A2 = 15'h1002;   // byte 0x2004, lane 2
    localparam [15:1] A3 = 15'h1003;   // byte 0x2006, lane 3
    localparam [15:1] B0 = 15'h1004;   // byte 0x2008, lane 0 of next 64-bit word

    localparam [15:0] W0 = 16'h1122;
    localparam [15:0] W1 = 16'h3344;
    localparam [15:0] W2 = 16'h5566;
    localparam [15:0] W3 = 16'h7788;

    reg [13:0] ixA, ixB;
    reg [15:0] r16;
    reg [63:0] r64;
    integer    i;

    initial begin
        for (i = 0; i < 16384; i = i + 1) mem[i] = 64'd0;

        repeat (5) @(posedge clk_avl);
        reset_sys <= 0; reset_avl <= 0;
        repeat (5) @(posedge clk_sys);

        // ---- Check 1: four narrow writes vs one wide write -> identical DDR ----
        eth_write16(A0, W0, 1'b0, 1'b0);
        eth_write16(A1, W1, 1'b0, 1'b0);
        eth_write16(A2, W2, 1'b0, 1'b0);
        eth_write16(A3, W3, 1'b0, 1'b0);

        eth_write64(B0, {W3, W2, W1, W0});

        ixA = idx_of(A0);
        ixB = idx_of(B0);
        if (mem[ixA] !== mem[ixB]) begin
            $display("FAIL: wide DDR 0x%016h != narrow DDR 0x%016h", mem[ixB], mem[ixA]);
            errors = errors + 1;
        end else begin
            $display("OK: wide write DDR == narrow write DDR (0x%016h)", mem[ixA]);
        end

        // ---- Check 2: wide read of the narrow-written word ----
        eth_read64(A0, r64);
        if (r64 !== {W3, W2, W1, W0}) begin
            $display("FAIL: wide read got 0x%016h exp 0x%016h", r64, {W3, W2, W1, W0});
            errors = errors + 1;
        end else begin
            $display("OK: wide read returns lane-ordered words 0x%016h", r64);
        end

        // ---- Check 3: narrow reads of the wide-written word ----
        eth_read16(B0, r16);
        if (r16 !== W0) begin $display("FAIL: narrow read lane0 got %04h exp %04h", r16, W0); errors=errors+1; end
        eth_read16(15'h1005, r16);
        if (r16 !== W1) begin $display("FAIL: narrow read lane1 got %04h exp %04h", r16, W1); errors=errors+1; end
        eth_read16(15'h1006, r16);
        if (r16 !== W2) begin $display("FAIL: narrow read lane2 got %04h exp %04h", r16, W2); errors=errors+1; end
        eth_read16(15'h1007, r16);
        if (r16 !== W3) begin $display("FAIL: narrow read lane3 got %04h exp %04h", r16, W3); errors=errors+1; end

        if (errors == 0)
            $display("PASS: eth_mailbox_wide_tb completed (all checks)");
        else
            $display("FAIL: eth_mailbox_wide_tb completed with %0d errors", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: eth_mailbox_wide_tb TIMEOUT");
        $finish;
    end

endmodule
