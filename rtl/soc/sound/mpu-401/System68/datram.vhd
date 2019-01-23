--===========================================================================--
--
--  S Y N T H E Z I A B L E    Dynamic Address Translation Registers
--
--  www.OpenCores.Org - December 2002
--  This core adheres to the GNU public license  
--
-- File name      : datram.vhd
--
-- entity name    : dat_ram
--
-- Purpose        : Implements a Dynamic Address Translation RAM module
--                  Maps the high order 4 address bits to 8 address lines
--                  extending the memory addressing range to 1 Mbytes
--                  Memory segments are mapped on 4 KByte boundaries
--                  The DAT registers map to the top of memory 
--                  ($FFF0 - $FFFF) and are write only so can map over ROM.
--                  Since the DAT is not supported by SWTBUG for the 6800,
--                  the resgisters reset state map the bottom 64K of RAM. 
--                  
-- Dependencies   : ieee.Std_Logic_1164
--                  ieee.std_logic_unsigned
--
-- Author         : John E. Kent      
--
--===========================================================================----
--
-- Revision History:
--
-- Date          Revision  Author 
-- 10 Nov 2002   0.1       John Kent
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity dat_ram is
	port (	
	 clk       : in  std_logic;
    rst       : in  std_logic;
    cs        : in  std_logic;
    rw        : in  std_logic;
    addr_hi   : in  std_logic_vector(3 downto 0);
    addr_lo   : in  std_logic_vector(3 downto 0);
    data_in   : in  std_logic_vector(7 downto 0);
	 data_out  : out std_logic_vector(7 downto 0));
end;

architecture datram_arch of dat_ram is
signal dat_reg0 : std_logic_vector(7 downto 0);
signal dat_reg1 : std_logic_vector(7 downto 0);
signal dat_reg2 : std_logic_vector(7 downto 0);
signal dat_reg3 : std_logic_vector(7 downto 0);
signal dat_reg4 : std_logic_vector(7 downto 0);
signal dat_reg5 : std_logic_vector(7 downto 0);
signal dat_reg6 : std_logic_vector(7 downto 0);
signal dat_reg7 : std_logic_vector(7 downto 0);
signal dat_reg8 : std_logic_vector(7 downto 0);
signal dat_reg9 : std_logic_vector(7 downto 0);
signal dat_reg10 : std_logic_vector(7 downto 0);
signal dat_reg11 : std_logic_vector(7 downto 0);
signal dat_reg12 : std_logic_vector(7 downto 0);
signal dat_reg13 : std_logic_vector(7 downto 0);
signal dat_reg14 : std_logic_vector(7 downto 0);
signal dat_reg15 : std_logic_vector(7 downto 0);

begin

---------------------------------
--
-- Write DAT RAM
--
---------------------------------

dat_write : process( clk, rst, addr_lo, cs, rw, data_in,
                     dat_reg0, dat_reg1, dat_reg2, dat_reg3,
                     dat_reg4, dat_reg5, dat_reg6, dat_reg7,
                     dat_reg8, dat_reg9, dat_reg10, dat_reg11,
                     dat_reg12, dat_reg13, dat_reg14, dat_reg15 )
begin
  if clk'event and clk = '0' then
    if rst = '1' then
      dat_reg0 <= "00000000";
      dat_reg1 <= "00000001";
      dat_reg2 <= "00000010";
      dat_reg3 <= "00000011";
      dat_reg4 <= "00000100";
      dat_reg5 <= "00000101";
      dat_reg6 <= "00000110";
      dat_reg7 <= "00000111";
      dat_reg8 <= "00001000";
      dat_reg9 <= "00001001";
      dat_reg10 <= "00001010";
      dat_reg11 <= "00001011";
      dat_reg12 <= "00001100";
      dat_reg13 <= "00001101";
      dat_reg14 <= "00001110";
      dat_reg15 <= "00001111";
    else
	   if cs = '1' and rw = '0' then
        case addr_lo is
	     when "0000" =>
		    dat_reg0 <= data_in;
	     when "0001" =>
		    dat_reg1 <= data_in;
	     when "0010" =>
		    dat_reg2 <= data_in;
	     when "0011" =>
		    dat_reg3 <= data_in;
	     when "0100" =>
		    dat_reg4 <= data_in;
	     when "0101" =>
		    dat_reg5 <= data_in;
	     when "0110" =>
		    dat_reg6 <= data_in;
	     when "0111" =>
		    dat_reg7 <= data_in;
	     when "1000" =>
		    dat_reg8 <= data_in;
	     when "1001" =>
		    dat_reg9 <= data_in;
	     when "1010" =>
		    dat_reg10 <= data_in;
	     when "1011" =>
		    dat_reg11 <= data_in;
	     when "1100" =>
		    dat_reg12 <= data_in;
	     when "1101" =>
		    dat_reg13 <= data_in;
	     when "1110" =>
		    dat_reg14 <= data_in;
	     when "1111" =>
		    dat_reg15 <= data_in;
        when others =>
		    null;
		  end case;
	   end if;
	 end if;
  end if;
end process;

dat_read : process(  addr_hi,
                     dat_reg0, dat_reg1, dat_reg2, dat_reg3,
                     dat_reg4, dat_reg5, dat_reg6, dat_reg7,
                     dat_reg8, dat_reg9, dat_reg10, dat_reg11,
                     dat_reg12, dat_reg13, dat_reg14, dat_reg15 )
begin
      case addr_hi is
	     when "0000" =>
		    data_out <= dat_reg0;
	     when "0001" =>
		    data_out <= dat_reg1;
	     when "0010" =>
		    data_out <= dat_reg2;
	     when "0011" =>
		    data_out <= dat_reg3;
	     when "0100" =>
		    data_out <= dat_reg4;
	     when "0101" =>
		    data_out <= dat_reg5;
	     when "0110" =>
		    data_out <= dat_reg6;
	     when "0111" =>
		    data_out <= dat_reg7;
	     when "1000" =>
		    data_out <= dat_reg8;
	     when "1001" =>
		    data_out <= dat_reg9;
	     when "1010" =>
		    data_out <= dat_reg10;
	     when "1011" =>
		    data_out <= dat_reg11;
	     when "1100" =>
		    data_out <= dat_reg12;
	     when "1101" =>
		    data_out <= dat_reg13;
	     when "1110" =>
		    data_out <= dat_reg14;
	     when "1111" =>
		    data_out <= dat_reg15;
        when others =>
		    null;
		end case;
end process;

end datram_arch;
	
