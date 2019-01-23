--===========================================================================--
--
--  S Y N T H E Z I A B L E    System68   System On a Chip
--
--  This core adheres to the GNU public license  
--
-- File name      : system68_tb.vhd
--
-- Purpose        : Top level file for a 6800 compatible system on a chip
--                  Designed for the Burch ED B5-Spartan IIe board with
--                  X2S300e FPGA,
--                  128K x 16 Word SRAM module (Modified B3_SRAM)
--                  CPU I/O module
--                  B5 Compact Flash Module
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
-- 28th June 2003
-- updated CPU to include Halt and Hold signals
-------------------------------------------------------------------------------
--
-- Memory Map:
--
-- $0000 - $7FFF RAM
-- $8000 - $9FFF IO
--     $8000 - $800F MiniUart / Acia
--     $8010 - $801F Compact Flash
--     $8020 - $802F Timer
--     $8030 - $803F IO register / Map switch
-- $A000 - $DFFF RAM
-- $E000 - $FFFF ROM (read) & DAT (write)
--
library ieee;
   use ieee.std_logic_1164.all;
   use IEEE.STD_LOGIC_ARITH.ALL;
   use IEEE.STD_LOGIC_UNSIGNED.ALL;
   use ieee.numeric_std.all;

entity System68 is
  port(
    -- Memory Interface signals B3-SRAM
    ram_csn     : out Std_Logic;  -- RAM Chip select (active low)
    ram_wrln    : out Std_Logic;  -- lower byte write strobe (active low)
    ram_wrun    : out Std_Logic;  -- upper byte write strobe (active low)
    ram_addr    : out Std_Logic_Vector(16 downto 0);   -- RAM Address bus
    ram_data    : inout Std_Logic_Vector(15 downto 0); -- RAM Data bus

	 -- Signals defined on B3-CPU-IO Module
    LED         : out std_logic;  -- Diagnostic LED Flasher

	 -- Uart Interface
    rxbit       : in  Std_Logic; -- UART receive data
	 txbit       : out Std_Logic; -- UART transmit data
    rts_n       : out Std_Logic; -- Request to send (active low)
    cts_n       : in  Std_Logic; -- Clear to send (active low)

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
    cf_rst_n     : out std_logic;
	 cf_cs0_n     : out std_logic;
	 cf_cs1_n     : out std_logic;
    cf_rd_n      : out std_logic;
    cf_wr_n      : out std_logic;
	 cf_cs16_n    : out std_logic;
    cf_a         : out std_logic_vector(2 downto 0);
    cf_d         : inout std_logic_vector(15 downto 0);
--    cf_intrq     : in std_logic;
--    cf_iordy     : in std_logic;
--  	cf_dase      : in std_logic;
--	   cf_pdiag     : in std_logic;
--	   cf_present   : in std_logic;

-- Test Pins
	 test_alu    : out std_logic_vector(15 downto 0); -- ALU output for timing constraints
	 test_cc     : out std_logic_vector(7 downto 0)   -- Condition Code Outputs for timing constraints
	 );
end;

-------------------------------------------------------------------------------
-- Architecture for memio Controller Unit
-------------------------------------------------------------------------------
architecture my_computer of System68 is
  -----------------------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------------------
  Signal SysClk    : std_logic;
  signal reset_n   : std_logic;

  -- Compact Flash BOOT ROM
--  signal boot_cs          : Std_Logic;
--  signal boot_data_out    : Std_Logic_Vector(7 downto 0);

  -- SWTBUG in Slices
  signal monitor_cs       : Std_Logic;
  signal monitor_data_out : Std_Logic_Vector(7 downto 0);

  -- SWTBUG in Block RAM
  signal swtbug_cs        : Std_Logic;
  signal swtbug_hold      : Std_Logic;
  signal swtbug_data_out  : Std_Logic_Vector(7 downto 0);

  -- UART Interface signals
  signal uart_cs       : Std_Logic;
  signal uart_data_out : Std_Logic_Vector(7 downto 0);  
  signal uart_irq      : Std_Logic;

  -- timer
  signal timer_cs       : std_logic;
  signal timer_data_out : std_logic_vector(7 downto 0);
  signal timer_irq      : std_logic;
  signal timer_out      : std_logic;

  -- trap
--  signal trap_cs       : std_logic;
--  signal trap_data_out : std_logic_vector(7 downto 0);
--  signal trap_irq      : std_logic;

  -- compact flash port
  signal cf_cs       : std_logic;
  signal cf_rd       : std_logic;
  signal cf_wr       : std_logic;
  signal cf_data_out : std_logic_vector(7 downto 0);

  -- RAM
  signal ram_cs       : std_logic; -- memory chip select
  signal ram_wrl      : std_logic; -- memory write lower
  signal ram_wru      : std_logic; -- memory write upper
  signal ram_data_out : std_logic_vector(7 downto 0);

  -- CPU Interface signals
  signal cpu_reset    : Std_Logic;
  signal cpu_rw       : std_logic;
  signal cpu_vma      : std_logic;
  signal cpu_halt     : std_logic;
  signal cpu_hold     : std_logic;
  signal cpu_irq      : std_logic;
  signal cpu_nmi      : std_logic;
  signal cpu_addr     : Std_Logic_Vector(15 downto 0);
  signal cpu_data_in  : Std_Logic_Vector(7 downto 0);
  signal cpu_data_out : Std_Logic_Vector(7 downto 0);

  -- test signals
--  signal test_alu     : std_logic_vector(15 downto 0); -- ALU output for timing constraints
--  signal test_cc      : std_logic_vector(7 downto 0);   -- Condition Code Outputs for timing constraints

  -- Dynamic Address Translation RAM
  signal dat_cs       : std_logic;
  signal dat_addr     : std_logic_vector(7 downto 0);

  -- Boot ROM map Switch
--  signal map_cs       : std_logic;
--  signal map_sw       : std_logic; -- reset high for ROM. Write low for RAM

  -- Clock Generator
--  signal CpuClk       : std_logic;     -- unbuffered clock - SysClk / 4
--  signal cpu_clk      : std_logic;     -- buffered clock
--  signal clk_divider  : std_logic_vector(1 downto 0); -- divide by 4 counter

  -- Flashing Led test signals
  signal countL       : std_logic_vector(23 downto 0);

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
	 nmi:      in  std_logic;
	 test_alu: out std_logic_vector(15 downto 0);
	 test_cc:  out std_logic_vector(7 downto 0)
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
     rst      : in  Std_Logic;  -- Reset input
     cs       : in  Std_Logic;
     rw       : in  Std_Logic;
     RxD      : in  Std_Logic;
     TxD      : out Std_Logic;
     CTS_n    : in  Std_Logic;
     RTS_n    : out Std_Logic;
     Irq      : out Std_logic;
     Addr     : in  Std_Logic;
     DataIn   : in  Std_Logic_Vector(7 downto 0); -- 
     DataOut  : out Std_Logic_Vector(7 downto 0)); -- 
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

--component trap
--	port (	
--	 clk        : in  std_logic;
--    rst        : in  std_logic;
--    cs         : in  std_logic;
--    rw         : in  std_logic;
--    vma        : in  std_logic;
--    addr       : in  std_logic_vector(15 downto 0);
--    data_in    : in  std_logic_vector(7 downto 0);
--	 data_out   : out std_logic_vector(7 downto 0);
--	 irq        : out std_logic
--  );
--end component trap;

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

--component boot_rom
--  port (
--	 cs    : in  std_logic;
--    addr  : in  Std_Logic_Vector(7 downto 0);  -- 256 byte cf boot rom
--	 data  : out Std_Logic_Vector(7 downto 0)
--  );
--end component boot_rom;

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
-- SWTBUG Monitor in Block RAM
--
component swtbug_rom
  port (
    clk    : in  std_logic;
  	 rst    : in  std_logic;
	 cs     : in  std_logic;
	 hold   : out std_logic;
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
	 clk	     => SysClk,
--    clk       => cpu_clk,
    rst       => cpu_reset,
    rw	     => cpu_rw,
    vma       => cpu_vma,
    address   => cpu_addr(15 downto 0),
    data_in   => cpu_data_in,
	 data_out  => cpu_data_out,
	 hold      => cpu_hold,
	 halt      => cpu_halt,
	 irq       => cpu_irq,
	 nmi       => cpu_nmi,
	 test_alu  => test_alu,
	 test_cc   => test_cc
  );

my_uart  : miniUART port map (
	 clk	     => SysClk,
--    clk       => cpu_clk,
	 rst       => cpu_reset,
    cs        => uart_cs,
	 rw        => cpu_rw,
	 RxD       => rxbit,
	 TxD       => txbit,
	 CTS_n     => cts_n,
	 RTS_n     => rts_n,
    Irq       => uart_irq,
    Addr      => cpu_addr(0),
	 Datain    => cpu_data_out,
	 DataOut   => uart_data_out
	 );

my_timer  : timer port map (
	 clk	     => SysClk,
--    clk       => cpu_clk,
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

--my_trap : trap port map (	
--	 clk        => cpu_clk,
--    rst        => cpu_reset,
--    cs         => trap_cs,
--    rw         => cpu_rw,
--	 vma        => cpu_vma,
--    addr       => cpu_addr,
--    data_in    => cpu_data_out,
--	 data_out   => trap_data_out,
--	 irq        => trap_irq
--  );

my_dat : dat_ram port map (
	 clk	     => SysClk,
--    clk       => cpu_clk,
	 rst        => cpu_reset,
	 cs         => dat_cs,
	 rw         => cpu_rw,
	 addr_hi    => cpu_addr(15 downto 12),
	 addr_lo    => cpu_addr(3 downto 0),
    data_in    => cpu_data_out,
	 data_out   => dat_addr(7 downto 0)
	 );

--my_boot_rom : boot_rom port map (
--    cs         => boot_cs,
--	 addr       => cpu_addr(7 downto 0),
--    data       => boot_data_out
--	 );

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
    clk      => SysClk,
	 rst      => cpu_reset,
    cs       => swtbug_cs,
    hold     => swtbug_hold,
    rw       => cpu_rw,
    addr     => cpu_addr(9 downto 0),
    wdata    => cpu_data_out,
    rdata    => swtbug_data_out
    );


--clock_buffer : BUFG port map (
--     i       => CpuClk,
--	  o       => cpu_clk
--  );
	 
----------------------------------------------------------------------
--
--  Processes to decode the CPU address
--
----------------------------------------------------------------------

decode: process( cpu_addr, cpu_rw, cpu_vma, cpu_data_in,
--                 boot_cs, boot_data_out,
					  monitor_cs, monitor_data_out,
				     ram_cs, ram_data_out,
				     swtbug_cs, swtbug_data_out,
				     uart_cs, uart_data_out,
				     cf_cs, cf_data_out,
				     timer_cs, timer_data_out,
--				     trap_cs, trap_data_out,
--					  map_cs, map_sw,
				     dat_cs )
begin
    --
	 -- Memory Map
	 --
      case cpu_addr(15 downto 13) is
		when "111" => -- $E000 - $FFFF
		   cpu_data_in <= monitor_data_out;            -- read ROM
		   monitor_cs <= cpu_vma;
		   swtbug_cs  <= '0';
--			boot_cs    <= '0';
			dat_cs     <= cpu_vma;                      -- write DAT
			ram_cs     <= '0';
			uart_cs    <= '0';
			cf_cs      <= '0';
			timer_cs   <= '0';
--			trap_cs    <= '0';
--			map_cs     <= '0';
--		when "1101" => -- $D000 - $DFFF
--		   monitor_cs <= '0';
--		   swtbug_cs  <= '0';
--		   if map_sw = '1' then
-- 		     cpu_data_in <= boot_data_out;             -- read ROM
--			  boot_cs     <= cpu_vma;                   -- boot rom read only
--			  dat_cs      <= '0';                       -- disable write to DAT
--			  ram_cs      <= cpu_vma;                   -- enable write to RAM
--			else
--			  cpu_data_in <= ram_data_out;              -- read RAM
--			  boot_cs     <= '0';                       -- disable boot rom
--			  dat_cs      <= cpu_vma;                   -- enable write DAT
--			  ram_cs      <= cpu_vma and cpu_rw;        -- disable write to RAM
--			end if;
--			uart_cs    <= '0';
--			cf_cs      <= '0';
--			timer_cs   <= '0';
--			trap_cs    <= '0';
--			map_cs     <= '0';
		when "110" => -- $C000 - $DFFF
		   cpu_data_in <= swtbug_data_out;
		   monitor_cs <= '0';
		   swtbug_cs  <= cpu_vma;
--			boot_cs    <= '0';
			dat_cs     <= '0';
			ram_cs     <= '0';
			uart_cs    <= '0';
			cf_cs      <= '0';
			timer_cs   <= '0';
--			trap_cs    <= '0';
--			map_cs     <= '0';
		when "100" => -- $8000 - $9FFF
		   monitor_cs <= '0';
		   swtbug_cs  <= '0';
--			boot_cs    <= '0';
			dat_cs     <= '0';
			ram_cs     <= '0';
		   case cpu_addr(6 downto 4) is
			--
			-- UART
			--
			when "000" => -- ($8000 - $800F)
		     cpu_data_in <= uart_data_out;
			  uart_cs     <= cpu_vma;
			  cf_cs       <= '0';
			  timer_cs    <= '0';
--			  trap_cs     <= '0';
--			  map_cs      <= '0';
			--
			-- Compact Flash
			--
			when "001" => -- ($8010 - $801F)
           cpu_data_in <= cf_data_out;
			  uart_cs     <= '0';
           cf_cs       <= cpu_vma;
			  timer_cs    <= '0';
--			  trap_cs     <= '0';
--			  map_cs      <= '0';
			--
			-- Timer
			--
			when "010" => -- ($8020 - $802F)
           cpu_data_in <= timer_data_out;
			  uart_cs     <= '0';
			  cf_cs       <= '0';
           timer_cs    <= cpu_vma;
--			  trap_cs     <= '0';
--			  map_cs      <= '0';
			--
			-- Memory Map switch
			--
			when "011" => -- ($8030 - $803F)
           cpu_data_in <= "00000000";
			  uart_cs     <= '0';
			  cf_cs       <= '0';
           timer_cs    <= '0';
--			  trap_cs     <= '0';
--			  map_cs      <= cpu_vma;
			--
			-- Trap hardware
			--
--			when "100" => -- ($8040 - $804F)
--           cpu_data_in <= trap_data_out;
--			  uart_cs     <= '0';
--			  cf_cs       <= '0';
--          timer_cs    <= '0';
--			  trap_cs     <= cpu_vma;
--			  map_cs      <= '0';
			--
			-- Null devices
			--
			when others => -- $8050 to $9FFF
           cpu_data_in <= "00000000";
			  uart_cs     <= '0';
			  cf_cs       <= '0';
			  timer_cs    <= '0';
--			  trap_cs     <= '0';
--			  map_cs      <= '0';
		   end case;
		 when "000" |  -- $0000 - $1FFF
	         "001" |  -- $2000 - $3FFF
			   "010" |  -- $4000 - $5FFF
			   "011" |  -- $6000 - $7FFF
		      "101" => -- $A000 - $BFFF
		   cpu_data_in <= ram_data_out;
		   monitor_cs <= '0';
		   swtbug_cs  <= '0';
--			boot_cs    <= '0';
		   ram_cs     <= cpu_vma;
		   dat_cs     <= '0';
		   uart_cs    <= '0';
		   cf_cs      <= '0';
		   timer_cs   <= '0';
--		   trap_cs    <= '0';
--		   map_cs     <= '0';
		 when others =>
		   cpu_data_in <= "00000000";
		   monitor_cs <= '0';
		   swtbug_cs  <= '0';
--			boot_cs    <= '0';
		   ram_cs     <= '0';
		   dat_cs     <= '0';
		   uart_cs    <= '0';
		   cf_cs      <= '0';
		   timer_cs   <= '0';
--		   trap_cs    <= '0';
--		   map_cs     <= '0';
	    end case;
end process;


----------------------------------------------------------------------
--
--  Processes to read and write B3_SRAM
--
----------------------------------------------------------------------
b3_sram: process( SysClk,   Reset_n,
                  cpu_addr, cpu_rw,   cpu_data_out,
                  ram_cs,   ram_wrl,  ram_wru,
		    		   dat_cs,   dat_addr, ram_data_out )
begin
    ram_csn <= not( ram_cs and Reset_n);
	 ram_wrl  <= dat_addr(5) and (not cpu_rw) and SysClk;
	 ram_wrln <= not ram_wrl;
    ram_wru  <= (not dat_addr(5)) and (not cpu_rw) and SysClk;
	 ram_wrun <= not ram_wru;
	 ram_addr(16 downto 12) <= dat_addr(4 downto 0);
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

	 if dat_addr(5) = '0' then
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
-- ROM Map switch
-- The Map switch output is initially set
-- On a Write to the Map Switch port, clear the Map Switch
-- and map the RAM in place of the boot ROM.
--
--map_proc : process( SysClk, Reset_n, map_cs, cpu_rw )
--begin
--  if Sysclk'event and Sysclk = '1' then
--    if Reset_n = '0' then
--	    map_sw <= '1';
--	 else
--	    if (map_cs = '1') and (cpu_rw = '0') then
--		   map_sw <= '0';
--		 else
--		   map_sw <= map_sw;
--		 end if;
--	 end if;
--  end if;
--end process;

--
-- Interrupts and Reset.
--
interrupts : process( Reset_n, cpu_vma,
--							 trap_irq,
							 swtbug_hold,
						    timer_irq, uart_irq )
begin
    cpu_halt  <= '0';
	 cpu_hold  <= swtbug_hold;
--	 cpu_hold  <= '0';
    cpu_irq   <= uart_irq or timer_irq;
--	 cpu_nmi   <= trap_irq;
	 cpu_nmi   <= '0';
 	 cpu_reset <= not Reset_n; -- CPU reset is active high
end process;

--
-- Divide by 4 clock generator
--
--clock_gen: process (SysClk, clk_divider )
--begin
--    if(SysClk'event and SysClk = '0') then
--      clk_divider <= clk_divider + "01";			 
--    end if;
--	 CpuClk <= clk_divider(1);
--end process;

--
-- flash led to indicate code is working
--
flash: process (SysClk, CountL )
begin
    if(SysClk'event and SysClk = '0') then
      countL <= countL + 1;			 
    end if;
	 LED <= countL(21);
end process;

-- *** Test Bench - User Defined Section ***
tb : PROCESS
	variable count : integer;
   BEGIN

	SysClk <= '0';
	Reset_n <= '0';

		for count in 0 to 512 loop
			SysClk <= '0';
			if count = 0 then
				Reset_n <= '0';
			elsif count = 1 then
				Reset_n <= '1';
			end if;
			wait for 100 ns;
			SysClk <= '1';
			wait for 100 ns;
		end loop;

      wait; -- will wait forever
   END PROCESS;
  
end my_computer; --===================== End of architecture =======================--

