--===========================================================================--
--
-- CPU68 Microprocessor Test Bench 4
-- Test Software - SWTBUG BLOCKRAM ROM
--
--
-- John Kent 4st September 2003
--
--
-------------------------------------------------------------------------------
library ieee;
   use ieee.std_logic_1164.all;
   use IEEE.STD_LOGIC_ARITH.ALL;
   use ieee.numeric_std.all;

entity testbench4 is
end testbench4;

-------------------------------------------------------------------------------
-- Architecture for memio Controller Unit
-------------------------------------------------------------------------------
architecture behavior of testbench4 is
  -----------------------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------------------
  signal cpu_irq    : std_Logic;
  signal cpu_firq   : std_logic;
  signal cpu_nmi    : std_logic;

  -- CPU Interface signals
  signal SysClk      : Std_Logic;
  signal cpu_reset   : Std_Logic;
  signal cpu_rw      : Std_Logic;
  signal cpu_vma     : Std_Logic;
  signal cpu_addr    : Std_Logic_Vector(15 downto 0);
  signal cpu_data_in : Std_Logic_Vector(7 downto 0);
  signal cpu_data_out: Std_Logic_Vector(7 downto 0);
  signal cpu_halt    : Std_logic;
  signal cpu_hold    : Std_logic;
  signal cpu_alu     : Std_Logic_Vector(15 downto 0);
  signal cpu_cc      : Std_Logic_Vector(7 downto 0);
  signal rom_data_out: Std_Logic_Vector(7 downto 0);
  signal rom_cs      : Std_Logic;
  signal rom_hold    : Std_Logic;
  signal ram_data_out: Std_Logic_Vector(7 downto 0);
  signal ram_cs      : Std_Logic;
 
component cpu68 is
  port (    
    clk     : in  std_logic;
    rst     : in  std_logic;
    rw      : out std_logic;		-- Asynchronous memory interface
    vma     : out std_logic;
    address : out std_logic_vector(15 downto 0);
    data_in : in  std_logic_vector(7 downto 0);
    data_out: out std_logic_vector(7 downto 0);
    hold    : in  std_logic;
    halt    : in  std_logic;
    irq     : in  std_logic;
    nmi     : in  std_logic;
    test_alu: out std_logic_vector(15 downto 0);
    test_cc : out std_logic_vector(7 downto 0)
  );
end component cpu68;

component swtbug_rom is
    Port (
       clk   : in  std_logic;
       rst   : in  std_logic;
       cs    : in  std_logic;
       hold  : out std_logic;
       rw    : in  std_logic;
       addr  : in  std_logic_vector (9 downto 0);
       wdata : in  std_logic_vector (7 downto 0);
       rdata : out std_logic_vector (7 downto 0)
    );
end component swtbug_rom;

component block_ram is
    Port (
       MEMclk   : in  std_logic;
       MEMcs    : in  std_logic;
       MEMrw    : in  std_logic;
       MEMaddr  : in  std_logic_vector (10 downto 0);
       MEMrdata : out std_logic_vector (7 downto 0);
       MEMwdata : in  std_logic_vector (7 downto 0)
    );
end component block_ram;

begin

my_cpu : cpu68  port map (    
    clk	     => SysClk,
    rst	     => cpu_reset,
    rw	     => cpu_rw,
    vma       => cpu_vma,
    address   => cpu_addr(15 downto 0),
    data_in   => cpu_data_in,
    data_out  => cpu_data_out,
    hold      => cpu_hold,
    halt      => cpu_halt,
    irq       => cpu_irq,
    nmi       => cpu_nmi,
    test_alu  => cpu_alu,
    test_cc   => cpu_cc
  );


my_ram : block_ram port map (
       MEMclk   => SysClk,
       MEMcs    => ram_cs,
       MEMrw    => cpu_rw,
       MEMaddr  => cpu_addr(10 downto 0),
       MEMrdata => ram_data_out,
       MEMwdata => cpu_data_out
    );

my_rom : swtbug_rom port map (
       clk      => SysClk,
       rst      => cpu_reset,
       cs       => rom_cs,
       hold     => rom_hold,
       rw       => cpu_rw,
       addr     => cpu_addr(9 downto 0),
       wdata    => cpu_data_out,
       rdata    => rom_data_out
    );

  -- *** Test Bench - User Defined Section ***
   tb : PROCESS
	variable count : integer;
   BEGIN

	cpu_reset <= '0';
	SysClk <= '0';
   cpu_irq <= '0';
   cpu_nmi <= '0';
	cpu_firq <= '0';
   cpu_halt <= '0';
	cpu_hold <= rom_hold;

		for count in 0 to 512 loop
			SysClk <= '0';
			if count = 0 then
				cpu_reset <= '1';
			elsif count = 1 then
				cpu_reset <= '0';
			end if;
			wait for 100 ns;
			SysClk <= '1';
			wait for 100 ns;
		end loop;

      wait; -- will wait forever
   END PROCESS;
-- *** End Test Bench - User Defined Section ***


  rom : PROCESS( cpu_addr, rom_data_out, ram_data_out )
  begin
    if( cpu_addr(15 downto 13) = "111" ) then
      cpu_data_in <= rom_data_out;
      ram_cs <= '0';
      rom_cs <= '1';
 	 else
      cpu_data_in <= ram_data_out;
      ram_cs <= '1';
      rom_cs <= '0';
 	 end if;
  end process;

end behavior; --===================== End of architecture =======================--

