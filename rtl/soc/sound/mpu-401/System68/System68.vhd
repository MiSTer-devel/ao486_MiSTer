--===========================================================================--
--
--  S Y N T H E Z I A B L E    System68   System On a Chip
--
--  This core adheres to the GNU public license  
--
-- File name      : system68.vhd
--
-- Purpose        : Top level file for a 6800 compatible system on a chip
--                  Designed for the Burch ED B5-Spartan IIe board with
--                  X2S300e FPGA,
--                  128K x 16 Word SRAM module (B5-SRAM)
--                  CPU I/O module (B5-Peripheral-Connectors)
--                  Compact Flash Module (B5-CF)
--                  Using mimiUart from open cores modified to look like a 6850
--                  This version of System68 boots the monitor program
--                  from LBA sectors $F478 / $F479 from a 32 Mbyte Compact Flash
--                  On Reset the Boot ROM is mapped for read at $E000,
--                  and Writes to $E000-$FFFF write to RAM
--                  Writing 0 to location $8030 disables the boot ROM and
--                  maps RAM for Read only at $E000 and Writes go to the DAT.
--                  
-- Dependencies   : ieee.Std_Logic_1164
--                  ieee.std_logic_unsigned
--                  ieee.std_logic_arith
--                  ieee.numeric_std
--
-- Uses           : miniuart.vhd, rxunit.vhd, tx_unit.vhd, clkunit.vhd
--                  swtbug.vhd (6800 SWTBUG ROM)
--                  datram.vhd (Dynamic address translation registers)
--                  cpu68.vhd  (6800 compatible CPU core)
--                  timer.vhd  (timer module)
--
-- Author         : John E. Kent      
--
--===========================================================================----
--
-- Revision History:
--===========================================================================--
--
-- Date:                Revision   Author
-- 22 September 2002    0.1        John Kent
-- Initial design.
-- 31 March 2003        0.2        John Kent
-- Removed Parallel I/O port
-- Added Compact Flash Interface
-- Added IO register to commit unused inputs
-- Used 16 byte port mapping
--
-- 28th June 2003			0.3        John Kent
-- updated CPU to include Halt and Hold signals
--
-- 9th January 2004     0.4        John Kent
-- Removed Redundant Map Switch Code.
-- Rearrange DAT
-- Added dual port IO at $8030 - $803F
--
-- 25th April 2004      0.5        John Kent
-- Changed CPU clock to run at 25MHz / 2 = 12.5 MHz
-- Added baud rate divider for 57.6 Kbaud.
--
-------------------------------------------------------------------------------
--
-- Memory Map:
--
-- $0000 - $7FFF RAM
-- $8000 - $8FFF IO
--     $8000 - $800F MiniUart / Acia
--     $8010 - $801F Compact Flash
--     $8020 - $802F Timer
--     $8030 - $803F IO port
--     $8040 - $804F Trap hardware
-- $9000 - $BFFF RAM
-- $C000 - $CFFF ROM
-- $D000 - $DFFF RAM
-- $E000 - $FFFF ROM (read) & DAT (write)
--
library ieee;
   use ieee.std_logic_1164.all;
   use IEEE.STD_LOGIC_ARITH.ALL;
   use IEEE.STD_LOGIC_UNSIGNED.ALL;
   use ieee.numeric_std.all;

entity Sys68 is
  port(
    SysClk      : in    Std_Logic;  -- System Clock input
	 Reset_n     : in    Std_logic;  -- Master Reset input (active low)

    -- Memory Interface signals B3-SRAM
    ram_csn     : out   Std_Logic;  -- RAM Chip select (active low)
    ram_wrln    : out   Std_Logic;  -- lower byte write strobe (active low)
    ram_wrun    : out   Std_Logic;  -- upper byte write strobe (active low)
    ram_addr    : out   Std_Logic_Vector(16 downto 0);   -- RAM Address bus
    ram_data    : inout Std_Logic_Vector(15 downto 0); -- RAM Data bus

	 -- Signals defined on B3-CPU-IO Module
    LED         : out   std_logic;  -- Diagnostic LED Flasher

	 -- Uart Interface
    rxbit       : in    Std_Logic; -- UART receive data
	 txbit       : out   Std_Logic; -- UART transmit data
    rts_n       : out   Std_Logic; -- Request to send (active low)
    cts_n       : in    Std_Logic; -- Clear to send (active low)

	 -- CRTC output signals
--	   v_drive     : out Std_Logic;
--    h_drive     : out Std_Logic;
--    blue_lo     : out std_logic;
--    blue_hi     : out std_logic;
--    green_lo    : out std_logic;
--    green_hi    : out std_logic;
--    red_lo      : out std_logic;
--    red_hi      : out std_logic;
--	   buzzer      : out std_logic;

    -- Compact Flash B5-CF Module
    cf_rst_n     : out   std_logic;
	 cf_cs0_n     : out   std_logic;
	 cf_cs1_n     : out   std_logic;
    cf_rd_n      : out   std_logic;
    cf_wr_n      : out   std_logic;
	 cf_cs16_n    : out   std_logic;
    cf_a         : out   std_logic_vector(2 downto 0);
    cf_d         : inout std_logic_vector(15 downto 0);
--    cf_intrq     : in std_logic;
--    cf_iordy     : in std_logic;
--  	cf_dase      : in std_logic;
--	   cf_pdiag     : in std_logic;
--	   cf_present   : in std_logic;

--- IOPort Pins
	 porta        : inout std_logic_vector(7 downto 0);
	 portb        : inout std_logic_vector(7 downto 0);

--- Timer output
    timer_out    : out std_logic;

-- External Bus
    bus_addr     : out   std_logic_vector(15 downto 0);
	 bus_data     : inout std_logic_vector(7 downto 0);
	 bus_rw       : out   std_logic;
	 bus_cs       : out   std_logic;
	 bus_clk      : out   std_logic;
	 bus_reset    : out   std_logic
	 );
end;

-------------------------------------------------------------------------------
-- Architecture for memio Controller Unit
-------------------------------------------------------------------------------
architecture my_computer of Sys68 is
  -----------------------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------------------
  -- SWTBUG in Slices
  signal monitor_cs       : Std_Logic;
  signal monitor_data_out : Std_Logic_Vector(7 downto 0);

  -- SWTBUG in Block RAM
  signal swtbug_cs       : Std_Logic;
  signal swtbug_data_out : Std_Logic_Vector(7 downto 0);

  -- UART Interface signals
  signal uart_cs         : Std_Logic;
  signal uart_data_out   : Std_Logic_Vector(7 downto 0);  
  signal uart_irq        : Std_Logic;
  signal dcd_n           : Std_Logic;
  signal baudclk         : Std_Logic;

  -- timer
  signal timer_cs        : std_logic;
  signal timer_data_out  : std_logic_vector(7 downto 0);
  signal timer_irq       : std_logic;

  -- trap
  signal trap_cs         : std_logic;
  signal trap_data_out   : std_logic_vector(7 downto 0);
  signal trap_irq        : std_logic;

  -- ioport
  signal ioport_cs       : std_logic;
  signal ioport_data_out : std_logic_vector(7 downto 0);

  -- compact flash port
  signal cf_cs           : std_logic;
  signal cf_rd           : std_logic;
  signal cf_wr           : std_logic;
  signal cf_data_out     : std_logic_vector(7 downto 0);

  -- RAM
  signal ram_cs          : std_logic; -- memory chip select
  signal ram_wrl         : std_logic; -- memory write lower
  signal ram_wru         : std_logic; -- memory write upper
  signal ram_data_out    : std_logic_vector(7 downto 0);

  -- CPU Interface signals
  signal cpu_reset       : Std_Logic;
  signal cpu_clk         : Std_Logic;
  signal cpu_rw          : std_logic;
  signal cpu_vma         : std_logic;
  signal cpu_halt        : std_logic;
  signal cpu_hold        : std_logic;
  signal cpu_irq         : std_logic;
  signal cpu_nmi         : std_logic;
  signal cpu_addr        : Std_Logic_Vector(15 downto 0);
  signal cpu_data_in     : Std_Logic_Vector(7 downto 0);
  signal cpu_data_out    : Std_Logic_Vector(7 downto 0);

  -- Dynamic Address Translation RAM
  signal dat_cs          : std_logic;
  signal dat_addr        : std_logic_vector(7 downto 0);

-- Flashing Led test signals
  signal countL          : std_logic_vector(23 downto 0);
  signal BaudCount       : std_logic_vector(4 downto 0);

-----------------------------------------------------------------
--
-- CPU68 CPU core
--
-----------------------------------------------------------------

component cpu68
  port (    
	 clk:	     in	std_logic;
    rst:	     in	std_logic;
    rw:	     out	std_logic;		-- Asynchronous memory interface
    vma:	     out	std_logic;
    address:  out	std_logic_vector(15 downto 0);
    data_in:  in	std_logic_vector(7 downto 0);
	 data_out: out std_logic_vector(7 downto 0);
	 hold:     in  std_logic;
	 halt:     in  std_logic;
	 irq:      in  std_logic;
	 nmi:      in  std_logic
  );
end component;

-----------------------------------------------------------------
--
-- Open Cores Mini UART
--
-----------------------------------------------------------------

component miniUART
  port (
     clk      : in  Std_Logic;  -- System Clock
     rst      : in  Std_Logic;  -- Reset input (active high)
     cs       : in  Std_Logic;  -- miniUART Chip Select
     rw       : in  Std_Logic;  -- Read / Not Write
     irq      : out Std_Logic;  -- Interrupt
     Addr     : in  Std_Logic;  -- Register Select
     DataIn   : in  Std_Logic_Vector(7 downto 0); -- Data Bus In 
     DataOut  : out Std_Logic_Vector(7 downto 0); -- Data Bus Out
     RxC      : in  Std_Logic;  -- Receive Baud Clock
     TxC      : in  Std_Logic;  -- Transmit Baud Clock
     RxD      : in  Std_Logic;  -- Receive Data
     TxD      : out Std_Logic;  -- Transmit Data
	  DCD_n    : in  Std_Logic;  -- Data Carrier Detect
     CTS_n    : in  Std_Logic;  -- Clear To Send
     RTS_n    : out Std_Logic );  -- Request To send
end component;


----------------------------------------
--
-- Timer module
--
----------------------------------------

component timer
  port (
     clk       : in std_logic;
	  rst       : in std_logic;
	  cs        : in std_logic;
	  rw        : in std_logic;
	  addr      : in std_logic;
	  data_in   : in std_logic_vector(7 downto 0);
	  data_out  : out std_logic_vector(7 downto 0);
	  irq       : out std_logic;
     timer_in  : in std_logic;
	  timer_out : out std_logic
	  );
end component;

component trap
	port (	
	 clk        : in  std_logic;
    rst        : in  std_logic;
    cs         : in  std_logic;
    rw         : in  std_logic;
    vma        : in  std_logic;
    addr       : in  std_logic_vector(15 downto 0);
    data_in    : in  std_logic_vector(7 downto 0);
	 data_out   : out std_logic_vector(7 downto 0);
	 irq        : out std_logic
  );
end component;

component ioport
	port (	
	 clk       : in  std_logic;
    rst       : in  std_logic;
    cs        : in  std_logic;
    rw        : in  std_logic;
    addr      : in  std_logic_vector(1 downto 0);
    data_in   : in  std_logic_vector(7 downto 0);
	 data_out  : out std_logic_vector(7 downto 0);
	 porta_io  : inout std_logic_vector(7 downto 0);
	 portb_io  : inout std_logic_vector(7 downto 0) );
end component;

component dat_ram
  port (
    clk:      in  std_logic;
	 rst:      in  std_logic;
	 cs:       in  std_logic;
	 rw:       in  std_logic;
	 addr_lo:  in  std_logic_vector(3 downto 0);
	 addr_hi:  in  std_logic_vector(3 downto 0);
    data_in:  in  std_logic_vector(7 downto 0);
	 data_out: out std_logic_vector(7 downto 0)
	 );
end component;

--
-- SWTBug Monitor ROM at $E000
--
component monitor_rom
  port (
	 cs    : in  std_logic;
    addr  : in  Std_Logic_Vector(9 downto 0);  -- 1K byte boot rom
	 data  : out Std_Logic_Vector(7 downto 0)
  );
end component;


component BUFG
  port (
     i: in std_logic;
	  o: out std_logic
  );
end component;

--
-- SWTBUG Monitor in Block RAM at $C000
--
component swtbug_rom
  port (
    clk    : in  std_logic;
  	 rst    : in  std_logic;
	 cs     : in  std_logic;
	 rw     : in  std_logic;
    addr   : in  std_logic_vector (9 downto 0);
    wdata  : in  std_logic_vector (7 downto 0);
    rdata  : out std_logic_vector (7 downto 0)
   );
end component;

begin
  -----------------------------------------------------------------------------
  -- Instantiation of internal components
  -----------------------------------------------------------------------------

my_cpu : cpu68  port map (    
	 clk	     => cpu_clk,
    rst       => cpu_reset,
    rw	     => cpu_rw,
    vma       => cpu_vma,
    address   => cpu_addr(15 downto 0),
    data_in   => cpu_data_in,
	 data_out  => cpu_data_out,
	 hold      => cpu_hold,
	 halt      => cpu_halt,
	 irq       => cpu_irq,
	 nmi       => cpu_nmi
  );

my_uart  : miniUART port map (
	 clk	     => cpu_clk,
	 rst       => cpu_reset,
    cs        => uart_cs,
	 rw        => cpu_rw,
    irq       => uart_irq,
    Addr      => cpu_addr(0),
	 Datain    => cpu_data_out,
	 DataOut   => uart_data_out,
	 RxC       => baudclk,
	 TxC       => baudclk,
	 RxD       => rxbit,
	 TxD       => txbit,
	 DCD_n     => dcd_n,
	 CTS_n     => cts_n,
	 RTS_n     => rts_n
	 );

my_timer  : timer port map (
	 clk	     => cpu_clk,
	 rst       => cpu_reset,
    cs        => timer_cs,
	 rw        => cpu_rw,
    addr      => cpu_addr(0),
	 data_in   => cpu_data_out,
	 data_out  => timer_data_out,
    irq       => timer_irq,
	 timer_in  => CountL(5),
	 timer_out => timer_out
    );

my_trap : trap port map (	
	 clk        => cpu_clk,
    rst        => cpu_reset,
    cs         => trap_cs,
    rw         => cpu_rw,
	 vma        => cpu_vma,
    addr       => cpu_addr,
    data_in    => cpu_data_out,
	 data_out   => trap_data_out,
	 irq        => trap_irq
    );

my_ioport : ioport port map (	
	 clk        => cpu_clk,
    rst        => cpu_reset,
    cs         => ioport_cs,
    rw         => cpu_rw,
    addr       => cpu_addr(1 downto 0),
    data_in    => cpu_data_out,
	 data_out   => ioport_data_out,
	 porta_io   => porta,
	 portb_io   => portb
    );

my_dat : dat_ram port map (
	 clk	      => cpu_clk,
	 rst        => cpu_reset,
	 cs         => dat_cs,
	 rw         => cpu_rw,
	 addr_hi    => cpu_addr(15 downto 12),
	 addr_lo    => cpu_addr(3 downto 0),
    data_in    => cpu_data_out,
	 data_out   => dat_addr(7 downto 0)
	 );

--
-- SWTBUG Monitor
--
my_monitor_rom : monitor_rom port map (
    cs       => monitor_cs,
	 addr     => cpu_addr(9 downto 0),
    data     => monitor_data_out
	 );

--
-- SWTBUG Monitor using BLOCKRAM
--
my_swtbug_rom : swtbug_rom port map (
    clk      => cpu_clk,
	 rst      => cpu_reset,
    cs       => swtbug_cs,
    rw       => cpu_rw,
    addr     => cpu_addr(9 downto 0),
    wdata    => cpu_data_out,
    rdata    => swtbug_data_out
    );


clock_buffer : BUFG port map (
    i       => CountL(0),
	 o       => cpu_clk
    );
	 
----------------------------------------------------------------------
--
--  Processes to decode the CPU address
--
----------------------------------------------------------------------

decode: process( cpu_addr, cpu_rw, cpu_vma, cpu_data_in,
					  monitor_data_out,
				     ram_data_out,
				     swtbug_data_out,
				     uart_data_out,
				     cf_data_out,
				     timer_data_out,
				     trap_data_out,
					  bus_data,
				     dat_cs )
begin
    --
	 -- Memory Map
	 --
      case cpu_addr(15 downto 12) is
		when "1111" | "1110" => -- $E000 - $FFFF
		   cpu_data_in <= monitor_data_out;            -- read ROM
		   monitor_cs <= cpu_vma;
		   swtbug_cs  <= '0';
			dat_cs     <= cpu_vma;                      -- write DAT
			ram_cs     <= '0';
			uart_cs    <= '0';
			cf_cs      <= '0';
			timer_cs   <= '0';
			trap_cs    <= '0';
			ioport_cs  <= '0';
			bus_cs     <= '0';
		when "1100" => -- $C000 - $CFFF
		   cpu_data_in <= swtbug_data_out;
		   monitor_cs <= '0';
		   swtbug_cs  <= cpu_vma;
			dat_cs     <= '0';
			ram_cs     <= '0';
			uart_cs    <= '0';
			cf_cs      <= '0';
			timer_cs   <= '0';
			trap_cs    <= '0';
			ioport_cs  <= '0';
			bus_cs     <= '0';
		when "1000" => -- $8000 - $8FFF
		   monitor_cs <= '0';
		   swtbug_cs  <= '0';
			dat_cs     <= '0';
			ram_cs     <= '0';
		   case cpu_addr(6 downto 4) is
			--
			-- UART
			--
			when "000" => -- ($8000 - $800F)
			  if cpu_addr(3 downto 2) = "01" then
		       cpu_data_in <= uart_data_out;
			    uart_cs     <= cpu_vma;
			    cf_cs       <= '0';
			    timer_cs    <= '0';
			    trap_cs     <= '0';
			    ioport_cs   <= '0';
			    bus_cs      <= '0';
           else
		       cpu_data_in <= "00000000";
			    uart_cs     <= '0';
			    cf_cs       <= '0';
			    timer_cs    <= '0';
			    trap_cs     <= '0';
			    ioport_cs   <= '0';
			    bus_cs     <= '0';
           end if;
			--
			-- Compact Flash
			--
			when "001" => -- ($8010 - $801F)
           cpu_data_in <= cf_data_out;
			  uart_cs     <= '0';
           cf_cs       <= cpu_vma;
			  timer_cs    <= '0';
			  trap_cs     <= '0';
			  ioport_cs   <= '0';
			  bus_cs      <= '0';
			--
			-- Timer
			--
			when "010" => -- ($8020 - $802F)
           cpu_data_in <= timer_data_out;
			  uart_cs     <= '0';
			  cf_cs       <= '0';
           timer_cs    <= cpu_vma;
			  trap_cs     <= '0';
			  ioport_cs   <= '0';
			  bus_cs      <= '0';
			--
			-- IO Port
			--
			when "011" => -- ($8030 - $803F)
           cpu_data_in <= ioport_data_out;
			  uart_cs     <= '0';
			  cf_cs       <= '0';
           timer_cs    <= '0';
			  trap_cs     <= '0';
			  ioport_cs   <= cpu_vma;
			  bus_cs      <= '0';
			--
			-- Trap hardware
			--
			when "100" => -- ($8040 - $804F)
           cpu_data_in <= trap_data_out;
			  uart_cs     <= '0';
			  cf_cs       <= '0';
           timer_cs    <= '0';
			  trap_cs     <= cpu_vma;
			  ioport_cs   <= '0';
			  bus_cs      <= '0';
			--
			-- Null devices
			--
			when others => -- $8050 to $9FFF
           cpu_data_in <= bus_data;
			  uart_cs     <= '0';
			  cf_cs       <= '0';
			  timer_cs    <= '0';
			  trap_cs     <= '0';
			  ioport_cs   <= '0';
			  bus_cs      <= cpu_vma;
		   end case;
		 when others =>
		   cpu_data_in <= ram_data_out;
		   monitor_cs <= '0';
		   swtbug_cs  <= '0';
		   ram_cs     <= cpu_vma;
		   dat_cs     <= '0';
		   uart_cs    <= '0';
		   cf_cs      <= '0';
		   timer_cs   <= '0';
		   trap_cs    <= '0';
			ioport_cs  <= '0';
	    end case;
end process;


----------------------------------------------------------------------
--
--  Processes to read and write B5_SRAM
--
----------------------------------------------------------------------
b5_sram: process( cpu_clk,   Reset_n,
                  cpu_addr, cpu_rw,   cpu_data_out,
                  ram_cs,   ram_wrl,  ram_wru,
		    		   dat_cs,   dat_addr, ram_data_out )
begin
    ram_csn <= not( ram_cs and Reset_n);
	 ram_wrl  <= dat_addr(0) and (not cpu_rw) and cpu_clk;
	 ram_wrln <= not ram_wrl;
    ram_wru  <= (not dat_addr(0)) and (not cpu_rw) and cpu_clk;
	 ram_wrun <= not ram_wru;
	 ram_addr(16 downto 12) <= dat_addr(5 downto 1);
	 ram_addr(11 downto 0 ) <= cpu_addr(11 downto 0);

    if ram_wrl = '1' then
		ram_data(7 downto 0) <= cpu_data_out;
	 else
      ram_data(7 downto 0)  <= "ZZZZZZZZ";
	 end if;

	 if ram_wru = '1' then
		ram_data(15 downto 8) <= cpu_data_out;
	 else
      ram_data(15 downto 8)  <= "ZZZZZZZZ";
    end if;

	 if dat_addr(0) = '0' then
      ram_data_out <= ram_data(15 downto 8);
	 else
      ram_data_out <= ram_data(7 downto 0);
    end if;

end process;

--
-- B5-CF Compact Flash Control
--
b5_cf: process( Reset_n,
                cpu_addr, cpu_rw, cpu_data_out,
					 cf_cs, cf_rd, cf_wr, cf_d )
begin
	 cf_rst_n  <= Reset_n;
	 cf_cs0_n  <= not( cf_cs ) or cpu_addr(3);
	 cf_cs1_n  <= not( cf_cs and cpu_addr(3));
	 cf_cs16_n <= '1';
	 cf_wr     <= cf_cs and (not cpu_rw);
	 cf_rd     <= cf_cs and cpu_rw;
	 cf_wr_n   <= not cf_wr;
	 cf_rd_n   <= not cf_rd;
	 cf_a      <= cpu_addr(2 downto 0);
	 if cf_wr = '1' then
	   cf_d(7 downto 0) <= cpu_data_out;
	 else
	   cf_d(7 downto 0) <= "ZZZZZZZZ";
	 end if;
	 cf_data_out <= cf_d(7 downto 0);
	 cf_d(15 downto 8) <= "ZZZZZZZZ";
end process;

--
-- CPU bus signals
--
my_bus : process( cpu_clk, cpu_reset, cpu_rw, cpu_addr, cpu_data_out )
begin
	bus_clk   <= cpu_clk;
   bus_reset <= cpu_reset;
	bus_rw    <= cpu_rw;
   bus_addr  <= cpu_addr;
	if( cpu_rw = '1' ) then
	   bus_data <= "ZZZZZZZZ";
   else
	   bus_data <= cpu_data_out;
   end if;
end process;


--
-- Interrupts and Reset.
--
interrupts : process( Reset_n,
							 trap_irq, timer_irq, uart_irq )
begin
    cpu_halt  <= '0';
    cpu_hold  <= '0';
    cpu_irq   <= uart_irq or timer_irq;
	 cpu_nmi   <= trap_irq;
 	 cpu_reset <= not Reset_n; -- CPU reset is active high
end process;

--
-- flash led to indicate code is working
--
flash: process (SysClk, Reset_n, CountL )
begin
    if(SysClk'event and SysClk = '0') then
--	   if Reset_n = '0' then
--		  countL <= "000000000000000000000000";
--    else
        countL <= countL + 1;
--		end if;			 
    end if;
	 LED <= countL(21);
--	 baudclk <= countL(5);  -- 9.8MHz / 64 = 153,600 KHz =  9600Bd * 16
--	 baudclk <= countL(4);  -- 9.8MHz / 32 = 307,200 KHz = 19200Bd * 16
--	 baudclk <= countL(3);  -- 9.8MHz / 16 = 614,400 KHz = 38400Bd * 16
--  baudclk <= countL(2);  -- 4.9MHz / 8  = 614,400 KHz = 38400Bd * 16
	 dcd_n <= '0';
end process;


--
-- 57.6 Kbaud * 16 divider for 25 MHz system clock
--
my_clock: process( SysClk )
begin
    if(SysClk'event and SysClk = '0') then
		if( BaudCount = 26 )	then
		   BaudCount <= "00000";
		else
		   BaudCount <= BaudCount + 1;
		end if;			 
    end if;
    baudclk <= BaudCount(4);  -- 25MHz / 27  = 926,000 KHz = 57,870Bd * 16
	 dcd_n <= '0';
end process;
  
  
end my_computer; --===================== End of architecture =======================--

