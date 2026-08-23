// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_status_write_cdc_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_status_write_cdc_tb.v
//
// Integration test for the FPGA->HPS status-write path across the clk_sys ->
// clk_avl clock-domain crossing.  Wires the REAL ethernet_interface background
// FSM to the REAL ne2000_ddr_mailbox and a behavioral 64-bit f2sdram slave, then
// lets the background HPS poll run and proves the status write actually crosses
// the CDC and completes.
//
// Regression target (found on hardware via ISSP, 2026-06-14):
//   The background FSM issued the FPGA status write INLINE inside the read-
//   completion block (BG_READ_HPS_SIG_HI_WAIT), re-asserting eth_dma_req in the
//   same cycle it was being deasserted.  eth_dma_req therefore stayed
//   continuously high between the signature read and the status write, so the
//   clk_avl mailbox -- which starts a transaction only on a RISING edge of
//   eth_dma_req (ne2000_ddr_mailbox.v: "if (eth_dma_req && !req_d)") -- never saw
//   a new request.  Result: bg stuck in BG_WRITE_STATUS_WAIT, mailbox idle,
//   wr_accept = 0, and the HPS read stale DRAM forever.
//
// The fix routes the status write through the gapped BG_WRITE_STATUS_REQ state,
// which guarantees the same req-low gap every read transaction already gets.
//
// This testbench FAILS (watchdog deadlock) against the inline code and PASSES
// against the fixed code -- i.e. it is non-vacuous.
// ===========================================================================

`timescale 1ns/1ps

module eth_status_write_cdc_tb;

    // Background FSM state encodings (must match rtl/ethernet.v)
    localparam [5:0] BG_IDLE              = 6'd0;
    localparam [5:0] BG_READ_HPS_SIG_HI_WAIT = 6'd30;
    localparam [5:0] BG_WRITE_STATUS_REQ  = 6'd31;
    localparam [5:0] BG_WRITE_STATUS_WAIT = 6'd32;

    // Status word lives at byte offset 0x1052 -> 16-bit-word offset 0x829
    localparam [15:1] STATUS_WORD_ADDR = 15'h0829;

    // ---- clocks (async, like clk_sys ~28.6MHz vs clk_audio ~24.5MHz) ----
    reg clk_sys = 0;
    reg clk_avl = 0;
    always #17 clk_sys = ~clk_sys;   // ~29.4 MHz
    always #21 clk_avl = ~clk_avl;   // ~23.8 MHz (async to clk_sys)

    reg reset_sys = 1;
    reg reset_avl = 1;

    // ---- ethernet_interface CPU-side stimulus (held idle) ----
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

    // ---- eth_dma interface between ethernet_interface and mailbox ----
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

    // ---- mailbox Avalon master (clk_avl) -> behavioral slave ----
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

    // =======================================================================
    // DUTs: the real ethernet background FSM and the real mailbox CDC
    // =======================================================================
    ne2000_core dut (
        .clk(clk_sys),
        .reset(reset_sys),
        .host_addr(cpu_addr),
        .host_wdata(cpu_data_in),
        .host_rdata(cpu_data_out),
        .host_rd(cpu_rd),
        .host_wr_hi(cpu_hwr),
        .host_wr_lo(cpu_lwr),
        .host_cyc_n(cpu_as),
        .host_be_hi_n(cpu_uds),
        .host_be_lo_n(cpu_lds),
        .host_sel_priv(sel_ethernet_shm),
        .host_sel(sel_ethernet),
        .eth_dma_ready(eth_dma_ready),
        .eth_dma_rdata(eth_dma_rdata),
        .eth_dma_rdata64(eth_dma_rdata64),
        .eth_dma_wide(eth_dma_wide),
        .eth_dma_wdata64(eth_dma_wdata64),
        .eth_dma_req(eth_dma_req),
        .eth_dma_write(eth_dma_write),
        .eth_dma_addr(eth_dma_addr),
        .eth_dma_wdata(eth_dma_wdata),
        .eth_dma_uds(eth_dma_uds),
        .eth_dma_lds(eth_dma_lds),
        .irq(eth_irq),
        .host_ack_n(dtack_eth)
    );

    ne2000_ddr_mailbox mailbox (
        .clk_sys(clk_sys),
        .reset_sys(reset_sys),
        .eth_dma_req(eth_dma_req),
        .eth_dma_write(eth_dma_write),
        .eth_dma_addr(eth_dma_addr),
        .eth_dma_wdata(eth_dma_wdata),
        .eth_dma_uds(eth_dma_uds),
        .eth_dma_lds(eth_dma_lds),
        .eth_dma_ready(eth_dma_ready),
        .eth_dma_rdata(eth_dma_rdata),
        .eth_dma_rdata64(eth_dma_rdata64),
        .eth_dma_wide(eth_dma_wide),
        .eth_dma_wdata64(eth_dma_wdata64),

        .clk_avl(clk_avl),
        .reset_avl(reset_avl),
        .avl_address(avl_address),
        .avl_burstcount(avl_burstcount),
        .avl_byteenable(avl_byteenable),
        .avl_writedata(avl_writedata),
        .avl_read(avl_read),
        .avl_write(avl_write),
        .avl_waitrequest(avl_waitrequest),
        .avl_readdata(avl_readdata),
        .avl_readdatavalid(avl_readdatavalid),

        .dbg()
    );

    // =======================================================================
    // Behavioral 64-bit f2sdram slave (clk_avl): single outstanding, accept
    // delay + read latency.  Mirrors the model in eth_mailbox_arbiter_tb.v.
    // =======================================================================
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
    assign avl_waitrequest = is_busy ? 1'b1 :
                             (cmd_present ? (acc_cnt < ACCEPT_DELAY) : 1'b0);
    wire cmd_accept = cmd_present & ~avl_waitrequest;

    reg        rdv = 0;
    reg [63:0] rdo = 0;
    assign avl_readdatavalid = rdv;
    assign avl_readdata      = rdo;

    integer i;
    initial begin
        for (i = 0; i < 16384; i = i + 1) mem[i] = 64'd0;
    end

    // Count writes the slave actually accepts (i.e. that crossed the CDC).
    integer slave_write_accepts = 0;

    always @(posedge clk_avl) begin
        if (reset_avl) begin
            ss_state <= SS_IDLE; acc_cnt <= 0; lat_cnt <= 0; beats <= 0;
            is_busy <= 0; rdv <= 0; rdo <= 0;
        end else begin
            rdv <= 0;

            if (cmd_present && avl_waitrequest && !is_busy)
                acc_cnt <= acc_cnt + 1'b1;
            else if (!cmd_present)
                acc_cnt <= 0;

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
                    slave_write_accepts <= slave_write_accepts + 1;
                end else begin
                    r_index <= avl_address[13:0];
                    beats   <= {1'b0, avl_burstcount};
                    lat_cnt <= READ_LAT;
                    is_busy <= 1'b1;
                    ss_state<= SS_LAT;
                end
            end

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

    // =======================================================================
    // Monitors (clk_sys)
    // =======================================================================
    // Track the bg FSM to detect the status write being issued and completed.
    reg        saw_status_req       = 0;   // bg reached BG_WRITE_STATUS_REQ
    reg        saw_status_wait      = 0;   // bg reached BG_WRITE_STATUS_WAIT
    reg        status_write_done    = 0;   // bg returned to IDLE after the write
    reg        status_addr_ok       = 0;   // the issued write targeted 0x829

    // Detect that eth_dma_req actually returns low between the signature read
    // completing and the status write being issued (the precise fix).  In the
    // buggy code eth_dma_req never dropped here.
    reg        in_sig_hi_wait_prev  = 0;
    reg        req_dropped_after_sig = 0;

    reg        prev_status_wait = 0;

    always @(posedge clk_sys) begin
        if (!reset_sys) begin
            if (dut.bg_state == BG_WRITE_STATUS_REQ) saw_status_req <= 1'b1;
            if (dut.bg_state == BG_WRITE_STATUS_WAIT) saw_status_wait <= 1'b1;

            // Capture the address of the status write whenever it is actually
            // presented on the eth_dma bus (the only write in this scenario;
            // the HB/SIG accesses are reads).  eth_dma_addr latches the cycle
            // after BG_WRITE_STATUS_REQ, so sample on the live bus, not on the
            // REQ state.
            if (eth_dma_req && eth_dma_write && (eth_dma_addr == STATUS_WORD_ADDR))
                status_addr_ok <= 1'b1;

            // After the signature-high read completes, eth_dma_req must go low
            // before the status write re-asserts it (rising edge for the CDC).
            in_sig_hi_wait_prev <= (dut.bg_state == BG_READ_HPS_SIG_HI_WAIT);
            if (in_sig_hi_wait_prev && !saw_status_req && !eth_dma_req)
                req_dropped_after_sig <= 1'b1;

            // bg returning to IDLE after having reached the status-write states
            prev_status_wait <= (dut.bg_state == BG_WRITE_STATUS_WAIT);
            if (prev_status_wait && (dut.bg_state == BG_IDLE))
                status_write_done <= 1'b1;
        end
    end

    // =======================================================================
    // Stimulus / checks
    // =======================================================================
    integer cyc = 0;
    integer guard;

    initial begin
        reset_sys = 1;
        reset_avl = 1;
        repeat (8) @(posedge clk_sys);
        @(posedge clk_avl);
        reset_sys = 0;
        reset_avl = 0;

        // After reset hps_poll_counter == 0, so the bg launches the HPS poll
        // (HB lo/hi, SIG lo/hi reads) and then the FPGA status write with no
        // CPU traffic to interfere.  Wait for the status write to complete or
        // a generous watchdog to expire.
        guard = 0;
        while (!status_write_done && guard < 20000) begin
            @(posedge clk_sys);
            guard = guard + 1;
        end

        // ---- assertions ----
        if (!saw_status_req) begin
            $display("FAIL: bg never reached BG_WRITE_STATUS_REQ (status write not issued through the gapped REQ state)");
            errors = errors + 1;
        end

        if (!status_addr_ok) begin
            $display("FAIL: status write did not target word addr 0x%04x", STATUS_WORD_ADDR);
            errors = errors + 1;
        end

        if (!req_dropped_after_sig) begin
            $display("FAIL: eth_dma_req never returned low between the signature read and the status write");
            $display("      -> no rising edge for the clk_avl mailbox: write would be silently dropped (the bug)");
            errors = errors + 1;
        end

        if (slave_write_accepts < 1) begin
            $display("FAIL: mailbox/slave accepted no writes -> status write never crossed the CDC (DEADLOCK)");
            errors = errors + 1;
        end

        if (!status_write_done) begin
            $display("FAIL: bg did not return to BG_IDLE after the status write within watchdog (bg stuck at WRITE_STATUS_WAIT)");
            $display("      bg_state=%0d eth_dma_req=%b bg_dma_inflight=%b slave_write_accepts=%0d",
                     dut.bg_state, eth_dma_req, dut.bg_dma_inflight, slave_write_accepts);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: eth_status_write_cdc_tb completed (status write crossed CDC: req-drop=%0b, slave_writes=%0d, bg recovered)",
                     req_dropped_after_sig, slave_write_accepts);
        end else begin
            $display("eth_status_write_cdc_tb FAILED with %0d error(s)", errors);
        end

        $finish;
    end

    // Hard backstop so a real deadlock cannot hang the simulator forever.
    initial begin
        #2000000;
        $display("FAIL: global timeout -- simulation did not finish (hard deadlock)");
        $finish;
    end

endmodule
