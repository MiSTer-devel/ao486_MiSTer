// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_rx_flood_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_rx_flood_tb.v
//
// Multi-packet RX flood + ring-wrap test. The single-packet eth_rx_driver_tb
// proves the mechanism in isolation; the REAL hardware is draining a continuous
// flood through a wrapping ring while the driver clears ISR ~8x per packet and
// (apparently) never replies. This test injects SEVERAL distinct frames one at
// a time through a deliberately SMALL NE2000 ring (PSTART=0x46..PSTOP=0x4A, 4
// pages) so CURR/BNRY wrap repeatedly, and after each delivery drains the frame
// exactly as the driver does (read CURR on page 1, remote-DMA read the RX
// header + payload via the 32-bit port 0x8880, advance BNRY). Each frame's
// payload carries a unique marker so a wrong page / wrap bug is caught as a data
// mismatch. If the FPGA's ring management breaks under repeated wrap, this fails
// here instead of needing the board.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_rx_flood_tb;

    localparam [15:0] OFF_FLAGS      = 16'h1000;
    localparam [15:0] OFF_HB         = 16'h1088;
    localparam [15:0] OFF_SIG        = 16'h108C;
    localparam [15:0] OFF_RX_HEAD    = 16'h2C04;
    localparam [15:0] OFF_RX_TAIL    = 16'h2C06;
    localparam [15:0] OFF_RX_LEN     = 16'h2C20;   // +slot*2
    localparam [15:0] OFF_RX_DATA    = 16'h9000;   // +slot*0x600
    localparam [15:0] RX_SLOT_SIZE   = 16'h0600;
    localparam integer RX_QUEUE_SLOTS = 16;
    localparam [15:0] FLAG_RX_AVAIL  = 16'h0004;

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
        input [15:0] byte_off; input [7:0] val;
        reg [13:0] widx; integer bsh;
        begin widx = byte_off >> 3; bsh = (byte_off & 7) * 8; mem[widx][bsh +: 8] = val; end
    endtask
    task automatic ddr_write_u16;
        input [15:0] byte_off; input [15:0] val;
        begin ddr_write_byte(byte_off, val[7:0]); ddr_write_byte(byte_off + 16'd1, val[15:8]); end
    endtask
    function [15:0] ddr_read_u16;
        input [15:0] byte_off; reg [13:0] widx; integer bsh;
        begin widx = byte_off >> 3; bsh = (byte_off & 7) * 8;
              ddr_read_u16 = {mem[widx][bsh+8 +: 8], mem[widx][bsh +: 8]}; end
    endfunction

    task automatic reg_write;
        input [14:0] word_offset; input [7:0] value;
        begin
            @(negedge clk_sys);
            cpu_addr = word_offset; cpu_data_in = {value, 8'h00};
            sel_ethernet = 1'b1; cpu_hwr = 1'b1; cpu_lwr = 1'b0;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b1;
            @(posedge clk_sys); @(negedge clk_sys);
            cpu_hwr = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1;
            sel_ethernet = 1'b0; cpu_data_in = 16'h0000;
        end
    endtask

    task automatic reg_read;
        input [14:0] word_offset; output [7:0] value; integer w; reg done;
        begin
            done = 1'b0; value = 8'hXX;
            @(negedge clk_sys);
            cpu_addr = word_offset; sel_ethernet = 1'b1; cpu_rd = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b1;
            for (w = 0; w < 64 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) begin value = cpu_data_out[15:8]; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin $display("FAIL: reg read timed out"); errors = errors + 1; end
            @(negedge clk_sys);
        end
    endtask

    task automatic data_port_read_word;
        input  [14:0] port_word_off; output [15:0] value; integer w; reg done;
        begin
            done = 1'b0; value = 16'hXXXX;
            @(negedge clk_sys);
            cpu_addr = port_word_off; sel_ethernet = 1'b1; cpu_rd = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                // 0x8880 applies the is_dport32 per-word read swap -> re-swap to recover.
                if (dtack_eth === 1'b0) begin value = (port_word_off == 15'h4440 || port_word_off == 15'h4640) ? {cpu_data_out[7:0], cpu_data_out[15:8]} : cpu_data_out; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin $display("FAIL: data-port read timed out"); errors = errors + 1; end
            @(negedge clk_sys);
        end
    endtask

    localparam [14:0] R_CR    = 15'h0600;
    localparam [14:0] R_PSTART= 15'h0602;
    localparam [14:0] R_PSTOP = 15'h0604;
    localparam [14:0] R_BNRY  = 15'h0606;
    localparam [14:0] R_RSAR0 = 15'h0610;
    localparam [14:0] R_RSAR1 = 15'h0612;
    localparam [14:0] R_RBCR0 = 15'h0614;
    localparam [14:0] R_RBCR1 = 15'h0616;
    localparam [14:0] R_RCR   = 15'h0618;
    localparam [14:0] R_DCR   = 15'h061C;
    localparam [14:0] R_ISR   = 15'h060E;       // page0 ISR / page1 CURR
    localparam [14:0] R_IMR   = 15'h061E;
    localparam [14:0] PORT32_RD = 15'h4440;     // 0x8880

    localparam integer NPKT = 8;                 // > ring size -> forces wrap
    localparam integer FLEN = 60;
    reg [7:0] frame [0:FLEN-1];
    integer p, k;
    reg [7:0] isr_v, curr_v, rdptr, next_v, st_v;
    reg [15:0] got, expw, hdr0;
    reg [7:0]  marker;

    // build a frame whose payload byte 14.. all equal `marker` so we know which
    // packet we actually read.
    task automatic build_frame; input [7:0] m;
        begin
            frame[0]=8'hFF; frame[1]=8'hFF; frame[2]=8'hFF; frame[3]=8'hFF; frame[4]=8'hFF; frame[5]=8'hFF;
            frame[6]=8'h12; frame[7]=8'h34; frame[8]=8'h56; frame[9]=8'h78; frame[10]=8'h9A; frame[11]=8'hBC;
            frame[12]=8'h08; frame[13]=8'h06;
            for (k = 14; k < FLEN; k = k + 1) frame[k] = m;
        end
    endtask

    integer slot; integer tail;

    // per-frame register-sync round-trip counter (bg_state 18 = BG_SYNC_WORD_WAIT)
    integer sync_writes = 0;
    integer sw_before;
    reg fl_req_d = 1'b0;
    always @(posedge clk_sys) begin
        fl_req_d <= eth_dma_req;
        if (eth_dma_req && !fl_req_d && dut.bg_state == 6'd18)
            sync_writes <= sync_writes + 1;
    end

    initial begin
        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys); @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        ddr_write_u16(OFF_SIG, 16'hBABE); ddr_write_u16(OFF_SIG+16'd2, 16'hCAFE);
        ddr_write_u16(OFF_HB, 16'h0001);
        repeat (300) @(posedge clk_sys);

        // small 4-page ring 0x46..0x49 to force wrap every 3 packets
        reg_write(R_PSTART, 8'h46);
        reg_write(R_PSTOP,  8'h4A);
        reg_write(R_BNRY,   8'h46);
        reg_write(R_DCR,    8'h4B);
        reg_write(R_RCR,    8'h0C);
        reg_write(R_CR,     8'h62); reg_write(R_ISR, 8'h47); reg_write(R_CR, 8'h22);  // CURR=0x47
        reg_write(R_IMR,    8'h0F);

        tail = 0;
        for (p = 0; p < NPKT; p = p + 1) begin
            marker = 8'hA0 + p[7:0];
            build_frame(marker);
            slot = p % RX_QUEUE_SLOTS;
            sw_before = sync_writes;

            // read CURR (page1) BEFORE injection -> the page the bg will write at
            reg_write(R_CR, 8'h62); reg_read(R_ISR, curr_v); reg_write(R_CR, 8'h22);
            rdptr = curr_v;                 // driver reads the new packet from here

            // inject one frame into the shared RX slot (daemon order)
            for (k = 0; k < FLEN; k = k + 1)
                ddr_write_byte(OFF_RX_DATA + slot*RX_SLOT_SIZE + k[15:0], frame[k]);
            ddr_write_u16(OFF_RX_LEN + slot*2, FLEN[15:0]);
            tail = (tail + 1) % RX_QUEUE_SLOTS;
            ddr_write_u16(OFF_RX_TAIL, tail[15:0]);
            ddr_write_u16(OFF_FLAGS, FLAG_RX_AVAIL);

            // wait for the bg to advance CURR past rdptr (delivery done)
            begin : wdel
                integer g;
                for (g = 0; g < 60000; g = g + 1) begin
                    @(posedge clk_sys);
                    if (dut.curr_register !== rdptr) disable wdel;
                end
            end
            if (dut.curr_register === rdptr) begin
                $display("FAIL: pkt %0d not delivered (CURR stuck at 0x%02x, bg_state=%0d)", p, rdptr, dut.bg_state);
                errors = errors + 1;
            end

            // driver drain: read ISR(page0), clear, read CURR(page1)
            reg_write(R_CR, 8'h22);
            reg_read(R_ISR, isr_v);
            if ((isr_v & 8'h01) == 8'h00) begin
                $display("FAIL: pkt %0d ISR.PRX not visible (ISR=0x%02x)", p, isr_v); errors = errors + 1;
            end
            reg_write(R_ISR, 8'h01);
            reg_write(R_CR, 8'h62); reg_read(R_ISR, curr_v); reg_write(R_CR, 8'h22);

            // remote-DMA read header at rdptr page via 0x8880
            reg_write(R_RSAR0, 8'h00);
            reg_write(R_RSAR1, rdptr);
            reg_write(R_RBCR0, 8'h04);
            reg_write(R_RBCR1, 8'h00);
            reg_write(R_CR,    8'h0A);
            data_port_read_word(PORT32_RD, hdr0);
            st_v   = hdr0[15:8];
            next_v = hdr0[7:0];
            if (st_v !== 8'h21) begin
                $display("FAIL: pkt %0d header status=0x%02x (want 0x21) at page 0x%02x", p, st_v, rdptr);
                errors = errors + 1;
            end

            // remote-DMA read payload via 0x8880; check the marker byte (offset 14)
            reg_write(R_RSAR0, 8'h04);
            reg_write(R_RSAR1, rdptr);
            reg_write(R_RBCR0, FLEN[7:0]);
            reg_write(R_RBCR1, 8'h00);
            reg_write(R_CR,    8'h0A);
            for (k = 0; k < FLEN; k = k + 2) begin
                data_port_read_word(PORT32_RD, got);
                expw = {frame[k], (k+1 < FLEN) ? frame[k+1] : 8'h00};
                if (got !== expw) begin
                    $display("FAIL: pkt %0d (marker 0x%02x) payload word @%0d = 0x%04x want 0x%04x",
                             p, marker, k/2, got, expw);
                    errors = errors + 1;
                    k = FLEN;   // stop dumping this packet
                end
            end

            // advance BNRY = next_page - 1 (driver frees the page)
            reg_write(R_BNRY, (next_v == 8'h46) ? 8'h49 : (next_v - 8'h01));
            repeat (1500) @(posedge clk_sys);   // let this frame's register sync settle
            $display("INFO: pkt %0d marker=0x%02x page 0x%02x next 0x%02x CURR 0x%02x  sync_round_trips=%0d",
                     p, marker, rdptr, next_v, curr_v, sync_writes - sw_before);
            // Steady-state regression guard: once the shadow is populated (pkt 0),
            // a frame must re-sync only the few register slots that actually
            // changed -- not the full ~41-slot mirror.  Catches an accidental
            // return to the unconditional per-frame full sync.
            if (p >= 1 && (sync_writes - sw_before) > 10) begin
                $display("FAIL: pkt %0d register sync did %0d round-trips (expected <=10 with incremental sync)",
                         p, sync_writes - sw_before);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: eth_rx_flood_tb completed (%0d frames drained through a wrapping ring, all data correct)", NPKT);
        else
            $display("eth_rx_flood_tb FAILED with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #40000000;
        $display("FAIL: global timeout"); $finish;
    end

endmodule
