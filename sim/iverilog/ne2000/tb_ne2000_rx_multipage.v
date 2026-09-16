// tb_ne2000_rx_multipage.v -- reproduce the multi-page RX read-out bug.
//
// Hardware finding (2026-08-03): a guest receives 1-page unicast frames fine
// (mTCP ping replies work) but never sees a DHCP OFFER, which is 342 bytes = 2
// ring pages. eth_rx_lensweep_tb proves the FPGA WRITES multi-page frames into
// packet RAM correctly, but it checks packet RAM directly. eth_rx_driver_tb
// reads a frame back through the DATA PORT the way a real driver does -- but
// only a 64-byte, single-page frame. This bench closes that gap: inject a
// 2-page frame and read the whole payload back through the 16-bit data port
// (0x0C80, the port the ao486 Crynwr driver uses), byte-for-byte.
//
// Harness (DDR slave, ddr_* helpers, reg_* helpers) is lifted from
// eth_rx_driver_tb.v; the frame is 342 bytes and the read-out uses the 16-bit
// port with standard x86 byte order (word = {frame[k+1], frame[k]}).

`timescale 1ns/1ps

module tb_ne2000_rx_multipage;

    localparam [15:0] OFF_HB      = 16'h1088;
    localparam [15:0] OFF_SIG     = 16'h108C;
    localparam [15:0] OFF_RX_TAIL = 16'h2C06;
    localparam [15:0] OFF_RX_LEN  = 16'h2C20;
    localparam [15:0] OFF_RX_DATA = 16'h9000;
    localparam [15:0] OFF_FLAGS   = 16'h1000;
    localparam [15:0] FLAG_RX_AVAIL = 16'h0004;

    reg clk_sys = 0, clk_avl = 0;
    always #17 clk_sys = ~clk_sys;
    always #21 clk_avl = ~clk_avl;
    reg reset_sys = 1, reset_avl = 1;

    reg  [15:1] cpu_addr = 0;
    reg  [15:0] cpu_data_in = 0;
    wire [15:0] cpu_data_out;
    reg  cpu_rd = 0, cpu_hwr = 0, cpu_lwr = 0;
    reg  cpu_as = 1, cpu_uds = 1, cpu_lds = 1;
    reg  sel_ethernet_shm = 0, sel_ethernet = 0;

    wire        eth_dma_ready;
    wire [15:0] eth_dma_rdata;
    wire [63:0] eth_dma_rdata64;
    wire        eth_dma_wide;
    wire [63:0] eth_dma_wdata64;
    wire        eth_dma_req, eth_dma_write;
    wire [15:1] eth_dma_addr;
    wire [15:0] eth_dma_wdata;
    wire        eth_dma_uds, eth_dma_lds;
    wire        eth_irq, dtack_eth;

    wire [28:0] avl_address;
    wire [ 7:0] avl_burstcount, avl_byteenable;
    wire [63:0] avl_writedata;
    wire        avl_read, avl_write, avl_waitrequest;
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
        .eth_dma_rdata64(eth_dma_rdata64), .eth_dma_wide(eth_dma_wide),
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
        .eth_dma_rdata64(eth_dma_rdata64), .eth_dma_wide(eth_dma_wide),
        .eth_dma_wdata64(eth_dma_wdata64),
        .clk_avl(clk_avl), .reset_avl(reset_avl),
        .avl_address(avl_address), .avl_burstcount(avl_burstcount),
        .avl_byteenable(avl_byteenable), .avl_writedata(avl_writedata),
        .avl_read(avl_read), .avl_write(avl_write),
        .avl_waitrequest(avl_waitrequest), .avl_readdata(avl_readdata),
        .avl_readdatavalid(avl_readdatavalid), .dbg()
    );

    // ---- behavioral f2sdram slave (from eth_rx_driver_tb) ----
    localparam ACCEPT_DELAY = 2, READ_LAT = 3;
    reg [63:0] mem [0:16383];
    localparam SS_IDLE = 2'd0, SS_LAT = 2'd1, SS_EMIT = 2'd2;
    reg [1:0] ss_state = SS_IDLE;
    reg [3:0] acc_cnt = 0, lat_cnt = 0;
    reg [8:0] beats = 0;
    reg [13:0] r_index = 0;
    reg is_busy = 0;
    wire cmd_present = avl_read | avl_write;
    assign avl_waitrequest = is_busy ? 1'b1 : (cmd_present ? (acc_cnt < ACCEPT_DELAY) : 1'b0);
    wire cmd_accept = cmd_present & ~avl_waitrequest;
    reg rdv = 0; reg [63:0] rdo = 0;
    assign avl_readdatavalid = rdv;
    assign avl_readdata = rdo;
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

    // ---- CPU bus helpers (16-bit port / byte registers) ----
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
            if (!done) begin $display("FAIL: register read @0x%04x timed out", word_offset<<1); errors = errors + 1; end
            @(negedge clk_sys);
        end
    endtask

    // 16-bit data-port word read (port 0x0C80 = word 0x0640). Full 16-bit access,
    // no lane swap (that is only for the Amiga 32-bit ports).
    task automatic dport_read_word;
        output [15:0] value; integer w; reg done;
        begin
            done = 1'b0; value = 16'hXXXX;
            @(negedge clk_sys);
            cpu_addr = 15'h0640; sel_ethernet = 1'b1; cpu_rd = 1'b1;
            cpu_as = 1'b0; cpu_uds = 1'b0; cpu_lds = 1'b0;
            for (w = 0; w < 600 && !done; w = w + 1) begin
                @(posedge clk_sys); #1;
                if (dtack_eth === 1'b0) begin value = cpu_data_out; done = 1'b1; end
            end
            @(negedge clk_sys);
            cpu_rd = 1'b0; cpu_as = 1'b1; cpu_uds = 1'b1; cpu_lds = 1'b1; sel_ethernet = 1'b0;
            if (!done) begin $display("FAIL: data-port read timed out"); errors = errors + 1; end
            @(negedge clk_sys);
        end
    endtask

    localparam [14:0] R_CR    = 15'h0600;
    localparam [14:0] R_BNRY  = 15'h0606;
    localparam [14:0] R_RSAR0 = 15'h0610;
    localparam [14:0] R_RSAR1 = 15'h0612;
    localparam [14:0] R_RBCR0 = 15'h0614;
    localparam [14:0] R_RBCR1 = 15'h0616;
    localparam [14:0] R_RCR   = 15'h0618;
    localparam [14:0] R_DCR   = 15'h061C;
    localparam [14:0] R_ISR   = 15'h060E;
    localparam [14:0] R_IMR   = 15'h061E;
    localparam [14:0] R_PSTART= 15'h0602;
    localparam [14:0] R_PSTOP = 15'h0604;

    localparam integer FRAME_LEN = 342;            // 2 ring pages (346 incl header)
    localparam [7:0]   EXP_NEXT  = 8'h49;           // 0x47 + 2 pages
    reg [7:0] frame [0:FRAME_LEN-1];
    integer k, mism;
    reg [7:0] curr_v, st_v, next_v, lenlo_v, lenhi_v;
    reg [15:0] got, expw, hdr0, hdr1;

    initial begin
        // position-dependent content so truncation/swap/misplacement is visible
        frame[0]=8'hFF; frame[1]=8'hFF; frame[2]=8'hFF; frame[3]=8'hFF; frame[4]=8'hFF; frame[5]=8'hFF;
        frame[6]=8'h52; frame[7]=8'h54; frame[8]=8'h05; frame[9]=8'h04; frame[10]=8'hFA; frame[11]=8'h25;
        frame[12]=8'h08; frame[13]=8'h00;
        for (k = 14; k < FRAME_LEN; k = k + 1) frame[k] = (k * 8'h07 + 8'h11) & 8'hFF;

        reset_sys = 1; reset_avl = 1;
        repeat (8) @(posedge clk_sys); @(posedge clk_avl);
        reset_sys = 0; reset_avl = 0;

        ddr_write_u16(OFF_SIG,         16'hBABE);
        ddr_write_u16(OFF_SIG + 16'd2, 16'hCAFE);
        ddr_write_u16(OFF_HB,          16'h0001);
        repeat (300) @(posedge clk_sys);

        reg_write(R_PSTART, 8'h46);
        reg_write(R_PSTOP,  8'h80);
        reg_write(R_BNRY,   8'h46);
        reg_write(R_DCR,    8'h01);          // word mode, x86 (16-bit port)
        reg_write(R_RCR,    8'h0C);
        reg_write(R_CR,     8'h62);          // page 1
        reg_write(R_ISR,    8'h47);          // CURR = 0x47
        reg_write(R_CR,     8'h22);          // page 0, STA
        reg_write(R_IMR,    8'h0F);

        // inject one 342-byte frame (daemon order)
        for (k = 0; k < FRAME_LEN; k = k + 1)
            ddr_write_byte(OFF_RX_DATA + k[15:0], frame[k]);
        ddr_write_u16(OFF_RX_LEN,  FRAME_LEN[15:0]);
        ddr_write_u16(OFF_RX_TAIL, 16'h0001);
        ddr_write_u16(OFF_FLAGS,   FLAG_RX_AVAIL);

        begin : wait_prx
            integer g;
            for (g = 0; g < 60000; g = g + 1) begin
                @(posedge clk_sys);
                if ((dut.isr_register & 8'h01) != 8'h00) disable wait_prx;
            end
        end
        if ((dut.isr_register & 8'h01) == 8'h00) begin
            $display("FAIL: ISR.PRX never set (bg_state=%0d curr=0x%02x)", dut.bg_state, dut.curr_register);
            errors = errors + 1;
        end

        // CURR must have advanced by two pages
        reg_write(R_CR, 8'h62);
        reg_read(R_ISR, curr_v);
        reg_write(R_CR, 8'h22);
        $display("INFO: CURR(page1)=0x%02x (expect 0x%02x)", curr_v, EXP_NEXT);
        if (curr_v !== EXP_NEXT) begin
            $display("FAIL: CURR=0x%02x, expected 0x%02x for a 2-page frame", curr_v, EXP_NEXT);
            errors = errors + 1;
        end

        // header via 16-bit port at 0x4700
        reg_write(R_RSAR0, 8'h00);
        reg_write(R_RSAR1, 8'h47);
        reg_write(R_RBCR0, 8'h04);
        reg_write(R_RBCR1, 8'h00);
        reg_write(R_CR,    8'h0A);
        dport_read_word(hdr0);   // {high=next_page, low=status}
        dport_read_word(hdr1);   // {high=len_hi, low=len_lo}
        st_v = hdr0[7:0]; next_v = hdr0[15:8];
        lenlo_v = hdr1[7:0]; lenhi_v = hdr1[15:8];
        $display("INFO: RX header status=0x%02x next=0x%02x len=0x%02x%02x",
                 st_v, next_v, lenhi_v, lenlo_v);
        if (next_v !== EXP_NEXT) begin
            $display("FAIL: header next_page=0x%02x, expected 0x%02x", next_v, EXP_NEXT);
            errors = errors + 1;
        end
        if ({lenhi_v, lenlo_v} !== (FRAME_LEN[15:0] + 16'h0004)) begin
            $display("FAIL: header length=0x%04x, expected 0x%04x",
                     {lenhi_v, lenlo_v}, FRAME_LEN[15:0] + 16'h0004);
            errors = errors + 1;
        end

        // payload via 16-bit port from 0x4704 -- the whole 342 bytes
        reg_write(R_RSAR0, 8'h04);
        reg_write(R_RSAR1, 8'h47);
        reg_write(R_RBCR0, FRAME_LEN[7:0]);      // 0x56
        reg_write(R_RBCR1, FRAME_LEN[15:8]);     // 0x01  <-- 342 needs both bytes
        reg_write(R_CR,    8'h0A);
        mism = 0;
        for (k = 0; k < FRAME_LEN; k = k + 2) begin
            dport_read_word(got);
            expw = {frame[k+1], frame[k]};        // x86: low byte first
            if (got !== expw) begin
                if (mism < 12)
                    $display("FAIL: payload word %0d (byte %0d) = 0x%04x, expected 0x%04x",
                             k/2, k, got, expw);
                mism = mism + 1;
                errors = errors + 1;
            end
        end
        if (mism == 0) $display("INFO: all %0d payload bytes read back correctly", FRAME_LEN);
        else $display("DIAG: %0d/%0d payload words mismatched", mism, FRAME_LEN/2);

        if (errors == 0) $display("PASS: tb_ne2000_rx_multipage");
        else             $display("FAIL: tb_ne2000_rx_multipage (%0d error(s))", errors);
        $finish;
    end

    initial begin
        #12000000;
        $display("FAIL: global timeout"); $finish;
    end

endmodule
