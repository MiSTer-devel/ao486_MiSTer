// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_rx_ringwrap_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_rx_ringwrap_tb.v
//
// Sweeps RX frames whose data crosses the ring stop page (PSTOP) at several
// different start pages and full 1500-byte length. A real RTL8019 wraps the
// receive write at PSTOP back to PSTART, keeping the frame inside the ring
// [PSTART, PSTOP). This core used to address packet RAM LINEARLY and mask only
// at the PHYSICAL 16 KB boundary (page 0x80 -> 0x40), so a crossing frame spilled
// its tail into pages 0x40..0x45 (the TX buffer), corrupting a staged ACK and
// mislaying the wrapped bytes -> the Amiga drops the frame on checksum and the
// server retransmits (ETHPERF retx>0 with every drop counter at zero).
//
// Drives the REAL ethernet_interface + REAL ne2000_ddr_mailbox + behavioral
// f2sdram, exactly like eth_rx_bg_tb.v. Geometry (defaults): TX page 0x40, ring
// PSTART=0x46 PSTOP=0x80. For each start page a 1500-byte frame is delivered
// then read back through the remote-DMA data port; the frame must read back
// byte-exact AND the TX buffer (pages 0x40..0x45) must be left untouched. A
// non-crossing control (0x70) confirms the wrap logic does not disturb the
// ordinary case.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_rx_ringwrap_tb;

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

    localparam integer FRAME_MAX = 1600;     // buffer; frames delivered are 1500

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

    task automatic pram_write_word;
        input [15:0] ne_addr;
        input [15:0] val;
        reg [12:0] idx;
        begin
            idx = (ne_addr - 16'h4000) >> 1;
            dut.packet_ram_inst.mem_u[idx] = val[15:8];
            dut.packet_ram_inst.mem_l[idx] = val[7:0];
        end
    endtask

    reg [7:0]  frame [0:FRAME_MAX-1];
    integer k;
    reg [15:0] tx_sentinel [0:(6*256)/2 - 1];
    integer    tx_words;
    integer    next_slot;
    reg [15:0] expected_head;

    // Deliver one frame starting at start_page, then verify (1) the TX buffer
    // (pages 0x40..0x45) is untouched and (2) the frame reads back byte-exact
    // through the remote-DMA data port. slot cycles through the shared RX
    // queue. xcross!=0 documents that this frame is expected to wrap at PSTOP.
    task automatic deliver_and_check;
        input [7:0]   start_page;
        input [31:0]  flen;
        input [31:0]  xcross;
        reg   [15:0]  sdata, slen, rsar, gg, ew;
        reg   [7:0]   eh, el;
        integer       kk, bad_tx, bad_rb, g;
        reg   [15:0]  tnow;
        begin
            sdata = OFF_RX_DATA + next_slot[15:0] * RX_SLOT_SIZE;
            slen  = OFF_RX_LEN  + next_slot[15:0] * 16'h0002;

            // Re-seed the TX-buffer sentinel before each delivery.
            for (kk = 0; kk < tx_words; kk = kk + 1)
                pram_write_word(16'h4000 + kk*2, tx_sentinel[kk]);

            // Place the ring so this frame starts at start_page with room ahead
            // (BNRY parked mid-ring, away from both ends).
            dut.curr_register = start_page;
            dut.bnry_register = 8'h60;
            repeat (4) @(posedge clk_sys);

            // Inject the frame into the next shared slot (daemon write order).
            for (kk = 0; kk < flen; kk = kk + 1)
                ddr_write_byte(sdata + kk[15:0], frame[kk]);
            ddr_write_u16(slen, flen[15:0]);
            expected_head = (next_slot + 1) % RX_QUEUE_SLOTS;
            ddr_write_u16(OFF_RX_TAIL, expected_head);
            ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);

            // Wait for the bg to consume the slot (head advances).
            for (g = 0; g < 400000; g = g + 1) begin
                @(posedge clk_sys);
                if (ddr_read_u16(OFF_RX_HEAD) == expected_head) g = 400001;
            end
            if (ddr_read_u16(OFF_RX_HEAD) !== expected_head) begin
                $display("FAIL[start=0x%02x]: bg never consumed slot (head=%0d bg_state=%0d curr=0x%02x)",
                         start_page, ddr_read_u16(OFF_RX_HEAD), dut.bg_state, dut.curr_register);
                errors = errors + 1;
            end
            repeat (200) @(posedge clk_sys);

            // CHECK 1: TX buffer (pages 0x40..0x45) intact.
            bad_tx = 0;
            for (kk = 0; kk < tx_words; kk = kk + 1) begin
                tnow = pram_word(16'h4000 + kk*2);
                if (tnow !== tx_sentinel[kk]) begin
                    if (bad_tx < 4)
                        $display("FAIL[start=0x%02x]: TX-buffer word @0x%04x clobbered: was 0x%04x now 0x%04x",
                                 start_page, 16'h4000 + kk*2, tx_sentinel[kk], tnow);
                    bad_tx = bad_tx + 1;
                end
            end
            if (bad_tx != 0) begin
                $display("FAIL[start=0x%02x]: %0d TX-buffer word(s) clobbered by RX wrap (xcross=%0d)",
                         start_page, bad_tx, xcross);
                errors = errors + 1;
            end

            // CHECK 2: read the frame back byte-exact via remote DMA.
            rsar = {start_page, 8'h04};
            write_high_reg(15'h0610, rsar[7:0]);
            write_high_reg(15'h0612, rsar[15:8]);
            write_high_reg(15'h0614, flen[7:0]);
            write_high_reg(15'h0616, flen[15:8]);
            write_high_reg(15'h0600, 8'h0A);   // CR remote read | STA
            bad_rb = 0;
            for (kk = 0; kk < flen; kk = kk + 2) begin
                data_port_read_word(gg);
                eh = frame[kk];
                el = (kk+1 < flen) ? frame[kk+1] : 8'h00;
                ew = {eh, el};
                if (gg !== ew) begin
                    if (bad_rb < 4)
                        $display("FAIL[start=0x%02x]: readback off %0d expected 0x%04x got 0x%04x",
                                 start_page, kk, ew, gg);
                    bad_rb = bad_rb + 1;
                end
            end
            if (bad_rb != 0) begin
                $display("FAIL[start=0x%02x]: %0d readback word(s) wrong (xcross=%0d)",
                         start_page, bad_rb, xcross);
                errors = errors + 1;
            end

            if (bad_tx == 0 && bad_rb == 0)
                $display("OK[start=0x%02x xcross=%0d len=%0d]: TX buffer intact + byte-exact readback",
                         start_page, xcross, flen);

            next_slot = (next_slot + 1) % RX_QUEUE_SLOTS;
        end
    endtask

    task automatic deliver_expect_bnry_overrun;
        input [7:0]   start_page;
        input [7:0]   bnry_page;
        input [31:0]  flen;
        reg   [15:0]  sdata, slen;
        reg   [15:0]  rx_sentinel;
        integer       kk, g;
        begin
            sdata = OFF_RX_DATA + next_slot[15:0] * RX_SLOT_SIZE;
            slen  = OFF_RX_LEN  + next_slot[15:0] * 16'h0002;

            rx_sentinel = 16'h5AFE;
            pram_write_word({start_page, 8'h00}, rx_sentinel);

            dut.curr_register  = start_page;
            dut.bnry_register  = bnry_page;
            dut.isr_register   = 8'h00;
            dut.rsr_register   = 8'h00;
            dut.cntr2_register = 8'h00;
            repeat (4) @(posedge clk_sys);

            for (kk = 0; kk < flen; kk = kk + 1)
                ddr_write_byte(sdata + kk[15:0], frame[kk]);
            ddr_write_u16(slen, flen[15:0]);
            expected_head = (next_slot + 1) % RX_QUEUE_SLOTS;
            ddr_write_u16(OFF_RX_TAIL, expected_head);
            ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);

            for (g = 0; g < 400000; g = g + 1) begin
                @(posedge clk_sys);
                if (ddr_read_u16(OFF_RX_HEAD) == expected_head) g = 400001;
            end
            repeat (200) @(posedge clk_sys);

            if (ddr_read_u16(OFF_RX_HEAD) !== expected_head) begin
                $display("FAIL[bnry-span]: bg never consumed dropped slot (head=%0d bg_state=%0d)",
                         ddr_read_u16(OFF_RX_HEAD), dut.bg_state);
                errors = errors + 1;
            end
            if (dut.curr_register !== start_page) begin
                $display("FAIL[bnry-span]: CURR advanced to 0x%02x despite overrun, expected 0x%02x",
                         dut.curr_register, start_page);
                errors = errors + 1;
            end
            if (dut.cntr2_register !== 8'h01 || dut.rsr_register !== 8'h10 ||
                (dut.isr_register & 8'h10) == 8'h00) begin
                $display("FAIL[bnry-span]: expected OVW/MPA/CNTR2, got ISR=0x%02x RSR=0x%02x CNTR2=%0d",
                         dut.isr_register, dut.rsr_register, dut.cntr2_register);
                errors = errors + 1;
            end
            if (pram_word({start_page, 8'h00}) !== rx_sentinel) begin
                $display("FAIL[bnry-span]: packet RAM header word was overwritten before overrun drop");
                errors = errors + 1;
            end

            if (dut.curr_register === start_page && dut.cntr2_register === 8'h01 &&
                pram_word({start_page, 8'h00}) === rx_sentinel)
                $display("OK[bnry-span]: large frame crossing BNRY is dropped before packet RAM overwrite");

            next_slot = (next_slot + 1) % RX_QUEUE_SLOTS;
        end
    endtask

    initial begin
        for (k = 0; k < 14; k = k + 1) frame[k] = k[7:0];
        frame[0]=8'h02; frame[1]=8'h11; frame[2]=8'h22; frame[3]=8'h33; frame[4]=8'h44; frame[5]=8'h55;
        frame[12]=8'h08; frame[13]=8'h00;
        for (k = 14; k < FRAME_MAX; k = k + 1) frame[k] = (k + 8'h5A) & 8'hFF;

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

        tx_words  = (6*256)/2;
        for (k = 0; k < tx_words; k = k + 1)
            tx_sentinel[k] = 16'hA500 | (k & 16'h00FF);
        next_slot = 0;

        // Control: a frame that does NOT xcross PSTOP (start 0x70, 6 pages ends 0x76).
        deliver_and_check(8'h70, 1500, 0);
        // Sweep crossing start pages: 1500B/6-page frame crosses PSTOP=0x80 with a
        // different number of pages before/after the wrap each time.
        deliver_and_check(8'h7B, 1500, 1);
        deliver_and_check(8'h7C, 1500, 1);
        deliver_and_check(8'h7D, 1500, 1);
        deliver_and_check(8'h7E, 1500, 1);
        deliver_and_check(8'h7F, 1500, 1);
        // Regression for the large-download corruption case: a 1500B/6-page
        // frame starting at 0x4F crosses unread BNRY=0x50 but does not END at
        // BNRY, so the old "next_page == BNRY" check missed it.
        deliver_expect_bnry_overrun(8'h4F, 8'h50, 1500);

        if (errors == 0)
            $display("PASS: eth_rx_ringwrap_tb (PSTOP sweep byte-exact, BNRY-span overrun rejected)");
        else
            $display("eth_rx_ringwrap_tb FAILED with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #80000000;
        $display("FAIL: global timeout"); $finish;
    end

endmodule
