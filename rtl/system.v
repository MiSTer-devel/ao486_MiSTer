
module system
(
	input         reset,

	input         clk_sys,
	input  [27:0] clock_rate,

	input         l1_disable,
	input         l2_disable,

	output [1:0]  fdd_request,
	output [2:0]  ide0_request,
	output [2:0]  ide1_request,
	input  [1:0]  floppy_wp,

	output        eth_dma_req,
	output        eth_dma_write,
	output [15:1] eth_dma_addr,
	output [15:0] eth_dma_wdata,
	output        eth_dma_wide,
	output [63:0] eth_dma_wdata64,
	output        eth_dma_uds,
	output        eth_dma_lds,
	input         eth_dma_ready,
	input  [15:0] eth_dma_rdata,
	input  [63:0] eth_dma_rdata64,

	input         ne2000_en,
	input   [1:0] ne2000_irq_sel,

	input   [1:0] joystick_dis,
	input  [13:0] joystick_dig_1,
	input  [13:0] joystick_dig_2,
	input  [15:0] joystick_ana_1,
	input  [15:0] joystick_ana_2,
	input  [1:0]  joystick_mode,
	input  [1:0]  joystick_timed,

	input  [15:0] mgmt_address,
	input         mgmt_read,
	output [15:0] mgmt_readdata,
	input         mgmt_write,
	input  [15:0] mgmt_writedata,

	input         ps2_kbclk_in,
	input         ps2_kbdat_in,
	output        ps2_kbclk_out,
	output        ps2_kbdat_out,
	input         ps2_mouseclk_in,
	input         ps2_mousedat_in,
	output        ps2_mouseclk_out,
	output        ps2_mousedat_out,
	output        ps2_reset_n,

	input   [5:0] bootcfg,
	input         uma_ram,
	output  [7:0] syscfg,

	input         clk_uart1,
	input         uart1_rx,
	output        uart1_tx,
	input         uart1_cts_n,
	input         uart1_dcd_n,
	input         uart1_dsr_n,
	output        uart1_rts_n,
	output        uart1_dtr_n,

	input         clk_uart2,
	input         uart2_rx,
	output        uart2_tx,
	input         uart2_cts_n,
	input         uart2_dcd_n,
	input         uart2_dsr_n,
	output        uart2_rts_n,
	output        uart2_dtr_n,

	input         clk_mpu,
	input         mpu_rx,
	output        mpu_tx,

	input         clk_audio,
	output  [8:0] sample_cms_l,
	output  [8:0] sample_cms_r,
	output [15:0] sample_sb_l,
	output [15:0] sample_sb_r,
	output [15:0] sample_opl_l,
	output [15:0] sample_opl_r,
	input         sound_fm_mode,
	input         sound_cms_en,
	output [15:0] sample_gus_l,
	output [15:0] sample_gus_r,

	output        speaker_out,

	output        sbp,

	output  [4:0] vol_master_l,
	output  [4:0] vol_master_r,
	output  [4:0] vol_voice_l,
	output  [4:0] vol_voice_r,
	output  [4:0] vol_midi_l,
	output  [4:0] vol_midi_r,
	output  [4:0] vol_cd_l,
	output  [4:0] vol_cd_r,
	output  [4:0] vol_line_l,
	output  [4:0] vol_line_r,
	output  [1:0] vol_spk,
	output  [4:0] vol_en,

	input         clk_vga,
	input  [27:0] clock_rate_vga,

	output        video_ce,
	output        video_blank_n,
	output        video_hsync,
	output        video_vsync,
	output [7:0]  video_r,
	output [7:0]  video_g,
	output [7:0]  video_b,
	input         video_f60,
	output [7:0]  video_pal_a,
	output [17:0] video_pal_d,
	output        video_pal_we,
	output [19:0] video_start_addr,
	output [8:0]  video_width,
	output [10:0] video_height,
	output [3:0]  video_flags,
	output [8:0]  video_stride,
	output        video_off,
	input         video_fb_en,
	input         video_lores,
	input         video_border,

	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [24:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	input         pll_locked,
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);

wire        a20_enable;
wire  [7:0] dma_floppy_readdata;
wire        dma_floppy_tc;
wire  [7:0] dma_floppy_writedata;
wire        dma_floppy_req;
wire        dma_floppy_ack;
wire        dma_sb_req_8;
wire        dma_sb_req_16;
wire        dma_sb_ack_8;
wire        dma_sb_ack_16;
wire  [7:0] dma_sb_readdata_8;
wire [15:0] dma_sb_readdata_16;
wire [15:0] dma_sb_writedata;
wire        dma_gus_req;
wire        dma_gus_ack;
wire        dma_gus_tc;
wire [15:0] dma_gus_readdata;
wire [15:0] dma_gus_writedata;
wire [15:0] dma_readdata;
wire        dma_waitrequest;
wire [23:0] dma_address;
wire        dma_read;
wire        dma_readdatavalid;
wire        dma_write;
wire [15:0] dma_writedata;
wire        dma_16bit;

wire [15:0] mgmt_fdd_readdata;
wire [15:0] mgmt_ide0_readdata;
wire [15:0] mgmt_ide1_readdata;
wire        mgmt_ide0_cs;
wire        mgmt_ide1_cs;
wire        mgmt_fdd_cs;
wire        mgmt_rtc_cs;

wire        interrupt_done;
wire        interrupt_do;
wire  [7:0] interrupt_vector;
wire [15:0] irq;

// IRQ map:
//
//  0 - PIT
//  1 - Keyboard
//  2 - VGA
//  3 - UART 2
//  4 - UART 1
//  5 - SB, GUS
//  6 - Floppy
//  7 - SB, GUS
//  8 - RTC
//  9 - MPU(MIDI)
// 10 - SB
// 11 - NE2000 (default)
// 12 - Mouse
// 13 - 
// 14 - IDE 0
// 15 - IDE 1

// NE2000 interrupt, OSD-selectable. IRQ 11 is the only line ao486 leaves free,
// so it is the default; 10/5/3 are shared with SB/GUS/COM2 and are the user's
// problem if those are also in use.
wire       ne2000_irq;
wire [3:0] ne2000_irq_line = (ne2000_irq_sel == 2'd1) ? 4'd10 :
                             (ne2000_irq_sel == 2'd2) ? 4'd5  :
                             (ne2000_irq_sel == 2'd3) ? 4'd3  : 4'd11;
wire       ne2000_irq_11 = ne2000_irq & (ne2000_irq_line == 4'd11);
wire       ne2000_irq_10 = ne2000_irq & (ne2000_irq_line == 4'd10);
wire       ne2000_irq_5  = ne2000_irq & (ne2000_irq_line == 4'd5);
wire       ne2000_irq_3  = ne2000_irq & (ne2000_irq_line == 4'd3);

assign irq[11] = ne2000_irq_11;
assign irq[13] = 0;


wire        sb_irq;
wire        sb_irq_5_en;
wire        sb_irq_7_en;
wire        sb_irq_10_en;
wire        gus_irq;

wire        cpu_io_read_do;
wire [15:0] cpu_io_read_address;
wire [2:0]  cpu_io_read_length;
wire [31:0] cpu_io_read_data;
wire        cpu_io_read_done;
wire        cpu_io_write_do;
wire [15:0] cpu_io_write_address;
wire [2:0]  cpu_io_write_length;
wire [31:0] cpu_io_write_data;
wire        cpu_io_write_done;
wire [15:0] iobus_address;
wire        iobus_write;
wire        iobus_read;
wire  [2:0] iobus_datasize;
wire [31:0] iobus_writedata;

reg         ide0_cs;
reg         ide1_cs;
reg         floppy0_cs;
reg         dma_master_cs;
reg         dma_page_cs;
reg         dma_slave_cs;
reg         pic_master_cs;
reg         pic_slave_cs;
reg         pit_cs;
reg         ps2_io_cs;
reg         ps2_ctl_cs;
reg         joy_cs;
reg         rtc_cs;
reg         fm_cs;
reg         sb_cs;
reg         gus_cs;
reg         ne2k_cs;
reg         shm_cs;
reg         uart1_cs;
reg         uart2_cs;
reg         mpu_cs;
reg         vga_b_cs;
reg         vga_c_cs;
reg         vga_d_cs;
reg         sysctl_cs;

wire        fdd0_inserted;

wire        gus_wait;

wire  [7:0] sound_readdata;
wire  [7:0] gus_readdata;
wire  [7:0] floppy0_readdata;
wire [31:0] ne2k_readdata;
wire  [7:0] shm_readdata;

// NE2000 core and probe transport masters, merged by ne2000_dma_mux below.
wire        core_dma_req, core_dma_write, core_dma_wide, core_dma_uds, core_dma_lds;
wire [15:1] core_dma_addr;
wire [15:0] core_dma_wdata, core_dma_rdata;
wire [63:0] core_dma_wdata64, core_dma_rdata64;
wire        core_dma_ready;
wire        probe_dma_req, probe_dma_write, probe_dma_wide, probe_dma_uds, probe_dma_lds;
wire [15:1] probe_dma_addr;
wire [15:0] probe_dma_wdata, probe_dma_rdata;
wire [63:0] probe_dma_wdata64;
wire        probe_dma_ready;
wire        ne2k_wait;
wire [31:0] ide0_readdata;
wire [31:0] ide1_readdata;
wire  [7:0] joystick_readdata;
wire  [7:0] pit_readdata;
wire  [7:0] ps2_readdata;
wire  [7:0] rtc_readdata;
wire  [7:0] uart1_readdata;
wire  [7:0] uart2_readdata;
wire        uart2_irq;
wire  [7:0] mpu_readdata;
wire  [7:0] dma_io_readdata;
wire  [7:0] pic_readdata;
wire  [7:0] vga_io_readdata;

wire [29:0] mem_address;
wire [31:0] mem_writedata;
wire [31:0] mem_readdata;
wire  [3:0] mem_byteenable;
wire  [3:0] mem_burstcount;
wire        mem_write;
wire        mem_read;
wire        mem_waitrequest;
wire        mem_readdatavalid;

wire [16:0] vga_address;
wire  [7:0] vga_readdata;
wire  [7:0] vga_writedata;
wire        vga_read;
wire        vga_write;
wire  [2:0] vga_memmode;
wire  [5:0] video_wr_seg;
wire  [5:0] video_rd_seg;

assign      DDRAM_CLK = clk_sys;

l2_cache cache
(
	.CLK               (clk_sys),
	.RESET             (reset),

	.DISABLE           (l2_disable),

	.CPU_ADDR          (mem_address),
	.CPU_DIN           (mem_writedata),
	.CPU_DOUT          (mem_readdata),
	.CPU_DOUT_READY    (mem_readdatavalid),
	.CPU_BE            (mem_byteenable),
	.CPU_BURSTCNT      (mem_burstcount),
	.CPU_BUSY          (mem_waitrequest),
	.CPU_RD            (mem_read),
	.CPU_WE            (mem_write),

	.DDRAM_ADDR        (DDRAM_ADDR),
	.DDRAM_DIN         (DDRAM_DIN),
	.DDRAM_DOUT        (DDRAM_DOUT),
	.DDRAM_DOUT_READY  (DDRAM_DOUT_READY),
	.DDRAM_BE          (DDRAM_BE),
	.DDRAM_BURSTCNT    (DDRAM_BURSTCNT),
	.DDRAM_BUSY        (DDRAM_BUSY),
	.DDRAM_RD          (DDRAM_RD),
	.DDRAM_WE          (DDRAM_WE),

	.VGA_ADDR          (vga_address),
	.VGA_DIN           (vga_readdata),
	.VGA_DOUT          (vga_writedata),
	.VGA_RD            (vga_read),
	.VGA_WE            (vga_write),
	.VGA_MODE          (vga_memmode),

	.VGA_WR_SEG        (video_wr_seg),
	.VGA_RD_SEG        (video_rd_seg),
	.VGA_FB_EN         (video_fb_en),

	.uma_ram           (uma_ram)
);

ao486 ao486
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.cache_disable     (l1_disable),

	.avm_address       (mem_address),
	.avm_writedata     (mem_writedata),
	.avm_byteenable    (mem_byteenable),
	.avm_burstcount    (mem_burstcount),
	.avm_write         (mem_write),
	.avm_read          (mem_read),
	.avm_waitrequest   (mem_waitrequest),
	.avm_readdatavalid (mem_readdatavalid),
	.avm_readdata      (mem_readdata),

	.interrupt_do      (interrupt_do),
	.interrupt_vector  (interrupt_vector),
	.interrupt_done    (interrupt_done),

	.io_read_do        (cpu_io_read_do),
	.io_read_address   (cpu_io_read_address),
	.io_read_length    (cpu_io_read_length),
	.io_read_data      (cpu_io_read_data),
	.io_read_done      (cpu_io_read_done),
	.io_write_do       (cpu_io_write_do),
	.io_write_address  (cpu_io_write_address),
	.io_write_length   (cpu_io_write_length),
	.io_write_data     (cpu_io_write_data),
	.io_write_done     (cpu_io_write_done),

	.a20_enable        (a20_enable),

	.dma_address       (dma_address),
	.dma_16bit         (dma_16bit),
	.dma_read          (dma_read),
	.dma_readdata      (dma_readdata),
	.dma_readdatavalid (dma_readdatavalid),
	.dma_waitrequest   (dma_waitrequest),
	.dma_write         (dma_write),
	.dma_writedata     (dma_writedata)
);

always @(posedge clk_sys) begin
	ide0_cs       <= ({iobus_address[15:3], 3'd0} == 16'h01F0) || ({iobus_address[15:0]} == 16'h03F6);
	ide1_cs       <= ({iobus_address[15:3], 3'd0} == 16'h0170) || ({iobus_address[15:0]} == 16'h0376);
	joy_cs        <= ({iobus_address[15:0]      } == 16'h0201);
	floppy0_cs    <= ({iobus_address[15:2], 2'd0} == 16'h03F0) || ({iobus_address[15:1], 1'd0} == 16'h03F4) || ({iobus_address[15:0]} == 16'h03F7) ;
	dma_master_cs <= ({iobus_address[15:5], 5'd0} == 16'h00C0);
	dma_page_cs   <= ({iobus_address[15:4], 4'd0} == 16'h0080);
	dma_slave_cs  <= ({iobus_address[15:4], 4'd0} == 16'h0000);
	pic_master_cs <= ({iobus_address[15:1], 1'd0} == 16'h0020);
	pic_slave_cs  <= ({iobus_address[15:1], 1'd0} == 16'h00A0);
	pit_cs        <= ({iobus_address[15:2], 2'd0} == 16'h0040) || (iobus_address == 16'h0061);
	ps2_io_cs     <= ({iobus_address[15:3], 3'd0} == 16'h0060);
	ps2_ctl_cs    <= ({iobus_address[15:4], 4'd0} == 16'h0090);
	rtc_cs        <= ({iobus_address[15:1], 1'd0} == 16'h0070);
	fm_cs         <= ({iobus_address[15:2], 2'd0} == 16'h0388);
	sb_cs         <= ({iobus_address[15:4], 4'd0} == 16'h0220);
	gus_cs        <= ({iobus_address[15:4], 4'd0} == 16'h0240) || ({iobus_address[15:4], 4'd0} == 16'h0340);
	uart1_cs      <= ({iobus_address[15:3], 3'd0} == 16'h03F8);
	uart2_cs      <= ({iobus_address[15:3], 3'd0} == 16'h02F8);
	mpu_cs        <= ({iobus_address[15:1], 1'd0} == 16'h0330);
	vga_b_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03B0);
	vga_c_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03C0);
	vga_d_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03D0);
	sysctl_cs     <= ({iobus_address[15:0]      } == 16'h8888);
	// NE2000 at 0x300: 0x300-0x31F is the card, 0x320-0x32F the debug aperture.
	// 0x330-0x33F is left alone -- that is the MPU-401.
	ne2k_cs       <= ne2000_en && ({iobus_address[15:6]} == 10'h00C) && (iobus_address[5:4] != 2'b11)
	                                                                 && (iobus_address[5:3] != 3'b101);
	// 0x328-0x32F: shared-window probe (Phase 1 transport bring-up)
	shm_cs        <= ne2000_en && ({iobus_address[15:6]} == 10'h00C) && (iobus_address[5:3] == 3'b101);
end

reg [7:0] ctlport = 0;
always @(posedge clk_sys) begin
	reg in_reset = 1;
	if(reset) begin
		ctlport <= 8'hA2;
		in_reset <= 1;
	end
	else if((ide0_cs|ide1_cs|floppy0_cs) && in_reset) begin
		ctlport <= 0;
		in_reset <= 0;
	end
	else if(iobus_write && sysctl_cs && iobus_datasize == 2 && iobus_writedata[15:8] == 8'hA1) begin
		ctlport <= iobus_writedata[7:0];
		in_reset <= 0;
	end
end

assign syscfg = ctlport;

wire [7:0] iobus_readdata8 =
	( floppy0_cs                             ) ? floppy0_readdata  :
	( dma_master_cs|dma_slave_cs|dma_page_cs ) ? dma_io_readdata   :
	( pic_master_cs|pic_slave_cs             ) ? pic_readdata      :
	( pit_cs                                 ) ? pit_readdata      :
	( ps2_io_cs|ps2_ctl_cs                   ) ? ps2_readdata      :
	( rtc_cs                                 ) ? rtc_readdata      :
	( sb_cs|fm_cs                            ) ? sound_readdata    :
	( gus_cs                                 ) ? gus_readdata      :
	( uart1_cs                               ) ? uart1_readdata    :
	( uart2_cs                               ) ? uart2_readdata    :
	( mpu_cs                                 ) ? mpu_readdata      :
	( vga_b_cs|vga_c_cs|vga_d_cs             ) ? vga_io_readdata   :
	( joy_cs                                 ) ? joystick_readdata :
	( shm_cs                                 ) ? shm_readdata      :
	                                             8'hFF;

iobus iobus
(
	.clk               (clk_sys),
	.reset             (reset),

	.cpu_read_do       (cpu_io_read_do),
	.cpu_read_address  (cpu_io_read_address),
	.cpu_read_length   (cpu_io_read_length),
	.cpu_read_data     (cpu_io_read_data),
	.cpu_read_done     (cpu_io_read_done),
	.cpu_write_do      (cpu_io_write_do),
	.cpu_write_address (cpu_io_write_address),
	.cpu_write_length  (cpu_io_write_length),
	.cpu_write_data    (cpu_io_write_data),
	.cpu_write_done    (cpu_io_write_done),

	.bus_address       (iobus_address),
	.bus_write         (iobus_write),
	.bus_read          (iobus_read),
	.bus_io32          (((ide0_cs | ide1_cs) & ~iobus_address[9]) | sysctl_cs | ne2k_io32),
	.bus_datasize      (iobus_datasize),
	.bus_writedata     (iobus_writedata),
	.bus_readdata      (ne2k_cs ? ne2k_readdata : ide0_cs ? ide0_readdata : ide1_cs ? ide1_readdata : iobus_readdata8),
	.bus_wait          (ide0_wait | ide1_wait | gus_wait | ne2k_wait)
);

dma dma
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.mem_address       (dma_address),
	.mem_16bit         (dma_16bit),
	.mem_waitrequest   (dma_waitrequest),
	.mem_read          (dma_read),
	.mem_readdatavalid (dma_readdatavalid),
	.mem_readdata      (dma_readdata),
	.mem_write         (dma_write),
	.mem_writedata     (dma_writedata),

	.io_address        (iobus_address[4:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (dma_io_readdata),
	.io_master_cs      (dma_master_cs),
	.io_slave_cs       (dma_slave_cs),
	.io_page_cs        (dma_page_cs),

	.dma_2_req         (dma_floppy_req),
	.dma_2_ack         (dma_floppy_ack),
	.dma_2_tc          (dma_floppy_tc),
	.dma_2_readdata    (dma_floppy_readdata),
	.dma_2_writedata   (dma_floppy_writedata),

	.dma_1_req         (dma_sb_req_8),
	.dma_1_ack         (dma_sb_ack_8),
	.dma_1_readdata    (dma_sb_readdata_8),
	.dma_1_writedata   (dma_sb_writedata[7:0]),

	.dma_5_req         (dma_sb_req_16),
	.dma_5_ack         (dma_sb_ack_16),
	.dma_5_readdata    (dma_sb_readdata_16),
	.dma_5_writedata   (dma_sb_writedata),

	.dma_7_req         (dma_gus_req),
	.dma_7_ack         (dma_gus_ack),
	.dma_7_tc          (dma_gus_tc),
	.dma_7_readdata    (dma_gus_readdata),
	.dma_7_writedata   (dma_gus_writedata)
);

floppy floppy
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.io_address        (iobus_address[2:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read & floppy0_cs),
	.io_write          (iobus_write & floppy0_cs),
	.io_readdata       (floppy0_readdata),

	.fdd0_inserted     (fdd0_inserted),

	.dma_req           (dma_floppy_req),
	.dma_ack           (dma_floppy_ack),
	.dma_tc            (dma_floppy_tc),
	.dma_readdata      (dma_floppy_readdata),
	.dma_writedata     (dma_floppy_writedata),

	.mgmt_address      (mgmt_address[3:0]),
	.mgmt_fddn         (mgmt_address[7]),
	.mgmt_writedata    (mgmt_writedata),
	.mgmt_readdata     (mgmt_fdd_readdata),
	.mgmt_write        (mgmt_write & mgmt_fdd_cs),
	.mgmt_read         (mgmt_read & mgmt_fdd_cs),

	.wp                (floppy_wp),

	.request           (fdd_request),
	.irq               (irq[6])
);

wire [3:0] ide_address = {iobus_address[9],iobus_address[2:0]};

wire ide0_nodata;
reg  ide0_wait = 0;
always @(posedge clk_sys) begin
	if(iobus_read & ide0_cs & ide0_nodata & !ide_address) ide0_wait <= 1;
	if(~ide0_nodata) ide0_wait <= 0;
end

// ---------------------------------------------------------------------------
// NE2000 network card (see NE2000_AO486_PLAN.md)
// ---------------------------------------------------------------------------
// I/O base 0x300. base+0x00..0x1F is the card; base+0x20..0x2F mirrors the
// core's debug snapshot registers so a DOS utility can read transport state
// without a JTAG session.
// The 16-bit remote-DMA data port at base+0x10 retires in one bus cycle via
// bus_io32, exactly like the IDE data port.
wire ne2k_dataport = (iobus_address[5:3] == 3'b010);
wire ne2k_io32     = ne2k_cs & ne2k_dataport & (iobus_datasize != 3'd1);

ne2000_shm_probe ne2000_shm
(
	.clk               (clk_sys),
	.reset             (reset),

	.io_address        (iobus_address[3:0]),
	.io_read           (iobus_read  & shm_cs),
	.io_write          (iobus_write & shm_cs),
	.io_writedata      (iobus_writedata[7:0]),
	.io_readdata       (shm_readdata),

	.eth_dma_req       (probe_dma_req),
	.eth_dma_write     (probe_dma_write),
	.eth_dma_addr      (probe_dma_addr),
	.eth_dma_wdata     (probe_dma_wdata),
	.eth_dma_wide      (probe_dma_wide),
	.eth_dma_wdata64   (probe_dma_wdata64),
	.eth_dma_uds       (probe_dma_uds),
	.eth_dma_lds       (probe_dma_lds),
	.eth_dma_ready     (probe_dma_ready),
	.eth_dma_rdata     (probe_dma_rdata)
);

// The device model and the probe share one transport master; the core wins.
ne2000_dma_mux ne2000_dma_arb
(
	.clk               (clk_sys),
	.reset             (reset),

	.m0_req            (core_dma_req),
	.m0_write          (core_dma_write),
	.m0_addr           (core_dma_addr),
	.m0_wdata          (core_dma_wdata),
	.m0_wide           (core_dma_wide),
	.m0_wdata64        (core_dma_wdata64),
	.m0_uds            (core_dma_uds),
	.m0_lds            (core_dma_lds),
	.m0_ready          (core_dma_ready),
	.m0_rdata          (core_dma_rdata),
	.m0_rdata64        (core_dma_rdata64),

	.m1_req            (probe_dma_req),
	.m1_write          (probe_dma_write),
	.m1_addr           (probe_dma_addr),
	.m1_wdata          (probe_dma_wdata),
	.m1_wide           (probe_dma_wide),
	.m1_wdata64        (probe_dma_wdata64),
	.m1_uds            (probe_dma_uds),
	.m1_lds            (probe_dma_lds),
	.m1_ready          (probe_dma_ready),
	.m1_rdata          (probe_dma_rdata),
	.m1_rdata64        (),

	.eth_dma_req       (eth_dma_req),
	.eth_dma_write     (eth_dma_write),
	.eth_dma_addr      (eth_dma_addr),
	.eth_dma_wdata     (eth_dma_wdata),
	.eth_dma_wide      (eth_dma_wide),
	.eth_dma_wdata64   (eth_dma_wdata64),
	.eth_dma_uds       (eth_dma_uds),
	.eth_dma_lds       (eth_dma_lds),
	.eth_dma_ready     (eth_dma_ready),
	.eth_dma_rdata     (eth_dma_rdata),
	.eth_dma_rdata64   (eth_dma_rdata64)
);

ne2000_isa ne2000
(
	.clk               (clk_sys),
	.reset             (reset),

	.io_address        (iobus_address[5:0]),
	.io_read           (iobus_read  & ne2k_cs),
	.io_write          (iobus_write & ne2k_cs),
	.io_writedata      (iobus_writedata),
	.io_32             (ne2k_io32),
	.io_readdata       (ne2k_readdata),
	.io_wait           (ne2k_wait),

	.irq               (ne2000_irq),

	.eth_dma_ready     (core_dma_ready),
	.eth_dma_rdata     (core_dma_rdata),
	.eth_dma_rdata64   (core_dma_rdata64),
	.eth_dma_req       (core_dma_req),
	.eth_dma_write     (core_dma_write),
	.eth_dma_addr      (core_dma_addr),
	.eth_dma_wdata     (core_dma_wdata),
	.eth_dma_wide      (core_dma_wide),
	.eth_dma_wdata64   (core_dma_wdata64),
	.eth_dma_uds       (core_dma_uds),
	.eth_dma_lds       (core_dma_lds)
);

ide ide0
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.io_address        (ide_address),
	.io_writedata      (iobus_writedata),
	.io_read           ((iobus_read & ide0_cs) | ide0_wait),
	.io_write          (iobus_write & ide0_cs),
	.io_readdata       (ide0_readdata),
	.io_32             (iobus_datasize[2]),

	.use_fast          (1),
	.no_data           (ide0_nodata),

	.mgmt_address      (mgmt_address[3:0]),
	.mgmt_writedata    (mgmt_writedata),
	.mgmt_readdata     (mgmt_ide0_readdata),
	.mgmt_write        (mgmt_write & mgmt_ide0_cs),
	.mgmt_read         (mgmt_read & mgmt_ide0_cs),

	.request           (ide0_request),
	.irq               (irq[14])
);

wire ide1_nodata;
reg  ide1_wait = 0;
always @(posedge clk_sys) begin
	if(iobus_read & ide1_cs & ide1_nodata & !ide_address) ide1_wait <= 1;
	if(~ide1_nodata) ide1_wait <= 0;
end

ide ide1
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.io_address        (ide_address),
	.io_writedata      (iobus_writedata),
	.io_read           ((iobus_read & ide1_cs) | ide1_wait),
	.io_write          (iobus_write & ide1_cs),
	.io_readdata       (ide1_readdata),
	.io_32             (iobus_datasize[2]),

	.use_fast          (1),
	.no_data           (ide1_nodata),

	.mgmt_address      (mgmt_address[3:0]),
	.mgmt_writedata    (mgmt_writedata),
	.mgmt_readdata     (mgmt_ide1_readdata),
	.mgmt_write        (mgmt_write & mgmt_ide1_cs),
	.mgmt_read         (mgmt_read & mgmt_ide1_cs),

	.request           (ide1_request),
	.irq               (irq[15])
);

joystick joystick
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.read              (iobus_read & joy_cs),
	.write             (iobus_write & joy_cs),
	.readdata          (joystick_readdata),

	.dis               (joystick_dis),

	.dig_1             (joystick_dig_1),
	.dig_2             (joystick_dig_2),
	.ana_1             (joystick_ana_1),
	.ana_2             (joystick_ana_2),
	.mode              (joystick_mode),
	.timed             (joystick_timed)
);

pit pit
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.io_address        ({iobus_address[5],iobus_address[1:0]}),
	.io_writedata      (iobus_writedata[7:0]),
	.io_readdata       (pit_readdata),
	.io_read           (iobus_read & pit_cs),
	.io_write          (iobus_write & pit_cs),

	.speaker_out       (speaker_out),
	.irq               (irq[0])
);

ps2 ps2
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.io_address        (iobus_address[3:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (ps2_readdata),
	.io_cs             (ps2_io_cs),
	.ctl_cs            (ps2_ctl_cs),

	.ps2_kbclk         (ps2_kbclk_in),
	.ps2_kbdat         (ps2_kbdat_in),
	.ps2_kbclk_out     (ps2_kbclk_out),
	.ps2_kbdat_out     (ps2_kbdat_out),

	.ps2_mouseclk      (ps2_mouseclk_in),
	.ps2_mousedat      (ps2_mousedat_in),
	.ps2_mouseclk_out  (ps2_mouseclk_out),
	.ps2_mousedat_out  (ps2_mousedat_out),

	.output_a20_enable (),
	.output_reset_n    (ps2_reset_n),
	.a20_enable        (a20_enable),

	.irq_keyb          (irq[1]),
	.irq_mouse         (irq[12])
);

rtc rtc
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.io_address        (iobus_address[0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read & rtc_cs),
	.io_write          (iobus_write & rtc_cs),
	.io_readdata       (rtc_readdata),

	.mgmt_address      (mgmt_address[7:0]),
	.mgmt_write        (mgmt_write & mgmt_rtc_cs),
	.mgmt_writedata    (mgmt_writedata[7:0]),

	.bootcfg           ({bootcfg[5:2], bootcfg[1:0] ? bootcfg[1:0] : {~fdd0_inserted, fdd0_inserted}}),

	.irq               (irq[8])
);

sound sound
(
	.clk               (clk_sys),
	.clk_audio         (clk_audio),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.address           (iobus_address[3:0]),
	.writedata         (iobus_writedata[7:0]),
	.read              (iobus_read),
	.write             (iobus_write),
	.readdata          (sound_readdata),
	.sb_cs             (sb_cs),
	.fm_cs             (fm_cs),

	.dma_req8          (dma_sb_req_8),
	.dma_req16         (dma_sb_req_16),
	.dma_ack           (dma_sb_ack_16 | dma_sb_ack_8),
	.dma_readdata      (dma_sb_req_16 ? dma_sb_readdata_16 : dma_sb_readdata_8),
	.dma_writedata     (dma_sb_writedata),

	.sbp               (sbp),

	.vol_master_l      (vol_master_l),
	.vol_master_r      (vol_master_r),
	.vol_voice_l       (vol_voice_l),
	.vol_voice_r       (vol_voice_r),
	.vol_midi_l        (vol_midi_l),
	.vol_midi_r        (vol_midi_r),
	.vol_cd_l          (vol_cd_l),
	.vol_cd_r          (vol_cd_r),
	.vol_line_l        (vol_line_l),
	.vol_line_r        (vol_line_r),
	.vol_spk           (vol_spk),
	.vol_en            (vol_en),

	.sample_cms_l      (sample_cms_l),
	.sample_cms_r      (sample_cms_r),
	.sample_sb_l       (sample_sb_l),
	.sample_sb_r       (sample_sb_r),
	.sample_opl_l      (sample_opl_l),
	.sample_opl_r      (sample_opl_r),

	.fm_mode           (sound_fm_mode),
	.cms_en            (sound_cms_en),

	.irq               (sb_irq),
	.irq_5_en          (sb_irq_5_en),
	.irq_7_en          (sb_irq_7_en),
	.irq_10_en         (sb_irq_10_en)
);

gus gus
(
	.clk               (clk_sys),
	.reset             (reset),

	.clock_rate        (clock_rate),

	.io_address8       (iobus_address[8]),
	.io_address        (iobus_address[3:0]),
	.writedata         (iobus_writedata[7:0]),
	.read              (iobus_read),
	.write             (iobus_write),
	.readdata          (gus_readdata),
	.gus_cs            (gus_cs),
	.fm_cs             (fm_cs),
	.io_wait           (gus_wait),

	.dma_req           (dma_gus_req),
	.dma_ack           (dma_gus_ack),
	.dma_tc            (dma_gus_tc),
	.dma_readdata      (dma_gus_readdata),
	.dma_writedata     (dma_gus_writedata),

	.audio_l           (sample_gus_l),
	.audio_r           (sample_gus_r),

	.irq               (gus_irq),

	.pll_locked        (pll_locked),
	.SDRAM_DQ          (SDRAM_DQ),
	.SDRAM_A           (SDRAM_A),
	.SDRAM_DQML        (SDRAM_DQML),
	.SDRAM_DQMH        (SDRAM_DQMH),
	.SDRAM_BA          (SDRAM_BA),
	.SDRAM_nCS         (SDRAM_nCS),
	.SDRAM_nWE         (SDRAM_nWE),
	.SDRAM_nRAS        (SDRAM_nRAS),
	.SDRAM_nCAS        (SDRAM_nCAS),
	.SDRAM_CLK         (SDRAM_CLK),
	.SDRAM_CKE         (SDRAM_CKE)

);

// GUS uses IRQ5 if SB doesn't occupy it, otherwise IRQ7
assign irq[5]  = (sb_irq_5_en & sb_irq) | (~sb_irq_5_en & gus_irq) | ne2000_irq_5;
assign irq[7]  = (sb_irq_7_en & sb_irq) | ( sb_irq_5_en & gus_irq);
assign irq[10] = (sb_irq_10_en & sb_irq) | ne2000_irq_10;

uart uart1
(
	.clk               (clk_sys),
	.br_clk            (clk_uart1),
	.reset             (reset),

	.address           (iobus_address[2:0]),
	.writedata         (iobus_writedata[7:0]),
	.read              (iobus_read),
	.write             (iobus_write),
	.readdata          (uart1_readdata),
	.cs                (uart1_cs),

	.rx                (uart1_rx),
	.tx                (uart1_tx),
	.cts_n             (uart1_cts_n),
	.dcd_n             (uart1_dcd_n),
	.dsr_n             (uart1_dsr_n),
	.rts_n             (uart1_rts_n),
	.dtr_n             (uart1_dtr_n),
	.ri_n              (1),

	.irq               (irq[4])
);

uart uart2
(
	.clk               (clk_sys),
	.br_clk            (clk_uart2),
	.reset             (reset),

	.address           (iobus_address[2:0]),
	.writedata         (iobus_writedata[7:0]),
	.read              (iobus_read),
	.write             (iobus_write),
	.readdata          (uart2_readdata),
	.cs                (uart2_cs),

	.rx                (uart2_rx),
	.tx                (uart2_tx),
	.cts_n             (uart2_cts_n),
	.dcd_n             (uart2_dcd_n),
	.dsr_n             (uart2_dsr_n),
	.rts_n             (uart2_rts_n),
	.dtr_n             (uart2_dtr_n),
	.ri_n              (1),

	.irq               (uart2_irq)
);

assign irq[3] = uart2_irq | ne2000_irq_3;

mpu mpu
(
	.clk               (clk_sys),
	.br_clk            (clk_mpu),
	.reset             (reset),

	.address           (iobus_address[0]),
	.writedata         (iobus_writedata[7:0]),
	.read              (iobus_read),
	.write             (iobus_write),
	.readdata          (mpu_readdata),
	.cs                (mpu_cs),

	.rx                (mpu_rx),
	.tx                (mpu_tx),

	.double_rate       (1),
	.irq               (irq[9])
);

vga vga
(
	.clk_sys           (clk_sys),
	.rst_n             (~reset),

	.clk_vga           (clk_vga),
	.clock_rate_vga    (clock_rate_vga),

	.io_address        (iobus_address[3:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (vga_io_readdata),
	.io_b_cs           (vga_b_cs),
	.io_c_cs           (vga_c_cs),
	.io_d_cs           (vga_d_cs),

	.mem_address       (vga_address),
	.mem_read          (vga_read),
	.mem_readdata      (vga_readdata),
	.mem_write         (vga_write),
	.mem_writedata     (vga_writedata),

	.vga_ce            (video_ce),
	.vga_blank_n       (video_blank_n),
	.vga_horiz_sync    (video_hsync),
	.vga_vert_sync     (video_vsync),
	.vga_r             (video_r),
	.vga_g             (video_g),
	.vga_b             (video_b),
	.vga_f60           (video_f60),
	.vga_memmode       (vga_memmode),
	.vga_pal_a         (video_pal_a),
	.vga_pal_d         (video_pal_d),
	.vga_pal_we        (video_pal_we),
	.vga_start_addr    (video_start_addr),
	.vga_wr_seg        (video_wr_seg),
	.vga_rd_seg        (video_rd_seg),
	.vga_width         (video_width),
	.vga_height        (video_height),
	.vga_flags         (video_flags),
	.vga_stride        (video_stride),
	.vga_off           (video_off),
	.vga_lores         (video_lores),
	.vga_border        (video_border),

	.irq               (irq[2])
);

pic pic
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.io_address        (iobus_address[0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (pic_readdata),
	.io_master_cs      (pic_master_cs),
	.io_slave_cs       (pic_slave_cs),

	.interrupt_vector  (interrupt_vector),
	.interrupt_done    (interrupt_done),
	.interrupt_do      (interrupt_do),
	.interrupt_input   (irq)
);

assign mgmt_ide0_cs  = (mgmt_address[15:8] == 8'hF0);
assign mgmt_ide1_cs  = (mgmt_address[15:8] == 8'hF1);
assign mgmt_fdd_cs   = (mgmt_address[15:8] == 8'hF2);
assign mgmt_rtc_cs   = (mgmt_address[15:8] == 8'hF4);
assign mgmt_readdata = mgmt_ide0_cs ? mgmt_ide0_readdata : mgmt_ide1_cs ? mgmt_ide1_readdata : mgmt_fdd_readdata;

endmodule
