// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/eth_station_mac_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ===========================================================================
// eth_station_mac_tb.v
//
// Verifies the NE2000 station MAC is consistent on BOTH sides of the mailbox:
//   (1) the value the Amiga driver reads from the station PROM via remote DMA
//       (x-surf-100.device reads 16 bytes from PROM addr 0 and takes the MAC
//        from the EVEN offsets 0,2,4,6,8,10), and
//   (2) the value the HPS daemon reads from ETH_CTRL_MAC (0x104C), which the
//       FPGA mirrors there via the shm-sync slots and which the daemon uses for
//       unicast RX filtering (minimig_eth.cpp read_shared_mac / receive_packet).
//
// If these disagree the daemon filters received unicast for the wrong address
// and ping replies are dropped, so both must equal the same MAC.
// ===========================================================================

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns/1ps

module eth_station_mac_tb;

    localparam [15:0] OFF_CTRL_MAC = 16'h104C;

    // Expected default station MAC (DEFAULT_MAC0..5 in ethernet.v), pre-byteswapped
    // pairwise now that the is_dport32 data-port swap is removed.
    localparam [7:0] MAC0 = 8'h52, MAC1 = 8'h54, MAC2 = 8'h05,
                     MAC3 = 8'h04, MAC4 = 8'h03, MAC5 = 8'h02;

    reg clk_sys = 0, clk_avl = 0;
    always #17 clk_sys = ~clk_sys;
    always #21 clk_avl = ~clk_avl;
    reg reset_sys = 1, reset_avl = 1;

    reg  [15:1] cpu_addr     = 0;
    reg  [15:0] cpu_data_in  = 0;
    wire [15:0] cpu_data_out;
    reg         cpu_rd = 0, cpu_hwr = 0, cpu_lwr = 0;
    reg         cpu_as = 1, cpu_uds = 1, cpu_lds = 1;
    reg         sel_ethernet_shm = 0, sel_ethernet = 0;

    wire        eth_dma_ready;  wire [15:0] eth_dma_rdata;
    wire [63:0] eth_dma_rdata64;
    wire        eth_dma_wide;
    wire [63:0] eth_dma_wdata64;
    wire        eth_dma_req, eth_dma_write;
    wire [15:1] eth_dma_addr;   wire [15:0] eth_dma_wdata;
    wire        eth_dma_uds, eth_dma_lds, eth_irq, dtack_eth;

    wire [28:0] avl_address;  wire [7:0] avl_burstcount, avl_byteenable;
    wire [63:0] avl_writedata; wire avl_read, avl_write, avl_waitrequest;
    wire [63:0] avl_readdata;  wire avl_readdatavalid;

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
        .avl_readdatavalid(avl_readdatavalid), .dbg()
    );

    // behavioral 64-bit f2sdram slave
    localparam ACCEPT_DELAY = 2, READ_LAT = 3;
    reg [63:0] mem [0:16383];
    localparam SS_IDLE = 2'd0, SS_LAT = 2'd1, SS_EMIT = 2'd2;
    reg [1:0] ss_state = SS_IDLE; reg [3:0] acc_cnt=0, lat_cnt=0;
    reg [8:0] beats=0; reg [13:0] r_index=0; reg is_busy=0;
    wire cmd_present = avl_read | avl_write;
    assign avl_waitrequest = is_busy ? 1'b1 : (cmd_present ? (acc_cnt < ACCEPT_DELAY) : 1'b0);
    wire cmd_accept = cmd_present & ~avl_waitrequest;
    reg rdv=0; reg [63:0] rdo=0;
    assign avl_readdatavalid = rdv; assign avl_readdata = rdo;
    integer i;
    initial for (i=0;i<16384;i=i+1) mem[i]=64'd0;
    always @(posedge clk_avl) begin
        if (reset_avl) begin ss_state<=SS_IDLE; acc_cnt<=0; lat_cnt<=0; beats<=0; is_busy<=0; rdv<=0; rdo<=0; end
        else begin
            rdv <= 0;
            if (cmd_present && avl_waitrequest && !is_busy) acc_cnt <= acc_cnt + 1'b1;
            else if (!cmd_present) acc_cnt <= 0;
            if (cmd_accept) begin
                acc_cnt <= 0;
                if (avl_write) begin
                    if (avl_byteenable[0]) mem[avl_address[13:0]][ 7: 0]<=avl_writedata[ 7: 0];
                    if (avl_byteenable[1]) mem[avl_address[13:0]][15: 8]<=avl_writedata[15: 8];
                    if (avl_byteenable[2]) mem[avl_address[13:0]][23:16]<=avl_writedata[23:16];
                    if (avl_byteenable[3]) mem[avl_address[13:0]][31:24]<=avl_writedata[31:24];
                    if (avl_byteenable[4]) mem[avl_address[13:0]][39:32]<=avl_writedata[39:32];
                    if (avl_byteenable[5]) mem[avl_address[13:0]][47:40]<=avl_writedata[47:40];
                    if (avl_byteenable[6]) mem[avl_address[13:0]][55:48]<=avl_writedata[55:48];
                    if (avl_byteenable[7]) mem[avl_address[13:0]][63:56]<=avl_writedata[63:56];
                end else begin
                    r_index<=avl_address[13:0]; beats<={1'b0,avl_burstcount};
                    lat_cnt<=READ_LAT; is_busy<=1'b1; ss_state<=SS_LAT;
                end
            end
            case (ss_state)
                SS_LAT:  if (lat_cnt==0) ss_state<=SS_EMIT; else lat_cnt<=lat_cnt-1'b1;
                SS_EMIT: begin rdv<=1'b1; rdo<=mem[r_index]; r_index<=r_index+1'b1; beats<=beats-1'b1;
                         if (beats==1) begin is_busy<=1'b0; ss_state<=SS_IDLE; end end
                default: ;
            endcase
        end
    end

    // daemon-style little-endian byte read of the shared window
    function [7:0] ddr_read_byte;
        input [15:0] byte_off;
        reg [13:0] widx; integer bsh;
        begin widx = byte_off>>3; bsh=(byte_off&7)*8; ddr_read_byte = mem[widx][bsh +: 8]; end
    endfunction

    task automatic write_high_reg;
        input [14:0] word_offset; input [7:0] value;
        begin
            @(negedge clk_sys);
            cpu_addr=word_offset; cpu_data_in={value,8'h00};
            sel_ethernet=1'b1; cpu_hwr=1'b1; cpu_lwr=1'b0; cpu_as=1'b0; cpu_uds=1'b0; cpu_lds=1'b1;
            @(posedge clk_sys); @(negedge clk_sys);
            cpu_hwr=1'b0; cpu_as=1'b1; cpu_uds=1'b1; cpu_lds=1'b1; sel_ethernet=1'b0; cpu_data_in=16'h0000;
        end
    endtask

    task automatic data_port_read_word;
        output [15:0] value; integer w; reg done;
        begin
            done=1'b0; value=16'hXXXX;
            @(negedge clk_sys);
            // Read via the X-Surf-100 32-bit DMA READ port at board 0x8880
            // (cpu_addr 0x4440) -- the path the driver actually uses in CardType=2
            // mode (lbC0002D4). sel_ethernet_shm stays 0 (cpu_wrapper carves this
            // offset out of the shm window) so it routes to is_data_port_access.
            cpu_addr=15'h4440; sel_ethernet=1'b1; cpu_rd=1'b1; cpu_as=1'b0; cpu_uds=1'b0; cpu_lds=1'b0;
            for (w=0; w<600 && !done; w=w+1) begin @(posedge clk_sys); #1; if (dtack_eth===1'b0) begin value=cpu_data_out; done=1'b1; end end
            @(negedge clk_sys);
            cpu_rd=1'b0; cpu_as=1'b1; cpu_uds=1'b1; cpu_lds=1'b1; sel_ethernet=1'b0;
            if (!done) begin $display("FAIL: data-port read timed out"); errors=errors+1; end
            @(negedge clk_sys);
        end
    endtask

    reg [7:0] prom_mac [0:5];
    reg [7:0] ddr_mac  [0:5];
    reg [7:0] exp_mac  [0:5];
    reg [15:0] w;
    integer k;

    initial begin
        exp_mac[0]=MAC0; exp_mac[1]=MAC1; exp_mac[2]=MAC2;
        exp_mac[3]=MAC3; exp_mac[4]=MAC4; exp_mac[5]=MAC5;

        reset_sys=1; reset_avl=1;
        repeat (8) @(posedge clk_sys); @(posedge clk_avl);
        reset_sys=0; reset_avl=0;

        // let the post-reset shm-sync mirror all slots (incl. MAC slots 32-34)
        repeat (12000) @(posedge clk_sys);

        // ---- (1) Amiga reads the station PROM via remote DMA (addr 0, 16 bytes)
        write_high_reg(15'h061c, 8'h03);   // DCR word mode
        write_high_reg(15'h0610, 8'h00);   // RSAR0 = 0
        write_high_reg(15'h0612, 8'h00);   // RSAR1 = 0  -> PROM addr 0
        write_high_reg(15'h0614, 8'h10);   // RBCR0 = 16
        write_high_reg(15'h0616, 8'h00);   // RBCR1 = 0
        write_high_reg(15'h0600, 8'h0A);   // CR = remote read | STA
        // 16 bytes = 8 words; driver takes MAC from even byte offsets 0,2,4,6,8,10
        // => MAC byte n is the LOW (even-offset) byte of word n for n in 0..5.
        for (k = 0; k < 8; k = k + 1) begin
            data_port_read_word(w);
            if (k < 6) prom_mac[k] = w[15:8];   // Amiga big-endian: even byte = high byte of the word
        end

        // ---- (2) daemon view: read the mirrored MAC from ETH_CTRL_MAC (LE bytes)
        for (k = 0; k < 6; k = k + 1)
            ddr_mac[k] = ddr_read_byte(OFF_CTRL_MAC + k[15:0]);

        // ---- checks ----
        for (k = 0; k < 6; k = k + 1) begin
            if (prom_mac[k] !== exp_mac[k]) begin
                $display("FAIL: PROM MAC byte %0d = 0x%02x, expected 0x%02x", k, prom_mac[k], exp_mac[k]);
                errors = errors + 1;
            end
        end
        for (k = 0; k < 6; k = k + 1) begin
            if (ddr_mac[k] !== exp_mac[k]) begin
                $display("FAIL: ETH_CTRL_MAC (daemon view) byte %0d = 0x%02x, expected 0x%02x", k, ddr_mac[k], exp_mac[k]);
                errors = errors + 1;
            end
        end

        $display("PROM  MAC (Amiga): %02x:%02x:%02x:%02x:%02x:%02x",
                 prom_mac[0],prom_mac[1],prom_mac[2],prom_mac[3],prom_mac[4],prom_mac[5]);
        $display("CTRL  MAC (daemon): %02x:%02x:%02x:%02x:%02x:%02x",
                 ddr_mac[0],ddr_mac[1],ddr_mac[2],ddr_mac[3],ddr_mac[4],ddr_mac[5]);

        if (errors == 0)
            $display("PASS: eth_station_mac_tb completed (Amiga PROM and daemon ETH_CTRL_MAC agree on the station MAC)");
        else
            $display("eth_station_mac_tb FAILED with %0d error(s)", errors);
        $finish;
    end

    initial begin #6000000; $display("FAIL: global timeout"); $finish; end

endmodule
