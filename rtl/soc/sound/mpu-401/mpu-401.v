module mpu_401
(
	////////////////////////	Clock Input	 	////////////////////////
	input RESET_N,
	input CLOCK,
	
	input MIDI_IN,
	output MIDI_OUT,
	
	input [2:0] MPU_ADDR,
	input MPU_READ,
	output [7:0] MPU_DO,
	
	input MPU_WRITE,
	input [7:0] MPU_DI,
	
	input OCC_INT_TRIG,
	input ICC_INT_TRIG,
	
	output [7:0] LEDG,
	output [9:0] LEDR
);


/*
MPU_READ==1  && MPU_ADDR[0]==0 Read MIDI Data.
MPU_WRITE==1 && MPU_ADDR[0]==0 Write MIDI Data.

MPU_READ==0  && MPU_ADDR[0]==1 Read Status (DSR[7]. DRR[6]).
MPU_WRITE==1 && MPU_ADDR[0]==1 Write Command. (0x85=Start Metronome tick etc.)
*/


// Data bus output driver...
assign MPU_DO = (MPU_ADDR[0]==1'b0) ? MPU_DATA : MPU_STAT;



rom	rom_inst (
	.clock ( CLOCK ),
	.address ( CPU_ADDR[11:0] ),
	.q ( ROM_DATA )
);
wire [7:0] ROM_DATA/*synthesis keep*/;

internal_ram	internal_ram_inst (
	.clock ( CLOCK ),
	
	.address ( CPU_ADDR[6:0] ),
	
	.data ( CPU_DATA_OUT ),
	.wren ( INT_RAM_CS && !CPU_RW ),
	.q ( INT_RAM_DATA )
);
wire [7:0] INT_RAM_DATA;


ram	ram_inst (
	.clock ( CLOCK ),

	.address ( CPU_ADDR[10:0] ),
	
	.data ( CPU_DATA_OUT ),
	.wren ( RAM_CS && !CPU_RW ),
	.q ( RAM_DATA )
);
wire [7:0] RAM_DATA/*synthesis keep*/;



wire IO_CS  = (CPU_ADDR>=16'h0000 && CPU_ADDR<=16'h001F)/*synthesis keep*/;		// "IO" here, meaning all of the internal CPU regs.

wire GA_CS  = (CPU_ADDR>=16'h0020 && CPU_ADDR<=16'h003F)/*synthesis keep*/;		

wire INT_RAM_CS = (CPU_ADDR>=16'h0080 && CPU_ADDR<=16'h00FF)/*synthesis keep*/;	// Made the internal RAM separate now, since I'm confident that the external is mapped higher up.

wire RAM_CS = (CPU_ADDR>=16'h0800 && CPU_ADDR<=16'h0FFF)/*synthesis keep*/;		// Pretty sure the external SRAM is mapped from 0x800 to 0xFFF,
																											// since the start of code clears the range from 0x800 to 0x690.

wire ROM_CS = (CPU_ADDR>=16'hF000 && CPU_ADDR<=16'hFFFF)/*synthesis keep*/;		// The Roland ROM is only 4KB, and the reset vector jumps to 0xF000 as well.


reg [7:0] MPU_DATA;
reg [7:0] MPU_CMD;
//wire [7:0] MPU_CMD = {1'b0, !KEY[3], 6'b000000};


//wire [7:0] GA_CONT = 8'h00;
//wire [7:0] GA_MUX = (CPU_ADDR==16'h0020) ? MPU_DATA :
//						  (CPU_ADDR==16'h0021) ? MPU_CMD :
//						  (CPU_ADDR==16'h0030) ? GA_CONT : 8'h00;


// Asserted (LOW) whenever the MPU-401 has an incoming MIDI byte (or Ack byte or Operation byte) waiting for you to read. Used as ISA Interrupt!
reg DSR_N = 1'b1;	// Data Set Ready. Active Low.


// Asserted (LOW) whenever it's OK for the host to write to the Data or Command ports / regs.
reg DRR_N = 1'b0;	// Data Receive Ready. Active Low.


wire [7:0] MPU_STAT = {DSR_N, DRR_N, 6'b000000};


wire CPU_RW/*synthesis keep*/;
wire CPU_VMA/*synthesis keep*/;

wire [15:0] CPU_ADDR/*synthesis keep*/;

wire [7:0] CPU_DATA_IN = (IO1_DIR_CS) ? IO1_DIR :
								 (IO2_DIR_CS) ? IO2_DIR :
								 //(IO1_DATA_CS) ? IO1_PORT :
								 (IO1_DATA_CS) ? 8'h80 :			// TESTING !! The MIDI / serial int routine seems to check the MSB of Port 1
																			// to determine whether it should re-transmit the incoming MIDI data? ElectronAsh.
								 (IO2_DATA_CS) ? IO2_PORT :
								 (IO3_DIR_CS) ? IO3_DIR :
								 (IO4_DIR_CS) ? IO4_DIR :
								 (IO3_DATA_CS) ? IO3_PORT :
								 (IO4_DATA_CS) ? IO4_PORT :
								 
								 (CTR_HIGH_CS) ? CTR_REG[15:8] :
								 (CTR_LOW_CS) ? CTR_REG[7:0] :
								 								 
								 (SCI_INT && CPU_ADDR==16'hFFF8) ? 8'hFC :	// Kludge, to point the normal IRQ vector at the SCI (MIDI IN / OUT) routine.
								 (SCI_INT && CPU_ADDR==16'hFFF9) ? 8'h7C :
								 
								 (TMR_INT && CPU_ADDR==16'hFFF8) ? 8'hFF :	// Kludge, to point the normal IRQ vector at the Timer Overflow interrupt routine.
								 (TMR_INT && CPU_ADDR==16'hFFF9) ? 8'hE0 :

 								 (OCC_INT && CPU_ADDR==16'hFFF8) ? 8'hFE :	// Kludge, to point the normal IRQ vector at the OCC (Output Capture / Compare) routine.
								 (OCC_INT && CPU_ADDR==16'hFFF9) ? 8'hA2 :
								 
								 (ICC_INT && CPU_ADDR==16'hFFF8) ? 8'hFE :	// Kludge, to point the normal IRQ vector at the ICC (Input Capture / Compare) routine.
								 (ICC_INT && CPU_ADDR==16'hFFF9) ? 8'h75 :

								 (TX_RX_CS) ? 8'h80 :
								 (RXDATA_CS) ? RXD_DATA :
								 
								 //(GA_CS) ? GA_MUX :
								 (CPU_ADDR==16'h0020) ? MPU_DATA :
								 (CPU_ADDR==16'h0021) ? MPU_CMD :
								 
								 (INT_RAM_CS) ? INT_RAM_DATA :
								 (RAM_CS) ? RAM_DATA :
								 (ROM_CS) ? ROM_DATA : 8'h00/*synthesis keep*/;
						
wire [7:0] CPU_DATA_OUT/*synthesis keep*/;


cpu68 cpu68_inst
(
	.clk( CLOCK ) ,				// input  clk
	.rst( !RESET_N ) ,				// input  rst (active HIGH!!!!!!!!!!!!!!!!!!)
	
	.rw( CPU_RW ) ,				// output  rw
	.vma( CPU_VMA ) ,				// output  vma
	
	.address( CPU_ADDR ) ,		// output [15:0] address
	
	.data_in( CPU_DATA_IN ) ,	// input [7:0] data_in
	.data_out( CPU_DATA_OUT ) ,// output [7:0] data_out
	
	.hold( 1'b0 ) ,// input  hold
	.halt( 1'b0 ) ,// input  halt
	
	// Roland MPU-401 does NOT use the /IRQ or /NMI pins!
	// (the ROM vectors for those just point to 0xF000 again.)
	//
	// The extra four vectors for the ICF, OCF, TOF, and SCI need to be implemented on
	// this CPU core before we can handle everything that the Hitachi HD6801 does! OzOnE.
	//
	.irq( SCI_INT | TMR_INT | OCC_INT | ICC_INT) ,	// input  irq
	.nmi( 1'b0 ) 	// input  nmi
);


wire IO1_DIR_CS   = (CPU_ADDR==16'h0000)/*synthesis keep*/;
wire IO2_DIR_CS   = (CPU_ADDR==16'h0001)/*synthesis keep*/;
wire IO1_DATA_CS  = (CPU_ADDR==16'h0002)/*synthesis keep*/;
wire IO2_DATA_CS  = (CPU_ADDR==16'h0003)/*synthesis keep*/;
wire IO3_DIR_CS   = (CPU_ADDR==16'h0004)/*synthesis keep*/;
wire IO4_DIR_CS   = (CPU_ADDR==16'h0005)/*synthesis keep*/;
wire IO3_DATA_CS  = (CPU_ADDR==16'h0006)/*synthesis keep*/;
wire IO4_DATA_CS  = (CPU_ADDR==16'h0007)/*synthesis keep*/;

wire TIMER_CS  	= (CPU_ADDR==16'h0008)/*synthesis keep*/;	// TCSR (Timer Control and Status Register).
wire CTR_HIGH_CS  = (CPU_ADDR==16'h0009)/*synthesis keep*/;
wire CTR_LOW_CS 	= (CPU_ADDR==16'h000A)/*synthesis keep*/;
wire OCC_HIGH_CS	= (CPU_ADDR==16'h000B)/*synthesis keep*/;

wire OCC_LOW_CS	= (CPU_ADDR==16'h000C)/*synthesis keep*/;
wire ICC_HIGH_CS	= (CPU_ADDR==16'h000D)/*synthesis keep*/;
wire ICC_LOW_CS	= (CPU_ADDR==16'h000E)/*synthesis keep*/;
wire P3_CONT_CS	= (CPU_ADDR==16'h000F)/*synthesis keep*/;

wire RATE_CS		= (CPU_ADDR==16'h0010)/*synthesis keep*/;
wire TX_RX_CS		= (CPU_ADDR==16'h0011)/*synthesis keep*/;
wire RXDATA_CS		= (CPU_ADDR==16'h0012)/*synthesis keep*/;
wire TXDATA_CS		= (CPU_ADDR==16'h0013)/*synthesis keep*/;

wire RAM_CONT_CS	= (CPU_ADDR==16'h0014)/*synthesis keep*/;


assign LEDR = {IO1_PORT[1:0], IO2_PORT};

assign LEDG = IO3_PORT;


reg [7:0] IO1_DIR;
reg [7:0] IO2_DIR;
reg [7:0] IO1_PORT;
reg [7:0] IO2_PORT;

reg [7:0] IO3_DIR;
reg [7:0] IO4_DIR;
reg [7:0] IO3_PORT;
reg [7:0] IO4_PORT;

reg [7:0] TIMER_CONT_REG;

reg [15:0] CTR_REG;

reg [15:0] OCC_REG;

reg [15:0] ICC_REG;

reg [7:0] P3_CONT_REG;

reg [7:0] RATE_REG;
reg [7:0] TX_RX_REG;
reg [7:0] RXDATA_REG;
reg [7:0] TXDATA_REG;

reg [7:0] RAM_CONT_REG;


async_receiver async_receiver_inst
(
	.clk( CLOCK ) ,	// input  clk
	.RxD( MIDI_IN ) ,	// input  RxD
	
	.RxD_data_ready( RXD_DATA_READY ) ,	// output  RxD_data_ready
	.RxD_data( RXD_DATA ) ,	// output [7:0] RxD_data
	.RxD_endofpacket( RXD_EOF ) ,	// output  RxD_endofpacket
	.RxD_idle( RXD_IDLE ) 	// output  RxD_idle
);
wire [7:0] RXD_DATA;
wire RXD_DATA_READY;
wire RXD_EOF;
wire RXD_IDLE;


reg SCI_INT/*synthesis keep*/;
reg ICC_INT/*synthesis keep*/;
reg TMR_INT/*synthesis keep*/;
reg OCC_INT/*synthesis keep*/;

reg [1:0] TIMER_DIV;

always @(posedge CLOCK or negedge RESET_N)
if (!RESET_N) begin
	IO1_DIR <= 8'h00;
	IO1_PORT <= 8'h00;
	IO2_DIR <= 8'h00;
	IO2_PORT <= 8'h00;
	IO3_DIR <= 8'h00;
	IO3_PORT <= 8'h00;
	IO4_DIR <= 8'h00;
	IO4_PORT <= 8'h00;
	
	TIMER_CONT_REG <= 8'h00;	// Offset 0x8.
	
	CTR_REG <= 16'h0000;			// (16-bit). Offsets 0x9 to 0xA.
	OCC_REG <= 16'h0000;			// (16-bit). Offsets 0xB to 0xC.
	ICC_REG <= 16'h0000;			// (16-bit). Offsets 0xD to 0xE.

	P3_CONT_REG <= 8'h00;
	RATE_REG <= 8'h00;
	TX_RX_REG <= 8'h00;
//	RXDATA_REG <= 8'h00;
	TXDATA_REG <= 8'h00;

	RAM_CONT_REG <= 8'h00;
	
	SCI_INT <= 1'b0;
	ICC_INT <= 1'b0;
	OCC_INT <= 1'b0;
	TMR_INT <= 1'b0;
	
	TIMER_DIV <= 4'h0;
	
	MPU_DATA <= 8'h00;
	MPU_CMD <= 8'h00;
end
else begin
	TIMER_DIV <= TIMER_DIV + 1;
	if (TIMER_DIV==4'h0000) CTR_REG <= CTR_REG + 1;

	if (CPU_ADDR==16'h0000 && !CPU_RW) IO1_DIR <= CPU_DATA_OUT;		// Bits are 1=Output, 0=Input.
	if (CPU_ADDR==16'h0002 && !CPU_RW) IO1_PORT <= CPU_DATA_OUT;

	if (CPU_ADDR==16'h0001 && !CPU_RW) IO2_DIR <= CPU_DATA_OUT;
	//if (CPU_ADDR==16'h0003 && !CPU_RW) IO2_PORT <= {CPU_DATA_OUT[7:4], MIDI_IN, CPU_DATA_OUT[2:0]};	// Passing the MIDI data directly to RXDATA reg. This wouldn't have worked anyway.
	if (CPU_ADDR==16'h0003 && !CPU_RW) IO2_PORT <= CPU_DATA_OUT;

	if (CPU_ADDR==16'h0004 && !CPU_RW) IO3_DIR <= CPU_DATA_OUT;
	if (CPU_ADDR==16'h0006 && !CPU_RW) IO3_PORT <= CPU_DATA_OUT;

	if (CPU_ADDR==16'h0005 && !CPU_RW) IO4_DIR <= CPU_DATA_OUT;
	if (CPU_ADDR==16'h0007 && !CPU_RW) IO4_PORT <= CPU_DATA_OUT;
	
	if (TIMER_CS && !CPU_RW) TIMER_CONT_REG <= CPU_DATA_OUT;
	if (CTR_HIGH_CS && !CPU_RW) CTR_REG[15:8] <= CPU_DATA_OUT;
	if (CTR_LOW_CS && !CPU_RW) CTR_REG[7:0] <= CPU_DATA_OUT;
	if (OCC_HIGH_CS && !CPU_RW) OCC_REG[15:8] <= CPU_DATA_OUT;

	if (OCC_LOW_CS && !CPU_RW) OCC_REG[7:0] <= CPU_DATA_OUT;
	if (ICC_HIGH_CS && !CPU_RW) ICC_REG[15:8] <= CPU_DATA_OUT;
	if (ICC_LOW_CS && !CPU_RW) ICC_REG[7:0] <= CPU_DATA_OUT;
	if (P3_CONT_CS && !CPU_RW) P3_CONT_REG <= CPU_DATA_OUT;

	if (RATE_CS && !CPU_RW) RATE_REG <= CPU_DATA_OUT;
	if (TX_RX_CS && !CPU_RW) TX_RX_REG <= CPU_DATA_OUT;
//	if (RXDATA_CS && !CPU_RW) RXDATA_REG <= CPU_DATA_OUT;
	if (TXDATA_CS && !CPU_RW) TXDATA_REG <= CPU_DATA_OUT;

	if (RAM_CONT_CS && !CPU_RW) RAM_CONT_REG <= CPU_DATA_OUT;
	
	if (RXD_DATA_READY) SCI_INT <= 1'b1;		// New MIDI byte received. Trigger an interrupt!
	if (CPU_ADDR==16'hFC7C) SCI_INT <= 1'b0;	// MIDI (SCI) interrupt routine has been triggered, clear the interrupt!

	if (CTR_REG ==16'hFFFF) TMR_INT <= 1'b1;
	if (CPU_ADDR==16'hFFE3) TMR_INT <= 1'b0;
	
	if (OCC_INT_TRIG) OCC_INT <= 1'b1;
	if (CPU_ADDR==16'hFEA4) OCC_INT <= 1'b0;
	
	if (ICC_INT_TRIG) ICC_INT <= 1'b1;
	if (CPU_ADDR==16'hFE77) ICC_INT <= 1'b0;
	
	
	// Handle Avalon IO Writes...
	if (MPU_ADDR[0]==1'b0 && MPU_WRITE) MPU_DATA <= MPU_DI;
	if (MPU_ADDR[0]==1'b1 && MPU_WRITE) MPU_CMD <= MPU_DI;
end

wire TXD_START = TXDATA_CS && !CPU_RW/*synthesis keep*/;

async_transmitter async_transmitter_inst
(
	.clk( CLOCK ) ,			// input  clk
	.TxD_start( TXD_START ) ,	// input  TxD_start
	.TxD_data( CPU_DATA_OUT ) ,	// input [7:0] TxD_data
	.TxD( MIDI_OUT ) ,		// output  TxD
	.TxD_busy( TXD_BUSY ) 	// output  TxD_busy
);
wire TXD_BUSY;


endmodule
