library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use ieee.math_real.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

entity ddrram_cache is
   port
   (
      CLK              : in  std_logic;
      RESET            : in  std_logic;

      -- CPU bus, master, 32bit
      CPU_ADDR         : in  std_logic_vector(26 downto 2);
      CPU_DIN          : in  std_logic_vector(31 downto 0);
      CPU_DOUT         : out std_logic_vector(31 downto 0);
      CPU_DOUT_READY   : out std_logic;
      CPU_BE           : in  std_logic_vector(3 downto 0);
      CPU_BURSTCNT     : in  std_logic_vector(3 downto 0);
      CPU_BUSY         : out std_logic;
      CPU_RD           : in  std_logic;
      CPU_WE           : in  std_logic;

      -- DMA bus, master, 8bit
      DMA_ADDR         : in  std_logic_vector(23 downto 0);
      DMA_DIN          : in  std_logic_vector(7 downto 0);
      DMA_DOUT         : out std_logic_vector(7 downto 0);
      DMA_DOUT_READY   : out std_logic;
      DMA_BUSY         : out std_logic;
      DMA_RD           : in  std_logic;
      DMA_WE           : in  std_logic;

      -- DDR3 RAM, slave, 64bit
      DDRAM_ADDR       : out std_logic_vector(26 downto 3);
      DDRAM_DIN        : out std_logic_vector(63 downto 0);
      DDRAM_DOUT       : in  std_logic_vector(63 downto 0);
      DDRAM_DOUT_READY : in  std_logic;
      DDRAM_BE         : out std_logic_vector(7 downto 0);
      DDRAM_BURSTCNT   : out std_logic_vector(7 downto 0);
      DDRAM_BUSY       : in  std_logic;
      DDRAM_RD         : out std_logic;
      DDRAM_WE         : out std_logic;

      -- VGA bus, slave, 8bit
      VGA_ADDR         : out std_logic_vector(16 downto 0);
      VGA_DIN          : in  std_logic_vector(7 downto 0);
      VGA_DOUT         : out std_logic_vector(7 downto 0);
      VGA_MODE         : in  std_logic_vector(2 downto 0);
      VGA_RD           : out std_logic;
      VGA_WE           : out std_logic;
      
      -- Snoop for Level 1 Cache
      SNOOP_ADDR       : out std_logic_vector(26 downto 2) := (others => '0');
      SNOOP_DIN        : out std_logic_vector(31 downto 0) := (others => '0');
      SNOOP_BE         : out std_logic_vector(3 downto 0) := (others => '0');
      SNOOP_WE         : out std_logic := '0'
   );
end entity;

architecture arch of ddrram_cache is

   -- cache settings
   constant LINES          : integer := 32; -- setting to 16 will half both logic and memory required, ~10% less performance
   constant LINESIZE       : integer := 16; -- changes here only reduces BRAMs required, ~5% less performance
   constant ASSOCIATIVITY  : integer := 4;  -- setting to 2 will half both logic and memory required, ~12% less performance
   constant ADDRBITS       : integer := 23;

   -- cache control
   constant ASSO_BITS      : integer := integer(ceil(log2(real(ASSOCIATIVITY))));
   constant LINESIZE_BITS  : integer := integer(ceil(log2(real(LINESIZE))));
   constant LINE_BITS      : integer := integer(ceil(log2(real(LINES))));
   constant RAMSIZEBITS    : integer := integer(ceil(log2(real(LINESIZE * LINES))));

   constant LINEMASKLSB    : integer := integer(ceil(log2(real(LINESIZE))));
   constant LINEMASKMSB    : integer := LINEMASKLSB + integer(ceil(log2(real(LINES)))) - 1;

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
      READCACHE_OUT,
      VGAREAD,
      VGAWAIT,
      VGAWRITE
   );
   signal state : tstate := IDLE;

   -- memory
   type treaddata_cache is array(0 to ASSOCIATIVITY-1) of std_logic_vector(63 downto 0);
   signal readdata_cache   : treaddata_cache;
   signal cache_mux        : integer range 0 to ASSOCIATIVITY-1 := 0;

   signal read_addr        : std_logic_vector(23 downto 0) := (others => '0');
   signal burst_left       : integer range 0 to 15 := 0;

   signal memory_addr_a    : natural range 0 to (LINESIZE * LINES) - 1;
   signal memory_addr_b    : natural range 0 to (LINESIZE * LINES) - 1;
   signal memory_datain    : std_logic_vector(63 downto 0);
   signal memory_we        : std_logic_vector(0 to ASSOCIATIVITY-1);
   signal memory_be        : std_logic_vector(7 downto 0);

   signal fillcount        : integer range 0 to LINESIZE - 1;

   signal data64_high      : std_logic := '0';
   signal data64_high_1    : std_logic := '0';

   signal busy             : std_logic;

   -- internal mux
   signal ram_dout_ready   : std_logic;
   signal ram_burstcnt     : std_logic_vector(7 downto 0);
   signal ram_addr         : std_logic_vector(26 downto 3);
   signal ram_rd           : std_logic;
   signal ram_din          : std_logic_vector(63 downto 0);
   signal ram_be           : std_logic_vector(7 downto 0);
   signal ram_we           : std_logic;

   signal ch_req           : std_logic;
   signal ch_run           : std_logic;
   signal ch_rd            : std_logic;
   signal ch_we            : std_logic;
   signal ch_dout          : std_logic_vector(31 downto 0);
   signal ch_be            : std_logic_vector(3 downto 0);
   signal ch_burst         : std_logic_vector(3 downto 0);
   signal ch_din           : std_logic_vector(31 downto 0);
   signal ch_addr          : std_logic_vector(24 downto 0);

   signal rom_rgn          : std_logic;

   signal dma_be           : std_logic_vector(3 downto 0);

   signal vga_ram          : std_logic;
   signal vga_data         : std_logic_vector(31 downto 0);
   signal vga_data_r       : std_logic_vector(31 downto 0);
   signal vga_be           : std_logic_vector(3 downto 0);
   signal vga_bcnt         : integer range 0 to 7 := 0;
   signal vga_ba           : std_logic_vector(1 downto 0);
   signal vga_wr           : std_logic;
   signal vga_re           : std_logic;
   signal vga_wa           : std_logic_vector(14 downto 0);
   signal vga_rgn          : std_logic;
   signal vga_mask         : std_logic_vector(1 downto 0);
   signal vga_cmp          : std_logic_vector(1 downto 0);
begin

   DDRAM_BURSTCNT  <= ram_burstcnt;
   DDRAM_ADDR      <= ram_addr;
   DDRAM_RD        <= ram_rd;
   DDRAM_DIN       <= ram_din;
   DDRAM_BE        <= ram_be;
   DDRAM_WE        <= ram_we;

   CPU_BUSY        <= DDRAM_BUSY when state = IDLE else ch_run or busy;
   CPU_DOUT        <= ch_dout;
   CPU_DOUT_READY  <= not ch_run and ram_dout_ready;

   VGA_DOUT        <= vga_data(7 downto 0);
   VGA_WE          <= vga_wr and vga_be(0);
   VGA_RD          <= vga_re and vga_be(0);
   VGA_ADDR        <= vga_wa & vga_ba;

   DMA_BUSY        <= CPU_RD or CPU_WE or DDRAM_BUSY when state = IDLE else not ch_run or busy;
   DMA_DOUT_READY  <= ch_run and ram_dout_ready;

   process (ch_dout, DMA_ADDR)
   begin
      case(DMA_ADDR(1 downto 0)) is
         when "00" =>
            dma_be   <= "0001";
            DMA_DOUT <= ch_dout(7 downto 0);

         when "01" =>
            dma_be   <= "0010";
            DMA_DOUT <= ch_dout(15 downto 8);

         when "10" =>
            dma_be   <= "0100";
            DMA_DOUT <= ch_dout(23 downto 16);

         when "11" =>
            dma_be   <= "1000";
            DMA_DOUT <= ch_dout(31 downto 24);
            
         when others => null;
      end case;
   end process;

   ch_dout  <= vga_data_r when vga_ram = '1' else readdata_cache(cache_mux)(63 downto 32) when data64_high_1 = '1' else readdata_cache(cache_mux)(31 downto 0);
   ch_req   <= not (CPU_RD or CPU_WE);
   ch_rd    <= CPU_RD       when ch_req = '0' else DMA_RD;
   ch_we    <= CPU_WE       when ch_req = '0' else DMA_WE;
   ch_be    <= CPU_BE       when ch_req = '0' else dma_be;
   ch_din   <= CPU_DIN      when ch_req = '0' else DMA_DIN & DMA_DIN & DMA_DIN & DMA_DIN;
   ch_burst <= CPU_BURSTCNT when ch_req = '0' else "0001";
   ch_addr  <= CPU_ADDR     when ch_req = '0' else "000" & DMA_ADDR(23 downto 2);

   busy     <= vga_wr or ram_we;

   rom_rgn  <= '1' when (ch_addr(24 downto 14) = ("000" & x"0C")) or (ch_addr(24 downto 14) = ("000" & x"0F")) else '0';
   vga_rgn  <= '1' when (ch_addr(24 downto 15) = ("00" & x"05")) and ((ch_addr(14 downto 13) and vga_mask) = vga_cmp) else '0';
   
   process (CLK)
   begin
      if rising_edge(CLK) then
         case(VGA_MODE) is
            when "100" => -- 128K
               vga_mask <= "00";
               vga_cmp  <= "00";

            when "101" => -- lower 64K
               vga_mask <= "10";
               vga_cmp  <= "00";

            when "110" => -- 3rd 32K
               vga_mask <= "11";
               vga_cmp  <= "10";

            when "111" => -- top 32K
               vga_mask <= "11";
               vga_cmp  <= "11";

            when others => -- disable VGA RAM
               vga_mask <= "00";
               vga_cmp  <= "11";
         end case;
      end if;
   end process;

   process (CLK)
   begin
      if rising_edge(CLK) then

         ram_dout_ready   <= '0';
         memory_we        <= (others => '0');
         SNOOP_WE         <= '0';

         data64_high_1    <= data64_high;

         if (RESET = '1') then

            rrb           <= (others => (others => '0'));
            tag_dirty     <= (others => '1');
            state         <= IDLE;

         else

            if (DDRAM_BUSY = '0') then
               ram_rd   <= '0';
               ram_we   <= '0';
            end if;

            case(state) is

               when IDLE =>
                  vga_wr  <= '0';
                  vga_re  <= '0';
                  if (DDRAM_BUSY = '0') then
                     if (ch_rd = '1') then
                        ch_run               <= ch_req;
                        burst_left           <= to_integer(unsigned(ch_burst));
                        if vga_rgn = '1' then
                           vga_wa            <= ch_addr(14 downto 0);
                           vga_be            <= ch_be;
                           vga_bcnt          <= 3;
                           vga_re            <= '1';
                           vga_ba            <= "00";
                           state             <= VGAWAIT;
                        else
                           state             <= READONE;
                           read_addr         <= ch_addr(24 downto 1);
                           data64_high       <= ch_addr(0);
                        end if;
                     elsif (ch_we = '1' and rom_rgn = '0') then
                        ch_run               <= ch_req;
                        if vga_rgn = '1' then
                           vga_wa            <= ch_addr(14 downto 0);
                           if ch_be(2 downto 0) = "000" then
                              vga_data       <= x"000000" & ch_din(31 downto 24);
                              vga_be         <= "000" & ch_be(3);
                              vga_ba         <= "11";
                           elsif ch_be(1 downto 0) = "00" then
                              vga_data       <= x"0000" & ch_din(31 downto 16);
                              vga_be         <= "00" & ch_be(3 downto 2);
                              vga_ba         <= "10";
                           elsif ch_be(0) = '0' then
                              vga_data       <= x"00" & ch_din(31 downto 8);
                              vga_be         <= '0' & ch_be(3 downto 1);
                              vga_ba         <= "01";
                           else
                              vga_data       <= ch_din;
                              vga_be         <= ch_be;
                              vga_ba         <= "00";
                           end if;
                           vga_wr            <= '1';
                           state             <= VGAWRITE;
                        else
                           state             <= WRITEONE;
                           ram_we            <= '1';
                           data64_high       <= ch_addr(0);
                           ram_burstcnt      <= x"01";
                           ram_addr          <= ch_addr(24 downto 1);
                           read_addr         <= ch_addr(24 downto 1);
                           memory_addr_b     <= to_integer(unsigned(ch_addr(RAMSIZEBITS downto 1)));
                           if (ch_addr(0) = '1') then
                              ram_din        <= ch_din & (31 downto 0 => '0');
                              memory_datain  <= ch_din & (31 downto 0 => '0');
                              ram_be         <= ch_be & ( 3 downto 0 => '0');
                              memory_be      <= ch_be & ( 3 downto 0 => '0');
                           else
                              ram_din        <= (63 downto 32 => '0') & ch_din;
                              memory_datain  <= (63 downto 32 => '0') & ch_din;
                              ram_be         <= ( 7 downto  4 => '0') & ch_be;
                              memory_be      <= ( 7 downto  4 => '0') & ch_be;
                           end if;
                           SNOOP_ADDR <= ch_addr;
                           SNOOP_DIN  <= ch_din;
                           SNOOP_BE   <= ch_be;
                           SNOOP_WE   <= '1';
                        end if;
                     end if;
                  end if;

               when WRITEONE =>
                  state <= IDLE;
                  for i in 0 to ASSOCIATIVITY - 1 loop
                     if (tag_dirty(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))) * ASSOCIATIVITY + i) = '0') then
                        if (tags_read(i) = read_addr(ADDRBITS downto RAMSIZEBITS)) then
                           memory_we(i)   <= '1';
                        end if;
                     end if;
                  end loop;

               when READONE =>
                  vga_ram                 <= '0';
                  state                   <= FILLCACHE;
                  ram_rd                  <= '1';
                  ram_addr                <= read_addr(read_addr'left downto LINESIZE_BITS) & (LINESIZE_BITS - 1 downto 0 => '0');
                  ram_be                  <= x"00";
                  ram_burstcnt            <= std_logic_vector(to_unsigned(LINESIZE, 8));
                  fillcount               <= 0;
                  memory_addr_b           <= to_integer(unsigned(read_addr(RAMSIZEBITS - 1 downto LINESIZE_BITS)) & (LINESIZE_BITS - 1 downto 0 => '0'));
                  --if (ASSOCIATIVITY > 1) then
                     cache_mux            <= to_integer(rrb(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB)))));
                  --end if;
                  for i in 0 to ASSOCIATIVITY - 1 loop
                     if (tag_dirty(to_integer(unsigned(read_addr(LINEMASKMSB downto LINEMASKLSB))) * ASSOCIATIVITY + i) = '0') then
                        if (tags_read(i) = read_addr(ADDRBITS downto RAMSIZEBITS)) then
                           ram_rd         <= '0';
                           cache_mux      <= i;
                           ram_dout_ready <= '1';
                           if (burst_left > 1) then
                              state       <= READONE;
                              burst_left  <= burst_left - 1;
                              if (data64_high = '1') then
                                 read_addr<= std_logic_vector(unsigned(read_addr) + 1);
                              end if;
                              data64_high <= not data64_high;
                           else
                              state       <= IDLE;
                           end if;
                        end if;
                     end if;
                  end loop;

               when FILLCACHE =>
                  if (DDRAM_DOUT_READY = '1') then
                     memory_datain        <= DDRAM_DOUT;
                     memory_we(cache_mux) <= '1';
                     memory_be            <= x"FF";
                     if (fillcount > 0) then
                        memory_addr_b     <= memory_addr_b + 1;
                     end if;

                     if (fillcount < LINESIZE - 1) then
                        fillcount         <= fillcount + 1;
                     else
                        state             <= READCACHE_OUT;
                     end if;
                  end if;

               when VGAWAIT =>
                  state                   <= VGAREAD;

               when VGAREAD =>
                  vga_ram                 <= '1';
                  vga_bcnt                <= vga_bcnt - 1;
                  vga_be                  <= '0' & vga_be(3 downto 1);
                  vga_ba                  <= std_logic_vector(unsigned(vga_ba) + 1);
                  vga_data                <= VGA_DIN & vga_data(31 downto 8);
                  state                   <= VGAWAIT;
                  if(vga_bcnt = 0) then
                     ram_dout_ready       <= '1';
                     vga_data_r           <= VGA_DIN & vga_data(31 downto 8);
                     if(burst_left > 1) then
                        vga_wa            <= std_logic_vector(unsigned(vga_wa) + 1);
                        vga_ba            <= "00";
                        vga_bcnt          <= 3;
                        vga_be            <= "1111";
                        burst_left        <= burst_left - 1;
                     else
                        state             <= IDLE;
                     end if;
                  end if;

               when VGAWRITE =>
                  vga_bcnt                <= vga_bcnt - 1;
                  vga_be                  <= '0' & vga_be(3 downto 1);
                  vga_ba                  <= std_logic_vector(unsigned(vga_ba) + 1);
                  vga_data                <= x"00" & vga_data(31 downto 8);
                  if vga_be(3 downto 1) = "000" then
                     state                <= IDLE;
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
         DATA_WIDTH => 64,
         BYTES      => 8
      )
      port map
      (
         clk        => CLK,

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
