
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

	input   [1:0] joystick_dis,
	input  [13:0] joystick_dig_1,
	input  [13:0] joystick_dig_2,
	input  [15:0] joystick_ana_1,
	input  [15:0] joystick_ana_2,
	input  [1:0]  joystick_mode,

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
	input         memcfg,
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

	input         clk_opl,
	output [15:0] sound_sample_l,
	output [15:0] sound_sample_r,
	input         sound_fm_mode,
	input         sound_cms_en,

	output        speaker_out,

	output  [4:0] vol_l,
	output  [4:0] vol_r,
	output  [4:0] vol_cd_l,
	output  [4:0] vol_cd_r,
	output  [4:0] vol_midi_l,
	output  [4:0] vol_midi_r,
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

	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [24:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE
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
reg  [15:0] interrupt;
wire        irq_0, irq_1, irq_2, irq_3, irq_4, irq_5, irq_6, irq_7, irq_8, irq_9, irq_10, irq_12, irq_14, irq_15;

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
reg         uart1_cs;
reg         uart2_cs;
reg         mpu_cs;
reg         vga_b_cs;
reg         vga_c_cs;
reg         vga_d_cs;
reg         sysctl_cs;

wire        fdd0_inserted;

wire  [7:0] sound_readdata;
wire  [7:0] floppy0_readdata;
wire [31:0] ide0_readdata;
wire [31:0] ide1_readdata;
wire  [7:0] joystick_readdata;
wire  [7:0] pit_readdata;
wire  [7:0] ps2_readdata;
wire  [7:0] rtc_readdata;
wire  [7:0] uart1_readdata;
wire  [7:0] uart2_readdata;
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
	.VGA_FB_EN         (video_fb_en)
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
	uart1_cs      <= ({iobus_address[15:3], 3'd0} == 16'h03F8);
	uart2_cs      <= ({iobus_address[15:3], 3'd0} == 16'h02F8);
	mpu_cs        <= ({iobus_address[15:1], 1'd0} == 16'h0330);
	vga_b_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03B0);
	vga_c_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03C0);
	vga_d_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03D0);
	sysctl_cs     <= ({iobus_address[15:0]      } == 16'h8888);
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
	( uart1_cs                               ) ? uart1_readdata    :
	( uart2_cs                               ) ? uart2_readdata    :
	( mpu_cs                                 ) ? mpu_readdata      :
	( vga_b_cs|vga_c_cs|vga_d_cs             ) ? vga_io_readdata   :
	( joy_cs                                 ) ? joystick_readdata :
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
	.bus_io32          (((ide0_cs | ide1_cs) & ~iobus_address[9]) | sysctl_cs),
	.bus_datasize      (iobus_datasize),
	.bus_writedata     (iobus_writedata),
	.bus_readdata      (ide0_cs ? ide0_readdata : ide1_cs ? ide1_readdata : iobus_readdata8),
	.bus_wait          (ide0_wait | ide1_wait)
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
	.dma_5_writedata   (dma_sb_writedata)
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
	.irq               (irq_6)
);

wire [3:0] ide_address = {iobus_address[9],iobus_address[2:0]};

wire ide0_nodata;
reg  ide0_wait = 0;
always @(posedge clk_sys) begin
	if(iobus_read & ide0_cs & ide0_nodata & !ide_address) ide0_wait <= 1;
	if(~ide0_nodata) ide0_wait <= 0;
end

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
	.irq               (irq_14)
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
	.irq               (irq_15)
);

joystick joystick
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.write             (iobus_write & joy_cs),
	.readdata          (joystick_readdata),

	.dis               (joystick_dis),

	.dig_1             (joystick_dig_1),
	.dig_2             (joystick_dig_2),
	.ana_1             (joystick_ana_1),
	.ana_2             (joystick_ana_2),
	.mode              (joystick_mode)
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
	.irq               (irq_0)
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

	.irq_keyb          (irq_1),
	.irq_mouse         (irq_12)
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

	.memcfg            (memcfg),
	.bootcfg           ({bootcfg[5:2], bootcfg[1:0] ? bootcfg[1:0] : {~fdd0_inserted, fdd0_inserted}}),

	.irq               (irq_8)
);

sound sound
(
	.clk               (clk_sys),
	.clk_opl           (clk_opl),
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

	.vol_l             (vol_l),
	.vol_r             (vol_r),
	.vol_cd_l          (vol_cd_l),
	.vol_cd_r          (vol_cd_r),
	.vol_midi_l        (vol_midi_l),
	.vol_midi_r        (vol_midi_r),
	.vol_line_l        (vol_line_l),
	.vol_line_r        (vol_line_r),
	.vol_spk           (vol_spk),
	.vol_en            (vol_en),

	.sample_l          (sound_sample_l),
	.sample_r          (sound_sample_r),

	.fm_mode           (sound_fm_mode),
	.cms_en            (sound_cms_en),

	.irq_5             (irq_5),
	.irq_7             (irq_7),
	.irq_10            (irq_10)
);

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

	.irq               (irq_4)
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

	.irq               (irq_3)
);

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
	.irq               (irq_9)
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

	.irq               (irq_2)
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
	.interrupt_input   (interrupt)
);

always @* begin
	interrupt = 0;

	interrupt[0]  = irq_0;
	interrupt[1]  = irq_1;
	interrupt[3]  = irq_3;
	interrupt[4]  = irq_4;
	interrupt[5]  = irq_5;
	interrupt[6]  = irq_6;
	interrupt[7]  = irq_7;
	interrupt[8]  = irq_8;
	interrupt[9]  = irq_9 | irq_2;
	interrupt[10] = irq_10;
	interrupt[12] = irq_12;
	interrupt[14] = irq_14;
	interrupt[15] = irq_15;
end

assign mgmt_ide0_cs  = (mgmt_address[15:8] == 8'hF0);
assign mgmt_ide1_cs  = (mgmt_address[15:8] == 8'hF1);
assign mgmt_fdd_cs   = (mgmt_address[15:8] == 8'hF2);
assign mgmt_rtc_cs   = (mgmt_address[15:8] == 8'hF4);
assign mgmt_readdata = mgmt_ide0_cs ? mgmt_ide0_readdata : mgmt_ide1_cs ? mgmt_ide1_readdata : mgmt_fdd_readdata;

endmodule
