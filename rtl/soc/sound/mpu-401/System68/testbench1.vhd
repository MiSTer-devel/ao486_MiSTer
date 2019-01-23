--===========================================================================--
--
-- CPU68 Microprocessor Test Bench 1
-- Print out "Hello World" on the Uart
--
--
-- John Kent 21st October 2002
--
--
-------------------------------------------------------------------------------
library ieee;
   use ieee.std_logic_1164.all;
   use IEEE.STD_LOGIC_ARITH.ALL;
   use IEEE.STD_LOGIC_UNSIGNED.ALL;
   use ieee.numeric_std.all;
library work;
--   use work.UART_Def.all;
--   use work.typedefines.all;
--   use work.memory.all;

entity my_testbench is
end my_testbench;

-------------------------------------------------------------------------------
-- Architecture for memio Controller Unit
-------------------------------------------------------------------------------
architecture behavior of my_testbench is
  -----------------------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------------------
  signal uart_irq    : Std_Logic;
  signal timer_irq   : std_logic;

  -- CPU Interface signals
  signal SysClk      : Std_Logic;
  signal cpu_reset   : Std_Logic;
  signal cpu_rw      : Std_Logic;
  signal cpu_vma     : Std_Logic;
  signal cpu_addr    : Std_Logic_Vector(15 downto 0);
  signal cpu_data_in : Std_Logic_Vector(7 downto 0);
  signal cpu_data_out: Std_Logic_Vector(7 downto 0);
  signal cpu_alu     : Std_Logic_Vector(15 downto 0);
  signal cpu_cc      : Std_Logic_Vector(7 downto 0);

  constant width   : integer := 8;
  constant memsize : integer := 64;

  type rom_array is array(0 to memsize-1) of std_logic_vector(width-1 downto 0);

  constant rom_data : rom_array :=
  (
    "11001110", "11111111", "11101000", -- E000 - CE E028  RESET LDX #MSG
	 "10000110", "00010001",             -- E003 - 86 11          LDAA #$11
	 "10110111", "10000000", "00000100", -- E005 - B7 8004        STAA UARTCR
    "10110110", "10000000", "00000100", -- E008 - B6 8004  POLL1 LDAA UARTCR
	 "10000101", "00000010",             -- E00B - 85 02          BITA #TXBE
--	 "00100111", "11111001",             -- E00D - 27 F9          BEQ POLL1
	 "00100110", "11111001",             -- E00D - 26 F9          BNE POLL1
	 "10100110", "00000000",             -- E00F - A6 00          LDAA 0,X
	 "00100111", "00000110",             -- E011 - 27 06          BEQ POLL2
	 "00001000",                         -- E013 - 08             INX
	 "10110111", "10000000", "00000101", -- E014 - B7 8005        STA UARTDR
    "00100110", "11101111",             -- E017 - 26 EF          BNE POLL1
	 "00001000", "10000000", "00000100", -- E019 - B6 8004  POLL2 LDAA UARTCR
	 "10000101", "00000001",             -- E01C - 85 01          BITA #RXBF
	 "00100111", "11111001",             -- E01E - 27 F9          BEQ POLL2
--	 "00100110", "11111001",             -- E01E - 26 F9          BEQ POLL2
	 "10110110", "10000000", "00000101", -- E020 - B6 8005        LDAA UARTDR
	 "00100000", "11100000", "00000000", -- E023 - 7E E000        JMP RESET
	 "00000000", "00000000",             -- E026 - 00 00          fcb $00,$00
    "01001000", "01100101", "01101100", -- E028 - 48 65 6c MSG   FCC "Hel"
	 "01101100", "01101111", "00100000", -- E02B - 6c 6f 20       FCC "lo "
	 "01010111", "01101111", "01110010", -- E02E - 57 6f 72       FCC "Wor"
    "01101100", "01100100",             -- E031 - 6c 64          FCC "ld"
    "00001010", "00001101", "00000000", -- E033 - 0a 0d 00       FCB LF,CR,NULL
    "00000000", "00000000",             -- E036 - 00 00          fcb null,null           
	 "11100000", "00000000",             -- E038 - E0 00          fdb $E000 ; Timer irq
	 "11100000", "00000000",             -- E03A - E0 00          fdb $E000 ; Ext IRQ
	 "11100000", "00000000",             -- E03C - E0 00          fcb $E000 ; SWI
	 "11100000", "00000000"              -- E03E - E0 00          fdb $E000 ; Reset
	 );

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
end component cpu68;


begin
cpu : cpu68  port map (    
	 clk	     => SysClk,
    rst	     => cpu_reset,
    rw	     => cpu_rw,
    vma       => cpu_vma,
    address   => cpu_addr(15 downto 0),
    data_in   => cpu_data_in,
	 data_out  => cpu_data_out,
	 hold      => cpu_hold,
	 halt      => cpu_halt,
	 irq       => uart_irq,
	 nmi       => timer_irq,
	 test_alu  => cpu_alu,
	 test_cc   => cpu_cc
  );

  -- *** Test Bench - User Defined Section ***
   tb : PROCESS
	variable count : integer;
   BEGIN

	cpu_reset <= '0';
	SysClk <= '0';
   uart_irq <= '0';
	timer_irq <= '0';

		for count in 0 to 256 loop
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


  rom : PROCESS( cpu_addr )
  begin
    cpu_data_in <= rom_data(conv_integer(cpu_addr(5 downto 0))); 
  end process;

end behavior; --===================== End of architecture =======================--

