`timescale 1 ps / 1 ps
module sysmem_lite
(
	input          ramclk1_clk,           //   ramclk1.clk
	input   [28:0] ram1_address,          //      ram1.address
	input    [7:0] ram1_burstcount,       //          .burstcount
	output         ram1_waitrequest,      //          .waitrequest
	output  [63:0] ram1_readdata,         //          .readdata
	output         ram1_readdatavalid,    //          .readdatavalid
	input          ram1_read,             //          .read
	input   [63:0] ram1_writedata,        //          .writedata
	input    [7:0] ram1_byteenable,       //          .byteenable
	input          ram1_write,            //          .write

	input          ramclk2_clk,           //   ramclk2.clk
	input   [28:0] ram2_address,          //      ram2.address
	input    [7:0] ram2_burstcount,       //          .burstcount
	output         ram2_waitrequest,      //          .waitrequest
	output  [63:0] ram2_readdata,         //          .readdata
	output         ram2_readdatavalid,    //          .readdatavalid
	input          ram2_read,             //          .read
	input   [63:0] ram2_writedata,        //          .writedata
	input    [7:0] ram2_byteenable,       //          .byteenable
	input          ram2_write,            //          .write

	output         ctl_clock,
	input          reset_cold_req,        //     reset.cold_req
	output         reset_reset,           //          .reset
	input          reset_reset_req,       //          .reset_req
	input          reset_warm_req,        //          .warm_req

	input          vbuf_clk,              //      vbuf.clk
	input   [27:0] vbuf_address,          //      vbuf.address
	input    [7:0] vbuf_burstcount,       //          .burstcount
	output         vbuf_waitrequest,      //          .waitrequest
	output [127:0] vbuf_readdata,         //          .readdata
	output         vbuf_readdatavalid,    //          .readdatavalid
	input          vbuf_read,             //          .read
	input  [127:0] vbuf_writedata,        //          .writedata
	input   [15:0] vbuf_byteenable,       //          .byteenable
	input          vbuf_write,            //          .write

	input          uart_cts,              //      uart.cts
	input          uart_dsr,              //          .dsr
	input          uart_dcd,              //          .dcd
	input          uart_ri,               //          .ri
	output         uart_dtr,              //          .dtr
	output         uart_rts,              //          .rts
	output         uart_out1_n,           //          .out1_n
	output         uart_out2_n,           //          .out2_n
	input          uart_rxd,              //          .rxd
	output         uart_txd               //          .txd 	
);

assign ctl_clock = clk_vip_clk;

wire hps_h2f_reset_reset;           // HPS:h2f_rst_n -> Reset_Source:reset_hps
wire reset_source_reset_cold_reset; // Reset_Source:reset_cold -> HPS:f2h_cold_rst_req_n
wire reset_source_reset_warm_reset; // Reset_Source:reset_warm -> HPS:f2h_warm_rst_req_n
wire clk_vip_clk;

sysmem_HPS_fpga_interfaces fpga_interfaces (
	.f2h_cold_rst_req_n       (~reset_source_reset_cold_reset), // f2h_cold_reset_req.reset_n
	.f2h_warm_rst_req_n       (~reset_source_reset_warm_reset), // f2h_warm_reset_req.reset_n
	.h2f_user0_clk            (clk_vip_clk),                    //    h2f_user0_clock.clk
	.h2f_rst_n                (hps_h2f_reset_reset),            //          h2f_reset.reset_n
	.f2h_sdram0_clk           (vbuf_clk),                       //   f2h_sdram0_clock.clk
	.f2h_sdram0_ADDRESS       (vbuf_address),                   //    f2h_sdram0_data.address
	.f2h_sdram0_BURSTCOUNT    (vbuf_burstcount),                //                   .burstcount
	.f2h_sdram0_WAITREQUEST   (vbuf_waitrequest),               //                   .waitrequest
	.f2h_sdram0_READDATA      (vbuf_readdata),                  //                   .readdata
	.f2h_sdram0_READDATAVALID (vbuf_readdatavalid),             //                   .readdatavalid
	.f2h_sdram0_READ          (vbuf_read),                      //                   .read
	.f2h_sdram0_WRITEDATA     (vbuf_writedata),                 //                   .writedata
	.f2h_sdram0_BYTEENABLE    (vbuf_byteenable),                //                   .byteenable
	.f2h_sdram0_WRITE         (vbuf_write),                     //                   .write
	.f2h_sdram1_clk           (ramclk1_clk),                    //   f2h_sdram1_clock.clk
	.f2h_sdram1_ADDRESS       (ram1_address),                   //    f2h_sdram1_data.address
	.f2h_sdram1_BURSTCOUNT    (ram1_burstcount),                //                   .burstcount
	.f2h_sdram1_WAITREQUEST   (ram1_waitrequest),               //                   .waitrequest
	.f2h_sdram1_READDATA      (ram1_readdata),                  //                   .readdata
	.f2h_sdram1_READDATAVALID (ram1_readdatavalid),             //                   .readdatavalid
	.f2h_sdram1_READ          (ram1_read),                      //                   .read
	.f2h_sdram1_WRITEDATA     (ram1_writedata),                 //                   .writedata
	.f2h_sdram1_BYTEENABLE    (ram1_byteenable),                //                   .byteenable
	.f2h_sdram1_WRITE         (ram1_write),                     //                   .write
	.f2h_sdram2_clk           (ramclk2_clk),                    //   f2h_sdram2_clock.clk
	.f2h_sdram2_ADDRESS       (ram2_address),                   //    f2h_sdram2_data.address
	.f2h_sdram2_BURSTCOUNT    (ram2_burstcount),                //                   .burstcount
	.f2h_sdram2_WAITREQUEST   (ram2_waitrequest),               //                   .waitrequest
	.f2h_sdram2_READDATA      (ram2_readdata),                  //                   .readdata
	.f2h_sdram2_READDATAVALID (ram2_readdatavalid),             //                   .readdatavalid
	.f2h_sdram2_READ          (ram2_read),                      //                   .read
	.f2h_sdram2_WRITEDATA     (ram2_writedata),                 //                   .writedata
	.f2h_sdram2_BYTEENABLE    (ram2_byteenable),                //                   .byteenable
	.f2h_sdram2_WRITE         (ram2_write),                     //                   .write
	.uart_cts                 (uart_cts),
	.uart_dsr                 (uart_dsr),
	.uart_dcd                 (uart_dcd),
	.uart_ri                  (uart_ri),
	.uart_dtr                 (uart_dtr),
	.uart_rts                 (uart_rts),
	.uart_out1_n              (uart_out1_n),
	.uart_out2_n              (uart_out2_n),
	.uart_rxd                 (uart_rxd),
	.uart_txd                 (uart_txd)
);

reset_source reset_source (
	.clk        (clk_vip_clk),                   //      clock.clk
	.reset_hps  (~hps_h2f_reset_reset),          //  reset_hps.reset
	.reset_sys  (),                              //  reset_sys.reset
	.cold_req   (reset_cold_req),                //  reset_ctl.cold_req
	.reset      (reset_reset),                   //           .reset
	.reset_req  (reset_reset_req),               //           .reset_req
	.reset_vip  (0),                             //           .reset_vip
	.warm_req   (reset_warm_req),                //           .warm_req
	.reset_warm (reset_source_reset_warm_reset), // reset_warm.reset
	.reset_cold (reset_source_reset_cold_reset)  // reset_cold.reset
);

endmodule

module sysmem_HPS_fpga_interfaces
(
	// h2f_reset
	output wire [1 - 1 : 0 ] h2f_rst_n

	// f2h_cold_reset_req
	,input wire [1 - 1 : 0 ] f2h_cold_rst_req_n

	// f2h_warm_reset_req
	,input wire [1 - 1 : 0 ] f2h_warm_rst_req_n

	// h2f_user0_clock
	,output wire [1 - 1 : 0 ] h2f_user0_clk

	// f2h_sdram0_data
	,input wire [28 - 1 : 0 ] f2h_sdram0_ADDRESS
	,input wire [8 - 1 : 0 ] f2h_sdram0_BURSTCOUNT
	,output wire [1 - 1 : 0 ] f2h_sdram0_WAITREQUEST
	,output wire [128 - 1 : 0 ] f2h_sdram0_READDATA
	,output wire [1 - 1 : 0 ] f2h_sdram0_READDATAVALID
	,input wire [1 - 1 : 0 ] f2h_sdram0_READ
	,input wire [128 - 1 : 0 ] f2h_sdram0_WRITEDATA
	,input wire [16 - 1 : 0 ] f2h_sdram0_BYTEENABLE
	,input wire [1 - 1 : 0 ] f2h_sdram0_WRITE

	// f2h_sdram0_clock
	,input wire [1 - 1 : 0 ] f2h_sdram0_clk

	// f2h_sdram1_data
	,input wire [29 - 1 : 0 ] f2h_sdram1_ADDRESS
	,input wire [8 - 1 : 0 ] f2h_sdram1_BURSTCOUNT
	,output wire [1 - 1 : 0 ] f2h_sdram1_WAITREQUEST
	,output wire [64 - 1 : 0 ] f2h_sdram1_READDATA
	,output wire [1 - 1 : 0 ] f2h_sdram1_READDATAVALID
	,input wire [1 - 1 : 0 ] f2h_sdram1_READ
	,input wire [64 - 1 : 0 ] f2h_sdram1_WRITEDATA
	,input wire [8 - 1 : 0 ] f2h_sdram1_BYTEENABLE
	,input wire [1 - 1 : 0 ] f2h_sdram1_WRITE

	// f2h_sdram1_clock
	,input wire [1 - 1 : 0 ] f2h_sdram1_clk

	// f2h_sdram2_data
	,input wire [29 - 1 : 0 ] f2h_sdram2_ADDRESS
	,input wire [8 - 1 : 0 ] f2h_sdram2_BURSTCOUNT
	,output wire [1 - 1 : 0 ] f2h_sdram2_WAITREQUEST
	,output wire [64 - 1 : 0 ] f2h_sdram2_READDATA
	,output wire [1 - 1 : 0 ] f2h_sdram2_READDATAVALID
	,input wire [1 - 1 : 0 ] f2h_sdram2_READ
	,input wire [64 - 1 : 0 ] f2h_sdram2_WRITEDATA
	,input wire [8 - 1 : 0 ] f2h_sdram2_BYTEENABLE
	,input wire [1 - 1 : 0 ] f2h_sdram2_WRITE

	// f2h_sdram2_clock
	,input wire [1 - 1 : 0 ] f2h_sdram2_clk

	,input          uart_cts              //    uart.cts
	,input          uart_dsr              //        .dsr
	,input          uart_dcd              //        .dcd
	,input          uart_ri               //        .ri
	,output         uart_dtr              //        .dtr
	,output         uart_rts              //        .rts
	,output         uart_out1_n           //        .out1_n
	,output         uart_out2_n           //        .out2_n
	,input          uart_rxd              //        .rxd
	,output         uart_txd               //        .txd 	
);


wire [29 - 1 : 0] intermediate;
assign intermediate[0:0] = ~intermediate[1:1];
assign intermediate[8:8] = intermediate[4:4]|intermediate[7:7];
assign intermediate[2:2] = intermediate[9:9];
assign intermediate[3:3] = intermediate[9:9];
assign intermediate[5:5] = intermediate[9:9];
assign intermediate[6:6] = intermediate[9:9];
assign intermediate[10:10] = intermediate[9:9];
assign intermediate[11:11] = ~intermediate[12:12];
assign intermediate[17:17] = intermediate[14:14]|intermediate[16:16];
assign intermediate[13:13] = intermediate[18:18];
assign intermediate[15:15] = intermediate[18:18];
assign intermediate[19:19] = intermediate[18:18];
assign intermediate[20:20] = ~intermediate[21:21];
assign intermediate[26:26] = intermediate[23:23]|intermediate[25:25];
assign intermediate[22:22] = intermediate[27:27];
assign intermediate[24:24] = intermediate[27:27];
assign intermediate[28:28] = intermediate[27:27];
assign f2h_sdram0_WAITREQUEST[0:0] = intermediate[0:0];
assign f2h_sdram1_WAITREQUEST[0:0] = intermediate[11:11];
assign f2h_sdram2_WAITREQUEST[0:0] = intermediate[20:20];
assign intermediate[4:4] = f2h_sdram0_READ[0:0];
assign intermediate[7:7] = f2h_sdram0_WRITE[0:0];
assign intermediate[9:9] = f2h_sdram0_clk[0:0];
assign intermediate[14:14] = f2h_sdram1_READ[0:0];
assign intermediate[16:16] = f2h_sdram1_WRITE[0:0];
assign intermediate[18:18] = f2h_sdram1_clk[0:0];
assign intermediate[23:23] = f2h_sdram2_READ[0:0];
assign intermediate[25:25] = f2h_sdram2_WRITE[0:0];
assign intermediate[27:27] = f2h_sdram2_clk[0:0];

cyclonev_hps_interface_clocks_resets clocks_resets(
 .f2h_warm_rst_req_n({
    f2h_warm_rst_req_n[0:0] // 0:0
  })
,.f2h_pending_rst_ack({
    1'b1 // 0:0
  })
,.f2h_dbg_rst_req_n({
    1'b1 // 0:0
  })
,.h2f_rst_n({
    h2f_rst_n[0:0] // 0:0
  })
,.f2h_cold_rst_req_n({
    f2h_cold_rst_req_n[0:0] // 0:0
  })
,.h2f_user0_clk({
    h2f_user0_clk[0:0] // 0:0
  })
);


cyclonev_hps_interface_dbg_apb debug_apb(
 .DBG_APB_DISABLE({
    1'b0 // 0:0
  })
,.P_CLK_EN({
    1'b0 // 0:0
  })
);


cyclonev_hps_interface_tpiu_trace tpiu(
 .traceclk_ctl({
    1'b1 // 0:0
  })
);


cyclonev_hps_interface_boot_from_fpga boot_from_fpga(
 .boot_from_fpga_ready({
    1'b0 // 0:0
  })
,.boot_from_fpga_on_failure({
    1'b0 // 0:0
  })
,.bsel_en({
    1'b0 // 0:0
  })
,.csel_en({
    1'b0 // 0:0
  })
,.csel({
    2'b01 // 1:0
  })
,.bsel({
    3'b001 // 2:0
  })
);


cyclonev_hps_interface_fpga2hps fpga2hps(
 .port_size_config({
    2'b11 // 1:0
  })
);


cyclonev_hps_interface_hps2fpga hps2fpga(
 .port_size_config({
    2'b11 // 1:0
  })
);


cyclonev_hps_interface_fpga2sdram f2sdram(
 .cfg_rfifo_cport_map({
    16'b0010000100000000 // 15:0
  })
,.cfg_wfifo_cport_map({
    16'b0010000100000000 // 15:0
  })
,.rd_ready_3({
    1'b1 // 0:0
  })
,.cmd_port_clk_2({
    intermediate[28:28] // 0:0
  })
,.rd_ready_2({
    1'b1 // 0:0
  })
,.cmd_port_clk_1({
    intermediate[19:19] // 0:0
  })
,.rd_ready_1({
    1'b1 // 0:0
  })
,.cmd_port_clk_0({
    intermediate[10:10] // 0:0
  })
,.rd_ready_0({
    1'b1 // 0:0
  })
,.wrack_ready_2({
    1'b1 // 0:0
  })
,.wrack_ready_1({
    1'b1 // 0:0
  })
,.wrack_ready_0({
    1'b1 // 0:0
  })
,.cmd_ready_2({
    intermediate[21:21] // 0:0
  })
,.cmd_ready_1({
    intermediate[12:12] // 0:0
  })
,.cmd_ready_0({
    intermediate[1:1] // 0:0
  })
,.cfg_port_width({
    12'b000000010110 // 11:0
  })
,.rd_valid_3({
    f2h_sdram2_READDATAVALID[0:0] // 0:0
  })
,.rd_valid_2({
    f2h_sdram1_READDATAVALID[0:0] // 0:0
  })
,.rd_valid_1({
    f2h_sdram0_READDATAVALID[0:0] // 0:0
  })
,.rd_clk_3({
    intermediate[22:22] // 0:0
  })
,.rd_data_3({
    f2h_sdram2_READDATA[63:0] // 63:0
  })
,.rd_clk_2({
    intermediate[13:13] // 0:0
  })
,.rd_data_2({
    f2h_sdram1_READDATA[63:0] // 63:0
  })
,.rd_clk_1({
    intermediate[3:3] // 0:0
  })
,.rd_data_1({
    f2h_sdram0_READDATA[127:64] // 63:0
  })
,.rd_clk_0({
    intermediate[2:2] // 0:0
  })
,.rd_data_0({
    f2h_sdram0_READDATA[63:0] // 63:0
  })
,.cfg_axi_mm_select({
    6'b000000 // 5:0
  })
,.cmd_valid_2({
    intermediate[26:26] // 0:0
  })
,.cmd_valid_1({
    intermediate[17:17] // 0:0
  })
,.cmd_valid_0({
    intermediate[8:8] // 0:0
  })
,.cfg_cport_rfifo_map({
    18'b000000000011010000 // 17:0
  })
,.wr_data_3({
    2'b00 // 89:88
   ,f2h_sdram2_BYTEENABLE[7:0] // 87:80
   ,16'b0000000000000000 // 79:64
   ,f2h_sdram2_WRITEDATA[63:0] // 63:0
  })
,.wr_data_2({
    2'b00 // 89:88
   ,f2h_sdram1_BYTEENABLE[7:0] // 87:80
   ,16'b0000000000000000 // 79:64
   ,f2h_sdram1_WRITEDATA[63:0] // 63:0
  })
,.wr_data_1({
    2'b00 // 89:88
   ,f2h_sdram0_BYTEENABLE[15:8] // 87:80
   ,16'b0000000000000000 // 79:64
   ,f2h_sdram0_WRITEDATA[127:64] // 63:0
  })
,.cfg_cport_type({
    12'b000000111111 // 11:0
  })
,.wr_data_0({
    2'b00 // 89:88
   ,f2h_sdram0_BYTEENABLE[7:0] // 87:80
   ,16'b0000000000000000 // 79:64
   ,f2h_sdram0_WRITEDATA[63:0] // 63:0
  })
,.cfg_cport_wfifo_map({
    18'b000000000011010000 // 17:0
  })
,.wr_clk_3({
    intermediate[24:24] // 0:0
  })
,.wr_clk_2({
    intermediate[15:15] // 0:0
  })
,.wr_clk_1({
    intermediate[6:6] // 0:0
  })
,.wr_clk_0({
    intermediate[5:5] // 0:0
  })
,.cmd_data_2({
    18'b000000000000000000 // 59:42
   ,f2h_sdram2_BURSTCOUNT[7:0] // 41:34
   ,3'b000 // 33:31
   ,f2h_sdram2_ADDRESS[28:0] // 30:2
   ,intermediate[25:25] // 1:1
   ,intermediate[23:23] // 0:0
  })
,.cmd_data_1({
    18'b000000000000000000 // 59:42
   ,f2h_sdram1_BURSTCOUNT[7:0] // 41:34
   ,3'b000 // 33:31
   ,f2h_sdram1_ADDRESS[28:0] // 30:2
   ,intermediate[16:16] // 1:1
   ,intermediate[14:14] // 0:0
  })
,.cmd_data_0({
    18'b000000000000000000 // 59:42
   ,f2h_sdram0_BURSTCOUNT[7:0] // 41:34
   ,4'b0000 // 33:30
   ,f2h_sdram0_ADDRESS[27:0] // 29:2
   ,intermediate[7:7] // 1:1
   ,intermediate[4:4] // 0:0
  })
);

cyclonev_hps_interface_peripheral_uart peripheral_uart1
(
	 .txd(uart_txd)
	,.cts(uart_cts)
	,.out1_n(uart_out1_n)
	,.dtr(uart_dtr)
	,.rts(uart_rts)
	,.out2_n(uart_out2_n)
	,.rxd(uart_rxd)
	,.ri(uart_ri)
	,.dsr(uart_dsr)
	,.dcd(uart_dcd)
);

endmodule
