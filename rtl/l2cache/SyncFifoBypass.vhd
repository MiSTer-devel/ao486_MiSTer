library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use ieee.math_real.all;   

entity SyncFifoBypass is
   generic 
   (
      SIZE             : integer;
      DATAWIDTH        : integer;
      NEARFULLDISTANCE : integer
   );
   port 
   ( 
      clk      : in  std_logic;
      reset    : in  std_logic;
               
      Din      : in  std_logic_vector(DATAWIDTH - 1 downto 0);
      Wr       : in  std_logic; 
      Full     : out std_logic;
      NearFull : out std_logic;
      
      Dout     : out std_logic_vector(DATAWIDTH - 1 downto 0);
      Rd       : in  std_logic;
      Empty    : out std_logic;
      Valid    : out std_logic
   );
end SyncFifoBypass;

architecture arch of SyncFifoBypass is

   constant SIZEBITS : integer := integer(ceil(log2(real(SIZE))));

   type t_memory is array(0 to SIZE - 1) of std_logic_vector(DATAWIDTH - 1 downto 0);
   signal memory : t_memory;  

   signal wrcnt   : unsigned(SIZEBITS - 1 downto 0) := (others => '0');
   signal rdcnt   : unsigned(SIZEBITS - 1 downto 0) := (others => '0');
 
   signal fifocnt : unsigned(SIZEBITS - 1 downto 0) := (others => '0');
 
   signal full_wire     : std_logic;
   signal empty_wire    : std_logic;

begin

   full_wire      <= '1' when rdcnt = wrcnt+1                else '0';
   empty_wire     <= '1' when rdcnt = wrcnt                  else '0';

   process(clk)
   begin
      if rising_edge(clk) then
         if (reset = '1') then
            wrcnt   <= (others => '0');
            rdcnt   <= (others => '0');
            fifocnt <= (others => '0');
         else
            if (Wr = '1' and full_wire = '0') then
               if (Rd = '0') then
                  fifocnt <= fifocnt + 1;
               end if;
            elsif (Rd = '1' and empty_wire = '0') then
               fifocnt <= fifocnt - 1;
            end if;
            
            if (fifocnt < NEARFULLDISTANCE) then
               NearFull <= '0';
            else
               NearFull <= '1';
            end if;
         
            if (Wr = '1' and full_wire = '0') then
               memory(to_integer(wrcnt)) <= Din;
               wrcnt <= wrcnt+1;
            end if;
            
            Valid <= '0';
            if (Rd = '1') then
               if (empty_wire = '0') then
                  Dout <= memory(to_integer(rdcnt)); 
                  rdcnt <= rdcnt+1;
                  Valid <= '1';
               elsif (Wr = '1') then
                  Dout  <= Din; 
                  rdcnt <= rdcnt+1;
                  Valid <= '1';
               end if;
            end if;
         end if;
      end if;
   end process;
  
   Full      <= full_wire;
   Empty     <= empty_wire;

end architecture;