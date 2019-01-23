--===========================================================================--
--
-- CPU68 Microprocessor Test Bench 5
-- Test Software - BLOCKRAM
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
library unisim;
	use unisim.all;
library simprim;
   use simprim.all;

entity testbench5 is
end testbench5;

-------------------------------------------------------------------------------
-- Architecture for memio Controller Unit
-------------------------------------------------------------------------------
architecture behavior of testbench5 is
  -----------------------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------------------

  -- CPU Interface signals
  signal SysClk      : Std_Logic;
  signal cpu_rw      : Std_Logic;
  signal cpu_addr    : Std_Logic_Vector(10 downto 0);
  signal cpu_data_out: Std_Logic_Vector(7 downto 0);
  signal ram_data_out: Std_Logic_Vector(7 downto 0);
  signal ram_cs      : Std_Logic;
 

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


my_ram: block_ram Port Map (
       MEMclk   => SysClk,
       MEMcs    => ram_cs,
		 MEMrw    => cpu_rw,
       MEMaddr  => cpu_addr,
       MEMrdata => ram_data_out,
       MEMwdata => cpu_data_out
    );

  -- *** Test Bench - User Defined Section ***
   tb : PROCESS
	variable count : integer;
   BEGIN

	SysClk <= '0';
   cpu_data_out <= "00000000";
	cpu_addr <= "00000000000";
	ram_cs <= '0';
	cpu_rw <= '1';
	for count in 0 to 5 loop

		SysClk <= '0';
		ram_cs <= '0';
		wait for 30 ns;
		cpu_addr <= "00111000111";
		cpu_data_out <= "11110000";
		cpu_rw <= '0'; -- write
		ram_cs <= '1';
		wait for 20 ns;
		SysClk <= '1';
		wait for 50 ns;

		SysClk <= '0';
		ram_cs <= '0';
		wait for 30 ns;
		cpu_addr <= "00111000110";
		cpu_data_out <= "10101010";
		cpu_rw <= '0'; -- write
		ram_cs <= '1';
		wait for 20 ns;
		SysClk <= '1';
		wait for 50 ns;

		SysClk <= '0';
		ram_cs <= '0';
		wait for 30 ns;
		cpu_addr <= "00111000111";
		cpu_data_out <= "00001111";
		cpu_rw <= '1'; -- read
		ram_cs <= '1';
		wait for 20 ns;
		SysClk <= '1';
		wait for 50 ns;

		SysClk <= '0';
		ram_cs <= '0';
		wait for 30 ns;
		cpu_addr <= "00111000110";
		cpu_data_out <= "00001111";
		cpu_rw <= '1'; -- read
		ram_cs <= '1';
		wait for 20 ns;
		SysClk <= '1';
		wait for 50 ns;
	end loop;

      wait; -- will wait forever
   END PROCESS;
-- *** End Test Bench - User Defined Section ***



end behavior; --===================== End of architecture =======================--

