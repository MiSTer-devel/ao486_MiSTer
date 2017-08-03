library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mix_2chan_8bits is
  port
  (
    wb_clk_i        : in std_logic;
    wb_rst_i        : in std_logic;
    
    a_l_i           : in std_logic_vector(7 downto 0);
    a_r_i           : in std_logic_vector(7 downto 0);

    b_l_i           : in std_logic_vector(7 downto 0);
    b_r_i           : in std_logic_vector(7 downto 0);

    mixed_l_o       : out std_logic_vector(7 downto 0);
    mixed_r_o       : out std_logic_vector(7 downto 0)
  );
end entity mix_2chan_8bits;

architecture SYN of mix_2chan_8bits is

  signal ABplus_l   : std_logic_vector(8 downto 0) := (others => '0');
  signal ABplus_r   : std_logic_vector(8 downto 0) := (others => '0');
  signal ABprod_l   : std_logic_vector(17 downto 0) := (others => '0');
  signal ABprod_r   : std_logic_vector(17 downto 0) := (others => '0');
  signal ABmixed_l  : std_logic_vector(8 downto 0) := (others => '0');
  signal ABmixed_r  : std_logic_vector(8 downto 0) := (others => '0');

begin

  -- For mixing 2 channels: Aout = A+B - A*B/(2^n)
  -- - where n - number of bits in A,B
  
  abadd_l : entity work.addsubu8
    port map
    (
      clock		    => wb_clk_i,
      dataa       => a_l_i,
      datab       => b_l_i,
      add_sub		  => '1',
      result		  => ABplus_l(7 downto 0),
      cout		    => ABplus_l(8)
    );

  abadd_r : entity work.addsubu8
    port map
    (
      clock		    => wb_clk_i,
      dataa       => a_r_i,
      datab       => b_r_i,
      add_sub		  => '1',
      result		  => ABplus_r(7 downto 0),
      cout		    => ABplus_r(8)
    );

  abmult_l : entity work.mult9
    port map
    (
      clock		          => wb_clk_i,
      dataa(8)          => '0',
      dataa(7 downto 0) => a_l_i,
      datab(8)          => '0',
      datab(7 downto 0) => b_l_i,
      result		        => ABprod_l
    );
    
  abmult_r : entity work.mult9
    port map
    (
      clock		          => wb_clk_i,
      dataa(8)          => '0',
      dataa(7 downto 0) => a_r_i,
      datab(8)          => '0',
      datab(7 downto 0) => b_r_i,
      result		        => ABprod_r
    );

  absub_l : entity work.addsubu9
    port map
    (
      clock		    => wb_clk_i,
      dataa       => ABplus_l,
      datab       => ABprod_l(16 downto 8),
      add_sub		  => '0',
      result		  => ABmixed_l,
      cout		    => open
    );
    
  absub_r : entity work.addsubu9
    port map
    (
      clock		    => wb_clk_i,
      dataa       => ABplus_r,
      datab       => ABprod_r(16 downto 8),
      add_sub		  => '0',
      result		  => ABmixed_r,
      cout		    => open
    );
    
  -- assign output
  mixed_l_o <= (others => '1') when ABmixed_l(8) = '1' else ABmixed_l(7 downto 0);
  mixed_r_o <= (others => '1') when ABmixed_r(8) = '1' else ABmixed_r(7 downto 0);

end architecture SYN;

