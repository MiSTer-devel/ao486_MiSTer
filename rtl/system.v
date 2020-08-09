
module system
(
	input         clk_opl,
	input         clk_sys,
	input         clk_uart,

	input         reset_cpu,
	input         reset_sys,

	input  [27:0] clock_rate,

	output [1:0]  fdd0_request,
	output [2:0]  hdd0_request,
	output [2:0]  hdd1_request,

	input  [13:0] joystick_dig_1,
	input  [13:0] joystick_dig_2,
	input  [15:0] joystick_ana_1,
	input  [15:0] joystick_ana_2,
	input  [1:0]  joystick_mode,
	input         joystick_clk_grav,

	input  [15:0] mgmt_address,
	input         mgmt_read,
	output [15:0] mgmt_readdata,
	input         mgmt_write,
	input  [15:0] mgmt_writedata,
	input         mgmt_active,

	input         ps2_kbclk_in,
	input         ps2_kbdat_in,
	output        ps2_kbclk_out,
	output        ps2_kbdat_out,
	input         ps2_mouseclk_in,
	input         ps2_mousedat_in,
	output        ps2_mouseclk_out,
	output        ps2_mousedat_out,
	output        ps2_misc_a20_enable,
	output        ps2_misc_reset_n,

	input         rtc_memcfg,

	input         serial_rx,
	output        serial_tx,
	input         serial_cts_n,
	input         serial_dcd_n,
	input         serial_dsr_n,
	input         serial_ri_n,
	output        serial_rts_n,
	output        serial_br_out,
	output        serial_dtr_n,

	output [15:0] sound_sample_l,
	output [15:0] sound_sample_r,
	input         sound_fm_mode,

	output        speaker_enable,
	output        speaker_out,

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

wire        iobus_in_read_do;
wire [15:0] iobus_in_read_address;
wire [2:0]  iobus_in_read_length;
wire [31:0] iobus_in_read_data;
wire        iobus_in_read_done;
wire        iobus_in_write_do;
wire [15:0] iobus_in_write_address;
wire [2:0]  iobus_in_write_length;
wire [31:0] iobus_in_write_data;
wire        iobus_in_write_done;
wire        a20_enable;
wire  [7:0] dma_floppy_readdata;
wire        dma_floppy_terminal;
wire  [7:0] dma_floppy_writedata;
wire        dma_floppy_req;
wire        dma_floppy_ack;
wire        dma_soundblaster_req;
wire        dma_soundblaster_terminal;
wire  [7:0] dma_soundblaster_readdata;
wire  [7:0] dma_soundblaster_writedata;
wire        dma_soundblaster_ack;
wire  [7:0] ide_3f6_readdata;
wire  [7:0] ide_3f6_writedata;
wire        ide_3f6_write;
wire        ide_3f6_read;
wire  [7:0] ide_370_readdata;
wire  [7:0] ide_370_writedata;
wire        ide_370_write;
wire        ide_370_read;
wire        interrupt_done;
wire        interrupt_do;
wire  [7:0] interrupt_vector;
wire        speaker_61h_read;
wire        speaker_61h_write;
wire  [7:0] speaker_61h_readdata;
wire  [7:0] speaker_61h_writedata;
wire  [7:0] pc_dma_readdata;
wire        pc_dma_waitrequest;
wire [23:0] pc_dma_address;
wire        pc_dma_read;
wire        pc_dma_readdatavalid;
wire        pc_dma_write;
wire  [7:0] pc_dma_writedata;
wire  [7:0] sound_fm_readdata;
wire  [1:0] sound_fm_address;
wire        sound_fm_read;
wire        sound_fm_write;
wire  [7:0] sound_fm_writedata;
wire  [7:0] floppy0_readdata;
wire  [2:0] floppy0_address;
wire        floppy0_read;
wire        floppy0_write;
wire  [7:0] floppy0_writedata;
wire [31:0] hdd0_readdata;
wire  [2:0] hdd0_address;
wire  [2:0] hdd0_datasize;
wire        hdd0_read;
wire        hdd0_write;
wire [31:0] hdd0_writedata;
wire [31:0] hdd1_readdata;
wire  [2:0] hdd1_address;
wire  [2:0] hdd1_datasize;
wire        hdd1_read;
wire        hdd1_write;
wire [31:0] hdd1_writedata;
wire  [7:0] hddext_0x370_readdata;
wire  [2:0] hddext_0x370_address;
wire        hddext_0x370_read;
wire        hddext_0x370_write;
wire  [7:0] hddext_0x370_writedata;
wire  [7:0] joystick_readdata;
wire        joystick_write;
wire  [7:0] pit_readdata;
wire  [1:0] pit_address;
wire        pit_read;
wire        pit_write;
wire  [7:0] pit_writedata;
wire  [7:0] ps2_io_readdata;
wire  [2:0] ps2_io_address;
wire        ps2_io_read;
wire        ps2_io_write;
wire  [7:0] ps2_io_writedata;
wire  [7:0] rtc_readdata;
wire        rtc_address;
wire        rtc_read;
wire        rtc_write;
wire  [7:0] rtc_writedata;
wire  [7:0] sound_io_readdata;
wire  [3:0] sound_io_address;
wire        sound_io_read;
wire        sound_io_write;
wire  [7:0] sound_io_writedata;
wire  [7:0] uart_io_readdata;
wire  [2:0] uart_io_address;
wire        uart_io_read;
wire        uart_io_write;
wire  [7:0] uart_io_writedata;
wire  [7:0] vga_io_c_readdata;
wire  [3:0] vga_io_c_address;
wire        vga_io_c_read;
wire        vga_io_c_write;
wire  [7:0] vga_io_c_writedata;
wire  [7:0] pc_dma_master_readdata;
wire  [4:0] pc_dma_master_address;
wire        pc_dma_master_read;
wire        pc_dma_master_write;
wire  [7:0] pc_dma_master_writedata;
wire  [7:0] pic_master_readdata;
wire        pic_master_address;
wire        pic_master_read;
wire        pic_master_write;
wire  [7:0] pic_master_writedata;
wire [31:0] mgmt_fdd0_readdata;
wire  [3:0] mgmt_fdd0_address;
wire        mgmt_fdd0_read;
wire        mgmt_fdd0_write;
wire [31:0] mgmt_fdd0_writedata;
wire [31:0] mgmt_hdd0_readdata;
wire  [3:0] mgmt_hdd0_address;
wire        mgmt_hdd0_read;
wire        mgmt_hdd0_write;
wire [31:0] mgmt_hdd0_writedata;
wire [31:0] mgmt_hdd1_readdata;
wire  [3:0] mgmt_hdd1_address;
wire        mgmt_hdd1_read;
wire        mgmt_hdd1_write;
wire [31:0] mgmt_hdd1_writedata;
wire  [7:0] mgmt_rtc_address;
wire        mgmt_rtc_write;
wire  [7:0] mgmt_rtc_writedata;
wire  [7:0] pc_dma_page_readdata;
wire  [3:0] pc_dma_page_address;
wire        pc_dma_page_read;
wire  [7:0] pc_dma_page_writedata;
wire        pc_dma_page_write;
wire  [7:0] pc_dma_slave_readdata;
wire  [3:0] pc_dma_slave_address;
wire        pc_dma_slave_read;
wire  [7:0] pc_dma_slave_writedata;
wire        pc_dma_slave_write;
wire  [7:0] pic_slave_readdata;
wire        pic_slave_address;
wire        pic_slave_read;
wire        pic_slave_write;
wire  [7:0] pic_slave_writedata;
wire  [7:0] ps2_sysctl_readdata;
wire  [3:0] ps2_sysctl_address;
wire        ps2_sysctl_read;
wire        ps2_sysctl_write;
wire  [7:0] ps2_sysctl_writedata;
wire  [7:0] uart_mpu_readdata;
wire        uart_mpu_address;
wire        uart_mpu_read;
wire  [7:0] uart_mpu_writedata;
wire        uart_mpu_write;
wire  [7:0] vga_io_b_readdata;
wire  [3:0] vga_io_b_address;
wire        vga_io_b_read;
wire  [7:0] vga_io_b_writedata;
wire        vga_io_b_write;
wire  [7:0] vga_io_d_readdata;
wire  [3:0] vga_io_d_address;
wire        vga_io_d_read;
wire  [7:0] vga_io_d_writedata;
wire        vga_io_d_write;
wire        irq_9;
wire        irq_0;
wire        irq_8;
wire        irq_14;
wire        irq_6;
wire        irq_15;
wire        irq_2;
wire        irq_5;
wire        irq_4;
wire        irq_1;
wire        irq_12;

reg  [15:0] interrupt_receiver;

wire [29:0] mem_address;
wire [31:0] mem_writedata;
wire [31:0] mem_readdata;
wire [3:0]  mem_byteenable;
wire [3:0]  mem_burstcount;
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
	.CLK              (clk_sys),
	.RESET            (reset_cpu),

	.CPU_ADDR         (mem_address),
	.CPU_DIN          (mem_writedata),
	.CPU_DOUT         (mem_readdata),
	.CPU_DOUT_READY   (mem_readdatavalid),
	.CPU_BE           (mem_byteenable),
	.CPU_BURSTCNT     (mem_burstcount),
	.CPU_BUSY         (mem_waitrequest),
	.CPU_RD           (mem_read),
	.CPU_WE           (mem_write),

	.DDRAM_ADDR       (DDRAM_ADDR),
	.DDRAM_DIN        (DDRAM_DIN),
	.DDRAM_DOUT       (DDRAM_DOUT),
	.DDRAM_DOUT_READY (DDRAM_DOUT_READY),
	.DDRAM_BE         (DDRAM_BE),
	.DDRAM_BURSTCNT   (DDRAM_BURSTCNT),
	.DDRAM_BUSY       (DDRAM_BUSY),
	.DDRAM_RD         (DDRAM_RD),
	.DDRAM_WE         (DDRAM_WE),

	.VGA_ADDR         (vga_address),
	.VGA_DIN          (vga_readdata),
	.VGA_DOUT         (vga_writedata),
	.VGA_RD           (vga_read),
	.VGA_WE           (vga_write),
	.VGA_MODE         (vga_memmode),

	.VGA_WR_SEG       (video_wr_seg),
	.VGA_RD_SEG       (video_rd_seg),
	.VGA_FB_EN        (video_fb_en)
);

ao486 ao486 (
	.clk                  (clk_sys),
	.rst_n                (~reset_cpu),
	.avm_address          (mem_address),
	.avm_writedata        (mem_writedata),
	.avm_byteenable       (mem_byteenable),
	.avm_burstcount       (mem_burstcount),
	.avm_write            (mem_write),
	.avm_read             (mem_read),
	.avm_waitrequest      (mem_waitrequest),
	.avm_readdatavalid    (mem_readdatavalid),
	.avm_readdata         (mem_readdata),
	.interrupt_do         (interrupt_do),
	.interrupt_vector     (interrupt_vector),
	.interrupt_done       (interrupt_done),
	.io_read_do           (iobus_in_read_do),
	.io_read_address      (iobus_in_read_address),
	.io_read_length       (iobus_in_read_length),
	.io_read_data         (iobus_in_read_data),
	.io_read_done         (iobus_in_read_done),
	.io_write_do          (iobus_in_write_do),
	.io_write_address     (iobus_in_write_address),
	.io_write_length      (iobus_in_write_length),
	.io_write_data        (iobus_in_write_data),
	.io_write_done        (iobus_in_write_done),
	.a20_enable           (a20_enable),
	.dma_address          (pc_dma_address),
	.dma_read             (pc_dma_read),
	.dma_readdata         (pc_dma_readdata),
	.dma_readdatavalid    (pc_dma_readdatavalid),
	.dma_waitrequest      (pc_dma_waitrequest),
	.dma_write            (pc_dma_write),
	.dma_writedata        (pc_dma_writedata)
);


iobus iobus (
	.clk                       (clk_sys),
	.in_read_do                (iobus_in_read_do),
	.in_read_address           (iobus_in_read_address),
	.in_read_length            (iobus_in_read_length),
	.in_read_data              (iobus_in_read_data),
	.in_read_done              (iobus_in_read_done),
	.in_write_do               (iobus_in_write_do),
	.in_write_address          (iobus_in_write_address),
	.in_write_length           (iobus_in_write_length),
	.in_write_data             (iobus_in_write_data),
	.in_write_done             (iobus_in_write_done),
	.floppy0_io_address        (floppy0_address),
	.floppy0_io_readdata       (floppy0_readdata),
	.floppy0_io_writedata      (floppy0_writedata),
	.floppy0_io_read           (floppy0_read),
	.floppy0_io_write          (floppy0_write),
	.hdd0_io_address           (hdd0_address),
	.hdd0_io_readdata          (hdd0_readdata),
	.hdd0_io_writedata         (hdd0_writedata),
	.hdd0_io_read              (hdd0_read),
	.hdd0_io_write             (hdd0_write),
	.hdd0_io_data_size         (hdd0_datasize),
	.hdd1_io_address           (hdd1_address),
	.hdd1_io_readdata          (hdd1_readdata),
	.hdd1_io_writedata         (hdd1_writedata),
	.hdd1_io_read              (hdd1_read),
	.hdd1_io_write             (hdd1_write),
	.hdd1_io_data_size         (hdd1_datasize),
	.hddext_0x370_io_address   (hddext_0x370_address),
	.hddext_0x370_io_readdata  (hddext_0x370_readdata),
	.hddext_0x370_io_writedata (hddext_0x370_writedata),
	.hddext_0x370_io_read      (hddext_0x370_read),
	.hddext_0x370_io_write     (hddext_0x370_write),
	.joystick_io_readdata      (joystick_readdata),
	.joystick_io_write         (joystick_write),
	.pc_dma_master_address     (pc_dma_master_address),
	.pc_dma_master_readdata    (pc_dma_master_readdata),
	.pc_dma_master_writedata   (pc_dma_master_writedata),
	.pc_dma_master_read        (pc_dma_master_read),
	.pc_dma_master_write       (pc_dma_master_write),
	.pc_dma_page_address       (pc_dma_page_address),
	.pc_dma_page_readdata      (pc_dma_page_readdata),
	.pc_dma_page_writedata     (pc_dma_page_writedata),
	.pc_dma_page_read          (pc_dma_page_read),
	.pc_dma_page_write         (pc_dma_page_write),
	.pc_dma_slave_address      (pc_dma_slave_address),
	.pc_dma_slave_readdata     (pc_dma_slave_readdata),
	.pc_dma_slave_writedata    (pc_dma_slave_writedata),
	.pc_dma_slave_read         (pc_dma_slave_read),
	.pc_dma_slave_write        (pc_dma_slave_write),
	.pic_master_address        (pic_master_address),
	.pic_master_readdata       (pic_master_readdata),
	.pic_master_writedata      (pic_master_writedata),
	.pic_master_read           (pic_master_read),
	.pic_master_write          (pic_master_write),
	.pic_slave_address         (pic_slave_address),
	.pic_slave_readdata        (pic_slave_readdata),
	.pic_slave_writedata       (pic_slave_writedata),
	.pic_slave_read            (pic_slave_read),
	.pic_slave_write           (pic_slave_write),
	.pit_io_address            (pit_address),
	.pit_io_readdata           (pit_readdata),
	.pit_io_writedata          (pit_writedata),
	.pit_io_read               (pit_read),
	.pit_io_write              (pit_write),
	.ps2_io_address            (ps2_io_address),
	.ps2_io_readdata           (ps2_io_readdata),
	.ps2_io_writedata          (ps2_io_writedata),
	.ps2_io_read               (ps2_io_read),
	.ps2_io_write              (ps2_io_write),
	.ps2_sysctl_address        (ps2_sysctl_address),
	.ps2_sysctl_readdata       (ps2_sysctl_readdata),
	.ps2_sysctl_writedata      (ps2_sysctl_writedata),
	.ps2_sysctl_read           (ps2_sysctl_read),
	.ps2_sysctl_write          (ps2_sysctl_write),
	.rtc_io_address            (rtc_address),
	.rtc_io_readdata           (rtc_readdata),
	.rtc_io_writedata          (rtc_writedata),
	.rtc_io_read               (rtc_read),
	.rtc_io_write              (rtc_write),
	.sound_io_address          (sound_io_address),
	.sound_io_readdata         (sound_io_readdata),
	.sound_io_writedata        (sound_io_writedata),
	.sound_io_read             (sound_io_read),
	.sound_io_write            (sound_io_write),
	.sound_fm_address          (sound_fm_address),
	.sound_fm_readdata         (sound_fm_readdata),
	.sound_fm_writedata        (sound_fm_writedata),
	.sound_fm_read             (sound_fm_read),
	.sound_fm_write            (sound_fm_write),
	.uart_io_address           (uart_io_address),
	.uart_io_readdata          (uart_io_readdata),
	.uart_io_writedata         (uart_io_writedata),
	.uart_io_read              (uart_io_read),
	.uart_io_write             (uart_io_write),
	.uart_mpu_address          (uart_mpu_address),
	.uart_mpu_readdata         (uart_mpu_readdata),
	.uart_mpu_writedata        (uart_mpu_writedata),
	.uart_mpu_read             (uart_mpu_read),
	.uart_mpu_write            (uart_mpu_write),
	.vga_io_b_address          (vga_io_b_address),
	.vga_io_b_readdata         (vga_io_b_readdata),
	.vga_io_b_writedata        (vga_io_b_writedata),
	.vga_io_b_read             (vga_io_b_read),
	.vga_io_b_write            (vga_io_b_write),
	.vga_io_c_address          (vga_io_c_address),
	.vga_io_c_readdata         (vga_io_c_readdata),
	.vga_io_c_writedata        (vga_io_c_writedata),
	.vga_io_c_read             (vga_io_c_read),
	.vga_io_c_write            (vga_io_c_write),
	.vga_io_d_address          (vga_io_d_address),
	.vga_io_d_readdata         (vga_io_d_readdata),
	.vga_io_d_writedata        (vga_io_d_writedata),
	.vga_io_d_read             (vga_io_d_read),
	.vga_io_d_write            (vga_io_d_write),
	.reset                     (reset_sys)
);

floppy floppy0 (
	.clk                  (clk_sys),
	.io_address           (floppy0_address),
	.io_read              (floppy0_read),
	.io_readdata          (floppy0_readdata),
	.io_write             (floppy0_write),
	.io_writedata         (floppy0_writedata),
	.mgmt_address         (mgmt_fdd0_address),
	.mgmt_write           (mgmt_fdd0_write),
	.mgmt_writedata       (mgmt_fdd0_writedata),
	.mgmt_read            (mgmt_fdd0_read),
	.mgmt_readdata        (mgmt_fdd0_readdata),
	.rst_n                (~reset_sys),
	.dma_floppy_req       (dma_floppy_req),
	.dma_floppy_ack       (dma_floppy_ack),
	.dma_floppy_terminal  (dma_floppy_terminal),
	.dma_floppy_readdata  (dma_floppy_readdata),
	.dma_floppy_writedata (dma_floppy_writedata),
	.ide_3f6_read         (ide_3f6_read),
	.ide_3f6_readdata     (ide_3f6_readdata),
	.ide_3f6_write        (ide_3f6_write),
	.ide_3f6_writedata    (ide_3f6_writedata),
	.irq                  (irq_6),
	.request              (fdd0_request),
	.clock_rate           (clock_rate)
);

hdd hdd0 (
	.clk               (clk_sys),
	.io_address        (hdd0_address),
	.io_data_size      (hdd0_datasize),
	.io_read           (hdd0_read),
	.io_readdata       (hdd0_readdata),
	.io_write          (hdd0_write),
	.io_writedata      (hdd0_writedata),
	.mgmt_address      (mgmt_hdd0_address),
	.mgmt_write        (mgmt_hdd0_write),
	.mgmt_writedata    (mgmt_hdd0_writedata),
	.mgmt_read         (mgmt_hdd0_read),
	.mgmt_readdata     (mgmt_hdd0_readdata),
	.rst_n             (~reset_sys),
	.irq               (irq_14),
	.ide_3f6_read      (ide_3f6_read),
	.ide_3f6_readdata  (ide_3f6_readdata),
	.ide_3f6_write     (ide_3f6_write),
	.ide_3f6_writedata (ide_3f6_writedata),
	.request           (hdd0_request)
);

hdd hdd1 (
	.clk               (clk_sys),
	.io_address        (hdd1_address),
	.io_data_size      (hdd1_datasize),
	.io_read           (hdd1_read),
	.io_readdata       (hdd1_readdata),
	.io_write          (hdd1_write),
	.io_writedata      (hdd1_writedata),
	.mgmt_address      (mgmt_hdd1_address),
	.mgmt_write        (mgmt_hdd1_write),
	.mgmt_writedata    (mgmt_hdd1_writedata),
	.mgmt_read         (mgmt_hdd1_read),
	.mgmt_readdata     (mgmt_hdd1_readdata),
	.rst_n             (~reset_sys),
	.irq               (irq_15),
	.ide_3f6_read      (ide_370_read),
	.ide_3f6_readdata  (ide_370_readdata),
	.ide_3f6_write     (ide_370_write),
	.ide_3f6_writedata (ide_370_writedata),
	.request           (hdd1_request)
);

hddext hddext_0x370 (
	.clk               (clk_sys),
	.io_address        (hddext_0x370_address),
	.io_read           (hddext_0x370_read),
	.io_readdata       (hddext_0x370_readdata),
	.io_write          (hddext_0x370_write),
	.io_writedata      (hddext_0x370_writedata),
	.rst_n             (~reset_sys),
	.ide_3f6_read      (ide_370_read),
	.ide_3f6_readdata  (ide_370_readdata),
	.ide_3f6_write     (ide_370_write),
	.ide_3f6_writedata (ide_370_writedata)
);

joystick joystick_0 (
	.rst_n     (~reset_sys),
	.clk       (clk_sys),
	.dig_1     (joystick_dig_1),
	.dig_2     (joystick_dig_2),
	.ana_1     (joystick_ana_1),
	.ana_2     (joystick_ana_2),
	.mode      (joystick_mode),
	.clk_grav  (joystick_clk_grav),
	.readdata  (joystick_readdata),
	.write     (joystick_write)
);

mgmt mgmt (
	.clk            (clk_sys),
	.in_address     (mgmt_address),
	.in_read        (mgmt_read),
	.in_readdata    (mgmt_readdata),
	.in_write       (mgmt_write),
	.in_writedata   (mgmt_writedata),
	.in_active      (mgmt_active),
	.hdd0_address   (mgmt_hdd0_address),
	.hdd0_readdata  (mgmt_hdd0_readdata),
	.hdd0_read      (mgmt_hdd0_read),
	.hdd0_write     (mgmt_hdd0_write),
	.hdd0_writedata (mgmt_hdd0_writedata),
	.hdd1_address   (mgmt_hdd1_address),
	.hdd1_readdata  (mgmt_hdd1_readdata),
	.hdd1_read      (mgmt_hdd1_read),
	.hdd1_write     (mgmt_hdd1_write),
	.hdd1_writedata (mgmt_hdd1_writedata),
	.fdd0_address   (mgmt_fdd0_address),
	.fdd0_readdata  (mgmt_fdd0_readdata),
	.fdd0_read      (mgmt_fdd0_read),
	.fdd0_write     (mgmt_fdd0_write),
	.fdd0_writedata (mgmt_fdd0_writedata),
	.rtc_address    (mgmt_rtc_address),
	.rtc_write      (mgmt_rtc_write),
	.rtc_writedata  (mgmt_rtc_writedata)
);

pc_dma pc_dma (
	.clk                        (clk_sys),
	.slave_address              (pc_dma_slave_address),
	.slave_read                 (pc_dma_slave_read),
	.slave_readdata             (pc_dma_slave_readdata),
	.slave_write                (pc_dma_slave_write),
	.slave_writedata            (pc_dma_slave_writedata),
	.page_address               (pc_dma_page_address),
	.page_read                  (pc_dma_page_read),
	.page_readdata              (pc_dma_page_readdata),
	.page_write                 (pc_dma_page_write),
	.page_writedata             (pc_dma_page_writedata),
	.master_address             (pc_dma_master_address),
	.master_read                (pc_dma_master_read),
	.master_readdata            (pc_dma_master_readdata),
	.master_write               (pc_dma_master_write),
	.master_writedata           (pc_dma_master_writedata),
	.rst_n                      (~reset_sys),
	.dma_floppy_req             (dma_floppy_req),
	.dma_floppy_ack             (dma_floppy_ack),
	.dma_floppy_terminal        (dma_floppy_terminal),
	.dma_floppy_readdata        (dma_floppy_readdata),
	.dma_floppy_writedata       (dma_floppy_writedata),
	.dma_soundblaster_req       (dma_soundblaster_req),
	.dma_soundblaster_ack       (dma_soundblaster_ack),
	.dma_soundblaster_terminal  (dma_soundblaster_terminal),
	.dma_soundblaster_readdata  (dma_soundblaster_readdata),
	.dma_soundblaster_writedata (dma_soundblaster_writedata),
	.avm_address                (pc_dma_address),
	.avm_waitrequest            (pc_dma_waitrequest),
	.avm_read                   (pc_dma_read),
	.avm_readdatavalid          (pc_dma_readdatavalid),
	.avm_readdata               (pc_dma_readdata),
	.avm_write                  (pc_dma_write),
	.avm_writedata              (pc_dma_writedata)
);

pic pic (
	.clk              (clk_sys),
	.master_address   (pic_master_address),
	.master_read      (pic_master_read),
	.master_readdata  (pic_master_readdata),
	.master_write     (pic_master_write),
	.master_writedata (pic_master_writedata),
	.slave_address    (pic_slave_address),
	.slave_read       (pic_slave_read),
	.slave_readdata   (pic_slave_readdata),
	.slave_write      (pic_slave_write),
	.slave_writedata  (pic_slave_writedata),
	.rst_n            (~reset_sys),
	.interrupt_vector (interrupt_vector),
	.interrupt_done   (interrupt_done),
	.interrupt_do     (interrupt_do),
	.interrupt_input  (interrupt_receiver)
);

pit pit (
	.clk                   (clk_sys),
	.io_address            (pit_address),
	.io_read               (pit_read),
	.io_readdata           (pit_readdata),
	.io_write              (pit_write),
	.io_writedata          (pit_writedata),
	.rst_n                 (~reset_sys),
	.speaker_61h_read      (speaker_61h_read),
	.speaker_61h_readdata  (speaker_61h_readdata),
	.speaker_61h_write     (speaker_61h_write),
	.speaker_61h_writedata (speaker_61h_writedata),
	.speaker_enable        (speaker_enable),
	.speaker_out           (speaker_out),
	.clock_rate            (clock_rate),
	.irq                   (irq_0)
);

ps2 ps2 (
	.clk                   (clk_sys),
	.io_address            (ps2_io_address),
	.io_read               (ps2_io_read),
	.io_readdata           (ps2_io_readdata),
	.io_write              (ps2_io_write),
	.io_writedata          (ps2_io_writedata),
	.sysctl_address        (ps2_sysctl_address),
	.sysctl_read           (ps2_sysctl_read),
	.sysctl_readdata       (ps2_sysctl_readdata),
	.sysctl_write          (ps2_sysctl_write),
	.sysctl_writedata      (ps2_sysctl_writedata),
	.rst_n                 (~reset_sys),
	.irq_mouse             (irq_12),
	.ps2_kbclk             (ps2_kbclk_in),
	.ps2_kbdat             (ps2_kbdat_in),
	.ps2_kbclk_out         (ps2_kbclk_out),
	.ps2_kbdat_out         (ps2_kbdat_out),
	.ps2_mouseclk          (ps2_mouseclk_in),
	.ps2_mousedat          (ps2_mousedat_in),
	.ps2_mouseclk_out      (ps2_mouseclk_out),
	.ps2_mousedat_out      (ps2_mousedat_out),
	.irq_keyb              (irq_1),
	.speaker_61h_read      (speaker_61h_read),
	.speaker_61h_readdata  (speaker_61h_readdata),
	.speaker_61h_write     (speaker_61h_write),
	.speaker_61h_writedata (speaker_61h_writedata),
	.output_a20_enable     (ps2_misc_a20_enable),
	.output_reset_n        (ps2_misc_reset_n),
	.a20_enable            (a20_enable)
);

rtc rtc (
	.clk            (clk_sys),
	.io_address     (rtc_address),
	.io_read        (rtc_read),
	.io_readdata    (rtc_readdata),
	.io_write       (rtc_write),
	.io_writedata   (rtc_writedata),
	.mgmt_address   (mgmt_rtc_address),
	.mgmt_write     (mgmt_rtc_write),
	.mgmt_writedata (mgmt_rtc_writedata),
	.rst_n          (~reset_sys),
	.irq            (irq_8),
	.rtc_memcfg     (rtc_memcfg),
	.clock_rate     (clock_rate)
);

sound sound (
	.clk                        (clk_sys),
	.clk_opl                    (clk_opl),
	.io_address                 (sound_io_address),
	.io_read                    (sound_io_read),
	.io_readdata                (sound_io_readdata),
	.io_write                   (sound_io_write),
	.io_writedata               (sound_io_writedata),
	.fm_address                 (sound_fm_address),
	.fm_read                    (sound_fm_read),
	.fm_readdata                (sound_fm_readdata),
	.fm_write                   (sound_fm_write),
	.fm_writedata               (sound_fm_writedata),
	.rst_n                      (~reset_sys),
	.irq                        (irq_5),
	.dma_soundblaster_req       (dma_soundblaster_req),
	.dma_soundblaster_ack       (dma_soundblaster_ack),
	.dma_soundblaster_terminal  (dma_soundblaster_terminal),
	.dma_soundblaster_readdata  (dma_soundblaster_readdata),
	.dma_soundblaster_writedata (dma_soundblaster_writedata),
	.sample_l                   (sound_sample_l),
	.sample_r                   (sound_sample_r),
	.fm_mode                    (sound_fm_mode),
	.clock_rate                 (clock_rate)
);

uart uart (
	.clk           (clk_sys),
	.br_clk        (clk_uart),
	.reset         (reset_sys|reset_cpu),
	.address       (uart_io_address),
	.read          (uart_io_read),
	.readdata      (uart_io_readdata),
	.write         (uart_io_write),
	.writedata     (uart_io_writedata),
	.rx            (serial_rx),
	.tx            (serial_tx),
	.cts_n         (serial_cts_n),
	.dcd_n         (serial_dcd_n),
	.dsr_n         (serial_dsr_n),
	.ri_n          (serial_ri_n),
	.rts_n         (serial_rts_n),
	.br_out        (serial_br_out),
	.dtr_n         (serial_dtr_n),
	.mpu_address   (uart_mpu_address),
	.mpu_read      (uart_mpu_read),
	.mpu_readdata  (uart_mpu_readdata),
	.mpu_write     (uart_mpu_write),
	.mpu_writedata (uart_mpu_writedata),
	.irq_mpu       (irq_9),
	.irq_uart      (irq_4)
);

vga vga (
	.clk_sys        (clk_sys),
	.io_b_address   (vga_io_b_address),
	.io_b_read      (vga_io_b_read),
	.io_b_readdata  (vga_io_b_readdata),
	.io_b_write     (vga_io_b_write),
	.io_b_writedata (vga_io_b_writedata),
	.io_c_address   (vga_io_c_address),
	.io_c_read      (vga_io_c_read),
	.io_c_readdata  (vga_io_c_readdata),
	.io_c_write     (vga_io_c_write),
	.io_c_writedata (vga_io_c_writedata),
	.io_d_address   (vga_io_d_address),
	.io_d_read      (vga_io_d_read),
	.io_d_readdata  (vga_io_d_readdata),
	.io_d_write     (vga_io_d_write),
	.io_d_writedata (vga_io_d_writedata),
	.mem_address    (vga_address),
	.mem_read       (vga_read),
	.mem_readdata   (vga_readdata),
	.mem_write      (vga_write),
	.mem_writedata  (vga_writedata),
	.rst_n          (~reset_sys),
	.vga_ce         (video_ce),
	.vga_blank_n    (video_blank_n),
	.vga_horiz_sync (video_hsync),
	.vga_vert_sync  (video_vsync),
	.vga_r          (video_r),
	.vga_g          (video_g),
	.vga_b          (video_b),
	.vga_f60        (video_f60),
	.vga_memmode    (vga_memmode),
	.vga_pal_a      (video_pal_a),
	.vga_pal_d      (video_pal_d),
	.vga_pal_we     (video_pal_we),
	.vga_start_addr (video_start_addr),
	.vga_wr_seg     (video_wr_seg),
	.vga_rd_seg     (video_rd_seg),
	.vga_width      (video_width),
	.vga_height     (video_height),
	.vga_flags      (video_flags),
	.vga_stride     (video_stride),
	.vga_off        (video_off),
	.clock_rate     (clock_rate),
	.irq            (irq_2)
);

always @* begin
	interrupt_receiver = 0;

	interrupt_receiver[0]  = irq_0;
	interrupt_receiver[1]  = irq_1;
	interrupt_receiver[2]  = irq_2;
	interrupt_receiver[4]  = irq_4;
	interrupt_receiver[5]  = irq_5;
	interrupt_receiver[6]  = irq_6;
	interrupt_receiver[8]  = irq_8;
	interrupt_receiver[9]  = irq_9;
	interrupt_receiver[12] = irq_12; 
	interrupt_receiver[14] = irq_14;
	interrupt_receiver[15] = irq_15;
end

endmodule
