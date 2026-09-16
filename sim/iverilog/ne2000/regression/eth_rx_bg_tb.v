// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_rx_bg_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_rx_bg_tb.v
//
// End-to-end RECEIVE-path test: host -> HPS -> FPGA -> Amiga.
//
// Drives the REAL ethernet_interface + REAL ne2000_ddr_mailbox + a behavioral
// f2sdram slave.  Mimics exactly what the HPS daemon does to inject a received
// frame (enqueue_shared_rx_packet in extra/minimig_eth.cpp): write the packet
// bytes into the slot data buffer, write the slot length, advance the RX queue
// tail, and set the RX_AVAIL flag.  Then it verifies the background FSM copies
// the frame into NE2000 packet RAM with a correct RX header, raises ISR.PRX /
// eth_irq, advances CURR and the shared queue head, clears RX_AVAIL, and that
// the Amiga can read the frame back through the remote-DMA data port.
//
// Shared-window ABI (bytes, must match minimig_eth_abi.h and ethernet.v):
//   CTRL_FLAGS      0x1000  (bit2 = RX_AVAIL = 0x04)
//   HPS_HEARTBEAT   0x1088 / signature 0x108C
//   RX_QUEUE_HEAD   0x2C04  (FPGA-consumed, low byte)
//   RX_QUEUE_TAIL   0x2C06  (HPS-produced, low byte)
//   RX_QUEUE_LEN    0x2C20  (uint16 per slot, +slot*2)
//   RX_QUEUE_DATA   0x9000  (slot*0x600 bytes per slot)
//   16 ring slots, slot buffer 0x600 bytes.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_rx_bg_tb;

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

    // ---- clocks ----
    reg clk_sys = 0;
    reg clk_avl = 0;
    always #17 clk_sys = ~clk_sys;
    always #21 clk_avl = ~clk_avl;

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

    // ---- throughput instrumentation: count mailbox round-trips ----
    // A "wide" round-trip moves a full 64-bit DDR word (4 payload words); a
    // narrow round-trip moves one 16-bit word.  Counting eth_dma_wide rising
    // edges proves the 64-bit packing path actually ran (non-vacuous) and lets
    // us compare against the per-16-bit-word round-trip count it replaced.
    integer wide_pulses = 0;
    integer req_pulses  = 0;
    integer sync_incr   = 0;
    integer st_hist [0:63];
    integer hh;
    initial for (hh = 0; hh < 64; hh = hh + 1) st_hist[hh] = 0;
    reg     wide_d = 1'b0;
    reg     req_d  = 1'b0;
    always @(posedge clk_sys) begin
        wide_d <= eth_dma_wide;
        req_d  <= eth_dma_req;
        if (eth_dma_wide && !wide_d) wide_pulses <= wide_pulses + 1;
        if (eth_dma_req  && !req_d)  begin
            req_pulses <= req_pulses + 1;
            st_hist[dut.bg_state] <= st_hist[dut.bg_state] + 1;
            if (dut.bg_state == 6'd18) sync_incr <= sync_incr + 1;
        end
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

    // ---- DDR seeding helpers (byte view of the 64-bit mem[], as the HPS daemon
    //      writes: native little-endian into the shared window) ----
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

    task automatic ddr_write_u16;       // little-endian, like the daemon
        input [15:0] byte_off;
        input [15:0] val;
        begin
            ddr_write_byte(byte_off,            val[7:0]);
            ddr_write_byte(byte_off + 16'd1,    val[15:8]);
        end
    endtask

    function [15:0] ddr_read_u16;       // little-endian read back
        input [15:0] byte_off;
        reg [13:0] widx; integer bsh;
        begin
            widx = byte_off >> 3;
            bsh  = (byte_off & 7) * 8;
            ddr_read_u16 = {mem[widx][bsh+8 +: 8], mem[widx][bsh +: 8]};
        end
    endfunction

    // ---- CPU bus helpers ----
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

    // packet RAM helpers (NE addr -> word index)
    function [15:0] pram_word;
        input [15:0] ne_addr;
        reg [12:0] idx;
        begin
            idx = (ne_addr - 16'h4000) >> 1;
            pram_word = {dut.packet_ram_inst.mem_u[idx], dut.packet_ram_inst.mem_l[idx]};
        end
    endfunction

    localparam integer FRAME_LEN = 60;
    reg [7:0] frame [0:FRAME_LEN-1];
    integer k;
    reg [15:0] w0, w1, got, expw;
    reg [7:0]  exp_lo, exp_hi;

    initial begin
        // a recognizable broadcast frame
        frame[0]=8'hFF; frame[1]=8'hFF; frame[2]=8'hFF; frame[3]=8'hFF; frame[4]=8'hFF; frame[5]=8'hFF;
        frame[6]=8'h02; frame[7]=8'h11; frame[8]=8'h22; frame[9]=8'h33; frame[10]=8'h44; frame[11]=8'h55;
        frame[12]=8'h08; frame[13]=8'h00;   // ethertype 0x0800 (IPv4)
        for (k = 14; k < FRAME_LEN; k = k + 1) frame[k] = k[7:0];

        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys);
        @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        // realistic mailbox state: HPS signature + heartbeat present
        ddr_write_u16(OFF_SIG,        16'hBABE);
        ddr_write_u16(OFF_SIG + 16'd2,16'hCAFE);
        ddr_write_u16(OFF_HB,         16'h0001);
        ddr_write_u16(OFF_HB + 16'd2, 16'h0000);

        repeat (300) @(posedge clk_sys);

        // ---- enable the receiver (RCR write arms rx_poll_enabled; CR STA) ----
        write_high_reg(15'h061c, 8'h03);   // DCR = word mode (for the read-back)
        write_high_reg(15'h0618, 8'h04);   // RCR = accept broadcast -> rx_poll_enabled
        write_high_reg(15'h0600, 8'h22);   // CR  = STA | RD2  -> receiver_active
        write_high_reg(15'h061e, 8'h01);   // IMR = PRX enable -> eth_irq on receive

        // ---- inject one received frame into shared RX slot 0 (daemon order) ----
        for (k = 0; k < FRAME_LEN; k = k + 1)
            ddr_write_byte(OFF_RX_DATA + k[15:0], frame[k]);
        ddr_write_u16(OFF_RX_LEN, FRAME_LEN[15:0]);     // slot 0 length
        ddr_write_u16(OFF_RX_TAIL, 16'h0001);           // advance tail 0 -> 1
        ddr_write_u16(OFF_FLAGS, FLAG_RX_AVAIL);        // RX_AVAIL set

        // ---- wait for the FPGA to deliver it: ISR.PRX ----
        begin : wait_prx
            integer g;
            for (g = 0; g < 40000; g = g + 1) begin
                @(posedge clk_sys);
                if ((dut.isr_register & 8'h01) != 8'h00) disable wait_prx;
            end
        end

        if ((dut.isr_register & 8'h01) == 8'h00) begin
            $display("FAIL: ISR.PRX never set -> FPGA did not deliver the RX frame (bg_state=%0d curr=0x%02x)",
                     dut.bg_state, dut.curr_register);
            errors = errors + 1;
        end

        // The head write-back + RX_AVAIL clear happen a few bg cycles AFTER PRX is
        // set; wait for the FPGA to finish consuming the slot before checking the
        // shared-queue side-effects.
        begin : wait_consume
            integer g;
            for (g = 0; g < 8000; g = g + 1) begin
                @(posedge clk_sys);
                if (ddr_read_u16(OFF_RX_HEAD) == 16'h0001) disable wait_consume;
            end
        end

        if (eth_irq !== 1'b1) begin
            $display("FAIL: eth_irq not asserted after RX with IMR.PRX set (ISR=0x%02x IMR=0x%02x)",
                     dut.isr_register, dut.imr_register);
            errors = errors + 1;
        end

        // CURR must advance 0x47 -> 0x48 (one page for a 60-byte frame)
        if (dut.curr_register !== 8'h48) begin
            $display("FAIL: CURR expected 0x48 after RX, got 0x%02x", dut.curr_register);
            errors = errors + 1;
        end

        // RX header in packet RAM at page 0x47 (byte 0x4700):
        //   word0 (Amiga big-endian view) = {status=0x21, next_page=0x48} = 0x2148
        //   word1 length (LE in NE header) = FRAME_LEN+4 stored swapped
        w0 = pram_word(16'h4700);
        if (w0 !== 16'h2148) begin
            $display("FAIL: RX header word0 expected 0x2148 (status|next_page), got 0x%04x", w0);
            errors = errors + 1;
        end

        // payload bytes must match the injected frame (check first 6 + a few)
        for (k = 0; k < FRAME_LEN; k = k + 2) begin
            got    = pram_word(16'h4704 + k[15:0]);
            exp_hi = frame[k];        // Amiga big-endian: high byte first
            exp_lo = (k+1 < FRAME_LEN) ? frame[k+1] : 8'h00;
            expw   = {exp_hi, exp_lo};
            if (got !== expw) begin
                $display("FAIL: RX payload word @0x%04x expected 0x%04x got 0x%04x",
                         16'h4704 + k, expw, got);
                errors = errors + 1;
            end
        end

        // FPGA must have advanced the shared queue head (consumed slot 0)
        if (ddr_read_u16(OFF_RX_HEAD) != 16'h0001) begin
            $display("FAIL: RX_QUEUE_HEAD expected 1 after consume, got %0d", ddr_read_u16(OFF_RX_HEAD));
            errors = errors + 1;
        end

        // ---- throughput proof: the 64-bit packing path must have moved the
        // bulk of the 60-byte payload.  Divert is on bytes_remaining > 8, so a
        // 60-byte frame copies 7 full 64-bit words (56 bytes) wide and the final
        // 4 bytes narrow: 7 wide + 3 narrow = 10 payload round-trips, versus the
        // 30 round-trips the old per-16-bit-word path needed.  Assert the wide
        // path actually ran (non-vacuous) and report the round-trip counts. ----
        $display("INFO: RX 60B payload used %0d wide round-trips (per-16-bit-word path needed ~30); total bg round-trips this frame = %0d",
                 wide_pulses, req_pulses);
        if (wide_pulses < 6) begin
            $display("FAIL: expected >=6 wide round-trips for a 60-byte frame, got %0d (wide packing not engaged)", wide_pulses);
            errors = errors + 1;
        end

        // ---- Amiga reads the frame back via remote DMA from page 0x47 ----
        // RSAR = 0x4704 (skip the 4-byte header), CR = remote read
        write_high_reg(15'h0610, 8'h04);   // RSAR0
        write_high_reg(15'h0612, 8'h47);   // RSAR1 -> 0x4704
        write_high_reg(15'h0614, FRAME_LEN[7:0]);  // RBCR0
        write_high_reg(15'h0616, 8'h00);   // RBCR1
        write_high_reg(15'h0600, 8'h0A);   // CR = remote read | STA
        for (k = 0; k < FRAME_LEN; k = k + 2) begin
            data_port_read_word(got);
            exp_hi = frame[k];
            exp_lo = (k+1 < FRAME_LEN) ? frame[k+1] : 8'h00;
            expw   = {exp_hi, exp_lo};
            if (got !== expw) begin
                $display("FAIL: remote-DMA readback word %0d expected 0x%04x got 0x%04x", k/2, expw, got);
                errors = errors + 1;
            end
        end

        // let any pending register sync finish, then dump the round-trip histogram
        repeat (5000) @(posedge clk_sys);
        $display("SYNC WRITES total (1 frame incl. first-time shadow population) = %0d", sync_incr);
        $display("ROUNDTRIP HISTOGRAM (bg_state : mailbox round-trips):");
        for (hh = 0; hh < 64; hh = hh + 1)
            if (st_hist[hh] != 0) $display("    state %0d : %0d", hh, st_hist[hh]);

        // (ao486: the integrity-probe slot assertion is gone with the probes.)

        if (errors == 0)
            $display("PASS: eth_rx_bg_tb completed (RX frame delivered to packet RAM, ISR.PRX/CURR/head OK, Amiga read-back matches)");
        else
            $display("eth_rx_bg_tb FAILED with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #8000000;
        $display("FAIL: global timeout"); $finish;
    end

endmodule
