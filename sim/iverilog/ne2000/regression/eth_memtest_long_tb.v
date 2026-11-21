// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_memtest_long_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_memtest_long_tb.v
//
// Reproduces the X-Surf TestPrg "Testing 16bit memory" byte-order matrix:
// default 16-bit port (board 0x0C40), the x-surf-100.device 16-bit alias
// (board 0x0C80), and the X-Surf-100 32-bit ("long") DMA ports (board 0x8880
// read / 0x8C80 write, cpu_addr 0x4440 / 0x4640) against the REAL ethernet_interface + REAL
// ne2000_ddr_mailbox + a behavioral f2sdram slave, with the background FSM
// actively cycling its HPS poll / mailbox writes.
//
// Hardware symptom (xsurftest_longread.txt / xsurftest_longwrite.txt,
// 2026-06-14, pre-data-port-race-fix build): the long memory test reported
// "PIOWriteMem Timeout!" and read back all 0xFFFFFFFF.  This testbench checks,
// against the actual current RTL:
//
//   (1) STRUCTURAL: after each remote-DMA burst through every port combination,
//       ISR.RDC (bit 6) sets - i.e. the byte count reaches 0 and the remote
//       DMA completes.  A stuck count (RDC never set) is what makes the real
//       driver's PIOWriteMem spin to its timeout.
//
//   (2) STRUCTURAL: a 32-bit-port read returns real packet-RAM data, not X /
//       all-ones (the float that produced 0xFFFFFFFF on hardware).
//
//   (3) BYTE ORDER: a read through any supported port returns the SAME bytes
//       that were written. This catches 16-bit read reversal, 16-bit write
//       reversal, and mixed long-write/default-read reversal.
//
// No fake logic: the data ports, RBCR/RSAR counting, RDC and packet RAM are all
// the real ethernet_interface.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_memtest_long_tb;

    parameter MODEL_CPU_LANE_CROSS = 0;

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

    task automatic read_high_reg;
        input  [14:0] word_offset;
        output [7:0]  value;
        integer w;
        reg done;
        begin
            done = 1'b0; value = 8'hXX;
            @(negedge clk_sys);
            cpu_addr = word_offset; sel_ethernet = 1'b1; cpu_rd = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b1;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) begin value = cpu_data_out[15:8]; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin
                $display("FAIL: register read timed out waiting for DTACK (off=0x%04x)", word_offset);
                errors = errors + 1;
            end
            @(negedge clk_sys);
        end
    endtask

    function is_port32;
        input [14:0] port_off;
        begin
            is_port32 = ((port_off >= 15'h4440) && (port_off <= 15'h444F)) ||
                        ((port_off >= 15'h4640) && (port_off <= 15'h464F));
        end
    endfunction

    function [15:0] cpu_bus_write_word;
        input [14:0] port_off;
        input [15:0] logical_word;
        begin
            // WRITE swap is KEPT on the 0x8C80 window, so pre-swap 32-bit-port
            // writes to compensate it (read swap removed -> see read helper).
            cpu_bus_write_word =
                is_port32(port_off)
                    ? {logical_word[7:0], logical_word[15:8]}
                    : logical_word;
        end
    endfunction

    function [15:0] cpu_bus_read_word;
        input [14:0] port_off;
        input [15:0] fpga_word;
        begin
            // 32-bit ports apply the is_dport32 read swap, so re-swap to recover.
            cpu_bus_read_word =
                is_port32(port_off)
                    ? {fpga_word[7:0], fpga_word[15:8]}
                    : fpga_word;
        end
    endfunction

    // Word write to a data port at an arbitrary word offset (0x0620 = 16-bit
    // reg-0x10 port 0xC40, 0x0640 = 16-bit port 0xC80, 0x4640 = 32-bit write
    // port 0x8C80), full UDS+LDS, waits DTACK.
    task automatic data_port_write_word;
        input [14:0] port_off;
        input [15:0] value;
        integer w;
        reg done;
        begin
            done = 1'b0;
            @(negedge clk_sys);
            cpu_addr = port_off;
            cpu_data_in = cpu_bus_write_word(port_off, value);
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
                $display("FAIL: data-port write timed out waiting for DTACK (port=0x%04x)", port_off);
                errors = errors + 1;
            end
            @(negedge clk_sys);
        end
    endtask

    task automatic data_port_read_word;
        input  [14:0] port_off;
        output [15:0] value;
        integer w;
        reg done;
        reg [15:0] raw;
        begin
            done = 1'b0; raw = 16'hXXXX;
            @(negedge clk_sys);
            cpu_addr = port_off; sel_ethernet = 1'b1; cpu_rd = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) begin raw = cpu_data_out; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin
                $display("FAIL: data-port read timed out waiting for DTACK (port=0x%04x)", port_off);
                errors = errors + 1;
            end
            value = cpu_bus_read_word(port_off, raw);
            @(negedge clk_sys);
        end
    endtask

    // Program RSAR/RBCR then issue CR.  remote write CR=0x12, remote read CR=0x0A.
    task automatic start_remote_dma;
        input [15:0] rsar;
        input [15:0] rbcr;
        input [7:0]  cr;
        begin
            write_high_reg(15'h0610, rsar[7:0]);    // RSAR0
            write_high_reg(15'h0612, rsar[15:8]);   // RSAR1
            write_high_reg(15'h0614, rbcr[7:0]);    // RBCR0
            write_high_reg(15'h0616, rbcr[15:8]);   // RBCR1
            write_high_reg(15'h0600, cr);           // CR
        end
    endtask

    // Clear ISR.RDC (write 1 to bit 6, page 0 reg 0x07 -> word offset 0x060E).
    task automatic clear_rdc;
        begin
            write_high_reg(15'h060E, 8'h40);
        end
    endtask

    // Check ISR.RDC is set; report and count an error if not.
    task automatic expect_rdc;
        input [511:0] label;
        begin
            if ((dut.isr_register & 8'h40) == 8'h00) begin
                $display("FAIL [%0s]: ISR.RDC (bit6) not set after burst -> remote DMA never completed (ISR=0x%02x, RBCR=0x%04x). This is the PIOWriteMem-timeout mechanism.",
                         label, dut.isr_register, dut.remote_byte_count);
                errors = errors + 1;
            end else begin
                $display("INFO [%0s]: ISR.RDC set, remote DMA completed (ISR=0x%02x, RBCR=0x%04x).",
                         label, dut.isr_register, dut.remote_byte_count);
            end
        end
    endtask

    localparam integer NWORDS = 8;
    localparam [15:0]  RSAR_BASE = 16'h4000;     // packet RAM page 0x40
    localparam [14:0]  PORT16_C40 = 15'h0620;    // board 0x0C40 (RTL8019 reg-0x10 data port)
    localparam [14:0]  PORT16_C80 = 15'h0640;    // board 0x0C80 (X-Surf 16-bit data port alias)
    localparam [14:0]  PORT32_RD  = 15'h4440;    // board 0x8880 (32-bit read port)
    localparam [14:0]  PORT32_WR  = 15'h4640;    // board 0x8C80 (32-bit write port)

    reg [15:0] pattern [0:NWORDS-1];
    reg [15:0] rd16 [0:NWORDS-1];
    reg [15:0] rd32 [0:NWORDS-1];
    reg [15:0] got;
    integer k;
    reg swap_seen;

    task automatic check_packet_ram_pattern;
        input [15:0] rsar;
        input [511:0] label;
        reg [15:0] pmem_word;
        integer word_index;
        begin
            for (k = 0; k < NWORDS; k = k + 1) begin
                word_index = ((rsar - RSAR_BASE + {k[14:0], 1'b0}) >> 1);
                pmem_word = {dut.packet_ram_inst.mem_u[word_index],
                             dut.packet_ram_inst.mem_l[word_index]};
                if (pmem_word !== pattern[k]) begin
                    $display("FAIL WRITEORDER [%0s]: packet RAM word %0d = 0x%04x != written 0x%04x (per-word-swap=%b)",
                             label, k, pmem_word, pattern[k], (pmem_word == {pattern[k][7:0], pattern[k][15:8]}));
                    errors = errors + 1;
                end
            end
        end
    endtask

    task automatic write_burst;
        input [14:0] port_off;
        input [15:0] rsar;
        input [511:0] label;
        begin
            clear_rdc();
            start_remote_dma(rsar, NWORDS*2, 8'h12);
            for (k = 0; k < NWORDS; k = k + 1) data_port_write_word(port_off, pattern[k]);
            expect_rdc(label);
            check_packet_ram_pattern(rsar, label);
        end
    endtask

    task automatic read_burst_expect;
        input [14:0] port_off;
        input [15:0] rsar;
        input [511:0] label;
        input        save_as_ref;
        begin
            clear_rdc();
            start_remote_dma(rsar, NWORDS*2, 8'h0A);
            for (k = 0; k < NWORDS; k = k + 1) begin
                data_port_read_word(port_off, got);
                if (save_as_ref) rd16[k] = got;
                if (got !== pattern[k]) begin
                    $display("FAIL BYTEORDER [%0s]: word %0d read 0x%04x != written 0x%04x (per-word-swap=%b)",
                             label, k, got, pattern[k], (got == {pattern[k][7:0], pattern[k][15:8]}));
                    errors = errors + 1;
                end
                if (got === 16'hxxxx || got === 16'hXXXX) begin
                    $display("FAIL STRUCTURAL [%0s]: word %0d is X/undriven", label, k);
                    errors = errors + 1;
                end
                if (got === 16'hffff) begin
                    $display("WARN [%0s]: word %0d read 0xffff; if persistent this is the all-FFFFFFFF hardware symptom", label, k);
                end
            end
            expect_rdc(label);
        end
    endtask

    initial begin
        // "Hello Here Is Am" - recognizable, non-zero, non-0xFFFF, asymmetric bytes.
        pattern[0] = 16'h4865; pattern[1] = 16'h6C6C;
        pattern[2] = 16'h6F20; pattern[3] = 16'h4865;
        pattern[4] = 16'h7265; pattern[5] = 16'h2049;
        pattern[6] = 16'h7320; pattern[7] = 16'h416D;

        if (MODEL_CPU_LANE_CROSS)
            $display("INFO: modeling 32-bit-port CPU lane crossing: logical words are byte-swapped at the FPGA pins");
        else
            $display("INFO: modeling 32-bit ports with the same 16-bit lane order as normal data ports");

        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys);
        @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        // Let the bg FSM start cycling (HPS poll / mailbox) so the data port runs
        // concurrently with live eth_dma traffic - the real failing condition.
        repeat (400) @(posedge clk_sys);

        // Match xsurftest: DCR = 0x49 (WTS=1, BOS=0). ethernet.v forces bit 7
        // high internally, but byte-swap bit 1 must remain clear.
        write_high_reg(15'h061c, 8'h4B);

        // ===================================================================
        // Phase A: xsurftest default path: write/read through board 0x0C40.
        // This is the primary 16-bit byte-order check.
        // ===================================================================
        write_burst(PORT16_C40, RSAR_BASE, "A: 16-bit 0x0C40 write burst");

        repeat (200) @(posedge clk_sys);

        read_burst_expect(PORT16_C40, RSAR_BASE, "A: 16-bit 0x0C40 read burst", 1'b1);

        // Also prove the x-surf-100.device 0x0C80 alias has the same 16-bit order.
        repeat (200) @(posedge clk_sys);
        write_burst(PORT16_C80, RSAR_BASE + 16'h0020, "A2: 16-bit 0x0C80 write burst");
        repeat (200) @(posedge clk_sys);
        read_burst_expect(PORT16_C80, RSAR_BASE + 16'h0020, "A2: 16-bit 0x0C80 read burst", 1'b0);

        // ===================================================================
        // Phase B: xsurftest -longread: default 0x0C40 write, 0x8880 read.
        // STRUCTURAL: must return real data (not X / all-ones) and set RDC.
        // BYTE ORDER: compare against the 16-bit readback - any per-word swap
        // means the 32-bit bulk-read path corrupts every frame the bg wrote.
        // ===================================================================
        repeat (200) @(posedge clk_sys);
        clear_rdc();
        start_remote_dma(RSAR_BASE, NWORDS*2, 8'h0A);   // remote read
        swap_seen = 1'b0;
        for (k = 0; k < NWORDS; k = k + 1) begin
            data_port_read_word(PORT32_RD, got);
            rd32[k] = got;
            if (got === 16'hxxxx || got === 16'hXXXX) begin
                $display("FAIL: 32-bit readback word %0d is X (undriven bus) -> the 0xFFFFFFFF hardware symptom", k);
                errors = errors + 1;
            end
            if (got !== rd16[k]) begin
                swap_seen = 1'b1;
                $display("FAIL BYTEORDER: word %0d  32-bit-port=0x%04x  16-bit-port=0x%04x  (swap=%b) -> 32-bit bulk RX would corrupt bg-written frames",
                         k, got, rd16[k], (got == {rd16[k][7:0], rd16[k][15:8]}));
                errors = errors + 1;
            end
        end
        expect_rdc("B: 32-bit read burst");
        if (swap_seen)
            $display("RESULT: 32-bit read DIFFERS from 16-bit read under this CPU-lane model -> long-port byte order is broken.");
        else
            $display("RESULT: 32-bit read MATCHES 16-bit read -> byte order is consistent across access widths under this CPU-lane model.");

        // ===================================================================
        // Phase C: xsurftest -longwrite: 0x8C80 write, default 0x0C40 read.
        // This catches the missing mixed 32-bit-write/16-bit-read byte reversal.
        // ===================================================================
        repeat (200) @(posedge clk_sys);
        write_burst(PORT32_WR, RSAR_BASE + 16'h0040, "C: 32-bit 0x8C80 write burst");

        repeat (200) @(posedge clk_sys);
        read_burst_expect(PORT16_C40, RSAR_BASE + 16'h0040, "C: 16-bit 0x0C40 read after 0x8C80 write", 1'b0);

        // ===================================================================
        // Phase D: driver bulk path: 0x8C80 write, 0x8880 read.
        // ===================================================================
        repeat (200) @(posedge clk_sys);
        write_burst(PORT32_WR, RSAR_BASE + 16'h0060, "D: 32-bit 0x8C80 write burst");

        repeat (200) @(posedge clk_sys);
        read_burst_expect(PORT32_RD, RSAR_BASE + 16'h0060, "D: 32-bit 0x8880 read after 0x8C80 write", 1'b0);

        if (errors == 0) begin
            $display("PASS: eth_memtest_long_tb completed (16-bit and long-port remote-DMA byte order OK with bg active)");
            $finish;
        end else begin
            $display("FAILED: eth_memtest_long_tb with %0d error(s)", errors);
            $fatal(1);
        end
    end

    // Global watchdog.
    initial begin
        #4000000;
        $display("FAIL: eth_memtest_long_tb global timeout");
        $finish;
    end

endmodule
