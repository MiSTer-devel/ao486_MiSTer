library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use ieee.math_real.all;  

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

entity l1_icache is
   port 
   (
      CLK        : in  std_logic;
      RESET      : in  std_logic;
      
      CPU_REQ    : in  std_logic; 
      CPU_ADDR   : in  std_logic_vector(31 downto 0); 
      CPU_VALID  : out std_logic := '0'; 
      CPU_DONE   : out std_logic := '0'; 
      CPU_DATA   : out std_logic_vector(31 downto 0) := (others => '0');
      
      MEM_REQ    : out std_logic := '0'; 
      MEM_ADDR   : out std_logic_vector(31 downto 0) := (others => '0'); 
      MEM_DONE   : in  std_logic; 
      MEM_DATA   : in  std_logic_vector(31 downto 0);
      
      snoop_addr : in std_logic_vector(26 downto 2);
      snoop_data : in std_logic_vector(31 downto 0);
      snoop_be   : in std_logic_vector( 3 downto 0);
      snoop_we   : in std_logic
   );
end entity;

architecture arch of l1_icache is
   
   -- cache settings
   constant LINES             : integer := 64; 
   constant LINESIZE          : integer := 8; 
   constant ASSOCIATIVITY     : integer := 2;  
   constant ADDRBITS          : integer := 29;
   constant CACHEBURST        : integer := 4;
   
   -- fifo for snoop
   signal Fifo_din         : std_logic_vector(60 downto 0);
   signal Fifo_dout        : std_logic_vector(60 downto 0);
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
   
   signal CPU_REQ_hold : std_logic := '0';

   -- memory
   type treaddata_cache is array(0 to ASSOCIATIVITY-1) of std_logic_vector(31 downto 0);
   signal readdata_cache : treaddata_cache;
   signal cache_mux          : integer range 0 to ASSOCIATIVITY-1 := 0;
   
   signal read_addr          : std_logic_vector(ADDRBITS downto 0) := (others => '0');
   
   signal memory_addr_a      : natural range 0 to (LINESIZE * LINES) - 1;
   signal memory_addr_b      : natural range 0 to (LINESIZE * LINES) - 1;
   signal memory_datain      : std_logic_vector(31 downto 0);
   signal memory_we          : std_logic_vector(0 to ASSOCIATIVITY-1);
   signal memory_be          : std_logic_vector(3 downto 0);
   
   signal fillcount          : integer range 0 to LINESIZE - 1;
   signal burstleft          : integer range 0 to CACHEBURST - 1;

   component simple_fifo_mlab
   generic 
   (
      width  : integer;
      widthu : integer
   );
   port
   (
      clk   : in  std_logic;                    
      rst_n : in  std_logic;                      
      sclr  : in  std_logic;                       
              
      rdreq : in  std_logic;                       
      wrreq : in  std_logic;                       
      data  : in  std_logic_vector(width-1 downto 0);    
           
      empty : out std_logic;                 
      full  : out std_logic;                
      q     : out std_logic_vector(width-1 downto 0); 
      usedw : out std_logic_vector(widthu-1 downto 0) 
   );
   end component;

begin 

   Fifo_din <= snoop_be & snoop_data & snoop_addr;
   
   isimple_fifo : simple_fifo_mlab
   generic map
   (
      widthu           => 4,
      width            => 61
   )
   port map
   ( 
      clk      => CLK,
      rst_n    => '1',
      sclr     => RESET,
               
      data     => Fifo_din,
      wrreq    => snoop_we,
      
      q        => Fifo_dout,
      rdreq    => Fifo_rd,
      empty    => Fifo_empty
   );

   Fifo_rd <= '1' when (state = IDLE and Fifo_empty = '0') else '0';
   
   CPU_DATA <= readdata_cache(cache_mux);

   process (CLK)
   begin
      if rising_edge(CLK) then
         
         memory_we     <= (others => '0');
         CPU_DONE      <= '0';
         CPU_VALID     <= '0';

         if (RESET = '1') then
            
            rrb           <= (others => (others => '0'));
            tag_dirty     <= (others => '1');
            state         <= IDLE;
            CPU_REQ_hold  <= '0';
            
         else
            
            if (CPU_REQ = '1') then
               CPU_REQ_hold <= '1';
            end if;
            
            case(state) is

               when IDLE =>
                  if (Fifo_empty = '0') then
                     state          <= WRITEONE;
                     read_addr      <= (ADDRBITS downto 25 => '0') & Fifo_dout(24 downto 0);
                     memory_addr_b  <= to_integer(unsigned(Fifo_dout(RAMSIZEBITS - 1 downto 0)));
                     memory_datain  <= Fifo_dout(56 downto 25);
                     memory_be      <= Fifo_dout(60 downto 57);
                  elsif (CPU_REQ = '1' or CPU_REQ_hold = '1') then
                     state        <= READONE;
                     read_addr    <= CPU_ADDR(CPU_ADDR'left downto 2);
                     CPU_REQ_hold <= '0';
                     burstleft    <= CACHEBURST - 1;
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
                  MEM_REQ        <= '1';
                  MEM_ADDR       <= read_addr(read_addr'left downto LINESIZE_BITS) & (LINESIZE_BITS - 1 downto 0 => '0') & "00";
                  fillcount          <= 0;
                  memory_addr_b      <= to_integer(unsigned(read_addr(RAMSIZEBITS - 1 downto LINESIZE_BITS)) & (LINESIZE_BITS - 1 downto 0 => '0'));
                  --if (ASSOCIATIVITY > 1) then
                     cache_mux     <= to_integer(rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB)))));
                  --end if;
                  for i in 0 to ASSOCIATIVITY - 1 loop
                     if (tag_dirty(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))) * ASSOCIATIVITY + i) = '0') then
                        if (tags_read(i) = read_addr(ADDRBITS downto RAMSIZEBITS)) then
                           MEM_REQ    <= '0';
                           cache_mux  <= i;
                           CPU_VALID  <= '1';
                           if (burstleft = 0) then
                              state      <= IDLE;
                              CPU_DONE   <= '1';
                           else
                              state      <= READONE;
                              burstleft  <= burstleft - 1;
                              read_addr  <= std_logic_vector(unsigned(read_addr) + 1);
                           end if;
                        end if;
                     end if;
                  end loop;
                  
               when FILLCACHE => 
                  if (MEM_DONE = '1') then
                     MEM_REQ              <= '0';
                     memory_datain        <= MEM_DATA;
                     memory_we(cache_mux) <= '1';
                     memory_be            <= x"F";
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
         inclock  => CLK,
         outclock => CLK,
      
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
         DATA_WIDTH => 32,
         BYTES      => 4
      )
      port map
      (
         clk        => CLK,
         
         addr_a     => memory_addr_a,   
         datain_a   => (31 downto 0 => '0'), 
         dataout_a  => readdata_cache(i),
         we_a       => '0',    
         be_a       => x"F",         
                  
         addr_b     => memory_addr_b,   
         datain_b   => memory_datain, 
         dataout_b  => open,
         we_b       => memory_we(i),
         be_b       => memory_be  
      );
   end generate;


end architecture;





