--===========================================================================--
--
-- CPU68 Microprocessor Test Bench 3
--
-- 16 bit compare test (CPX)
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

  -- Sequencer Interface signals
  signal SysClk      : Std_Logic;
  signal cpu_reset   : Std_Logic;
  signal cpu_rw      : std_logic;
  signal cpu_vma     : std_logic;
  signal cpu_addr    : Std_Logic_Vector(15 downto 0);
  signal cpu_data_in : Std_Logic_Vector(7 downto 0);
  signal cpu_data_out: Std_Logic_Vector(7 downto 0);

  constant width   : integer := 8;
  constant memsize : integer := 64;

  type rom_array is array(0 to memsize-1) of std_logic_vector(width-1 downto 0);

  constant rom_data : rom_array :=
  (
    "10001110", "11111111", "11011101", -- FFC0 - 8E FFDD  RESET LDS #$FFDD
	 "11111110", "11111111", "11001110", -- FFC3 - FE FFCE        LDX BEGA
	 "00001000",                         -- FFC6 - 08        LOOP INX
	 "10111100", "11111111", "11010000", -- FFC7 - BC FFD0        CPX ENDA
    "00100011", "11111010",             -- FFCA - 23 FA    REENT BLS LOOP
	 "00100000", "11110010",             -- FFCC - 20 F2          BRA RESET
	 "00010010", "00110100",             -- FFCE - 12 34          FDB $1234
	 "00010010", "00110110",             -- FFD0 - 12 36          FDB $1236
	 -- the rest is junk
	 "00110111",                         -- FFD2 - 37             PSHB
	 "11100110", "00000001",             -- FFD3 - E6 01          LDAB 1,X
	 "11100001", "00000011",             -- FFD5 - E1 03          CMPB 3,X
	 "00110011",                         -- FFD7 - 33             PULB
	 "00111001",                         -- FFD8 - 39             RTS
	 "11111111", "11100000",             -- FFD9 - FF E0          FDB $FFE0
	 "01010101",                         -- FFDB - 55             FCB $55
	 "11111111", "11001000",             -- FFDC - FFC8           FDB REENT
	 "00100000", "11100000",             -- FFDE - 20 E0          BRA RESET
	 "00000000", "00000000",             -- FFE0 - 00 00          fcb $00,$00
	 "00000000", "00000000",             -- FFE2 - 00 00          fcb $00,$00
	 "00000000", "00000000",             -- FFE4 - 00 00          fcb $00,$00
	 "00000000", "00000000",             -- FFE6 - 00 00          fcb $00,$00
    "01001000", "01100101", "01101100", -- FFE8 - 48 65 6c MSG   FCC "Hel"
	 "01101100", "01101111", "00100000", -- FFEB - 6c 6f 20       FCC "lo "
	 "01010111", "01101111", "01110010", -- FFEE - 57 6f 72       FCC "Wor"
    "01101100", "01100100",             -- FFF1 - 6c 64          FCC "ld"
    "00001010", "00001101", "00000000", -- FFF3 - 0a 0d 00       FCB LF,CR,NULL
    "00000000", "00000000",             -- FFF6 - 00 00          fcb null,null           
	 "11111111", "11000000",             -- FFF8 - FF C0          fdb $FFC0 ; Timer irq
	 "11111111", "11000000",             -- FFFA - FF C0          fdb $FFC0 ; Ext IRQ
	 "11111111", "11000000",             -- FFFC - FF C0          fcb $FFC0 ; SWI
	 "11111111", "11000000"              -- FFFE - FF C0          fdb $FFC0 ; Reset
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

