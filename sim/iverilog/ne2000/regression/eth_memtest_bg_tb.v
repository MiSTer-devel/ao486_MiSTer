// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_memtest_bg_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_memtest_bg_tb.v
//
// Reproduces the X-Surf TestPrg "Testing 16bit memory" step against the REAL
// ethernet_interface + REAL ne2000_ddr_mailbox + a behavioral f2sdram slave, WITH
// the background FSM actively cycling its HPS poll / mailbox writes.
//
// The hardware symptom (xsurftest4.txt, 2026-06-14): after the mailbox deadlock
// was fixed the bg runs continuously; a remote-DMA write burst into packet RAM
// followed by a remote-DMA read-back returned all zeros.  This testbench drives
// the exact NE2000 sequence (RSAR/RBCR + remote-write, then RSAR/RBCR +
// remote-read through the data port) over the CPU bus while the bg is live and
// checks the data round-trips through packet RAM.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_memtest_bg_tb;

    // ---- clocks ----
    reg clk_sys = 0;
    reg clk_avl = 0;
    always #17 clk_sys = ~clk_sys;   // ~29.4 MHz
    always #21 clk_avl = ~clk_avl;   // ~23.8 MHz (async)

    reg reset_sys = 1;
    reg reset_avl = 1;

    // ---- CPU bus ----
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

    // ---- eth_dma between ethernet_interface and mailbox ----
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

    // ---- mailbox Avalon master -> slave ----
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

    // ---- behavioral 64-bit f2sdram slave ----
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

    // ----- CPU bus helpers (high-byte register writes, like the real driver) -
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

    // Word write to the X-Surf 16-bit data port (word offset 0x0640,
    // byte offset 0x0C80), waits for DTACK.
    task automatic data_port_write_word;
        input [15:0] value;
        integer w;
        reg done;
        begin
            done = 1'b0;
            @(negedge clk_sys);
            cpu_addr = 15'h0640; cpu_data_in = value;   // X-Surf 16-bit data port at 0xEA0C80 (the driver's port)
            sel_ethernet = 1'b1; cpu_hwr = 1'b1; cpu_lwr = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) done = 1'b1;
            end
            @(negedge clk_sys);
            cpu_hwr = 1'b0; cpu_lwr = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1;
            sel_ethernet = 1'b0; cpu_data_in = 16'h0000;
            if (!done) begin
                $display("FAIL: data-port write timed out waiting for DTACK");
                errors = errors + 1;
            end
            @(negedge clk_sys);
        end
    endtask

    // Word read from the X-Surf 16-bit data port (word offset 0x0640,
    // byte offset 0x0C80), waits for DTACK, returns value.
    task automatic data_port_read_word;
        output [15:0] value;
        integer w;
        reg done;
        begin
            done = 1'b0; value = 16'hXXXX;
            @(negedge clk_sys);
            cpu_addr = 15'h0640; sel_ethernet = 1'b1; cpu_rd = 1'b1;   // 16-bit data port 0xEA0C80
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) begin value = cpu_data_out; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin
                $display("FAIL: data-port read timed out waiting for DTACK");
                errors = errors + 1;
            end
            @(negedge clk_sys);
        end
    endtask

    localparam integer NWORDS = 8;
    reg [15:0] pattern [0:NWORDS-1];
    reg [15:0] got;
    integer k;

    initial begin
        // "Hello Here Is Am" ... a recognizable, non-zero, non-0xFFFF pattern.
        pattern[0] = 16'h4865; pattern[1] = 16'h6C6C;
        pattern[2] = 16'h6F20; pattern[3] = 16'h4865;
        pattern[4] = 16'h7265; pattern[5] = 16'h2049;
        pattern[6] = 16'h7320; pattern[7] = 16'h416D;

        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys);
        @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        // Let the background FSM start cycling its HPS poll / mailbox writes so
        // the data-port runs concurrently with live eth_dma traffic (the real
        // condition that broke the memory test).
        repeat (400) @(posedge clk_sys);

        // ---- DCR: word-wide DMA (WTS=1) so 16-bit transfers go to packet RAM
        write_high_reg(15'h061c, 8'h03);   // DCR = 0x01 (word mode)

        // ---- Remote-DMA WRITE burst: RSAR=0x4000, RBCR=NWORDS*2, CR=remote write
        write_high_reg(15'h0610, 8'h00);   // RSAR0 = 0x00
        write_high_reg(15'h0612, 8'h40);   // RSAR1 = 0x40  -> 0x4000
        write_high_reg(15'h0614, NWORDS*2);// RBCR0
        write_high_reg(15'h0616, 8'h00);   // RBCR1
        write_high_reg(15'h0600, 8'h12);   // CR = remote write + STA
        for (k = 0; k < NWORDS; k = k + 1) data_port_write_word(pattern[k]);

        // small gap so the bg keeps running between the bursts
        repeat (200) @(posedge clk_sys);

        // ---- Remote-DMA READ burst: RSAR=0x4000, RBCR=NWORDS*2, CR=remote read
        write_high_reg(15'h0610, 8'h00);
        write_high_reg(15'h0612, 8'h40);
        write_high_reg(15'h0614, NWORDS*2);
        write_high_reg(15'h0616, 8'h00);
        write_high_reg(15'h0600, 8'h0A);   // CR = remote read + STA
        for (k = 0; k < NWORDS; k = k + 1) begin
            data_port_read_word(got);
            if (got !== pattern[k]) begin
                $display("FAIL: word %0d readback 0x%04x != written 0x%04x", k, got, pattern[k]);
                errors = errors + 1;
            end
        end

        // Also confirm packet RAM physically holds the pattern.
        for (k = 0; k < NWORDS; k = k + 1) begin
            got = {dut.packet_ram_inst.mem_u[(16'h4000 - 16'h4000 + k*2) >> 1],
                   dut.packet_ram_inst.mem_l[(16'h4000 - 16'h4000 + k*2) >> 1]};
            if (got !== pattern[k]) begin
                $display("FAIL: packet RAM[0x%04x] = 0x%04x != written 0x%04x", 16'h4000 + k*2, got, pattern[k]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: eth_memtest_bg_tb completed (remote-DMA mem round-trip OK with bg active)");
        else
            $display("eth_memtest_bg_tb FAILED with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #4000000;
        $display("FAIL: global timeout");
        $finish;
    end

endmodule
