// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_rx_concurrent_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_rx_concurrent_tb.v
//
// Stresses the one RX delivery path no other testbench exercises: the Amiga
// reading a received frame through the remote-DMA data port WHILE the background
// FSM is simultaneously writing a NEW frame into the ring. Both touch the single
// -port packet RAM, muxed by priority in ethernet.v; during a real download this
// happens constantly (bg writes frame N+1 while the 68020 PIO-reads frame N). If
// the contention/deferral mux ever returns stale or wrong data for the CPU read,
// the Amiga gets a corrupt frame -> TCP drops it -> dup-ACK -> the server
// retransmits (ETHPERF retx) with every drop counter at zero -- the residual
// download loss under investigation.
//
// Drives the REAL ethernet_interface + REAL ne2000_ddr_mailbox + behavioral
// f2sdram. Frame A is delivered to page 0x50; then frame B is delivered to page
// 0x60 while, concurrently (fork/join), the Amiga reads frame A back through the
// data port. Both must be byte-exact: A through the concurrent reads, B in
// packet RAM afterwards.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_rx_concurrent_tb;

    localparam [15:0] OFF_FLAGS      = 16'h1000;
    localparam [15:0] OFF_HB         = 16'h1088;
    localparam [15:0] OFF_SIG        = 16'h108C;
    localparam [15:0] OFF_RX_HEAD    = 16'h2C04;
    localparam [15:0] OFF_RX_TAIL    = 16'h2C06;
    localparam [15:0] OFF_RX_LEN     = 16'h2C20;
    localparam [15:0] OFF_RX_DATA    = 16'h9000;
    localparam [15:0] RX_SLOT_SIZE   = 16'h0600;
    localparam integer RX_QUEUE_SLOTS = 16;
    localparam [15:0] FLAG_RX_AVAIL  = 16'h0004;

    localparam integer FLEN      = 1024;     // frame payload bytes
    localparam [7:0]   PAGE_A    = 8'h50;
    localparam [7:0]   PAGE_B    = 8'h60;

    reg clk_sys = 0;
    reg clk_avl = 0;
    always #17 clk_sys = ~clk_sys;
    always #21 clk_avl = ~clk_avl;

    reg reset_sys = 1;
    reg reset_avl = 1;

    reg  [15:1] cpu_addr     = 0;
    reg  [15:0] cpu_data_in  = 0;
    wire [15:0] cpu_data_out;
    reg         cpu_rd       = 0;
    reg         cpu_hwr      = 0;
    reg         cpu_lwr      = 0;
    reg         cpu_as       = 1;
    reg         cpu_uds      = 1;
    reg         cpu_lds      = 1;
    reg         sel_ethernet_shm = 0;
    reg         sel_ethernet     = 0;

    wire        eth_dma_ready;
    wire [15:0] eth_dma_rdata;
    wire [63:0] eth_dma_rdata64;
    wire        eth_dma_wide;
    wire [63:0] eth_dma_wdata64;
    wire        eth_dma_req;
    wire        eth_dma_write;
    wire [15:1] eth_dma_addr;
    wire [15:0] eth_dma_wdata;
    wire        eth_dma_uds;
    wire        eth_dma_lds;
    wire        eth_irq;
    wire        dtack_eth;

    wire [28:0] avl_address;
    wire [ 7:0] avl_burstcount;
    wire [ 7:0] avl_byteenable;
    wire [63:0] avl_writedata;
    wire        avl_read;
    wire        avl_write;
    wire        avl_waitrequest;
    wire [63:0] avl_readdata;
    wire        avl_readdatavalid;

    integer errors = 0;

    // Count cycles in the exact race window: a data-port read is in its settling
    // cycle (port B) while the bg is writing the ring (port A, pmem_wren_a). On the
    // OLD single-port code that latched the bg's bytes as the Amiga's frame byte
    // -> corrupt RX -> retx; the true dual-port RAM makes the two ports physically
    // independent so the CPU read can NEVER see the bg write. race_hits>0 proves
    // the test actually exercised the window, and the byte-exact checks below prove
    // the dual-port keeps the read clean through it.
    integer race_hits = 0;
    always @(posedge clk_sys) begin
        if (!reset_sys && dut.data_port_read_pending && dut.local_pmem_read_wait && dut.pmem_wren_a)
            race_hits = race_hits + 1;
    end

    ne2000_core dut (
        .clk(clk_sys), .reset(reset_sys),
        .host_addr(cpu_addr), .host_wdata(cpu_data_in), .host_rdata(cpu_data_out),
        .host_rd(cpu_rd), .host_wr_hi(cpu_hwr), .host_wr_lo(cpu_lwr),
        .host_cyc_n(cpu_as), .host_be_hi_n(cpu_uds), .host_be_lo_n(cpu_lds),
        .host_sel_priv(sel_ethernet_shm), .host_sel(sel_ethernet),
        .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
        .eth_dma_rdata64(eth_dma_rdata64),
        .eth_dma_wide(eth_dma_wide),
        .eth_dma_wdata64(eth_dma_wdata64),
        .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
        .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
        .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
        .irq(eth_irq), .host_ack_n(dtack_eth)
    );

    ne2000_ddr_mailbox mailbox (
        .clk_sys(clk_sys), .reset_sys(reset_sys),
        .eth_dma_req(eth_dma_req), .eth_dma_write(eth_dma_write),
        .eth_dma_addr(eth_dma_addr), .eth_dma_wdata(eth_dma_wdata),
        .eth_dma_uds(eth_dma_uds), .eth_dma_lds(eth_dma_lds),
        .eth_dma_ready(eth_dma_ready), .eth_dma_rdata(eth_dma_rdata),
        .eth_dma_rdata64(eth_dma_rdata64),
        .eth_dma_wide(eth_dma_wide),
        .eth_dma_wdata64(eth_dma_wdata64),
        .clk_avl(clk_avl), .reset_avl(reset_avl),
        .avl_address(avl_address), .avl_burstcount(avl_burstcount),
        .avl_byteenable(avl_byteenable), .avl_writedata(avl_writedata),
        .avl_read(avl_read), .avl_write(avl_write),
        .avl_waitrequest(avl_waitrequest), .avl_readdata(avl_readdata),
        .avl_readdatavalid(avl_readdatavalid),
        .dbg()
    );

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
    wire cmd_present = avl_read | avl_write;
    assign avl_waitrequest = is_busy ? 1'b1 : (cmd_present ? (acc_cnt < ACCEPT_DELAY) : 1'b0);
    wire cmd_accept = cmd_present & ~avl_waitrequest;
    reg        rdv = 0;
    reg [63:0] rdo = 0;
    assign avl_readdatavalid = rdv;
    assign avl_readdata      = rdo;
    integer i;
    initial for (i = 0; i < 16384; i = i + 1) mem[i] = 64'd0;

    always @(posedge clk_avl) begin
        if (reset_avl) begin
            ss_state <= SS_IDLE; acc_cnt <= 0; lat_cnt <= 0; beats <= 0;
            is_busy <= 0; rdv <= 0; rdo <= 0;
        end else begin
            rdv <= 0;
            if (cmd_present && avl_waitrequest && !is_busy) acc_cnt <= acc_cnt + 1'b1;
            else if (!cmd_present) acc_cnt <= 0;
            if (cmd_accept) begin
                acc_cnt <= 0;
                if (avl_write) begin
                    if (avl_byteenable[0]) mem[avl_address[13:0]][ 7: 0] <= avl_writedata[ 7: 0];
                    if (avl_byteenable[1]) mem[avl_address[13:0]][15: 8] <= avl_writedata[15: 8];
                    if (avl_byteenable[2]) mem[avl_address[13:0]][23:16] <= avl_writedata[23:16];
                    if (avl_byteenable[3]) mem[avl_address[13:0]][31:24] <= avl_writedata[31:24];
                    if (avl_byteenable[4]) mem[avl_address[13:0]][39:32] <= avl_writedata[39:32];
                    if (avl_byteenable[5]) mem[avl_address[13:0]][47:40] <= avl_writedata[47:40];
                    if (avl_byteenable[6]) mem[avl_address[13:0]][55:48] <= avl_writedata[55:48];
                    if (avl_byteenable[7]) mem[avl_address[13:0]][63:56] <= avl_writedata[63:56];
                end else begin
                    r_index <= avl_address[13:0]; beats <= {1'b0, avl_burstcount};
                    lat_cnt <= READ_LAT; is_busy <= 1'b1; ss_state <= SS_LAT;
                end
            end
            case (ss_state)
                SS_LAT:  if (lat_cnt == 0) ss_state <= SS_EMIT; else lat_cnt <= lat_cnt - 1'b1;
                SS_EMIT: begin
                    rdv <= 1'b1; rdo <= mem[r_index]; r_index <= r_index + 1'b1; beats <= beats - 1'b1;
                    if (beats == 1) begin is_busy <= 1'b0; ss_state <= SS_IDLE; end
                end
                default: ;
            endcase
        end
    end

    task automatic ddr_write_byte;
        input [15:0] byte_off;
        input [7:0]  val;
        reg [13:0] widx; integer bsh;
        begin
            widx = byte_off >> 3;
            bsh  = (byte_off & 7) * 8;
            mem[widx][bsh +: 8] = val;
        end
    endtask

    task automatic ddr_write_u16;
        input [15:0] byte_off;
        input [15:0] val;
        begin
            ddr_write_byte(byte_off,         val[7:0]);
            ddr_write_byte(byte_off + 16'd1, val[15:8]);
        end
    endtask

    function [15:0] ddr_read_u16;
        input [15:0] byte_off;
        reg [13:0] widx; integer bsh;
        begin
            widx = byte_off >> 3;
            bsh  = (byte_off & 7) * 8;
            ddr_read_u16 = {mem[widx][bsh+8 +: 8], mem[widx][bsh +: 8]};
        end
    endfunction

    task automatic write_high_reg;
        input [14:0] word_offset;
        input [7:0]  value;
        begin
            @(negedge clk_sys);
            cpu_addr = word_offset; cpu_data_in = {value, 8'h00};
            sel_ethernet = 1'b1; cpu_hwr = 1'b1; cpu_lwr = 1'b0;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b1;
            @(posedge clk_sys);
            @(negedge clk_sys);
            cpu_hwr = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1;
            sel_ethernet = 1'b0; cpu_data_in = 16'h0000;
        end
    endtask

    task automatic data_port_read_word;
        output [15:0] value;
        integer w;
        reg done;
        begin
            done = 1'b0; value = 16'hXXXX;
            @(negedge clk_sys);
            cpu_addr = 15'h0620; sel_ethernet = 1'b1; cpu_rd = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) begin value = cpu_data_out; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin
                $display("FAIL: data-port read timed out"); errors = errors + 1;
            end
            @(negedge clk_sys);
        end
    endtask

    function [15:0] pram_word;
        input [15:0] ne_addr;
        reg [12:0] idx;
        begin
            idx = (ne_addr - 16'h4000) >> 1;
            pram_word = {dut.packet_ram_inst.mem_u[idx], dut.packet_ram_inst.mem_l[idx]};
        end
    endfunction

    reg [7:0]  frame [0:FLEN-1];
    integer    k;
    reg [15:0] gg, ew;
    reg [7:0]  eh, el;
    integer    bad_a, bad_b;
    reg [15:0] a_read [0:FLEN/2 - 1];

    // Deliver frame[] (length FLEN) at start_page into shared slot; wait until
    // the bg has consumed it (head==expected). Does NOT verify -- callers verify.
    task automatic deliver;
        input [7:0]   start_page;
        input integer slot;
        reg   [15:0]  sdata, slen, exp_head;
        integer       kk, g;
        begin
            sdata = OFF_RX_DATA + slot[15:0]*RX_SLOT_SIZE;
            slen  = OFF_RX_LEN  + slot[15:0]*16'h0002;
            dut.curr_register = start_page;
            dut.bnry_register = 8'h7E;            // far from A/B: ring has room
            repeat (4) @(posedge clk_sys);
            for (kk = 0; kk < FLEN; kk = kk + 1)
                ddr_write_byte(sdata + kk[15:0], frame[kk]);
            ddr_write_u16(slen, FLEN[15:0]);
            exp_head = (slot + 1) % RX_QUEUE_SLOTS;
            ddr_write_u16(OFF_RX_TAIL, exp_head);
            ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);
            for (g = 0; g < 400000; g = g + 1) begin
                @(posedge clk_sys);
                if (ddr_read_u16(OFF_RX_HEAD) == exp_head) g = 400001;
            end
        end
    endtask

    initial begin
        frame[0]=8'h02; frame[1]=8'h11; frame[2]=8'h22; frame[3]=8'h33; frame[4]=8'h44; frame[5]=8'h55;
        frame[6]=8'hDE; frame[7]=8'hAD; frame[8]=8'hBE; frame[9]=8'hEF; frame[10]=8'h01; frame[11]=8'h02;
        frame[12]=8'h08; frame[13]=8'h00;
        for (k = 14; k < FLEN; k = k + 1) frame[k] = (k + 8'h33) & 8'hFF;

        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys);
        @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        ddr_write_u16(OFF_SIG,         16'hBABE);
        ddr_write_u16(OFF_SIG + 16'd2, 16'hCAFE);
        ddr_write_u16(OFF_HB,          16'h0001);
        ddr_write_u16(OFF_HB + 16'd2,  16'h0000);
        repeat (300) @(posedge clk_sys);

        write_high_reg(15'h061c, 8'h03);   // DCR word mode
        write_high_reg(15'h0618, 8'h04);   // RCR accept broadcast
        write_high_reg(15'h0600, 8'h22);   // CR  STA | RD2
        write_high_reg(15'h061e, 8'h01);   // IMR PRX

        // 1) Deliver frame A to page 0x50 and let it settle.
        deliver(PAGE_A, 0);
        repeat (200) @(posedge clk_sys);

        // 2) Concurrently: trigger delivery of frame B to page 0x60 (bg writes the
        //    ring) WHILE the Amiga reads frame A back through the data port.
        //    Arm A's remote-DMA read first, then fork.
        write_high_reg(15'h0610, 8'h04);          // RSAR0 -> 0x5004
        write_high_reg(15'h0612, PAGE_A);         // RSAR1
        write_high_reg(15'h0614, FLEN[7:0]);      // RBCR0
        write_high_reg(15'h0616, FLEN[15:8]);     // RBCR1
        write_high_reg(15'h0600, 8'h0A);          // CR remote read | STA

        fork
            begin : drive_b
                // Stage frame B in slot 1 and kick the bg while A is being read.
                reg [15:0] sdb, slb; integer kk, g;
                sdb = OFF_RX_DATA + 16'h0001*RX_SLOT_SIZE;
                slb = OFF_RX_LEN  + 16'h0001*16'h0002;
                dut.curr_register = PAGE_B;
                dut.bnry_register = 8'h7E;
                for (kk = 0; kk < FLEN; kk = kk + 1)
                    ddr_write_byte(sdb + kk[15:0], frame[kk]);
                ddr_write_u16(slb, FLEN[15:0]);
                ddr_write_u16(OFF_RX_TAIL, 16'h0002);
                ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);
                for (g = 0; g < 400000; g = g + 1) begin
                    @(posedge clk_sys);
                    if (ddr_read_u16(OFF_RX_HEAD) == 16'h0002) g = 400001;
                end
            end
            begin : read_a
                integer kk;
                for (kk = 0; kk < FLEN/2; kk = kk + 1)
                    data_port_read_word(a_read[kk]);
            end
        join

        // Verify frame A (read concurrently with B's delivery) is byte-exact.
        bad_a = 0;
        for (k = 0; k < FLEN; k = k + 2) begin
            eh = frame[k]; el = frame[k+1]; ew = {eh, el};
            if (a_read[k/2] !== ew) begin
                if (bad_a < 6)
                    $display("FAIL: frame A concurrent read off %0d expected 0x%04x got 0x%04x",
                             k, ew, a_read[k/2]);
                bad_a = bad_a + 1;
            end
        end
        if (bad_a != 0) begin
            $display("FAIL: %0d word(s) of frame A corrupted by concurrent bg write", bad_a);
            errors = errors + 1;
        end else
            $display("OK: frame A read byte-exact while bg wrote frame B concurrently");

        // Verify frame B landed correctly in packet RAM at PAGE_B (header skipped).
        bad_b = 0;
        for (k = 0; k < FLEN; k = k + 2) begin
            gg = pram_word({PAGE_B, 8'h00} + 16'h0004 + k[15:0]);
            eh = frame[k];                 // Amiga big-endian: high byte first
            el = frame[k+1];
            ew = {eh, el};
            if (gg !== ew) begin
                if (bad_b < 6)
                    $display("FAIL: frame B packet-RAM off %0d expected 0x%04x got 0x%04x", k, ew, gg);
                bad_b = bad_b + 1;
            end
        end
        if (bad_b != 0) begin
            $display("FAIL: %0d word(s) of frame B wrong after concurrent delivery", bad_b);
            errors = errors + 1;
        end else
            $display("OK: frame B delivered byte-exact during concurrent data-port reads");

        $display("INFO: data-port-read-during-bg race window hit %0d time(s)", race_hits);

        if (errors == 0)
            $display("PASS: eth_rx_concurrent_tb (concurrent bg-write + data-port-read both byte-exact)");
        else
            $display("eth_rx_concurrent_tb FAILED with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #60000000;
        $display("FAIL: global timeout"); $finish;
    end

endmodule
