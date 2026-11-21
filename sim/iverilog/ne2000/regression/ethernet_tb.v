// Converted from the Minimig bench suite for the ao486 NE2000 port.
// Source: third_party/minimig_eth/sim/ethernet_tb.v
//   (apolkosnik/Minimig-AGA_MiSTer @ Ethernet_shmem2 9598b936, GPL --
//    see third_party/minimig_eth/doc/PROVENANCE.md)
// Change: the DUT is ne2000_core driven through its generic host port; the
// bench's own signal names, stimuli and assertions are unchanged.

// ao486 note: DCR.BOS is set here (0x02) where the Minimig original left it
// clear.  ne2000_core now uses standard DP8390 BOS polarity (BOS_INVERT=1),
// so this keeps the PHYSICAL byte order under test identical -- the data
// expectations below are unchanged from the original bench.

`timescale 1ns / 1ps

module ethernet_tb;

reg clk;
reg reset;

reg [15:1] cpu_addr;
reg [15:0] cpu_data_in;
wire [15:0] cpu_data_out;
reg cpu_rd;
reg cpu_hwr;
reg cpu_lwr;
reg cpu_as;
reg cpu_uds;
reg cpu_lds;

reg sel_ethernet_shm;
reg sel_ethernet;
reg [7:0] ethernet_base;
reg        eth_dma_ready;
reg [15:0] eth_dma_rdata;
reg [63:0] eth_dma_rdata64 = 64'h0;

wire eth_irq;
wire dtack_eth;
wire        eth_dma_req;
wire        eth_dma_write;
wire [15:1] eth_dma_addr;
wire [15:0] eth_dma_wdata;
wire        eth_dma_wide;
wire [63:0] eth_dma_wdata64;
wire        eth_dma_uds;
wire        eth_dma_lds;
integer     timeout_cycles;

ne2000_core dut (
    .clk(clk),
    .reset(reset),
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
    .eth_dma_req(eth_dma_req),
    .eth_dma_write(eth_dma_write),
    .eth_dma_addr(eth_dma_addr),
    .eth_dma_wdata(eth_dma_wdata),
    .eth_dma_wide(eth_dma_wide),
    .eth_dma_wdata64(eth_dma_wdata64),
    .eth_dma_uds(eth_dma_uds),
    .eth_dma_lds(eth_dma_lds),
    .irq(eth_irq),
    .host_ack_n(dtack_eth)
);

always #5 clk = ~clk;

task automatic write_high_reg;
    input [14:0] word_offset;
    input [7:0] value;
    begin
        @(negedge clk);
        cpu_addr = word_offset;
        cpu_data_in = {value, 8'h00};
        sel_ethernet = 1'b1;
        cpu_hwr = 1'b1;
        cpu_lwr = 1'b0;
        cpu_as = 1'b0;
        cpu_uds = 1'b0;
        cpu_lds = 1'b1;
        @(posedge clk);
        @(negedge clk);
        cpu_hwr = 1'b0;
        cpu_lwr = 1'b0;
        cpu_as = 1'b1;
        cpu_uds = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
        cpu_data_in = 16'h0000;
    end
endtask

task automatic write_low_reg;
    input [14:0] word_offset;
    input [7:0] value;
    begin
        @(negedge clk);
        cpu_addr = word_offset;
        cpu_data_in = {8'h00, value};
        sel_ethernet = 1'b1;
        cpu_hwr = 1'b0;
        cpu_lwr = 1'b1;
        cpu_as = 1'b0;
        cpu_uds = 1'b1;
        cpu_lds = 1'b0;
        @(posedge clk);
        @(negedge clk);
        cpu_hwr = 1'b0;
        cpu_lwr = 1'b0;
        cpu_as = 1'b1;
        cpu_uds = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
        cpu_data_in = 16'h0000;
    end
endtask

task automatic complete_dma;
    input [15:0] read_data;
    begin
        @(negedge clk);
        eth_dma_rdata = read_data;
        eth_dma_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        eth_dma_ready = 1'b0;
        eth_dma_rdata = 16'h0000;
    end
endtask

task automatic expect_dma_request;
    input        expected_write;
    input [14:0] expected_addr;
    input [15:0] expected_wdata;
    input        check_wdata;
    input [255:0] label;
    integer timeout;
    begin
        timeout = 0;
        while (!eth_dma_req && (timeout < 256)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!eth_dma_req) begin
            $display("FAIL: %0s timed out waiting for DMA request", label);
            $fatal(1);
        end
        #1;
        if (eth_dma_write !== expected_write) begin
            $display("FAIL: %0s expected write=%0d got %0d", label, expected_write, eth_dma_write);
            $fatal(1);
        end
        if (eth_dma_addr !== expected_addr) begin
            $display("FAIL: %0s expected addr=0x%04x got 0x%04x", label, expected_addr, eth_dma_addr);
            $fatal(1);
        end
        if (check_wdata && (eth_dma_wdata !== expected_wdata)) begin
            $display("FAIL: %0s expected wdata=0x%04x got 0x%04x", label, expected_wdata, eth_dma_wdata);
            $fatal(1);
        end
    end
endtask

task automatic expect_dma_request_filtered;
    input        expected_write;
    input [14:0] expected_addr;
    input [15:0] expected_wdata;
    input        check_wdata;
    input [255:0] label;
    integer timeout;
    reg matched;
    begin
        timeout = 0;
        matched = 1'b0;
        while (!matched && (timeout < 512)) begin
            while (!eth_dma_req && (timeout < 512)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!eth_dma_req) begin
                $display("FAIL: %0s timed out waiting for DMA request", label);
                $fatal(1);
            end
            #1;
            if ((eth_dma_write === expected_write) &&
                (eth_dma_addr === expected_addr) &&
                (!check_wdata || (eth_dma_wdata === expected_wdata))) begin
                matched = 1'b1;
            end else begin
                complete_dma(16'h0000);
            end
        end
        if (!matched) begin
            $display("FAIL: %0s did not observe expected DMA request", label);
            $fatal(1);
        end
    end
endtask

task automatic expect_no_dma_request;
    input [255:0] label;
    begin
        #1;
        if (eth_dma_req !== 1'b0) begin
            $display("FAIL: %0s should not issue external DMA", label);
            $fatal(1);
        end
    end
endtask

task automatic quiesce_background;
    begin
        dut.shm_sync_enabled = 1'b0;
        dut.bg_state = 6'd0;
        dut.bg_dma_inflight = 1'b0;
        dut.eth_dma_req = 1'b0;
        dut.hps_poll_counter = 8'hFF;
        dut.data_port_cycle_active = 1'b0;
        dut.data_port_transfer_done = 1'b0;
        dut.data_port_bus_active_prev = 1'b0;
        dut.data_port_wait_counter = 10'd0;
    end
endtask

task automatic expect_packet_ram_word;
    input [15:0] ne_addr;
    input [15:0] expected;
    input [255:0] label;
    reg [15:0] actual;
    reg [12:0] index;
    begin
        index = (ne_addr - 16'h4000) >> 1;
        actual = {dut.packet_ram_inst.mem_u[index],
                  dut.packet_ram_inst.mem_l[index]};
        if (actual !== expected) begin
            $display("FAIL: %0s expected packet RAM[0x%04x]=0x%04x got 0x%04x",
                     label, ne_addr, expected, actual);
            $fatal(1);
        end
    end
endtask

task automatic expect_packet_ram_byte;
    input [15:0] ne_addr;
    input [7:0] expected;
    input [255:0] label;
    reg [7:0] actual;
    reg [12:0] index;
    begin
        index = (ne_addr - 16'h4000) >> 1;
        actual = ne_addr[0] ?
            dut.packet_ram_inst.mem_l[index] :
            dut.packet_ram_inst.mem_u[index];
        if (actual !== expected) begin
            $display("FAIL: %0s expected packet RAM[0x%04x]=0x%02x got 0x%02x",
                     label, ne_addr, expected, actual);
            $fatal(1);
        end
    end
endtask

task automatic poke_packet_ram_word;
    input [15:0] ne_addr;
    input [15:0] value;
    reg [12:0] index;
    begin
        index = (ne_addr - 16'h4000) >> 1;
        dut.packet_ram_inst.mem_u[index] = value[15:8];
        dut.packet_ram_inst.mem_l[index] = value[7:0];
    end
endtask

task automatic read_reg_expect;
    input [14:0] word_offset;
    input [15:0] expected;
    input [255:0] label;
    begin
        @(negedge clk);
        cpu_addr = word_offset;
        sel_ethernet = 1'b1;
        cpu_rd = 1'b1;
        cpu_as = 1'b0;
        cpu_uds = 1'b0;
        cpu_lds = 1'b0;
        @(posedge clk);
        #1;
        if (cpu_data_out !== expected) begin
            $display("FAIL: %0s expected 0x%04x got 0x%04x", label, expected, cpu_data_out);
            $fatal(1);
        end
        @(negedge clk);
        cpu_rd = 1'b0;
        cpu_as = 1'b1;
        cpu_uds = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
    end
endtask

task automatic read_reg_expect_low;
    input [14:0] word_offset;
    input [15:0] expected;
    input [255:0] label;
    begin
        @(negedge clk);
        cpu_addr = word_offset;
        sel_ethernet = 1'b1;
        cpu_rd = 1'b1;
        cpu_as = 1'b0;
        cpu_uds = 1'b1;
        cpu_lds = 1'b0;
        @(posedge clk);
        #1;
        if (cpu_data_out !== expected) begin
            $display("FAIL: %0s expected 0x%04x got 0x%04x", label, expected, cpu_data_out);
            $fatal(1);
        end
        @(negedge clk);
        cpu_rd = 1'b0;
        cpu_as = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
end
endtask

task automatic read_dummy_aperture_expect;
    input [14:0] word_offset;
    input        shm_marker;
    input [255:0] label;
    begin
        @(negedge clk);
        cpu_addr = word_offset;
        sel_ethernet_shm = shm_marker;
        sel_ethernet = 1'b1;
        cpu_rd = 1'b1;
        cpu_as = 1'b0;
        cpu_uds = 1'b0;
        cpu_lds = 1'b0;
        @(posedge clk);
        #1;
        if (dtack_eth !== 1'b0) begin
            $display("FAIL: %0s expected immediate dummy DTACK", label);
            $fatal(1);
        end
        if (cpu_data_out !== 16'hFFFF) begin
            $display("FAIL: %0s expected dummy 0xFFFF got 0x%04x", label, cpu_data_out);
            $fatal(1);
        end
        @(negedge clk);
        cpu_rd = 1'b0;
        cpu_as = 1'b1;
        cpu_uds = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
        sel_ethernet_shm = 1'b0;
    end
endtask

task automatic read_aperture_expect;
    input [14:0] word_offset;
    input [15:0] expected;
    input [255:0] label;
    begin
        @(negedge clk);
        cpu_addr = word_offset;
        sel_ethernet = 1'b1;
        sel_ethernet_shm = 1'b0;
        cpu_rd = 1'b1;
        cpu_as = 1'b0;
        cpu_uds = 1'b0;
        cpu_lds = 1'b0;
        @(posedge clk);
        #1;
        if (cpu_data_out !== expected) begin
            $display("FAIL: %0s expected 0x%04x got 0x%04x", label, expected, cpu_data_out);
            $fatal(1);
        end
        @(negedge clk);
        cpu_rd = 1'b0;
        cpu_as = 1'b1;
        cpu_uds = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
    end
endtask

task automatic read_data_port_expect;
    input [14:0] word_offset;
    input [15:0] expected;
    input [255:0] label;
    integer wait_cycles;
    reg matched;
    begin
        matched = 1'b0;
        @(negedge clk);
        cpu_addr = word_offset;
        sel_ethernet = 1'b1;
        cpu_rd = 1'b1;
        cpu_as = 1'b0;
        cpu_uds = 1'b0;
        cpu_lds = 1'b0;
        for (wait_cycles = 0; wait_cycles < 6; wait_cycles = wait_cycles + 1) begin
            @(posedge clk);
            #1;
            if (dut.host_ack_n === 1'b0) begin
                if (cpu_data_out !== expected) begin
                    $display("FAIL: %0s expected 0x%04x got 0x%04x", label, expected, cpu_data_out);
                    $fatal(1);
                end
                matched = 1'b1;
                wait_cycles = 6;
            end
        end
        if (!matched) begin
            $display("FAIL: %0s timed out waiting for data-port DTACK", label);
            $fatal(1);
        end
        @(negedge clk);
        cpu_rd = 1'b0;
        cpu_as = 1'b1;
        cpu_uds = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
end
endtask

task automatic read_data_port_timeout_expect;
    input [14:0] word_offset;
    input [15:0] expected;
    input [255:0] label;
    integer wait_cycles;
    reg matched;
    begin
        matched = 1'b0;
        @(negedge clk);
        cpu_addr = word_offset;
        sel_ethernet = 1'b1;
        cpu_rd = 1'b1;
        cpu_as = 1'b0;
        cpu_uds = 1'b0;
        cpu_lds = 1'b0;
        for (wait_cycles = 0; wait_cycles < 560; wait_cycles = wait_cycles + 1) begin
            @(posedge clk);
            #1;
            if (dut.host_ack_n === 1'b0) begin
                if (cpu_data_out !== expected) begin
                    $display("FAIL: %0s expected timeout value 0x%04x got 0x%04x",
                             label, expected, cpu_data_out);
                    $fatal(1);
                end
                matched = 1'b1;
                wait_cycles = 560;
            end
        end
        if (!matched) begin
            $display("FAIL: %0s timed out waiting for watchdog DTACK", label);
            $fatal(1);
        end
        @(negedge clk);
        cpu_rd = 1'b0;
        cpu_as = 1'b1;
        cpu_uds = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    cpu_addr = 15'h0;
    cpu_data_in = 16'h0000;
    cpu_rd = 1'b0;
    cpu_hwr = 1'b0;
    cpu_lwr = 1'b0;
    cpu_as = 1'b1;
    cpu_uds = 1'b1;
    cpu_lds = 1'b1;
    sel_ethernet_shm = 1'b0;
    sel_ethernet = 1'b0;
    eth_dma_ready = 1'b0;
    eth_dma_rdata = 16'h0000;

    repeat (2) @(posedge clk);
    reset = 1'b0;
    repeat (2) @(posedge clk);

    read_dummy_aperture_expect(15'h0000, 1'b0, "unused card aperture read terminates");
    read_dummy_aperture_expect(15'h0800, 1'b1, "mailbox aperture read terminates");
    read_reg_expect(15'h0600, 16'h2121, "reset CR");
    read_reg_expect(15'h0602, 16'h0000, "page0 CLDA0 reset");
    read_reg_expect(15'h0604, 16'h0000, "page0 CLDA1 reset");
    read_reg_expect(15'h060a, 16'h0000, "page0 NCR reset");
    read_reg_expect(15'h060c, 16'h0000, "page0 FIFO reset");
    read_reg_expect(15'h061a, 16'h0000, "page0 CNTR0 reset");
    read_reg_expect(15'h061c, 16'h0000, "page0 CNTR1 reset");
    read_reg_expect(15'h061e, 16'h0000, "page0 CNTR2 reset");
    read_reg_expect_low(15'h0614, 16'h0050, "ID0 is visible on lower byte lane");
    read_reg_expect_low(15'h0616, 16'h0070, "ID1 is visible on lower byte lane");
    if (dut.pstart_register !== 8'h46 || dut.pstop_register !== 8'h80 ||
        dut.tpsr_register !== 8'h40 || dut.bnry_register !== 8'h46 ||
        dut.curr_register !== 8'h47) begin
        $display("FAIL: reset ring layout expected TX=0x40 RX=0x46-0x80 BNRY=0x46 CURR=0x47, got TPSR=0x%02x PSTART=0x%02x PSTOP=0x%02x BNRY=0x%02x CURR=0x%02x",
                 dut.tpsr_register, dut.pstart_register, dut.pstop_register, dut.bnry_register, dut.curr_register);
        $fatal(1);
    end

    if (dut.shm_sync_enabled !== 1'b1) begin
        $display("FAIL: reset should request initial shared-memory mirror sync");
        $fatal(1);
    end
    expect_dma_request_filtered(1'b0, 15'h0844, 16'h0000, 1'b0,
                                "reset HPS heartbeat poll reads heartbeat low");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b0, 15'h0845, 16'h0000, 1'b0,
                                "reset HPS heartbeat poll reads heartbeat high");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b0, 15'h0846, 16'h0000, 1'b0,
                                "reset HPS heartbeat poll reads signature low");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b0, 15'h0847, 16'h0000, 1'b0,
                                "reset HPS heartbeat poll reads signature high");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b1, 15'h0829, 16'h0001, 1'b1,
                                "reset HPS status poll publishes sampled bit");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b1, 15'h0802, 16'h0021, 1'b1,
                                "reset mirror publishes CR");
    complete_dma(16'h0000);
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    dut.hps_poll_counter = 8'hFF;
    dut.data_port_cycle_active = 1'b0;
    dut.data_port_transfer_done = 1'b0;
    dut.data_port_bus_active_prev = 1'b0;
    dut.data_port_wait_counter = 10'd0;

    // Regression (2026-06-14): a CPU data-port read must NOT be blocked merely
    // because the background mailbox DMA is in flight. The bg HPS-poll/mailbox
    // traffic uses eth_dma (DDR) and never touches the packet RAM, so with
    // eth_dma_req high but bg not in a packet-RAM state the data-port read must
    // still launch and complete. Gating it on eth_dma_req stalled the CPU and
    // broke xsurftest's 16-bit memory test. remote_dma_addr is 0 here, so this
    // reads station PROM word 0 (0x5252); it must return that, not the watchdog
    // value, and must not trip the timeout.
    dut.bg_state = 6'd0;            // not a packet-RAM state -> bg_pmem_active=0
    dut.bg_dma_inflight = 1'b1;     // a background mailbox transfer is in flight
    dut.eth_dma_req = 1'b1;
    dut.eth_dma_write = 1'b0;
    dut.eth_dma_wait_counter = 10'd0;
    read_data_port_expect(15'h0620, 16'h5252,
                          "data-port read completes while background mailbox DMA is in flight");
    if (dut.debug_dma_timeout_sticky === 1'b1) begin
        $display("FAIL: data-port read tripped the watchdog while only the mailbox DMA was busy");
        $fatal(1);
    end
    quiesce_background();

    // The watchdog must STILL fire when the data-port genuinely cannot proceed,
    // i.e. when the background FSM is actually holding the shared single-port
    // packet RAM (an RX-write / TX-read state -> bg_pmem_active). Hold bg in a
    // packet-RAM write state so the read cannot launch, and confirm the watchdog
    // completes the cycle with 0xFFFF and sets the sticky bit.
    dut.bg_state = 6'd13;           // BG_WRITE_PAYLOAD_REQ -> bg_pmem_active=1
    dut.bg_dma_inflight = 1'b1;     // freeze the request block so bg stays on the RAM port
    dut.eth_dma_req = 1'b0;
    dut.eth_dma_write = 1'b0;
    dut.eth_dma_wait_counter = 10'd0;
    read_data_port_timeout_expect(15'h0620, 16'hFFFF,
                                  "data-port watchdog still fires while bg holds the packet-RAM port");
    if (dut.debug_dma_timeout_sticky !== 1'b1) begin
        $display("FAIL: data-port watchdog should set debug timeout sticky bit");
        $fatal(1);
    end
    dut.debug_dma_timeout_sticky = 1'b0;
    dut.bg_state = 6'd0;
    quiesce_background();

    write_high_reg(15'h0618, 8'h20);
    if (dut.rx_poll_enabled !== 1'b1) begin
        $display("FAIL: RCR write should arm rx_poll_enabled even while stopped");
        $fatal(1);
    end
    if (dut.shm_sync_enabled !== 1'b1 || dut.bg_sync_slot !== 6'd0) begin
        $display("FAIL: RCR write while stopped should start shared-memory sync");
        $fatal(1);
    end
    dut.rx_poll_enabled = 1'b0;
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;

    write_high_reg(15'h0600, 8'h22);
    write_high_reg(15'h0618, 8'h20);
    if (dut.shm_sync_enabled !== 1'b1 || dut.bg_sync_slot !== 6'd0) begin
        $display("FAIL: RCR write while started should start shared-memory sync");
        $fatal(1);
    end
    if (dut.bg_poll_counter !== 8'h00) begin
        $display("FAIL: RCR write should not perturb bg_poll_counter, got 0x%02x", dut.bg_poll_counter);
        $fatal(1);
    end
    write_high_reg(15'h0600, 8'h21);
    dut.rx_poll_enabled = 1'b0;

    write_high_reg(15'h0600, 8'h02);
    write_high_reg(15'h061c, 8'h03);
    write_high_reg(15'h063e, 8'hA5);
    if (dut.cr_register !== 8'h02) begin
        $display("FAIL: reset port write should not reset CR, got 0x%02x", dut.cr_register);
        $fatal(1);
    end
    if (dut.dcr_register !== 8'h81) begin
        $display("FAIL: reset port write should not reset DCR, got 0x%02x", dut.dcr_register);
        $fatal(1);
    end
    read_reg_expect(15'h063e, 16'hA5A5, "reset port returns latched write value");
    if (dut.cr_register !== 8'h21) begin
        $display("FAIL: reset port should restore CR to 0x21, got 0x%02x", dut.cr_register);
        $fatal(1);
    end
    if (dut.dcr_register !== 8'h80) begin
        $display("FAIL: reset port should clear DCR, got 0x%02x", dut.dcr_register);
        $fatal(1);
    end
    if (dut.isr_register !== 8'h80) begin
        $display("FAIL: reset port should set ISR.RST, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    write_high_reg(15'h060e, 8'h80);
    if (dut.isr_register !== 8'h00) begin
        $display("FAIL: ISR clear should clear reset status, got 0x%02x", dut.isr_register);
        $fatal(1);
    end

    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    // Case A: CPU remote-DMA abort with NO background transfer in flight
    // (bg_dma_inflight=0). The abort clears the CPU data-port state and, since
    // eth_dma is not owned by the bg, also clears eth_dma_req.
    dut.bg_dma_inflight = 1'b0;
    dut.data_port_write_pending = 1'b1;
    dut.eth_dma_req = 1'b1;
    dut.eth_dma_write = 1'b1;
    dut.eth_dma_uds = 1'b0;
    dut.eth_dma_lds = 1'b0;
    write_high_reg(15'h0600, 8'h22);
    if ((dut.isr_register & 8'h40) == 8'h00) begin
        $display("FAIL: CR abort/complete should set ISR.RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (dut.data_port_write_pending !== 1'b0 || dut.eth_dma_req !== 1'b0) begin
        $display("FAIL: CR abort/complete should clear pending remote DMA state");
        $fatal(1);
    end
    if (dut.local_remote_dma_active !== 1'b0) begin
        $display("FAIL: CR abort/complete should not leave local_remote_dma_active asserted");
        $fatal(1);
    end

    // Case B (regression for the Amiga lockup): a CPU remote-DMA abort must NOT
    // stomp a BACKGROUND mailbox transfer that owns eth_dma. With
    // bg_dma_inflight=1 (and a data-port op also pending, the concurrent case the
    // data-port decouple made normal), the abort clears the CPU data-port state
    // but must LEAVE eth_dma_req asserted so the bg transfer completes instead of
    // wedging at *_WAIT (ISSP showed bg=26 inflight=1 req=0 -> CPU spins on
    // CR/ISR -> lockup).
    dut.bg_dma_inflight = 1'b1;
    dut.eth_dma_req = 1'b1;
    dut.eth_dma_write = 1'b0;
    dut.data_port_read_pending = 1'b1;
    write_high_reg(15'h0600, 8'h22);   // CR remote-DMA abort while bg owns eth_dma
    if (dut.eth_dma_req !== 1'b1) begin
        $display("FAIL: CR abort stomped the background eth_dma transfer (eth_dma_req cleared while bg_dma_inflight)");
        $fatal(1);
    end
    if (dut.data_port_read_pending !== 1'b0) begin
        $display("FAIL: CR abort should still clear the CPU data-port state even when bg owns eth_dma");
        $fatal(1);
    end
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    quiesce_background();
    write_high_reg(15'h060e, 8'h40);
    write_high_reg(15'h0600, 8'h21);

    // Case C (regression for the Amiga lockup, second stomp path): a LOCAL
    // packet-RAM read completion must NOT stomp a background mailbox transfer
    // that owns eth_dma. complete_data_port_transfer used to clear eth_dma_req
    // unconditionally; with the data-port decouple the pmem read completes while
    // bg_dma_inflight=1, so it wedged the bg (ISSP: bg=18 BG_SYNC_WORD_WAIT
    // inflight=1 req=0, hb frozen -> CPU remote DMA blocked -> driver spins on
    // CR(0x0A)/ISR -> lockup). eth_dma_ready held low so the bg FSM cannot
    // advance on its own; only the pmem completion can touch eth_dma_req here.
    eth_dma_ready = 1'b0;
    dut.bg_dma_inflight = 1'b1;        // bg owns eth_dma...
    dut.eth_dma_req = 1'b1;
    dut.eth_dma_write = 1'b0;
    dut.bg_state = 6'd18;              // BG_SYNC_WORD_WAIT -> bg_pmem_active = 0
    dut.remote_dma_addr = 16'h4000;   // pmem region -> remote_dma_pmem_region = 1
    dut.local_pmem_read_wait = 1'b0;  // skip the wait state, fire completion now
    dut.data_port_read_pending = 1'b1;// a local pmem read is outstanding
    @(posedge clk);                   // complete_data_port_transfer(pmem_q) fires
    #1;
    if (dut.eth_dma_req !== 1'b1) begin
        $display("FAIL: local pmem read completion stomped the background eth_dma transfer (eth_dma_req cleared while bg_dma_inflight)");
        $fatal(1);
    end
    if (dut.bg_dma_inflight !== 1'b1) begin
        $display("FAIL: local pmem read completion cleared bg_dma_inflight");
        $fatal(1);
    end
    if (dut.data_port_read_pending !== 1'b0) begin
        $display("FAIL: local pmem read completion should clear data_port_read_pending");
        $fatal(1);
    end
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    quiesce_background();
    write_high_reg(15'h060e, 8'h40);
    write_high_reg(15'h0600, 8'h21);

    // Case D (regression for the Amiga interrupt-storm lockup during online):
    // CR=0x22 (STA + RD2:0=100 abort/complete) is the driver's idle command,
    // written on every interrupt-handler entry and exit. With NO remote DMA in
    // flight it must NOT set ISR.RDC. Unconditionally re-arming RDC on every
    // CR=0x22 kept (ISR & IMR) nonzero so eth_irq/irq_pending stayed high and
    // the IRQ handler re-entered forever (ISSP: CPU spinning CR 0x0C00 / ISR
    // 0x0C1C, no data-port access, bg healthy). On real NE2000 RDC is set when
    // the remote-DMA byte count reaches zero, not by an abort with nothing
    // pending. (Case A above covers the positive case: abort WITH a DMA pending
    // still sets RDC.)
    quiesce_background();
    dut.data_port_read_pending = 1'b0;
    dut.data_port_write_pending = 1'b0;
    dut.remote_byte_count = 16'h0000;
    write_high_reg(15'h060e, 8'hFF);   // clear all ISR bits, including any stray RDC
    if ((dut.isr_register & 8'h40) !== 8'h00) begin
        $display("FAIL: Case D setup - ISR.RDC should be clear, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    write_high_reg(15'h0600, 8'h22);   // CR=0x22 abort/complete with NO DMA pending
    if ((dut.isr_register & 8'h40) !== 8'h00) begin
        $display("FAIL: CR=0x22 abort with no remote DMA pending must NOT set ISR.RDC (interrupt storm), got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    quiesce_background();
    write_high_reg(15'h060e, 8'h40);
    write_high_reg(15'h0600, 8'h21);

    // Match the xsurftest 16-bit RAM probe sequence:
    // write reset port, read reset port, mirror the read value back, then
    // program RCR/DCR/PSTART/PSTOP, arm remote DMA write, stream 16 words
    // through the aliased data port, and poll for ISR.RDC.
    write_high_reg(15'h063e, 8'h00);
    if (dut.cr_register !== 8'h21) begin
        $display("FAIL: xsurftest reset-port write should not reset CR, got 0x%02x", dut.cr_register);
        $fatal(1);
    end
    read_reg_expect(15'h063e, 16'h0000, "xsurftest reset-port read");
    write_high_reg(15'h063e, 8'h00);
    write_high_reg(15'h0600, 8'h21);
    write_high_reg(15'h0618, 8'h20);
    write_high_reg(15'h061c, 8'h4B);
    write_high_reg(15'h0602, 8'h40);
    write_high_reg(15'h0604, 8'h80);
    write_high_reg(15'h0600, 8'h22);
    write_high_reg(15'h060e, 8'h40);
    write_high_reg(15'h0614, 8'h20);
    write_high_reg(15'h0616, 8'h00);
    write_high_reg(15'h0610, 8'h00);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0600, 8'h12);
    // Idle the background mailbox engine so this local data-port write check sees
    // only the data-port path. The CR remote-DMA-abort above no longer stomps an
    // in-flight background eth_dma transfer (that stomp wedged the mailbox on
    // hardware), so the bg must be quiesced here rather than relying on the abort
    // to clear a background eth_dma_req.
    quiesce_background;

    for (timeout_cycles = 0; timeout_cycles < 16; timeout_cycles = timeout_cycles + 1) begin
        @(negedge clk);
        cpu_addr = 15'h0620;
        cpu_data_in = 16'h4100 + timeout_cycles;
        sel_ethernet = 1'b1;
        cpu_hwr = 1'b1;
        cpu_lwr = 1'b1;
        cpu_as = 1'b0;
        cpu_uds = 1'b0;
        cpu_lds = 1'b0;
        @(posedge clk);
        expect_no_dma_request("xsurftest local packet-RAM write");
        @(negedge clk);
        cpu_hwr = 1'b0;
        cpu_lwr = 1'b0;
        cpu_as = 1'b1;
        cpu_uds = 1'b1;
        cpu_lds = 1'b1;
        sel_ethernet = 1'b0;
        cpu_data_in = 16'h0000;
        @(posedge clk);
        expect_packet_ram_word(16'h4000 + {timeout_cycles[14:0], 1'b0},
                               16'h4100 + timeout_cycles[15:0],
                               "xsurftest local packet-RAM word");
    end

    if (dut.remote_dma_addr !== 16'h4020) begin
        $display("FAIL: xsurftest sequence should advance remote_dma_addr to 0x4020, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    if (dut.remote_byte_count !== 16'h0000) begin
        $display("FAIL: xsurftest sequence should drain remote_byte_count to 0, got 0x%04x", dut.remote_byte_count);
        $fatal(1);
    end
    if ((dut.isr_register & 8'h40) == 8'h00) begin
        $display("FAIL: xsurftest sequence should set ISR.RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    write_high_reg(15'h060e, 8'h40);
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;

    // A completed data-port write must hold its completion until the current
    // bus cycle releases, but it must not relaunch the same word while the
    // old write strobe is still asserted.
    write_high_reg(15'h0610, 8'h20);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0614, 8'h04);
    write_high_reg(15'h0616, 8'h00);
    write_high_reg(15'h0600, 8'h12);
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    dut.hps_poll_counter = 8'hFF;
    dut.data_port_cycle_active = 1'b0;
    dut.data_port_transfer_done = 1'b0;
    dut.data_port_bus_active_prev = 1'b0;

    @(negedge clk);
    cpu_addr = 15'h0620;
    cpu_data_in = 16'h1122;
    sel_ethernet = 1'b1;
    cpu_hwr = 1'b1;
    cpu_lwr = 1'b1;
    cpu_as = 1'b0;
    cpu_uds = 1'b0;
    cpu_lds = 1'b0;
    @(posedge clk);
    expect_no_dma_request("first back-to-back local packet-RAM write");

    @(negedge clk);
    cpu_hwr = 1'b0;
    cpu_lwr = 1'b0;
    cpu_as = 1'b1;
    cpu_uds = 1'b1;
    cpu_lds = 1'b1;
    sel_ethernet = 1'b0;
    @(posedge clk);
    @(negedge clk);
    cpu_addr = 15'h0620;
    cpu_data_in = 16'h3344;
    sel_ethernet = 1'b1;
    cpu_hwr = 1'b1;
    cpu_lwr = 1'b1;
    cpu_as = 1'b0;
    cpu_uds = 1'b0;
    cpu_lds = 1'b0;
    @(posedge clk);
    expect_no_dma_request("second back-to-back local packet-RAM write");
    @(negedge clk);
    cpu_hwr = 1'b0;
    cpu_lwr = 1'b0;
    cpu_as = 1'b1;
    cpu_uds = 1'b1;
    cpu_lds = 1'b1;
    sel_ethernet = 1'b0;
    @(posedge clk);
    if (dut.remote_dma_addr !== 16'h4024) begin
        $display("FAIL: consecutive writes should advance remote_dma_addr to 0x4024, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    if (dut.remote_byte_count !== 16'h0000) begin
        $display("FAIL: consecutive writes should drain remote_byte_count to 0, got 0x%04x", dut.remote_byte_count);
        $fatal(1);
    end
    if ((dut.isr_register & 8'h40) == 8'h00) begin
        $display("FAIL: consecutive writes should set ISR.RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    expect_packet_ram_word(16'h4020, 16'h1122, "first consecutive local packet-RAM word");
    expect_packet_ram_word(16'h4022, 16'h3344, "second consecutive local packet-RAM word");
    write_high_reg(15'h060e, 8'h40);

    write_high_reg(15'h0600, 8'h40);
    read_reg_expect(15'h0600, 16'h4040, "CR write preserves stop/start bits");

    write_high_reg(15'h0600, 8'h02);
    read_reg_expect(15'h0600, 16'h0202, "CR returns to page 0");

    write_high_reg(15'h0610, 8'h34);
    write_high_reg(15'h0612, 8'h12);
    if (dut.remote_dma_addr !== 16'h1234) begin
        $display("FAIL: remote_dma_addr expected 0x1234 got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    read_reg_expect(15'h0610, 16'h3434, "CRDA0 reflects RSAR0");
    read_reg_expect(15'h0612, 16'h1212, "CRDA1 reflects RSAR1");

    write_low_reg(15'h0610, 8'h78);
    write_low_reg(15'h0612, 8'h56);
    if (dut.remote_dma_addr !== 16'h5678) begin
        $display("FAIL: lower-byte lane writes should update remote_dma_addr to 0x5678, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    read_reg_expect_low(15'h0610, 16'h0078, "CRDA0 is readable on lower byte lane");
    read_reg_expect_low(15'h0612, 16'h0056, "CRDA1 is readable on lower byte lane");

    write_high_reg(15'h0614, 8'h78);
    write_high_reg(15'h0616, 8'h56);
    if (dut.remote_byte_count !== 16'h5678) begin
        $display("FAIL: remote_byte_count expected 0x5678 got 0x%04x", dut.remote_byte_count);
        $fatal(1);
    end
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    dut.hps_poll_counter = 8'hFF;
    read_reg_expect(15'h0630, 16'h7878, "debug RSAR0 mirrors remote_dma_addr low");
    read_reg_expect(15'h0632, 16'h5656, "debug RSAR1 mirrors remote_dma_addr high");
    read_reg_expect(15'h0634, 16'h7878, "debug RBCR0 mirrors remote_byte_count low");
    read_reg_expect(15'h0636, 16'h5656, "debug RBCR1 mirrors remote_byte_count high");
    read_reg_expect(15'h0638, 16'h0000, "debug status reset state");
    read_reg_expect(15'h063a, 16'h0000, "debug wait counter reset state");
    read_reg_expect(15'h063c, 16'h0000, "debug state reset state");

    write_high_reg(15'h061c, 8'h03);
    if (dut.dcr_word_mode !== 1'b1) begin
        $display("FAIL: dcr_word_mode expected 1 got %0d", dut.dcr_word_mode);
        $fatal(1);
    end

    write_high_reg(15'h0610, 8'h00);
    write_high_reg(15'h0612, 8'h00);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    dut.hps_poll_counter = 8'hFF;
    dut.data_port_cycle_active = 1'b0;
    dut.data_port_transfer_done = 1'b0;
    dut.data_port_bus_active_prev = 1'b0;
    read_data_port_expect(15'h0620, 16'h5252, "station PROM word 0");
    if (dut.data_port_read_pending || dut.data_port_write_pending) begin
        $display("FAIL: station PROM reads should not leave external data-port DMA pending");
        $fatal(1);
    end
    if (dut.remote_dma_addr !== 16'h0002) begin
        $display("FAIL: station PROM read should advance remote_dma_addr to 0x0002, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    if ((dut.isr_register & 8'h40) == 8'h00) begin
        $display("FAIL: station PROM read should set RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    write_high_reg(15'h060e, 8'h40);

    write_high_reg(15'h0610, 8'h00);
    write_high_reg(15'h0612, 8'h00);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    dut.hps_poll_counter = 8'hFF;
    dut.data_port_cycle_active = 1'b0;
    dut.data_port_transfer_done = 1'b0;
    dut.data_port_bus_active_prev = 1'b0;

    @(negedge clk);
    cpu_addr = 15'h0620;
    cpu_data_in = 16'hA55A;
    sel_ethernet = 1'b1;
    cpu_hwr = 1'b1;
    cpu_lwr = 1'b1;
    cpu_as = 1'b0;
    cpu_uds = 1'b0;
    cpu_lds = 1'b0;
    @(posedge clk);
    #1;
    if (dut.data_port_read_pending || dut.data_port_write_pending) begin
        $display("FAIL: station PROM shadow write should not leave external data-port DMA pending");
        $fatal(1);
    end
    @(negedge clk);
    cpu_hwr = 1'b0;
    cpu_lwr = 1'b0;
    cpu_as = 1'b1;
    cpu_uds = 1'b1;
    cpu_lds = 1'b1;
    sel_ethernet = 1'b0;
    @(posedge clk);
    if (dut.remote_dma_addr !== 16'h0002) begin
        $display("FAIL: station PROM shadow write should advance remote_dma_addr to 0x0002, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    if ((dut.isr_register & 8'h40) == 8'h00) begin
        $display("FAIL: station PROM shadow write should set RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    write_high_reg(15'h060e, 8'h40);

    write_high_reg(15'h0610, 8'h00);
    write_high_reg(15'h0612, 8'h00);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    dut.hps_poll_counter = 8'hFF;
    dut.data_port_cycle_active = 1'b0;
    dut.data_port_transfer_done = 1'b0;
    dut.data_port_bus_active_prev = 1'b0;
    read_data_port_expect(15'h0620, 16'hA55A, "station PROM shadow write is readable");
    write_high_reg(15'h060e, 8'h40);

    write_high_reg(15'h0610, 8'h00);
    write_high_reg(15'h0612, 8'h80);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.eth_dma_req = 1'b0;
    dut.hps_poll_counter = 8'hFF;
    dut.data_port_cycle_active = 1'b0;
    dut.data_port_transfer_done = 1'b0;
    dut.data_port_bus_active_prev = 1'b0;
    read_data_port_expect(15'h0620, 16'hFFFF, "packet memory above 16KB window reads as unmapped");
    if (dut.data_port_read_pending || dut.data_port_write_pending) begin
        $display("FAIL: unmapped packet memory reads should not leave external data-port DMA pending");
        $fatal(1);
    end
    if (dut.remote_dma_addr !== 16'h8002) begin
        $display("FAIL: unmapped packet memory read should advance remote_dma_addr to 0x8002, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    if ((dut.isr_register & 8'h40) == 8'h00) begin
        $display("FAIL: unmapped packet memory read should still set RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    write_high_reg(15'h060e, 8'h40);

    write_high_reg(15'h0610, 8'h10);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    quiesce_background();

    @(negedge clk);
    cpu_addr = 15'h0620;
    cpu_data_in = 16'hBEEF;
    sel_ethernet = 1'b1;
    cpu_hwr = 1'b1;
    cpu_lwr = 1'b1;
    cpu_as = 1'b0;
    cpu_uds = 1'b0;
    cpu_lds = 1'b0;
    @(posedge clk);
    #1;
    expect_no_dma_request("data port packet-RAM write");
    @(negedge clk);
    cpu_hwr = 1'b0;
    cpu_lwr = 1'b0;
    cpu_as = 1'b1;
    cpu_uds = 1'b1;
    cpu_lds = 1'b1;
    sel_ethernet = 1'b0;
    @(posedge clk);

    if (dut.remote_dma_addr !== 16'h4012) begin
        $display("FAIL: data port write should advance remote_dma_addr to 0x4012, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    if (dut.remote_byte_count !== 16'h0000) begin
        $display("FAIL: data port write should drain remote_byte_count to 0, got 0x%04x", dut.remote_byte_count);
        $fatal(1);
    end
    if ((dut.isr_register & 8'h40) == 8'h00) begin
        $display("FAIL: data port completion should set RDC in ISR, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    expect_packet_ram_word(16'h4010, 16'hBEEF, "data port packet-RAM word write");

    write_high_reg(15'h0610, 8'h14);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    quiesce_background();

    @(negedge clk);
    cpu_addr = 15'h0621;
    cpu_data_in = 16'hA55A;
    sel_ethernet = 1'b1;
    cpu_hwr = 1'b1;
    cpu_lwr = 1'b1;
    cpu_as = 1'b0;
    cpu_uds = 1'b0;
    cpu_lds = 1'b0;
    @(posedge clk);
    #1;
    expect_no_dma_request("data port alias packet-RAM write");
    @(negedge clk);
    cpu_hwr = 1'b0;
    cpu_lwr = 1'b0;
    cpu_as = 1'b1;
    cpu_uds = 1'b1;
    cpu_lds = 1'b1;
    sel_ethernet = 1'b0;
    @(posedge clk);

    if (dut.remote_dma_addr !== 16'h4016) begin
        $display("FAIL: data port alias write should advance remote_dma_addr to 0x4016, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    expect_packet_ram_word(16'h4014, 16'hA55A, "data port alias packet-RAM word write");

    write_high_reg(15'h061c, 8'h03);
    write_high_reg(15'h0610, 8'h18);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    quiesce_background();

    @(negedge clk);
    cpu_addr = 15'h0620;
    cpu_data_in = 16'hCAFE;
    sel_ethernet = 1'b1;
    cpu_hwr = 1'b1;
    cpu_lwr = 1'b1;
    cpu_as = 1'b0;
    cpu_uds = 1'b0;
    cpu_lds = 1'b0;
    @(posedge clk);
    #1;
    expect_no_dma_request("BOS packet-RAM write");
    @(negedge clk);
    cpu_hwr = 1'b0;
    cpu_lwr = 1'b0;
    cpu_as = 1'b1;
    cpu_uds = 1'b1;
    cpu_lds = 1'b1;
    sel_ethernet = 1'b0;
    @(posedge clk);
    expect_packet_ram_word(16'h4018, 16'hFECA, "BOS packet-RAM word stores swapped bytes");

    write_high_reg(15'h0610, 8'h18);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    quiesce_background();
    read_data_port_expect(15'h0620, 16'hCAFE, "BOS data port read swaps bytes back");
    write_high_reg(15'h060e, 8'h40);
    write_high_reg(15'h061c, 8'h03);

    write_high_reg(15'h0610, 8'h20);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    quiesce_background();
    read_data_port_expect(15'h0620, 16'h1122, "data port read returns local packet-RAM word");

    write_high_reg(15'h060e, 8'h40);
    if (dut.isr_register !== 8'h00) begin
        $display("FAIL: ISR clear should clear RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end

    write_high_reg(15'h0610, 8'h30);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    poke_packet_ram_word(16'h4030, 16'h1234);
    quiesce_background();
    read_data_port_expect(15'h0620, 16'h1234, "local packet-RAM read returns stored word");

    write_high_reg(15'h060e, 8'h40);
    if (dut.isr_register !== 8'h00) begin
        $display("FAIL: ISR clear should clear local read RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end

    write_high_reg(15'h0610, 8'h34);
    write_high_reg(15'h0612, 8'h40);
    write_high_reg(15'h0614, 8'h02);
    write_high_reg(15'h0616, 8'h00);
    write_high_reg(15'h0600, 8'h12);
    quiesce_background();

    @(negedge clk);
    cpu_addr = 15'h0620;
    cpu_data_in = 16'hDEAD;
    sel_ethernet = 1'b1;
    cpu_hwr = 1'b1;
    cpu_lwr = 1'b1;
    cpu_as = 1'b0;
    cpu_uds = 1'b0;
    cpu_lds = 1'b0;
    @(posedge clk);
    #1;
    expect_no_dma_request("local packet-RAM write should not pend on external DMA");
    @(negedge clk);
    cpu_hwr = 1'b0;
    cpu_lwr = 1'b0;
    cpu_as = 1'b1;
    cpu_uds = 1'b1;
    cpu_lds = 1'b1;
    sel_ethernet = 1'b0;
    cpu_data_in = 16'h0000;
    @(posedge clk);
    #1;
    if (dut.remote_dma_addr !== 16'h4036) begin
        $display("FAIL: local write should advance remote_dma_addr to 0x4036, got 0x%04x", dut.remote_dma_addr);
        $fatal(1);
    end
    if (dut.remote_byte_count !== 16'h0000) begin
        $display("FAIL: local write should drain remote_byte_count to 0, got 0x%04x", dut.remote_byte_count);
        $fatal(1);
    end
    if ((dut.isr_register & 8'h40) == 8'h00) begin
        $display("FAIL: local write should complete remote DMA and set RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (dut.data_port_write_pending !== 1'b0) begin
        $display("FAIL: local write should clear the pending write state");
        $fatal(1);
    end
    if (dut.debug_dma_timeout_sticky) begin
        $display("FAIL: local packet-RAM write should not latch the DMA-timeout sticky flag");
        $fatal(1);
    end
    expect_packet_ram_word(16'h4034, 16'hDEAD, "local packet-RAM write updates memory immediately");
    write_high_reg(15'h060e, 8'h40);
    if (dut.isr_register !== 8'h00) begin
        $display("FAIL: ISR clear should clear local write RDC, got 0x%02x", dut.isr_register);
        $fatal(1);
    end

    write_high_reg(15'h0618, 8'h11);
    write_high_reg(15'h061a, 8'h22);
    write_high_reg(15'h061c, 8'h4B);
    write_high_reg(15'h061e, 8'h33);

    write_high_reg(15'h0600, 8'h80);
    read_reg_expect(15'h0602, 16'h4040, "page2 PSTART readback");
    read_reg_expect(15'h0604, 16'h8080, "page2 PSTOP readback");
    read_reg_expect(15'h0618, 16'h1111, "page2 RCR readback");
    read_reg_expect(15'h061a, 16'h2222, "page2 TCR readback");
    read_reg_expect(15'h061c, 16'hCBCB, "page2 DCR readback");
    read_reg_expect(15'h061e, 16'h3333, "page2 IMR readback");

    write_high_reg(15'h0600, 8'hC0);
    read_reg_expect(15'h0602, 16'h0000, "page3 9346CR default");
    read_reg_expect(15'h0606, 16'h0000, "page3 CONFIG0 default");
    read_reg_expect(15'h0608, 16'h8080, "page3 CONFIG1 default");
    read_reg_expect(15'h060a, 16'h4040, "page3 CONFIG2 default");
    read_reg_expect(15'h060c, 16'h4040, "page3 CONFIG3 default");
    read_reg_expect(15'h061c, 16'h5050, "page3 ID0 readback");
    read_reg_expect(15'h061e, 16'h7070, "page3 ID1 readback");

    write_high_reg(15'h0606, 8'hFF);
    write_high_reg(15'h0608, 8'h00);
    write_high_reg(15'h060a, 8'hE0);
    write_high_reg(15'h060c, 8'h06);
    read_reg_expect(15'h0606, 16'h0000, "page3 CONFIG0 ignores writes while 9346CR is locked");
    read_reg_expect(15'h0608, 16'h8080, "page3 CONFIG1 ignores writes while 9346CR is locked");
    read_reg_expect(15'h060a, 16'h4040, "page3 CONFIG2 ignores writes while 9346CR is locked");
    read_reg_expect(15'h060c, 16'h4040, "page3 CONFIG3 ignores writes while 9346CR is locked");

    write_high_reg(15'h0602, 8'hC0);
    read_reg_expect(15'h0602, 16'hC0C0, "page3 9346CR enables config writes");
    write_high_reg(15'h0606, 8'hFF);
    write_high_reg(15'h0608, 8'h00);
    write_high_reg(15'h060a, 8'hE0);
    write_high_reg(15'h060c, 8'h06);
    read_reg_expect(15'h0606, 16'hC0C0, "page3 CONFIG0 only updates writable bits");
    read_reg_expect(15'h0608, 16'h0000, "page3 CONFIG1 updates IRQEN when unlocked");
    read_reg_expect(15'h060a, 16'hE0E0, "page3 CONFIG2 only updates writable bits");
    read_reg_expect(15'h060c, 16'h4646, "page3 CONFIG3 only updates writable bits");

    write_high_reg(15'h0600, 8'h02);
    dut.rx_poll_enabled = 1'b0;
    dut.shm_sync_enabled = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.bg_polling_rx_flags = 1'b0;
    dut.bg_clear_rx_avail = 1'b0;
    dut.eth_dma_req = 1'b0;

    write_high_reg(15'h0600, 8'h40);
    write_high_reg(15'h0602, 8'h12);
    write_high_reg(15'h0604, 8'h34);
    write_high_reg(15'h060e, 8'h4A);
    write_high_reg(15'h0610, 8'hAA);
    read_reg_expect(15'h0602, 16'h1212, "page1 PAR0 stores written value");
    read_reg_expect(15'h0604, 16'h3434, "page1 PAR1 stores written value");
    read_reg_expect(15'h060e, 16'h4A4A, "page1 CURR stores written value");
    read_reg_expect(15'h0610, 16'hAAAA, "page1 MAR0 stores written value");

    // Real-hardware ring layout: TX page (TPSR=0x40) sits BELOW the RX ring
    // (PSTART=0x46). This is what the X-Surf/Roadshow driver programs and it
    // must transmit successfully (the transmit gate must not require TPSR to be
    // inside [PSTART, PSTOP)).
    write_high_reg(15'h0600, 8'h02);
    write_high_reg(15'h0602, 8'h46);
    write_high_reg(15'h0604, 8'h80);
    write_high_reg(15'h0606, 8'h46);
    write_high_reg(15'h0608, 8'h40);
    write_high_reg(15'h060a, 8'h04);
    write_high_reg(15'h060c, 8'h00);
    write_high_reg(15'h061a, 8'h00);
    write_high_reg(15'h061e, 8'h02);
    poke_packet_ram_word(16'h4000, 16'hCAFE);
    poke_packet_ram_word(16'h4002, 16'hBEEF);

    write_high_reg(15'h0600, 8'h06);   // CR: STA|TXP -> transmit

    // Complete-on-command: PTX is reported immediately when the transmit is
    // issued (like a real NE2000 accepting the frame), independent of the slow
    // word-by-word background mailbox staging. This is what keeps the driver
    // from hitting "No IRQ received / Transmit timeout".
    repeat (3) @(posedge clk);
    #1;
    if (dut.tsr_register !== 8'h01) begin
        $display("FAIL: complete-on-command should set TSR.PTX immediately, got 0x%02x", dut.tsr_register);
        $fatal(1);
    end
    if (dut.isr_register !== 8'h02) begin
        $display("FAIL: complete-on-command should set ISR.PTX immediately, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (eth_irq !== 1'b1) begin
        $display("FAIL: eth_irq should assert immediately on transmit command");
        $fatal(1);
    end

    // X-Surf interrupt-status register at board offset 0x40 must reflect the IRQ
    // line. PTX is pending here, so bit 7 should read set.
    read_aperture_expect(15'h0020, 16'h8080, "xsurf int status reflects pending IRQ");
    // Link/media status register (reg 0x17 = byte 0xC5C = word 0x62E): bit0 link
    // up, bits[2:1]=01 -> 10 Mbit/s full duplex. Must not read as data-port (0).
    read_aperture_expect(15'h062e, 16'h0303, "reg 0x17 reports link up / 10Mbit full duplex");
    read_reg_expect(15'h0608, 16'h0101, "page0 TSR reports PTX immediately on command");
    read_reg_expect(15'h060e, 16'h0202, "page0 ISR reports PTX immediately on command");
    read_reg_expect(15'h0600, 16'h0202, "CR clears TXP immediately on complete-on-command");

    // The frame must still stage to the HPS mailbox in the background so the HPS
    // can transmit it (addr/len/payload/seq published). expect_dma_request_filtered
    // skips any interleaved status-sync DMAs.
    expect_dma_request_filtered(1'b1, 15'h1600, 16'h0040, 1'b1, "background TX staging writes packet address");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b1, 15'h1601, 16'h0400, 1'b1, "background TX staging writes packet length");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b1, 15'h1000, 16'hCAFE, 1'b1, "background TX staging stages first TX word");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b1, 15'h1001, 16'hBEEF, 1'b1, "background TX staging stages second TX word");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b1, 15'h1604, 16'h0100, 1'b1, "background TX staging publishes request sequence");
    complete_dma(16'h0000);

    quiesce_background;

    write_high_reg(15'h060e, 8'h02);
    @(posedge clk);
    #1;
    if (dut.isr_register !== 8'h00) begin
        $display("FAIL: ISR clear should clear PTX, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (eth_irq !== 1'b0) begin
        $display("FAIL: eth_irq should deassert after clearing PTX");
        $fatal(1);
    end

    // With the IRQ cleared, the X-Surf interrupt-status register must read 0
    // (bit 7 clear) so the test does not report "Falsche Karte".
    read_aperture_expect(15'h0020, 16'h0000, "xsurf int status clear when no IRQ pending");

    write_high_reg(15'h0600, 8'h40);
    write_high_reg(15'h060e, 8'h49);
    write_high_reg(15'h0600, 8'h02);
    write_high_reg(15'h0618, 8'h01);
    write_high_reg(15'h061a, 8'h02);
    write_high_reg(15'h061e, 8'h03);

    write_high_reg(15'h0600, 8'h06);
    repeat (2) @(posedge clk);
    #1;
    if (dut.isr_register !== 8'h02) begin
        $display("FAIL: loopback transmit should set PTX without ISR.PRX, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (dut.rsr_register !== 8'h01) begin
        $display("FAIL: loopback receive should set RSR PRX, got 0x%02x", dut.rsr_register);
        $fatal(1);
    end
    if (dut.bnry_register !== 8'h46) begin
        $display("FAIL: loopback should not move BNRY, got 0x%02x", dut.bnry_register);
        $fatal(1);
    end
    write_high_reg(15'h0600, 8'h40);
    read_reg_expect(15'h060e, 16'h4949, "loopback does not advance CURR");
    write_high_reg(15'h0600, 8'h02);
    read_reg_expect(15'h0618, 16'h0101, "page0 RSR reports loopback receive");

    write_high_reg(15'h060e, 8'h02);
    @(posedge clk);
    #1;
    if (dut.isr_register !== 8'h00) begin
        $display("FAIL: ISR clear should clear loopback PTX, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    dut.tx_request_pending = 1'b0;
    dut.mirrored_fpga_flags = 16'h0000;

    write_high_reg(15'h0602, 8'h40);
    write_high_reg(15'h0604, 8'h80);
    write_high_reg(15'h0606, 8'h40);
    write_high_reg(15'h0618, 8'h00);
    write_high_reg(15'h061a, 8'h00);
    write_high_reg(15'h061e, 8'h01);
    write_high_reg(15'h0600, 8'h40);
    write_high_reg(15'h060e, 8'h41);
    write_high_reg(15'h0600, 8'h02);
    dut.shm_sync_enabled = 1'b0;
    dut.mirrored_fpga_flags = dut.fpga_owned_flags;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.bg_polling_rx_flags = 1'b0;
    dut.bg_clear_rx_avail = 1'b0;
    dut.bg_poll_counter = 8'h00;
    dut.eth_dma_req = 1'b0;

    expect_dma_request_filtered(1'b0, 15'h0800, 16'h0000, 1'b0, "RX poll reads CTRL_FLAGS");
    complete_dma(16'h0400);

    expect_dma_request_filtered(1'b0, 15'h1602, 16'h0000, 1'b0, "RX poll reads shared queue head");
    complete_dma(16'h0000);

    expect_dma_request_filtered(1'b0, 15'h1603, 16'h0000, 1'b0, "RX poll reads shared queue tail");
    complete_dma(16'h0100);

    expect_dma_request_filtered(1'b0, 15'h1610, 16'h0000, 1'b0, "RX poll reads queue slot length");
    complete_dma(16'h0200);

    repeat (3) @(posedge clk);
    expect_packet_ram_word(16'h4100, 16'h2142, "RX injection writes NE2000 header word 0 locally");
    expect_packet_ram_word(16'h4102, 16'h0600, "RX injection writes NE2000 header word 1 locally");

    expect_dma_request_filtered(1'b0, 15'h4800, 16'h0000, 1'b0, "RX injection reads queue slot payload");
    complete_dma(16'hA1B2);

    repeat (2) @(posedge clk);
    expect_packet_ram_word(16'h4104, 16'hA1B2, "RX injection writes payload into NE memory locally");

    expect_dma_request_filtered(1'b1, 15'h1602, 16'h0100, 1'b1, "RX injection advances shared queue head");
    complete_dma(16'h0000);

    expect_dma_request_filtered(1'b1, 15'h0800, 16'h2800, 1'b1, "RX injection clears RX_AVAIL");
    complete_dma(16'h0000);

    repeat (2) @(posedge clk);
    #1;
    if (dut.rsr_register !== 8'h21) begin
        $display("FAIL: HPS RX injection should set RSR PRX|PHY, got 0x%02x", dut.rsr_register);
        $fatal(1);
    end
    if (dut.isr_register !== 8'h01) begin
        $display("FAIL: HPS RX injection should set ISR PRX, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (dut.curr_register !== 8'h42) begin
        $display("FAIL: HPS RX injection should advance CURR to 0x42, got 0x%02x", dut.curr_register);
        $fatal(1);
    end
    if (eth_irq !== 1'b1) begin
        $display("FAIL: HPS RX injection should assert eth_irq for enabled PRX");
        $fatal(1);
    end
    read_reg_expect(15'h060e, 16'h0101, "page0 ISR reports HPS RX PRX");
    write_high_reg(15'h0600, 8'h40);
    read_reg_expect(15'h060e, 16'h4242, "page1 CURR reflects HPS RX advance");
    write_high_reg(15'h0600, 8'h02);
    read_reg_expect(15'h0618, 16'h2121, "page0 RSR reports HPS RX receive with PHY");

    dut.shm_sync_enabled = 1'b1;
    dut.mirrored_fpga_flags = dut.fpga_owned_flags;
    expect_dma_request_filtered(1'b1, 15'h0830, 16'h0042, 1'b1, "shared CURR mirror write");
    complete_dma(16'h0000);

    dut.isr_register = 8'h00;
    dut.rsr_register = 8'h00;
    dut.cntr2_register = 8'h00;
    dut.curr_register = 8'h41;
    dut.bnry_register = 8'h42;
    dut.imr_register = 8'h10;
    dut.shm_sync_enabled = 1'b0;
    dut.mirrored_fpga_flags = dut.fpga_owned_flags;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.bg_polling_rx_flags = 1'b0;
    dut.bg_clear_rx_avail = 1'b0;
    dut.bg_poll_counter = 8'h00;
    dut.eth_dma_req = 1'b0;
    write_high_reg(15'h0600, 8'h02);

    expect_dma_request_filtered(1'b0, 15'h0800, 16'h0000, 1'b0, "RX overrun poll reads CTRL_FLAGS");
    complete_dma(16'h0400);

    expect_dma_request_filtered(1'b0, 15'h1602, 16'h0000, 1'b0, "RX overrun poll reads shared queue head");
    complete_dma(16'h0000);

    expect_dma_request_filtered(1'b0, 15'h1603, 16'h0000, 1'b0, "RX overrun poll reads shared queue tail");
    complete_dma(16'h0100);

    expect_dma_request_filtered(1'b0, 15'h1610, 16'h0000, 1'b0, "RX overrun poll reads queue slot length");
    complete_dma(16'h0200);

    expect_dma_request_filtered(1'b1, 15'h1602, 16'h0100, 1'b1, "RX overrun advances shared queue head");
    complete_dma(16'h0000);

    expect_dma_request_filtered(1'b1, 15'h0800, 16'h2800, 1'b1, "RX overrun clears RX_AVAIL and publishes OVW IRQ");
    complete_dma(16'h0000);

    repeat (2) @(posedge clk);
    #1;
    if (dut.rsr_register !== 8'h10) begin
        $display("FAIL: HPS RX overrun should set RSR MPA, got 0x%02x", dut.rsr_register);
        $fatal(1);
    end
    if (dut.isr_register !== 8'h10) begin
        $display("FAIL: HPS RX overrun should set ISR OVW, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (dut.cntr2_register !== 8'h01) begin
        $display("FAIL: HPS RX overrun should increment CNTR2, got 0x%02x", dut.cntr2_register);
        $fatal(1);
    end
    if (dut.curr_register !== 8'h41) begin
        $display("FAIL: HPS RX overrun should leave CURR unchanged, got 0x%02x", dut.curr_register);
        $fatal(1);
    end
    read_reg_expect(15'h0618, 16'h1010, "page0 RSR reports missed packet");
    read_reg_expect(15'h061e, 16'h0101, "page0 CNTR2 reports missed packet tally");

    dut.isr_register = 8'h00;
    dut.rsr_register = 8'h00;
    dut.cntr2_register = 8'h00;
    dut.curr_register = 8'h41;
    dut.bnry_register = 8'h40;
    dut.imr_register = 8'h01;
    dut.rx_poll_enabled = 1'b1;
    dut.shm_sync_enabled = 1'b0;
    dut.mirrored_fpga_flags = dut.fpga_owned_flags;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.bg_polling_rx_flags = 1'b0;
    dut.bg_clear_rx_avail = 1'b0;
    dut.bg_poll_counter = 8'h00;
    dut.eth_dma_req = 1'b0;
    write_high_reg(15'h0600, 8'h02);

    expect_dma_request_filtered(1'b0, 15'h0800, 16'h0000, 1'b0, "stale RX flag poll reads CTRL_FLAGS");
    complete_dma(16'h2400);

    expect_dma_request_filtered(1'b0, 15'h1602, 16'h0000, 1'b0, "stale RX flag poll reads shared queue head");
    complete_dma(16'h0100);

    expect_dma_request_filtered(1'b0, 15'h1603, 16'h0000, 1'b0, "stale RX flag poll reads shared queue tail");
    complete_dma(16'h0100);

    expect_dma_request_filtered(1'b1, 15'h0800, 16'h2000, 1'b1, "stale RX flag is cleared when queue is empty");
    complete_dma(16'h0000);

    repeat (2) @(posedge clk);
    #1;
    if (dut.isr_register !== 8'h00) begin
        $display("FAIL: stale RX flag with empty queue should not raise ISR, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (dut.curr_register !== 8'h41) begin
        $display("FAIL: stale RX flag with empty queue should not advance CURR, got 0x%02x", dut.curr_register);
        $fatal(1);
    end

    dut.isr_register = 8'h00;
    dut.rsr_register = 8'h00;
    dut.curr_register = 8'h41;
    dut.bnry_register = 8'h40;
    dut.rx_poll_enabled = 1'b1;
    dut.shm_sync_enabled = 1'b0;
    dut.mirrored_fpga_flags = dut.fpga_owned_flags;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.bg_polling_rx_flags = 1'b0;
    dut.bg_clear_rx_avail = 1'b0;
    dut.bg_poll_counter = 8'h00;
    dut.eth_dma_req = 1'b0;
    write_high_reg(15'h0600, 8'h02);

    expect_dma_request_filtered(1'b0, 15'h0800, 16'h0000, 1'b0, "RX slot1 poll reads CTRL_FLAGS");
    complete_dma(16'h2400);

    expect_dma_request_filtered(1'b0, 15'h1602, 16'h0000, 1'b0, "RX slot1 poll reads shared queue head");
    complete_dma(16'h0100);

    expect_dma_request_filtered(1'b0, 15'h1603, 16'h0000, 1'b0, "RX slot1 poll reads shared queue tail");
    complete_dma(16'h0200);

    expect_dma_request_filtered(1'b0, 15'h1611, 16'h0000, 1'b0, "RX slot1 poll reads queue slot length");
    complete_dma(16'h0200);

    repeat (3) @(posedge clk);
    expect_packet_ram_word(16'h4100, 16'h2142, "RX slot1 writes NE2000 header word 0 locally");
    expect_packet_ram_word(16'h4102, 16'h0600, "RX slot1 writes NE2000 header word 1 locally");

    expect_dma_request_filtered(1'b0, 15'h4B00, 16'h0000, 1'b0, "RX slot1 reads queue slot payload");
    complete_dma(16'hC3D4);

    repeat (2) @(posedge clk);
    expect_packet_ram_word(16'h4104, 16'hC3D4, "RX slot1 writes payload into NE memory locally");

    expect_dma_request_filtered(1'b1, 15'h1602, 16'h0200, 1'b1, "RX slot1 advances shared queue head");
    complete_dma(16'h0000);

    expect_dma_request_filtered(1'b1, 15'h0800, 16'h2800, 1'b1, "RX slot1 clears RX_AVAIL and publishes PRX IRQ");
    complete_dma(16'h0000);

    repeat (2) @(posedge clk);
    #1;
    if (dut.rsr_register !== 8'h21) begin
        $display("FAIL: RX slot1 should set RSR PRX|PHY, got 0x%02x", dut.rsr_register);
        $fatal(1);
    end
    if (dut.isr_register !== 8'h01) begin
        $display("FAIL: RX slot1 should set ISR PRX, got 0x%02x", dut.isr_register);
        $fatal(1);
    end
    if (dut.curr_register !== 8'h42) begin
        $display("FAIL: RX slot1 should advance CURR to 0x42, got 0x%02x", dut.curr_register);
        $fatal(1);
    end

    dut.rx_poll_enabled = 1'b0;
    dut.shm_sync_enabled = 1'b0;
    dut.tx_request_pending = 1'b0;
    dut.bg_state = 6'd0;
    dut.bg_dma_inflight = 1'b0;
    dut.bg_polling_rx_flags = 1'b0;
    dut.bg_clear_rx_avail = 1'b0;
    dut.eth_dma_req = 1'b0;
    dut.mirrored_fpga_flags = dut.fpga_owned_flags;
    dut.hps_poll_counter = 8'h00;
    dut.hps_status_sampled = 1'b0;
    dut.hps_heartbeat_change_seen = 1'b0;
    dut.hps_heartbeat_seen = 32'h00000000;
    dut.hps_signature_seen = 32'h00000000;
    dut.bg_hps_heartbeat_lo = 16'h0000;
    dut.bg_hps_signature_lo = 16'h0000;
    write_high_reg(15'h0600, 8'h02);

    expect_dma_request_filtered(1'b0, 15'h0844, 16'h0000, 1'b0, "HPS status poll reads heartbeat low");
    complete_dma(16'h3412);
    expect_dma_request_filtered(1'b0, 15'h0845, 16'h0000, 1'b0, "HPS status poll reads heartbeat high");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b0, 15'h0846, 16'h0000, 1'b0, "HPS status poll reads signature low");
    complete_dma(16'hBEBA);
    expect_dma_request_filtered(1'b0, 15'h0847, 16'h0000, 1'b0, "HPS status poll reads signature high");
    complete_dma(16'hFECA);
    expect_dma_request_filtered(1'b1, 15'h0829, 16'h0007, 1'b1, "HPS status poll writes sampled/signature/heartbeat flags");
    complete_dma(16'h0000);

    repeat (2) @(posedge clk);
    #1;
    if (dut.hps_heartbeat_seen !== 32'h00001234) begin
        $display("FAIL: HPS status poll should latch heartbeat 0x00001234, got 0x%08x", dut.hps_heartbeat_seen);
        $fatal(1);
    end
    if (dut.hps_signature_seen !== 32'hCAFEBABE) begin
        $display("FAIL: HPS status poll should latch signature 0xCAFEBABE, got 0x%08x", dut.hps_signature_seen);
        $fatal(1);
    end
    if (dut.hps_comm_status_word !== 16'h0700) begin
        $display("FAIL: first HPS status word should be 0x0700, got 0x%04x", dut.hps_comm_status_word);
        $fatal(1);
    end
    read_reg_expect(15'h063a, 16'h0700, "debug HPS status word after first sample");
    read_reg_expect(15'h063c, 16'h1234, "debug HPS heartbeat low after first sample");

    dut.hps_poll_counter = 8'h00;
    expect_dma_request_filtered(1'b0, 15'h0844, 16'h0000, 1'b0, "HPS status poll rereads heartbeat low");
    complete_dma(16'h3512);
    expect_dma_request_filtered(1'b0, 15'h0845, 16'h0000, 1'b0, "HPS status poll rereads heartbeat high");
    complete_dma(16'h0000);
    expect_dma_request_filtered(1'b0, 15'h0846, 16'h0000, 1'b0, "HPS status poll rereads signature low");
    complete_dma(16'hBEBA);
    expect_dma_request_filtered(1'b0, 15'h0847, 16'h0000, 1'b0, "HPS status poll rereads signature high");
    complete_dma(16'hFECA);
    expect_dma_request_filtered(1'b1, 15'h0829, 16'h001F, 1'b1, "HPS status poll writes comm-ok flags after heartbeat advance");
    complete_dma(16'h0000);

    repeat (2) @(posedge clk);
    #1;
    if (dut.hps_comm_status_word !== 16'h1F00) begin
        $display("FAIL: second HPS status word should be 0x1F00, got 0x%04x", dut.hps_comm_status_word);
        $fatal(1);
    end
    read_reg_expect(15'h063a, 16'h1F00, "debug HPS status word after heartbeat advance");
    read_reg_expect(15'h063c, 16'h1235, "debug HPS heartbeat low after heartbeat advance");

    $display("PASS: ethernet_tb completed");
    $finish;
end

endmodule
