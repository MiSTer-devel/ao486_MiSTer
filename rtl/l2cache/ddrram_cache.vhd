library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use ieee.math_real.all;  

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

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
      DDRAM_OUT_ADDR       : out std_logic_vector(26 downto 0); 
      DDRAM_OUT_RD         : out std_logic; 
      DDRAM_OUT_DIN        : out std_logic_vector(63 downto 0);
      DDRAM_OUT_BE         : out std_logic_vector(7 downto 0);
      DDRAM_OUT_WE         : out std_logic; 
      
      -- core side
      DDRAM_IN_BUSY        : out std_logic; 
      DDRAM_IN_DOUT        : out std_logic_vector(31 downto 0); 
      DDRAM_IN_DOUT_READY  : out std_logic; 
      DDRAM_IN_BURSTCNT    : in  std_logic_vector(2 downto 0); 
      DDRAM_IN_ADDR        : in  std_logic_vector(26 downto 0); 
      DDRAM_IN_RD          : in  std_logic; 
      DDRAM_IN_DIN         : in  std_logic_vector(31 downto 0);
      DDRAM_IN_BE          : in  std_logic_vector(3 downto 0);
      DDRAM_IN_WE          : in  std_logic
   );
end entity;

architecture arch of ddrram_cache is
   
   -- cache settings
   constant LINES             : integer := 32; -- setting to 16 will half both logic and memory required, ~10% less performance
   constant LINESIZE          : integer := 16; -- changes here only reduces BRAMs required, ~5% less performance
   constant ASSOCIATIVITY     : integer := 4;  -- setting to 2 will half both logic and memory required, ~12% less performance
   constant ADDRBITS          : integer := 23;
   
   -- fifo for incoming reads
   signal Fifo_din         : std_logic_vector(65 downto 0);
   signal Fifo_dout        : std_logic_vector(65 downto 0);
   signal Fifo_we          : std_logic;
   signal Fifo_nearfull    : std_logic;
   signal Fifo_rd          : std_logic;
   signal Fifo_empty       : std_logic;
   signal Fifo_valid       : std_logic := '0';  
   
   -- cache control
   constant ASSO_BITS     : integer := integer(ceil(log2(real(ASSOCIATIVITY))));
   constant LINESIZE_BITS : integer := integer(ceil(log2(real(LINESIZE))));
   constant LINE_BITS     : integer := integer(ceil(log2(real(LINES))));
   constant RAMSIZEBITS   : integer := integer(ceil(log2(real(LINESIZE * LINES))));
   
   constant LINEMASKLSB   : integer := integer(ceil(log2(real(LINESIZE))));
   constant LINEMASKMSB   : integer := LINEMASKLSB + integer(ceil(log2(real(LINES)))) - 1;
  
   type t_rrb is array(0 to LINES-1) of unsigned(ASSO_BITS - 1 downto 0);
   signal rrb : t_rrb := (others => (others => '0'));
   
   signal tag_dirty : std_logic_vector(0 to (LINES * ASSOCIATIVITY) -1) := (others => '1');
   
   type t_tags_data is array(0 to ASSOCIATIVITY-1) of std_logic_vector(ADDRBITS - RAMSIZEBITS downto 0);
   signal tags_read : t_tags_data;
  
   type tState is
   (
      IDLE,
      WRITEONE,
      READONE,
      FILLCACHE,
      READCACHE_OUT
   );
   signal state : tstate := IDLE;

   -- memory
   type treaddata_cache is array(0 to ASSOCIATIVITY-1) of std_logic_vector(63 downto 0);
   signal readdata_cache : treaddata_cache;
   signal cache_mux          : integer range 0 to ASSOCIATIVITY-1 := 0;
   
   signal read_addr          : std_logic_vector(23 downto 0) := (others => '0');
   signal burst_left         : integer range 0 to 7 := 0;
   
   signal memory_addr_a      : natural range 0 to (LINESIZE * LINES) - 1;
   signal memory_addr_b      : natural range 0 to (LINESIZE * LINES) - 1;
   signal memory_datain      : std_logic_vector(63 downto 0);
   signal memory_we          : std_logic_vector(0 to ASSOCIATIVITY-1);
   signal memory_be          : std_logic_vector(7 downto 0);
   
   signal fillcount          : integer range 0 to LINESIZE - 1;

   signal DDRAM_IN_ADDR_32   : std_logic_vector(24 downto 0);
   signal data64_high        : std_logic := '0';
   signal data64_high_1      : std_logic := '0';
   
   -- internal mux
   signal DDRAM_DOUT_READY : std_logic; 
   signal DDRAM_BURSTCNT   : std_logic_vector(7 downto 0); 
   signal DDRAM_ADDR       : std_logic_vector(26 downto 0); 
   signal DDRAM_RD         : std_logic; 
   signal DDRAM_DIN        : std_logic_vector(63 downto 0);
   signal DDRAM_BE         : std_logic_vector(7 downto 0);
   signal DDRAM_WE         : std_logic; 

begin 

   DDRAM_OUT_BURSTCNT   <= DDRAM_BURSTCNT;
   DDRAM_OUT_ADDR       <= DDRAM_ADDR;    
   DDRAM_OUT_RD         <= DDRAM_RD;      
   DDRAM_OUT_DIN        <= DDRAM_DIN;     
   DDRAM_OUT_BE         <= DDRAM_BE;      
   DDRAM_OUT_WE         <= DDRAM_WE;      
                           
   DDRAM_IN_BUSY        <= Fifo_nearfull;
   DDRAM_IN_DOUT        <= readdata_cache(cache_mux)(63 downto 32) when data64_high_1 = '1' else readdata_cache(cache_mux)(31 downto 0);
   DDRAM_IN_DOUT_READY  <= DDRAM_DOUT_READY;


   DDRAM_IN_ADDR_32 <= DDRAM_IN_ADDR(26 downto 2);
   
   Fifo_din <= DDRAM_IN_RD & DDRAM_IN_WE & DDRAM_IN_BE & DDRAM_IN_DIN & DDRAM_IN_BURSTCNT & DDRAM_IN_ADDR_32;
   Fifo_we  <= DDRAM_IN_RD or DDRAM_IN_WE when Fifo_nearfull = '0' else '0';
   
   iSyncFifo : entity work.SyncFifoBypass
   generic map
   (
      SIZE             => 128,
      DATAWIDTH        => 66,
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
   
   Fifo_rd <= '1' when (DDRAM_OUT_BUSY = '0' and Fifo_valid = '0' and (state = IDLE or state = WRITEONE)) else '0';

   process (DDRAM_CLK)
   begin
      if rising_edge(DDRAM_CLK) then
         
         DDRAM_DOUT_READY <= '0';
         memory_we           <= (others => '0');
         
         data64_high_1 <= data64_high;

         if (RESET = '1') then
            
            rrb           <= (others => (others => '0'));
            tag_dirty     <= (others => '1');
            state         <= IDLE;
            
         else
            
            if (DDRAM_OUT_BUSY = '0') then
               DDRAM_RD  <= '0';
               DDRAM_WE  <= '0';
            end if;

            case(state) is
            
               when IDLE =>
                  if (Fifo_valid = '1') then
                     if (Fifo_dout(65) = '1') then
                        state       <= READONE;
                        read_addr   <= Fifo_dout(24 downto 1);
                        data64_high <= Fifo_dout(0);
                        burst_left  <= to_integer(unsigned(Fifo_dout(27 downto 25)));
                     elsif (Fifo_dout(64) = '1') then
                        state          <= WRITEONE;
                        DDRAM_WE       <= '1';
                        DDRAM_ADDR     <= Fifo_dout(24 downto 1) & "000";
                        read_addr      <= Fifo_dout(24 downto 1);
                        DDRAM_BURSTCNT <= x"01";
                        memory_addr_b  <= to_integer(unsigned(Fifo_dout(RAMSIZEBITS downto 1)));
                        if (Fifo_dout(0) = '1') then
                           DDRAM_DIN      <= Fifo_dout(59 downto 28) & (31 downto 0 => '0');
                           memory_datain  <= Fifo_dout(59 downto 28) & (31 downto 0 => '0');
                           DDRAM_BE       <= Fifo_dout(63 downto 60) & ( 3 downto 0 => '0');
                           memory_be      <= Fifo_dout(63 downto 60) & ( 3 downto 0 => '0');
                        else
                           DDRAM_DIN      <= (63 downto 32 => '0') & Fifo_dout(59 downto 28);
                           memory_datain  <= (63 downto 32 => '0') & Fifo_dout(59 downto 28);
                           DDRAM_BE       <= ( 7 downto  4 => '0') & Fifo_dout(63 downto 60);
                           memory_be      <= ( 7 downto  4 => '0') & Fifo_dout(63 downto 60);
                        end if;
                     end if;
                  elsif (Fifo_empty = '1' and DDRAM_OUT_BUSY = '0' and DDRAM_IN_RD = '1') then
                     state       <= READONE;
                     read_addr   <= DDRAM_IN_ADDR_32(24 downto 1);
                     data64_high <= DDRAM_IN_ADDR_32(0);
                     burst_left  <= to_integer(unsigned(DDRAM_IN_BURSTCNT));
                  end if;
                  
               when WRITEONE =>
                  state <= IDLE;
                  for i in 0 to ASSOCIATIVITY - 1 loop
                     if (tag_dirty(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))) * ASSOCIATIVITY + i) = '0') then
                        if (tags_read(i) = read_addr(ADDRBITS downto RAMSIZEBITS)) then  
                           memory_we(i) <= '1';
                        end if;
                     end if;
                  end loop;
            
               when READONE =>
                  state          <= FILLCACHE;
                  DDRAM_RD       <= '1';
                  DDRAM_ADDR     <= read_addr(read_addr'left downto LINESIZE_BITS) & (LINESIZE_BITS - 1 downto 0 => '0') & "000";
                  DDRAM_BE       <= x"00";
                  DDRAM_BURSTCNT <= std_logic_vector(to_unsigned(LINESIZE, 8));
                  fillcount          <= 0;
                  memory_addr_b      <= to_integer(unsigned(read_addr(RAMSIZEBITS - 1 downto LINESIZE_BITS)) & (LINESIZE_BITS - 1 downto 0 => '0'));
                  if (ASSOCIATIVITY > 1) then
                     cache_mux     <= to_integer(rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB)))));
                  end if;
                  for i in 0 to ASSOCIATIVITY - 1 loop
                     if (tag_dirty(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))) * ASSOCIATIVITY + i) = '0') then
                        if (tags_read(i) = read_addr(ADDRBITS downto RAMSIZEBITS)) then
                           DDRAM_RD          <= '0';
                           cache_mux         <= i;
                           DDRAM_DOUT_READY  <= '1';
                           if (burst_left > 1) then
                              state       <= READONE;
                              burst_left  <= burst_left - 1;
                              if (data64_high = '1') then
                                 read_addr   <= std_logic_vector(unsigned(read_addr) + 1);
                              end if;
                              data64_high <= not data64_high;
                           else
                              state      <= IDLE;
                           end if;
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
                  tag_dirty(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))) * ASSOCIATIVITY + cache_mux) <= '0';
                  rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))))                                   <= rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB)))) + 1;
              
            end case; 
            
         end if;

      end if;
   end process;
   
   memory_addr_a <= to_integer(unsigned(read_addr(RAMSIZEBITS - 1 downto 0)));
   
   gcache : for i in 0 to ASSOCIATIVITY-1 generate
      signal wren : std_logic;
   begin
   
      wren <= '1' when (state = READCACHE_OUT and cache_mux = i) else '0';
      
      altdpram_component : altdpram
      GENERIC MAP (
         indata_aclr => "OFF",
         indata_reg => "INCLOCK",
         intended_device_family => "Cyclone V",
         lpm_type => "altdpram",
         outdata_aclr => "OFF",
         outdata_reg => "UNREGISTERED",
         ram_block_type => "MLAB",
         rdaddress_aclr => "OFF",
         rdaddress_reg => "UNREGISTERED",
         rdcontrol_aclr => "OFF",
         rdcontrol_reg => "UNREGISTERED",
         read_during_write_mode_mixed_ports => "CONSTRAINED_DONT_CARE",
         width => ADDRBITS - RAMSIZEBITS + 1,
         widthad => LINE_BITS,
         width_byteena => 1,
         wraddress_aclr => "OFF",
         wraddress_reg => "INCLOCK",
         wrcontrol_aclr => "OFF",
         wrcontrol_reg => "INCLOCK"
      )
      PORT MAP (
         inclock  => DDRAM_CLK,
         outclock => DDRAM_CLK,
      
         data      => read_addr(ADDRBITS downto RAMSIZEBITS),
         rdaddress => read_addr(LINEMASKMSB downto LINEMASKLSB),
         wraddress => read_addr(LINEMASKMSB downto LINEMASKLSB),
         wren      => wren,
         q         => tags_read(i)
      );
   
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





