library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use ieee.math_real.all;  

entity ddrram_cache is
   port 
   (
      DDRAM_CLK            : in  std_logic;
      RESET                : in  std_logic;
      
      -- ddrram side
      DDRAM_OUT_BUSY       : in  std_logic; 
      DDRAM_OUT_DOUT       : in  std_logic_vector(63 downto 0); 
      DDRAM_OUT_DOUT_READY : in  std_logic; 
      DDRAM_OUT_BURSTCNT   : out std_logic_vector(7 downto 0); 
      DDRAM_OUT_ADDR       : out std_logic_vector(28 downto 0); 
      DDRAM_OUT_RD         : out std_logic; 
      DDRAM_OUT_DIN        : out std_logic_vector(63 downto 0);
      DDRAM_OUT_BE         : out std_logic_vector(7 downto 0);
      DDRAM_OUT_WE         : out std_logic; 
      
      -- core side
      DDRAM_IN_BUSY        : out std_logic; 
      DDRAM_IN_DOUT        : out std_logic_vector(63 downto 0); 
      DDRAM_IN_DOUT_READY  : out std_logic; 
      DDRAM_IN_BURSTCNT    : in  std_logic_vector(7 downto 0); 
      DDRAM_IN_ADDR        : in  std_logic_vector(28 downto 0); 
      DDRAM_IN_RD          : in  std_logic; 
      DDRAM_IN_DIN         : in  std_logic_vector(63 downto 0);
      DDRAM_IN_BE          : in  std_logic_vector(7 downto 0);
      DDRAM_IN_WE          : in  std_logic
   );
end entity;

architecture arch of ddrram_cache is
   
   -- cache settings
   constant LINES             : integer := 32; -- setting to 16 will half both logic and memory required, ~10% less performance
   constant LINESIZE          : integer := 16; -- changes here only reduces BRAMs required, ~5% less performance
   constant ASSOCIATIVITY     : integer := 4;  -- setting to 2 will half both logic and memory required, ~12% less performance
   constant ADDRBITS          : integer := 25;
   
   -- fifo for incoming reads
   signal Fifo_din         : std_logic_vector(107 downto 0);
   signal Fifo_dout        : std_logic_vector(107 downto 0);
   signal Fifo_we          : std_logic;
   signal Fifo_nearfull    : std_logic;
   signal Fifo_rd          : std_logic;
   signal Fifo_empty       : std_logic;
   signal Fifo_valid       : std_logic := '0';  
   
   -- cache control
   constant ASSO_BITS     : integer := integer(ceil(log2(real(ASSOCIATIVITY))));
   constant LINESIZE_BITS : integer := integer(ceil(log2(real(LINESIZE))));
   constant RAMSIZEBITS   : integer := integer(ceil(log2(real(LINESIZE * LINES))));
   
   constant LINEMASKLSB   : integer := integer(ceil(log2(real(LINESIZE))));
   constant LINEMASKMSB   : integer := LINEMASKLSB + integer(ceil(log2(real(LINES)))) - 1;
  
   type t_rrb is array(0 to LINES-1) of unsigned(ASSO_BITS - 1 downto 0);
   signal rrb : t_rrb := (others => (others => '0'));
   
   type t_tags is array(0 to LINES-1, 0 to ASSOCIATIVITY - 1) of std_logic_vector(ADDRBITS - RAMSIZEBITS + 1 downto 0);
   signal tags : t_tags := (others => (others =>(others => '1')));
  
   type tState is
   (
      IDLE,
      READONE,
      FILLCACHE,
      READCACHE_OUT
   );
   signal state : tstate := IDLE;

   -- memory
   type treaddata_cache is array(0 to ASSOCIATIVITY-1) of std_logic_vector(63 downto 0);
   signal readdata_cache : treaddata_cache;
   signal cache_mux          : integer range 0 to ASSOCIATIVITY-1 := 0;
   
   signal read_addr          : std_logic_vector(25 downto 0) := (others => '0');
   signal burst_left         : integer range 0 to 255 := 0;
   
   signal memory_addr_a      : natural range 0 to (LINESIZE * LINES) - 1;
   signal memory_addr_b      : natural range 0 to (LINESIZE * LINES) - 1;
   signal memory_datain      : std_logic_vector(63 downto 0);
   signal memory_datain224   : std_logic_vector(223 downto 0);
   signal memory_we          : std_logic_vector(0 to ASSOCIATIVITY-1);
   signal memory_be          : std_logic_vector(7 downto 0);
   
   signal fillcount          : integer range 0 to LINESIZE - 1;

   signal DDRAM_IN_ADDR_64   : std_logic_vector(25 downto 0);

begin 

   DDRAM_IN_ADDR_64 <= DDRAM_IN_ADDR(28 downto 3);
   
   Fifo_din <= DDRAM_IN_RD & DDRAM_IN_WE & DDRAM_IN_BE & DDRAM_IN_DIN & DDRAM_IN_BURSTCNT & DDRAM_IN_ADDR_64;
   Fifo_we  <= DDRAM_IN_RD or DDRAM_IN_WE when Fifo_nearfull = '0' else '0';
   
   DDRAM_IN_BUSY <= Fifo_nearfull;
   
   iSyncFifo : entity work.SyncFifoBypass
   generic map
   (
      SIZE             => 128,
      DATAWIDTH        => 108,
      NEARFULLDISTANCE => 64
   )
   port map
   ( 
      clk      => DDRAM_CLK,
      reset    => RESET,
               
      Din      => Fifo_din,
      Wr       => Fifo_we,
      Full     => open,
      NearFull => Fifo_nearfull,
      
      Dout     => Fifo_dout,
      Rd       => Fifo_rd,
      Empty    => Fifo_empty,
      Valid    => Fifo_valid
   );
   
   Fifo_rd <= '1' when (DDRAM_OUT_BUSY = '0' and state = IDLE and Fifo_valid = '0') else '0';

   process (DDRAM_CLK)
   begin
      if rising_edge(DDRAM_CLK) then
         
         DDRAM_IN_DOUT_READY <= '0';
         memory_we           <= (others => '0');

         if (RESET = '1') then
            
            rrb           <= (others => (others => '0'));
            tags          <= (others => (others => (others => '1')));
            state         <= IDLE;
            
         else
            
            if (DDRAM_OUT_BUSY = '0') then
               DDRAM_OUT_RD  <= '0';
               DDRAM_OUT_WE  <= '0';
            end if;

            case(state) is
            
               when IDLE =>
                  if (Fifo_valid = '1') then
                     if (Fifo_dout(107) = '1') then
                        state      <= READONE;
                        read_addr  <= Fifo_dout(25 downto 0);
                        burst_left <= to_integer(unsigned(Fifo_dout(33 downto 26)));
                     elsif (Fifo_dout(106) = '1') then
                        DDRAM_OUT_DIN      <= Fifo_dout(97 downto 34);
                        DDRAM_OUT_WE       <= '1';
                        DDRAM_OUT_ADDR     <= Fifo_dout(25 downto 0) & "000";
                        DDRAM_OUT_BE       <= Fifo_dout(105 downto 98);
                        DDRAM_OUT_BURSTCNT <= x"01";
                        
                        memory_addr_b <= to_integer(unsigned(Fifo_dout(RAMSIZEBITS - 1 downto 0)));
                        memory_datain <= Fifo_dout(97 downto 34);
                        memory_we     <= (others => '0');
                        memory_be     <= Fifo_dout(105 downto 98);
                        for i in 0 to ASSOCIATIVITY - 1 loop
                           if (tags(to_integer(unsigned(Fifo_dout(LINEMASKMSB downto LINEMASKLSB))), i) = '0' & Fifo_dout(ADDRBITS downto RAMSIZEBITS)) then  
                              memory_we(i) <= '1';
                           end if;
                        end loop;
                     end if;
                  elsif (Fifo_empty = '1' and DDRAM_OUT_BUSY = '0' and DDRAM_IN_RD = '1') then
                     state      <= READONE;
                     read_addr  <= DDRAM_IN_ADDR_64;
                     burst_left <= to_integer(unsigned(DDRAM_IN_BURSTCNT));
                  end if;
            
               when READONE =>
                  state              <= FILLCACHE;
                  DDRAM_OUT_RD       <= '1';
                  DDRAM_OUT_ADDR     <= read_addr(read_addr'left downto LINESIZE_BITS) & (LINESIZE_BITS - 1 downto 0 => '0') & "000";
                  DDRAM_OUT_BE       <= x"00";
                  DDRAM_OUT_BURSTCNT <= std_logic_vector(to_unsigned(LINESIZE, 8));
                  fillcount          <= 0;
                  memory_addr_b      <= to_integer(unsigned(read_addr(RAMSIZEBITS - 1 downto LINESIZE_BITS)) & (LINESIZE_BITS - 1 downto 0 => '0'));
                  if (ASSOCIATIVITY > 1) then
                     cache_mux     <= to_integer(rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB)))));
                  end if;
                  for i in 0 to ASSOCIATIVITY - 1 loop
                     if (tags(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))), i) = '0' & read_addr(ADDRBITS downto RAMSIZEBITS)) then
                        DDRAM_OUT_RD         <= '0';
                        cache_mux            <= i;
                        DDRAM_IN_DOUT_READY  <= '1';
                        if (burst_left > 1) then
                           state      <= READONE;
                           burst_left <= burst_left - 1;
                           read_addr  <= std_logic_vector(unsigned(read_addr) + 1);
                        else
                           state      <= IDLE;
                        end if;
                     end if;
                  end loop;
                  
               when FILLCACHE => 
                  if (DDRAM_OUT_DOUT_READY = '1') then
                     memory_datain        <= DDRAM_OUT_DOUT;
                     memory_we(cache_mux) <= '1';
                     memory_be            <= x"FF";
                     if (fillcount > 0) then
                        memory_addr_b <= memory_addr_b + 1;
                     end if;
                     
                     if (fillcount < LINESIZE - 1) then
                        fillcount <= fillcount + 1;
                     else
                        state <= READCACHE_OUT;
                     end if;
                  end if;
                  
               when READCACHE_OUT =>
                  state <= READONE;
                  tags(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))), to_integer(rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB)))))) <= '0' & read_addr(ADDRBITS downto RAMSIZEBITS);
                  rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB)))) <= rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB)))) + 1;
              
            end case; 
            
         end if;

      end if;
   end process;
   
   DDRAM_IN_DOUT <= readdata_cache(cache_mux);
   
   memory_addr_a <= to_integer(unsigned(read_addr(RAMSIZEBITS - 1 downto 0)));
   
   gcache : for i in 0 to ASSOCIATIVITY-1 generate
   begin
      iRamMemory : entity work.SyncRamDualByteEnable
      generic map
      (
         ADDR_WIDTH => RAMSIZEBITS,
         DATA_WIDTH => 64,
         BYTES      => 8
      )
      port map
      (
         clk        => DDRAM_CLK,
         
         addr_a     => memory_addr_a,   
         datain_a   => (63 downto 0 => '0'), 
         dataout_a  => readdata_cache(i),
         we_a       => '0',    
         be_a       => x"FF",         
                  
         addr_b     => memory_addr_b,   
         datain_b   => memory_datain, 
         dataout_b  => open,
         we_b       => memory_we(i),
         be_b       => memory_be  
      );
   end generate;


end architecture;





