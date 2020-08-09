
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
wire        interrupt_done;
wire        interrupt_do;
wire  [7:0] interrupt_vector;
reg  [15:0] interrupt_receiver;
wire        irq_0, irq_1, irq_2, irq_4, irq_5, irq_6, irq_8, irq_9, irq_12, irq_14, irq_15;

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
reg   [7:0] iobus_readdata8;

reg         hdd0_cs;
reg         hdd1_cs;
reg         floppy0_cs;
reg         hdd1_ext_cs;
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
reg         uart_cs;
reg         mpu_cs;
reg         vga_b_cs;
reg         vga_c_cs;
reg         vga_d_cs;

wire  [7:0] sound_fm_readdata;
wire  [7:0] sound_io_readdata;
wire  [7:0] floppy0_readdata;
wire [31:0] hdd0_readdata;
wire [31:0] hdd1_readdata;
wire  [7:0] hdd1_ext_readdata;
wire  [7:0] joystick_readdata;
wire  [7:0] pit_readdata;
wire  [7:0] ps2_io_readdata;
wire  [7:0] ps2_sysctl_readdata;
wire  [7:0] rtc_readdata;
wire  [7:0] uart_readdata;
wire  [7:0] pc_dma_master_readdata;
wire  [7:0] pc_dma_page_readdata;
wire  [7:0] pc_dma_slave_readdata;
wire  [7:0] pic_master_readdata;
wire  [7:0] pic_slave_readdata;
wire  [7:0] vga_io_c_readdata;
wire  [7:0] vga_io_b_readdata;
wire  [7:0] vga_io_d_readdata;

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

ao486 ao486
(
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

	.io_read_do           (cpu_io_read_do),
	.io_read_address      (cpu_io_read_address),
	.io_read_length       (cpu_io_read_length),
	.io_read_data         (cpu_io_read_data),
	.io_read_done         (cpu_io_read_done),
	.io_write_do          (cpu_io_write_do),
	.io_write_address     (cpu_io_write_address),
	.io_write_length      (cpu_io_write_length),
	.io_write_data        (cpu_io_write_data),
	.io_write_done        (cpu_io_write_done),

	.a20_enable           (a20_enable),

	.dma_address          (pc_dma_address),
	.dma_read             (pc_dma_read),
	.dma_readdata         (pc_dma_readdata),
	.dma_readdatavalid    (pc_dma_readdatavalid),
	.dma_waitrequest      (pc_dma_waitrequest),
	.dma_write            (pc_dma_write),
	.dma_writedata        (pc_dma_writedata)
);

always @(posedge clk_sys) begin
	hdd0_cs       <= ({iobus_address[15:3], 3'd0} == 16'h01F0);
	hdd1_cs       <= ({iobus_address[15:3], 3'd0} == 16'h0170);
	joy_cs        <= ({iobus_address[15:0]      } == 16'h0201);
	floppy0_cs    <= ({iobus_address[15:3], 3'd0} == 16'h03F0);
	hdd1_ext_cs   <= ({iobus_address[15:3], 3'd0} == 16'h0370);
	dma_master_cs <= ({iobus_address[15:5], 5'd0} == 16'h00C0);
	dma_page_cs   <= ({iobus_address[15:4], 4'd0} == 16'h0080);
	dma_slave_cs  <= ({iobus_address[15:4], 4'd0} == 16'h0000);
	pic_master_cs <= ({iobus_address[15:1], 1'd0} == 16'h0020);
	pic_slave_cs  <= ({iobus_address[15:1], 1'd0} == 16'h00A0);
	pit_cs        <= ({iobus_address[15:2], 2'd0} == 16'h0040);
	ps2_io_cs     <= ({iobus_address[15:3], 3'd0} == 16'h0060);
	ps2_ctl_cs    <= ({iobus_address[15:4], 4'd0} == 16'h0090);
	rtc_cs        <= ({iobus_address[15:1], 1'd0} == 16'h0070);
	fm_cs         <= ({iobus_address[15:2], 2'd0} == 16'h0388);
	sb_cs         <= ({iobus_address[15:4], 4'd0} == 16'h0220);
	uart_cs       <= ({iobus_address[15:3], 3'd0} == 16'h03F8);
	mpu_cs        <= ({iobus_address[15:1], 1'd0} == 16'h0330);
	vga_b_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03B0);
	vga_c_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03C0);
	vga_d_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03D0);
end

always @* begin
	     if(floppy0_cs    ) iobus_readdata8 = floppy0_readdata;
	else if(hdd1_ext_cs   ) iobus_readdata8 = hdd1_ext_readdata;
	else if(dma_master_cs ) iobus_readdata8 = pc_dma_master_readdata;
	else if(dma_page_cs   ) iobus_readdata8 = pc_dma_page_readdata;
	else if(dma_slave_cs  ) iobus_readdata8 = pc_dma_slave_readdata;
	else if(pic_master_cs ) iobus_readdata8 = pic_master_readdata;
	else if(pic_slave_cs  ) iobus_readdata8 = pic_slave_readdata;
	else if(pit_cs        ) iobus_readdata8 = pit_readdata;
	else if(ps2_io_cs     ) iobus_readdata8 = ps2_io_readdata;
	else if(ps2_ctl_cs    ) iobus_readdata8 = ps2_sysctl_readdata;
	else if(rtc_cs        ) iobus_readdata8 = rtc_readdata;
	else if(fm_cs         ) iobus_readdata8 = sound_fm_readdata;
	else if(sb_cs         ) iobus_readdata8 = sound_io_readdata;
	else if(uart_cs|mpu_cs) iobus_readdata8 = uart_readdata;
	else if(vga_b_cs      ) iobus_readdata8 = vga_io_b_readdata;
	else if(vga_c_cs      ) iobus_readdata8 = vga_io_c_readdata;
	else if(vga_d_cs      ) iobus_readdata8 = vga_io_d_readdata;
	else if(joy_cs        ) iobus_readdata8 = joystick_readdata;
	else                    iobus_readdata8 = 8'hFF;
end

iobus iobus
(
	.clk               (clk_sys),
	.reset             (reset_sys),

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
	.bus_io32          (hdd0_cs | hdd1_cs),
	.bus_datasize      (iobus_datasize),
	.bus_writedata     (iobus_writedata),
	.bus_readdata8     (iobus_readdata8),
	.bus_readdata32    (hdd0_cs ? hdd0_readdata : hdd1_readdata)
);

floppy floppy0
(
	.clk                  (clk_sys),
	.rst_n                (~reset_sys),

	.clock_rate           (clock_rate),

	.io_address           (iobus_address[2:0]),
	.io_read              (iobus_read & floppy0_cs),
	.io_readdata          (floppy0_readdata),
	.io_write             (iobus_write & floppy0_cs),
	.io_writedata         (iobus_writedata[7:0]),

	.dma_floppy_req       (dma_floppy_req),
	.dma_floppy_ack       (dma_floppy_ack),
	.dma_floppy_terminal  (dma_floppy_terminal),
	.dma_floppy_readdata  (dma_floppy_readdata),
	.dma_floppy_writedata (dma_floppy_writedata),

	.ide_3f6_read         (ide_3f6_read),
	.ide_3f6_readdata     (ide_3f6_readdata),
	.ide_3f6_write        (ide_3f6_write),
	.ide_3f6_writedata    (ide_3f6_writedata),

	.mgmt_address         (mgmt_fdd0_address),
	.mgmt_write           (mgmt_fdd0_write),
	.mgmt_writedata       (mgmt_fdd0_writedata),
	.mgmt_read            (mgmt_fdd0_read),
	.mgmt_readdata        (mgmt_fdd0_readdata),

	.request              (fdd0_request),
	.irq                  (irq_6)
);

hdd hdd0
(
	.clk               (clk_sys),
	.rst_n             (~reset_sys),

	.io_address        (iobus_address[2:0]),
	.io_data_size      (iobus_datasize),
	.io_read           (iobus_read & hdd0_cs),
	.io_readdata       (hdd0_readdata),
	.io_write          (iobus_write & hdd0_cs),
	.io_writedata      (iobus_writedata),

	.ide_3f6_read      (ide_3f6_read),
	.ide_3f6_readdata  (ide_3f6_readdata),
	.ide_3f6_write     (ide_3f6_write),
	.ide_3f6_writedata (ide_3f6_writedata),

	.mgmt_address      (mgmt_hdd0_address),
	.mgmt_write        (mgmt_hdd0_write),
	.mgmt_writedata    (mgmt_hdd0_writedata),
	.mgmt_read         (mgmt_hdd0_read),
	.mgmt_readdata     (mgmt_hdd0_readdata),

	.request           (hdd0_request),
	.irq               (irq_14)
);

hdd hdd1
(
	.clk               (clk_sys),
	.rst_n             (~reset_sys),

	.io_address        (iobus_address[2:0]),
	.io_data_size      (iobus_datasize),
	.io_read           (iobus_read & hdd1_cs),
	.io_readdata       (hdd1_readdata),
	.io_write          (iobus_write & hdd1_cs),
	.io_writedata      (iobus_writedata),

	.ide_3f6_read      (ide_370_read),
	.ide_3f6_readdata  (ide_370_readdata),
	.ide_3f6_write     (ide_370_write),
	.ide_3f6_writedata (ide_370_writedata),

	.mgmt_address      (mgmt_hdd1_address),
	.mgmt_write        (mgmt_hdd1_write),
	.mgmt_writedata    (mgmt_hdd1_writedata),
	.mgmt_read         (mgmt_hdd1_read),
	.mgmt_readdata     (mgmt_hdd1_readdata),

	.request           (hdd1_request),
	.irq               (irq_15)
);

hddext hdd1_ext
(
	.clk               (clk_sys),
	.rst_n             (~reset_sys),

	.io_address        (iobus_address[2:0]),
	.io_read           (iobus_read & hdd1_ext_cs),
	.io_readdata       (hdd1_ext_readdata),
	.io_write          (iobus_write & hdd1_ext_cs),
	.io_writedata      (iobus_writedata[7:0]),

	.ide_3f6_read      (ide_370_read),
	.ide_3f6_readdata  (ide_370_readdata),
	.ide_3f6_write     (ide_370_write),
	.ide_3f6_writedata (ide_370_writedata)
);

joystick joystick
(
	.clk       (clk_sys),
	.rst_n     (~reset_sys),

	.clk_grav  (joystick_clk_grav),

	.readdata  (joystick_readdata),
	.write     (iobus_write & joy_cs),

	.dig_1     (joystick_dig_1),
	.dig_2     (joystick_dig_2),
	.ana_1     (joystick_ana_1),
	.ana_2     (joystick_ana_2),
	.mode      (joystick_mode)
);

mgmt mgmt
(
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

pc_dma pc_dma
(
	.clk                        (clk_sys),
	.rst_n                      (~reset_sys),

	.avm_address                (pc_dma_address),
	.avm_waitrequest            (pc_dma_waitrequest),
	.avm_read                   (pc_dma_read),
	.avm_readdatavalid          (pc_dma_readdatavalid),
	.avm_readdata               (pc_dma_readdata),
	.avm_write                  (pc_dma_write),
	.avm_writedata              (pc_dma_writedata),

	.master_address             (iobus_address[4:0]),
	.master_read                (iobus_read & dma_master_cs),
	.master_readdata            (pc_dma_master_readdata),
	.master_write               (iobus_write & dma_master_cs),
	.master_writedata           (iobus_writedata[7:0]),

	.slave_address              (iobus_address[3:0]),
	.slave_read                 (iobus_read & dma_slave_cs),
	.slave_readdata             (pc_dma_slave_readdata),
	.slave_write                (iobus_write & dma_slave_cs),
	.slave_writedata            (iobus_writedata[7:0]),

	.page_address               (iobus_address[3:0]),
	.page_read                  (iobus_read & dma_page_cs),
	.page_readdata              (pc_dma_page_readdata),
	.page_write                 (iobus_write & dma_page_cs),
	.page_writedata             (iobus_writedata[7:0]),

	.dma_floppy_req             (dma_floppy_req),
	.dma_floppy_ack             (dma_floppy_ack),
	.dma_floppy_terminal        (dma_floppy_terminal),
	.dma_floppy_readdata        (dma_floppy_readdata),
	.dma_floppy_writedata       (dma_floppy_writedata),

	.dma_soundblaster_req       (dma_soundblaster_req),
	.dma_soundblaster_ack       (dma_soundblaster_ack),
	.dma_soundblaster_terminal  (dma_soundblaster_terminal),
	.dma_soundblaster_readdata  (dma_soundblaster_readdata),
	.dma_soundblaster_writedata (dma_soundblaster_writedata)
);

pic pic
(
	.clk              (clk_sys),
	.rst_n            (~reset_sys),

	.master_address   (iobus_address[0]),
	.master_read      (iobus_read & pic_master_cs),
	.master_readdata  (pic_master_readdata),
	.master_write     (iobus_write & pic_master_cs),
	.master_writedata (iobus_writedata[7:0]),

	.slave_address    (iobus_address[0]),
	.slave_read       (iobus_read & pic_slave_cs),
	.slave_readdata   (pic_slave_readdata),
	.slave_write      (iobus_write & pic_slave_cs),
	.slave_writedata  (iobus_writedata[7:0]),

	.interrupt_vector (interrupt_vector),
	.interrupt_done   (interrupt_done),
	.interrupt_do     (interrupt_do),
	.interrupt_input  (interrupt_receiver)
);

pit pit
(
	.clk                   (clk_sys),
	.rst_n                 (~reset_sys),

	.clock_rate            (clock_rate),

	.io_address            (iobus_address[1:0]),
	.io_read               (iobus_read & pit_cs),
	.io_readdata           (pit_readdata),
	.io_write              (iobus_write & pit_cs),
	.io_writedata          (iobus_writedata[7:0]),

	.speaker_61h_read      (speaker_61h_read),
	.speaker_61h_readdata  (speaker_61h_readdata),
	.speaker_61h_write     (speaker_61h_write),
	.speaker_61h_writedata (speaker_61h_writedata),
	.speaker_enable        (speaker_enable),
	.speaker_out           (speaker_out),

	.irq                   (irq_0)
);

ps2 ps2
(
	.clk                   (clk_sys),
	.rst_n                 (~reset_sys),

	.io_address            (iobus_address[2:0]),
	.io_read               (iobus_read & ps2_io_cs),
	.io_readdata           (ps2_io_readdata),
	.io_write              (iobus_write & ps2_io_cs),
	.io_writedata          (iobus_writedata[7:0]),

	.sysctl_address        (iobus_address[3:0]),
	.sysctl_read           (iobus_read & ps2_ctl_cs),
	.sysctl_readdata       (ps2_sysctl_readdata),
	.sysctl_write          (iobus_write & ps2_ctl_cs),
	.sysctl_writedata      (iobus_writedata[7:0]),

	.ps2_kbclk             (ps2_kbclk_in),
	.ps2_kbdat             (ps2_kbdat_in),
	.ps2_kbclk_out         (ps2_kbclk_out),
	.ps2_kbdat_out         (ps2_kbdat_out),

	.ps2_mouseclk          (ps2_mouseclk_in),
	.ps2_mousedat          (ps2_mousedat_in),
	.ps2_mouseclk_out      (ps2_mouseclk_out),
	.ps2_mousedat_out      (ps2_mousedat_out),

	.speaker_61h_read      (speaker_61h_read),
	.speaker_61h_readdata  (speaker_61h_readdata),
	.speaker_61h_write     (speaker_61h_write),
	.speaker_61h_writedata (speaker_61h_writedata),

	.output_a20_enable     (ps2_misc_a20_enable),
	.output_reset_n        (ps2_misc_reset_n),
	.a20_enable            (a20_enable),

	.irq_keyb              (irq_1),
	.irq_mouse             (irq_12)
);

rtc rtc
(
	.clk            (clk_sys),
	.rst_n          (~reset_sys),

	.clock_rate     (clock_rate),

	.io_address     (iobus_address[0]),
	.io_read        (iobus_read & rtc_cs),
	.io_readdata    (rtc_readdata),
	.io_write       (iobus_write & rtc_cs),
	.io_writedata   (iobus_writedata[7:0]),

	.mgmt_address   (mgmt_rtc_address),
	.mgmt_write     (mgmt_rtc_write),
	.mgmt_writedata (mgmt_rtc_writedata),

	.rtc_memcfg     (rtc_memcfg),

	.irq            (irq_8)
);

sound sound
(
	.clk                        (clk_sys),
	.clk_opl                    (clk_opl),
	.rst_n                      (~reset_sys),

	.clock_rate                 (clock_rate),

	.io_address                 (iobus_address[3:0]),
	.io_read                    (iobus_read & sb_cs),
	.io_readdata                (sound_io_readdata),
	.io_write                   (iobus_write & sb_cs),
	.io_writedata               (iobus_writedata[7:0]),

	.fm_address                 (iobus_address[1:0]),
	.fm_read                    (iobus_read & fm_cs),
	.fm_readdata                (sound_fm_readdata),
	.fm_write                   (iobus_write & fm_cs),
	.fm_writedata               (iobus_writedata[7:0]),

	.dma_soundblaster_req       (dma_soundblaster_req),
	.dma_soundblaster_ack       (dma_soundblaster_ack),
	.dma_soundblaster_terminal  (dma_soundblaster_terminal),
	.dma_soundblaster_readdata  (dma_soundblaster_readdata),
	.dma_soundblaster_writedata (dma_soundblaster_writedata),

	.sample_l                   (sound_sample_l),
	.sample_r                   (sound_sample_r),

	.fm_mode                    (sound_fm_mode),

	.irq                        (irq_5)
);

uart uart
(
	.clk           (clk_sys),
	.br_clk        (clk_uart),
	.reset         (reset_sys|reset_cpu),

	.address       (iobus_address[2:0]),
	.read          (iobus_read),
	.readdata      (uart_readdata),
	.write         (iobus_write),
	.writedata     (iobus_writedata[7:0]),
	.uart_cs       (uart_cs),
	.mpu_cs        (mpu_cs),

	.rx            (serial_rx),
	.tx            (serial_tx),
	.cts_n         (serial_cts_n),
	.dcd_n         (serial_dcd_n),
	.dsr_n         (serial_dsr_n),
	.ri_n          (serial_ri_n),
	.rts_n         (serial_rts_n),
	.br_out        (serial_br_out),
	.dtr_n         (serial_dtr_n),

	.irq_uart      (irq_4),
	.irq_mpu       (irq_9)
);

vga vga
(
	.clk_sys        (clk_sys),
	.rst_n          (~reset_sys),

	.clock_rate     (clock_rate),

	.io_b_address   (iobus_address[3:0]),
	.io_b_read      (iobus_read & vga_b_cs),
	.io_b_readdata  (vga_io_b_readdata),
	.io_b_write     (iobus_write & vga_b_cs),
	.io_b_writedata (iobus_writedata[7:0]),

	.io_c_address   (iobus_address[3:0]),
	.io_c_read      (iobus_read & vga_c_cs),
	.io_c_readdata  (vga_io_c_readdata),
	.io_c_write     (iobus_write & vga_c_cs),
	.io_c_writedata (iobus_writedata[7:0]),

	.io_d_address   (iobus_address[3:0]),
	.io_d_read      (iobus_read & vga_d_cs),
	.io_d_readdata  (vga_io_d_readdata),
	.io_d_write     (iobus_write & vga_d_cs),
	.io_d_writedata (iobus_writedata[7:0]),

	.mem_address    (vga_address),
	.mem_read       (vga_read),
	.mem_readdata   (vga_readdata),
	.mem_write      (vga_write),
	.mem_writedata  (vga_writedata),

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
