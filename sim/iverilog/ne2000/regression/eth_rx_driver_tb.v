// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_rx_driver_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_rx_driver_tb.v
//
// Replicates the x-surf-100.device driver's ACTUAL receive-drain sequence to
// find why, on hardware, the driver gets the RX interrupt (eth_irq fires per
// RX, confirmed by ISSP) but never drains the ring (TX stuck, no data-port
// reads). It is NOT enough that the bg delivers the frame (eth_rx_bg_tb proves
// that); the driver reads the ring a specific way the older test never did:
//
//   1. read ISR on PAGE 0   (CR=0x22, reg 7)            -> expect PRX (0x01)
//   2. clear ISR            (write 0x01 to reg 7 page0)
//   3. read CURR on PAGE 1  (CR=0x62, reg 7)            -> expect advanced page
//      (this is the page-1 read the driver compares against its read pointer;
//       ISR and CURR share byte address 0x0C1C, distinguished only by CR page)
//   4. remote-DMA read the 4-byte NE2000 RX header at the read-pointer page via
//      the 32-bit data port 0xEA8880 (CardType=2)       -> {status,next,len}
//   5. remote-DMA read the payload via 0xEA8880          -> must match frame
//   6. advance BNRY to next_page-1                        (page0 reg 3)
//
// If the page-1 CURR read or the 32-bit-port ring read returns the wrong value,
// the driver decides "ring empty" and never replies -> exactly the HW symptom.
//
// Uses the REAL ethernet_interface + REAL ne2000_ddr_mailbox + a behavioral
// f2sdram slave, injecting the frame exactly like the HPS daemon.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_rx_driver_tb;

    localparam [15:0] OFF_FLAGS      = 16'h1000;
    localparam [15:0] OFF_HB         = 16'h1088;
    localparam [15:0] OFF_SIG        = 16'h108C;
    localparam [15:0] OFF_RX_HEAD    = 16'h2C04;
    localparam [15:0] OFF_RX_TAIL    = 16'h2C06;
    localparam [15:0] OFF_RX_LEN     = 16'h2C20;
    localparam [15:0] OFF_RX_DATA    = 16'h9000;
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
    function [7:0] ddr_read_byte;       // exactly what the HPS daemon reads (native LE byte)
        input [15:0] byte_off; reg [13:0] widx; integer bsh;
        begin widx = byte_off >> 3; bsh = (byte_off & 7) * 8; ddr_read_byte = mem[widx][bsh +: 8]; end
    endfunction

    // ---- CPU bus helpers ----
    // Register write (upper byte, like the driver's MOVE.B to an even reg addr).
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

    // Register read (upper byte). Register reads ack immediately; sample
    // cpu_data_out[15:8] once dtack_eth asserts.
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
            if (!done) begin $display("FAIL: register read @0x%04x timed out", word_offset<<1); errors = errors + 1; end
            @(negedge clk_sys);
        end
    endtask

    // Word write to a data port at the given word offset (16-bit access).
    task automatic data_port_write_word;
        input [14:0] port_word_off; input [15:0] value; integer w; reg done;
        begin
            done = 1'b0;
            @(negedge clk_sys);
            // Data-port WRITE: the 0x8C80 write window STILL applies the
            // is_dport32 swap (write swap kept; only the read swap was removed),
            // so pre-swap the 32-bit-port write value to compensate.
            cpu_addr = port_word_off;
            cpu_data_in = (port_word_off == 15'h4440 || port_word_off == 15'h4640)
                          ? {value[7:0], value[15:8]} : value;
            sel_ethernet = 1'b1; cpu_hwr = 1'b1; cpu_lwr = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) done = 1'b1;
            end
            @(negedge clk_sys);
            cpu_hwr = 1'b0; cpu_lwr = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin $display("FAIL: data-port write timed out"); errors = errors + 1; end
            @(negedge clk_sys);
        end
    endtask

    // Word read from a data port at the given word offset (16-bit access).
    task automatic data_port_read_word;
        input  [14:0] port_word_off; output [15:0] value; integer w; reg done;
        begin
            done = 1'b0; value = 16'hXXXX;
            @(negedge clk_sys);
            cpu_addr = port_word_off; sel_ethernet = 1'b1; cpu_rd = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                // 32-bit ports (0x8880/0x8C80) apply the is_dport32 per-word swap
                // on read too, so re-swap the sampled word to recover the value.
                if (dtack_eth === 1'b0) begin value = (port_word_off == 15'h4440 || port_word_off == 15'h4640) ? {cpu_data_out[7:0], cpu_data_out[15:8]} : cpu_data_out; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin $display("FAIL: data-port read timed out"); errors = errors + 1; end
            @(negedge clk_sys);
        end
    endtask

    // NIC register word offsets (byte 0x0C00 + reg*4 -> word (0x0C00+reg*4)>>1)
    localparam [14:0] R_CR    = 15'h0600;       // reg 0
    localparam [14:0] R_BNRY  = 15'h0606;       // reg 3
    localparam [14:0] R_TPSR  = 15'h0608;       // reg 4
    localparam [14:0] R_RSAR0 = 15'h0610;       // reg 8
    localparam [14:0] R_RSAR1 = 15'h0612;       // reg 9
    localparam [14:0] R_RBCR0 = 15'h0614;       // reg 10
    localparam [14:0] R_RBCR1 = 15'h0616;       // reg 11
    localparam [14:0] R_RCR   = 15'h0618;       // reg 12
    localparam [14:0] R_DCR   = 15'h061C;       // reg 14
    localparam [14:0] R_ISR   = 15'h060E;       // reg 7  (page0=ISR, page1=CURR)
    localparam [14:0] R_IMR   = 15'h061E;       // reg 15
    localparam [14:0] R_PSTART= 15'h0602;       // reg 1
    localparam [14:0] R_PSTOP = 15'h0604;       // reg 2

    localparam [14:0] XSURF_INT_STATUS = 15'h0020; // board byte offset 0x0040
    localparam [14:0] PORT32_RD = 15'h4440;     // byte 0x8880 (32-bit DMA read port)
    localparam [14:0] PORT16    = 15'h0640;     // byte 0x0C80 (16-bit data port)

    localparam integer FRAME_LEN = 64;
    reg [7:0] frame [0:FRAME_LEN-1];
    integer k;
    reg [7:0] isr_v, curr_v, bnry_v, st_v, next_v, lenlo_v, lenhi_v, xsurf_irq_v;
    reg [15:0] got, expw, hdr0, hdr1;

    initial begin
        // ARP-request-like broadcast frame
        frame[0]=8'hFF; frame[1]=8'hFF; frame[2]=8'hFF; frame[3]=8'hFF; frame[4]=8'hFF; frame[5]=8'hFF;
        frame[6]=8'h12; frame[7]=8'h34; frame[8]=8'h56; frame[9]=8'h78; frame[10]=8'h9A; frame[11]=8'hBC;
        frame[12]=8'h08; frame[13]=8'h06;   // ARP
        for (k = 14; k < FRAME_LEN; k = k + 1) frame[k] = 8'hA0 + k[7:0];

        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys); @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        ddr_write_u16(OFF_SIG,         16'hBABE);
        ddr_write_u16(OFF_SIG + 16'd2, 16'hCAFE);
        ddr_write_u16(OFF_HB,          16'h0001);
        repeat (300) @(posedge clk_sys);

        // ---- driver-style ring + receiver setup ----
        reg_write(R_PSTART, 8'h46);
        reg_write(R_PSTOP,  8'h80);
        reg_write(R_BNRY,   8'h46);          // BNRY = PSTART
        reg_write(R_DCR,    8'h4B);          // DCR = word mode (CardType 2 uses 32-bit port)
        reg_write(R_RCR,    8'h0C);          // accept broadcast+multicast -> arms rx_poll
        reg_write(R_CR,     8'h62);          // page 1 to set CURR
        reg_write(R_ISR,    8'h47);          // CURR = PSTART+1
        reg_write(R_CR,     8'h22);          // back to page 0, STA -> receiver_active
        reg_write(R_IMR,    8'h0F);          // PRX|PTX|RXE|TXE

        // ---- inject one received frame (daemon order) ----
        for (k = 0; k < FRAME_LEN; k = k + 1)
            ddr_write_byte(OFF_RX_DATA + k[15:0], frame[k]);
        ddr_write_u16(OFF_RX_LEN,  FRAME_LEN[15:0]);
        ddr_write_u16(OFF_RX_TAIL, 16'h0001);
        ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);

        // ---- wait for delivery (ISR.PRX) ----
        begin : wait_prx
            integer g;
            for (g = 0; g < 40000; g = g + 1) begin
                @(posedge clk_sys);
                if ((dut.isr_register & 8'h01) != 8'h00) disable wait_prx;
            end
        end
        if ((dut.isr_register & 8'h01) == 8'h00) begin
            $display("FAIL: ISR.PRX never set (bg_state=%0d curr=0x%02x)", dut.bg_state, dut.curr_register);
            errors = errors + 1;
        end
        repeat (4) @(posedge clk_sys);   // eth_irq is registered; let it settle
        if (eth_irq !== 1'b1) begin
            $display("FAIL: eth_irq not asserted after RX (ISR=0x%02x IMR=0x%02x)", dut.isr_register, dut.imr_register);
            errors = errors + 1;
        end
        reg_read(XSURF_INT_STATUS, xsurf_irq_v);
        if ((xsurf_irq_v & 8'h80) == 8'h00) begin
            $display("FAIL: X-Surf board irq status @0x0040=0x%02x; driver will not signal RX task", xsurf_irq_v);
            errors = errors + 1;
        end

        // ===================================================================
        // Replicate the driver's interrupt-handler RX drain
        // ===================================================================

        // 1. read ISR on page 0
        reg_write(R_CR, 8'h22);
        reg_read(R_ISR, isr_v);
        if ((isr_v & 8'h01) == 8'h00) begin
            $display("FAIL: driver read ISR(page0)=0x%02x, PRX not visible to the CPU", isr_v);
            errors = errors + 1;
        end

        // 2. clear ISR (write-1-to-clear PRX)
        reg_write(R_ISR, 8'h01);
        repeat (2) @(posedge clk_sys);
        reg_read(XSURF_INT_STATUS, xsurf_irq_v);
        if ((xsurf_irq_v & 8'h80) != 8'h00) begin
            $display("FAIL: X-Surf board irq status @0x0040 stuck high after ISR clear: 0x%02x", xsurf_irq_v);
            errors = errors + 1;
        end

        // 3. read CURR on page 1  <-- the key page-1 read the driver compares
        reg_write(R_CR, 8'h62);
        reg_read(R_ISR, curr_v);     // reg 7 on page 1 = CURR
        reg_write(R_CR, 8'h22);      // back to page 0
        $display("INFO: driver sees CURR(page1)=0x%02x (expect 0x48)", curr_v);
        if (curr_v !== 8'h48) begin
            $display("FAIL: page-1 CURR read = 0x%02x, expected 0x48 -> driver thinks ring empty!", curr_v);
            errors = errors + 1;
        end

        // read BNRY (page0 reg3) -> the driver's read pointer is BNRY+1
        reg_read(R_BNRY, bnry_v);
        $display("INFO: BNRY=0x%02x -> read pointer = 0x%02x", bnry_v, bnry_v + 8'h01);

        // 4. remote-DMA read the 4-byte RX header at the read-pointer page (0x47)
        //    via the 32-bit DMA read port 0x8880.
        reg_write(R_RSAR0, 8'h00);
        reg_write(R_RSAR1, 8'h47);          // 0x4700 = page 0x47
        reg_write(R_RBCR0, 8'h04);
        reg_write(R_RBCR1, 8'h00);
        reg_write(R_CR,    8'h0A);          // remote read
        data_port_read_word(PORT32_RD, hdr0);   // {status, next_page}
        data_port_read_word(PORT32_RD, hdr1);   // {len_lo, len_hi}
        st_v    = hdr0[15:8];
        next_v  = hdr0[7:0];
        lenlo_v = hdr1[15:8];
        lenhi_v = hdr1[7:0];
        $display("INFO: RX header via 0x8880: status=0x%02x next=0x%02x len=0x%02x%02x",
                 st_v, next_v, lenhi_v, lenlo_v);
        if (st_v !== 8'h21) begin
            $display("FAIL: RX header status via 0x8880 = 0x%02x, expected 0x21", st_v);
            errors = errors + 1;
        end
        if (next_v !== 8'h48) begin
            $display("FAIL: RX header next_page via 0x8880 = 0x%02x, expected 0x48", next_v);
            errors = errors + 1;
        end
        if ({lenhi_v, lenlo_v} !== (FRAME_LEN[15:0] + 16'h0004)) begin
            $display("FAIL: RX header length via 0x8880 = 0x%04x, expected RTL8029/NE2000 count 0x%04x",
                     {lenhi_v, lenlo_v}, FRAME_LEN[15:0] + 16'h0004);
            errors = errors + 1;
        end

        // 5. remote-DMA read the payload via 0x8880 (driver subtracts the
        //    4-byte NE2000 header count before reading from 0x4704).
        reg_write(R_RSAR0, 8'h04);
        reg_write(R_RSAR1, 8'h47);          // 0x4704
        reg_write(R_RBCR0, FRAME_LEN[7:0]);
        reg_write(R_RBCR1, 8'h00);
        reg_write(R_CR,    8'h0A);
        for (k = 0; k < FRAME_LEN; k = k + 2) begin
            data_port_read_word(PORT32_RD, got);
            expw = {frame[k], (k+1 < FRAME_LEN) ? frame[k+1] : 8'h00};
            if (got !== expw) begin
                $display("FAIL: payload via 0x8880 word %0d = 0x%04x, expected 0x%04x", k/2, got, expw);
                errors = errors + 1;
            end
        end

        // Read-side probe validation: the driver read back exactly the 4-byte
        // header + 64-byte payload the bg wrote, so the read-side running sum
        // (dp_rd_csum) must equal the write-side running sum (ring_wr_csum). This
        // exercises the ACTUAL data-port read -> dp_rd_csum accumulation path.

        // PER-FRAME read-corruption probe: the driver just did an even-length,
        // offset-4, count>8 payload read (FRAME_LEN=64) -- exactly the armed case.
        // The bg stored this frame's payload csum; the read re-summed it; a clean
        // read must leave rd_corrupt == 0 (no false positive on a correct read).

        // 6. advance BNRY = next_page - 1 (0x47); ring now empty (read ptr == CURR)
        reg_write(R_BNRY, next_v - 8'h01);

        // ===================================================================
        // TX path: replicate the driver's transmit (CardType=2, 32-bit write
        // port 0x8C80) and verify ISR.PTX + eth_irq fire. The X-Surf test's
        // "No IRQ received !!!! Transmit timeout!" says this interrupt never
        // reaches the CPU on HW.
        // ===================================================================
        // clear any pending ISR first
        reg_write(R_CR, 8'h22);
        reg_write(R_ISR, 8'hFF);
        repeat (4) @(posedge clk_sys);
        if (eth_irq !== 1'b0) begin
            $display("FAIL: eth_irq still set after clearing ISR (ISR=0x%02x)", dut.isr_register);
            errors = errors + 1;
        end

        // write a short TX frame to TX page 0x40 (0x4000) via the 32-bit write port
        reg_write(R_RSAR0, 8'h00);
        reg_write(R_RSAR1, 8'h40);          // 0x4000
        reg_write(R_RBCR0, 8'h40);          // 64 bytes
        reg_write(R_RBCR1, 8'h00);
        reg_write(R_CR,    8'h12);          // remote write
        for (k = 0; k < 64; k = k + 2)
            data_port_write_word(15'h4640, {frame[k], frame[k+1]});   // 0x8C80 write port

        // issue the transmit
        reg_write(R_TPSR,  8'h40);          // transmit page start
        reg_write(R_RBCR0, 8'h40);          // (TBCR shares regs 5/6) - set length
        reg_write(15'h060A, 8'h40);         // TBCR0 (reg5) = 64
        reg_write(15'h060C, 8'h00);         // TBCR1 (reg6) = 0
        reg_write(R_CR,    8'h26);          // STA | TXP -> transmit

        // wait for ISR.PTX
        begin : wait_ptx
            integer g;
            for (g = 0; g < 40000; g = g + 1) begin
                @(posedge clk_sys);
                if ((dut.isr_register & 8'h02) != 8'h00) disable wait_ptx;
            end
        end
        if ((dut.isr_register & 8'h02) == 8'h00) begin
            $display("FAIL: ISR.PTX never set after TXP (bg_state=%0d)", dut.bg_state);
            errors = errors + 1;
        end else begin
            $display("INFO: TX complete, ISR.PTX set (ISR=0x%02x)", dut.isr_register);
        end
        repeat (4) @(posedge clk_sys);
        if (eth_irq !== 1'b1) begin
            $display("FAIL: eth_irq not asserted after TX with IMR.PTX set (ISR=0x%02x IMR=0x%02x) -> 'No IRQ received'",
                     dut.isr_register, dut.imr_register);
            errors = errors + 1;
        end else begin
            $display("INFO: eth_irq asserted after TX (PTX interrupt reaches INT2)");
        end

        // ---- verify the staged TX frame byte order (what the HPS daemon reads
        //      from the TX ring slot and transmits). Fix B: the frame is staged
        //      into slot (tx_request_seq % 8) at 0x3000 + slot*1536, not the old
        //      fixed 0x2000 single buffer. ----
        repeat (4000) @(posedge clk_sys);   // let the bg stage all 64 bytes to shm
        begin : tx_order
            integer b; reg [7:0] sb; integer swaperr; reg [15:0] slot_base;
            swaperr = 0;
            slot_base = 16'h3000 + ({13'd0, dut.tx_request_seq[2:0]} * 16'h0600);
            for (b = 0; b < 64; b = b + 1) begin
                sb = ddr_read_byte(slot_base + b[15:0]);
                if (sb !== frame[b]) begin
                    errors = errors + 1;
                    if (sb === frame[b ^ 1]) swaperr = swaperr + 1;
                    if (b < 16)
                        $display("FAIL: TX shm[0x%04x]=0x%02x, frame[%0d]=0x%02x%s",
                                 slot_base+b, sb, b, frame[b],
                                 (sb === frame[b^1]) ? "  (BYTE-SWAPPED with neighbor)" : "");
                end
            end
            if (swaperr > 0)
                $display("DIAG: %0d/64 TX bytes are swapped with their 16-bit neighbor -> per-word byte-swap in TX staging", swaperr);
        end

        if (errors == 0)
            $display("PASS: eth_rx_driver_tb completed (page-1 CURR + 32-bit-port ring drain match the driver)");
        else
            $display("eth_rx_driver_tb FAILED with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #9000000;
        $display("FAIL: global timeout"); $finish;
    end

endmodule
