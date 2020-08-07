library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;
use ieee.math_real.all;      

entity etb  is
end entity;

architecture arch of etb is

   signal DDRAM_CLK            : std_logic := '1';
   signal RESET                : std_logic := '1';
    
   signal DDRAM_OUT_BUSY       : std_logic := '0'; 
   signal DDRAM_OUT_DOUT       : std_logic_vector(63 downto 0); 
   signal DDRAM_OUT_DOUT_READY : std_logic; 
   signal DDRAM_OUT_BURSTCNT   : std_logic_vector(7 downto 0); 
   signal DDRAM_OUT_ADDR       : std_logic_vector(27 downto 0) := (others => '0'); 
   signal DDRAM_OUT_RD         : std_logic; 
   signal DDRAM_OUT_DIN        : std_logic_vector(63 downto 0);
   signal DDRAM_OUT_BE         : std_logic_vector(7 downto 0);
   signal DDRAM_OUT_WE         : std_logic; 
    
   signal DDRAM_IN_BUSY        : std_logic; 
   signal DDRAM_IN_DOUT        : std_logic_vector(31 downto 0); 
   signal DDRAM_IN_DOUT_READY  : std_logic; 
   signal DDRAM_IN_BURSTCNT    : std_logic_vector(3 downto 0); 
   signal DDRAM_IN_ADDR        : std_logic_vector(31 downto 0); 
   signal DDRAM_IN_RD          : std_logic := '0'; 
   signal DDRAM_IN_DIN         : std_logic_vector(31 downto 0) := (others => '0');
   signal DDRAM_IN_BE          : std_logic_vector(3 downto 0) := x"F";
   signal DDRAM_IN_WE          : std_logic := '0';

   type t_ramdata is array(0 to 8191) of std_logic_vector(63 downto 0);
   signal ramdata    : t_ramdata;
   signal shadowdata : t_ramdata;
   
   signal errorcount : integer := 0;

begin

   DDRAM_CLK <= not DDRAM_CLK after 5 ns;
   
   process
   begin
      RESET <= '0';
      wait for 1 us;
      RESET <= '1';
      wait for 1 us;
      RESET <= '0';
      wait;
   end process;
   
   
   iddrram_cache : entity work.l2_cache
   port map
   (
      CLK                  => DDRAM_CLK           ,
      RESET                => RESET,
                                          
      DDRAM_ADDR           => DDRAM_OUT_ADDR(27 downto 3)      ,
      DDRAM_DIN            => DDRAM_OUT_DIN       ,
      DDRAM_DOUT           => DDRAM_OUT_DOUT ,
      DDRAM_DOUT_READY     => DDRAM_OUT_DOUT_READY   ,
      DDRAM_BE             => DDRAM_OUT_BE      ,
      DDRAM_BURSTCNT       => DDRAM_OUT_BURSTCNT         ,
      DDRAM_BUSY           => DDRAM_OUT_BUSY        ,
      DDRAM_RD             => DDRAM_OUT_RD         ,
      DDRAM_WE             => DDRAM_OUT_WE        ,
                                                  
      CPU_ADDR             => DDRAM_IN_ADDR(31 downto 2)       ,
      CPU_DIN              => DDRAM_IN_DIN        ,
      CPU_DOUT             => DDRAM_IN_DOUT  ,
      CPU_DOUT_READY       => DDRAM_IN_DOUT_READY    ,
      CPU_BE               => DDRAM_IN_BE        ,
      CPU_BURSTCNT         => DDRAM_IN_BURSTCNT          ,
      CPU_BUSY             => DDRAM_IN_BUSY         ,
      CPU_RD               => DDRAM_IN_RD          ,
      CPU_WE               => DDRAM_IN_WE        ,

      VGA_DIN              => (7 downto 0 => '0'),
      VGA_MODE             => "000",
      VGA_WR_SEG           => (5 downto 0 => '0'),
      VGA_RD_SEG           => (5 downto 0 => '0'),
      VGA_FB_EN            => '0'
   );
   
   process
   begin
   
      for i in 0 to 100 loop
         wait until rising_edge(DDRAM_CLK);
         wait until rising_edge(DDRAM_CLK);
         wait until rising_edge(DDRAM_CLK);
         DDRAM_OUT_BUSY <= not DDRAM_OUT_BUSY;
      end loop;
      
      wait for 100 us;
   
   end process;
   
   process
      variable seed1, seed2 : integer := 999;
      variable r : real;
      variable nextaddr  : integer;
      variable nextdata  : std_logic_vector(31 downto 0);
      variable nextburst : integer;
   begin
      wait for 10 us;
   
      -- read initial values
      for i in 0 to 6 loop
         DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(i * 8, 32));
         DDRAM_IN_RD       <= '1';
         DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(i + 1, 4));
         wait until rising_edge(DDRAM_CLK); 
         while (DDRAM_IN_BUSY = '1') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         DDRAM_IN_RD       <= '0';
         for j in 0 to i loop
            while (DDRAM_IN_DOUT_READY = '0') loop
               wait until rising_edge(DDRAM_CLK);
            end loop;
            if (j mod 2 = 1) then
               if (unsigned(DDRAM_IN_DOUT) /= 0) then
                  report "wrong read value" severity warning;
                  errorcount <= errorcount + 1;
               end if;
            else
               if (unsigned(DDRAM_IN_DOUT) /= (10 + i + (j / 2))) then
                  report "wrong read value" severity warning;
                  errorcount <= errorcount + 1;
               end if;
            end if;
            wait until rising_edge(DDRAM_CLK);
         end loop;
      end loop;
      
      wait for 10 us;
      
      -- check first 4
      for i in 0 to 3 loop
         DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(i * 8, 32));
         DDRAM_IN_RD       <= '1';
         DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(1, 4));
         wait until rising_edge(DDRAM_CLK); 
         while (DDRAM_IN_BUSY = '1') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         DDRAM_IN_RD       <= '0';
         while (DDRAM_IN_DOUT_READY = '0') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         if (unsigned(DDRAM_IN_DOUT) /= (10 + i)) then
            report "wrong read value" severity warning;
            errorcount <= errorcount + 1;
         end if;
         wait until rising_edge(DDRAM_CLK);
      end loop;
      
      wait for 10 us;
      
      -- overwrite first 4 values
      for i in 0 to 3 loop
         DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(i * 8, 32));
         DDRAM_IN_WE       <= '1';
         DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(1, 4));
         DDRAM_IN_DIN      <= std_logic_vector(to_unsigned(i + 20, 32));
         wait until rising_edge(DDRAM_CLK); 
         while (DDRAM_IN_BUSY = '1') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         DDRAM_IN_WE       <= '0';
         wait until rising_edge(DDRAM_CLK);
      end loop;
      
      wait for 10 us;
      
      -- check first 4 again
      for i in 0 to 3 loop
         DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(i * 8, 32));
         DDRAM_IN_RD       <= '1';
         DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(1, 4));
         wait until rising_edge(DDRAM_CLK); 
         while (DDRAM_IN_BUSY = '1') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         DDRAM_IN_RD       <= '0';
         while (DDRAM_IN_DOUT_READY = '0') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         if (unsigned(DDRAM_IN_DOUT) /= (20 + i)) then
            report "wrong read value" severity warning;
            errorcount <= errorcount + 1;
         end if;
         wait until rising_edge(DDRAM_CLK);
      end loop;
      
      wait for 10 us;

      -- read many values in burst 1
      for i in 16 to 2047 loop
         DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(i * 8, 32));
         DDRAM_IN_RD       <= '1';
         DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(1, 4));
         wait until rising_edge(DDRAM_CLK); 
         while (DDRAM_IN_BUSY = '1') loop
            wait until rising_edge(DDRAM_CLK);
         end loop; 
         DDRAM_IN_RD       <= '0';
         while (DDRAM_IN_DOUT_READY = '0') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         if (unsigned(DDRAM_IN_DOUT) /= (10 + i)) then
            report "wrong read value" severity warning;
            errorcount <= errorcount + 1;
         end if;
         wait until rising_edge(DDRAM_CLK);
      end loop;
      
      wait for 10 us;
      
      -- read large addresses in burst 1
      for i in 4 to 23 loop
         DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned((2**i) * 8, 32));
         DDRAM_IN_RD       <= '1';
         DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(1, 4));
         wait until rising_edge(DDRAM_CLK); 
         while (DDRAM_IN_BUSY = '1') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         DDRAM_IN_RD       <= '0';
         while (DDRAM_IN_DOUT_READY = '0') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         if (unsigned(DDRAM_IN_DOUT) /= (10 + (2**i))) then
            report "wrong read value" severity warning;
            errorcount <= errorcount + 1;
         end if;
         wait until rising_edge(DDRAM_CLK);
      end loop;
      
      wait for 10 us;
      
      -- read many values in burst 2
      for i in 16 to 2047 loop
         DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(i * 8, 32));
         DDRAM_IN_RD       <= '1';
         DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(2, 4));
         wait until rising_edge(DDRAM_CLK); 
         while (DDRAM_IN_BUSY = '1') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         DDRAM_IN_RD       <= '0';
         for j in 0 to 1 loop
            while (DDRAM_IN_DOUT_READY = '0') loop
               wait until rising_edge(DDRAM_CLK);
            end loop;
            if (j = 1) then
               if (unsigned(DDRAM_IN_DOUT) /= 0) then
                  report "wrong read value" severity warning;
                  errorcount <= errorcount + 1;
               end if;
            else
               if (unsigned(DDRAM_IN_DOUT) /= (10 + i)) then
                  report "wrong read value" severity warning;
                  errorcount <= errorcount + 1;
               end if;
            end if;
            wait until rising_edge(DDRAM_CLK);
         end loop;
      end loop;
      
      wait for 10 us;
      
      -- enable share region
      DDRAM_IN_ADDR     <= x"000CE000";
      DDRAM_IN_WE       <= '1';
      DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(1, 4));
      DDRAM_IN_DIN      <= x"0000A345";
      wait until rising_edge(DDRAM_CLK); 
      while (DDRAM_IN_BUSY = '1') loop
         wait until rising_edge(DDRAM_CLK);
      end loop;
      DDRAM_IN_WE       <= '0';
      
      wait for 10 us;
      
      -- read from shared region
      DDRAM_IN_ADDR     <= x"000CE000";
      DDRAM_IN_RD       <= '1';
      DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(4, 4));
      wait until rising_edge(DDRAM_CLK); 
      while (DDRAM_IN_BUSY = '1') loop
         wait until rising_edge(DDRAM_CLK);
      end loop;
      DDRAM_IN_RD       <= '0';
      for j in 0 to 3 loop
         while (DDRAM_IN_DOUT_READY = '0') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         wait until rising_edge(DDRAM_CLK);
      end loop;
      
      wait for 10 us;
      
      -- random tests
      for i in 0 to 8191 loop
         shadowdata(i) <= ramdata(i);
      end loop;
      
      while (1 = 1) loop
         while (DDRAM_IN_BUSY = '1') loop
            wait until rising_edge(DDRAM_CLK);
         end loop;
         
         uniform(seed1, seed2, r);
         DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(integer(round(r * 16100.0)) * 4, 32));
         --DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(integer(round(r * 4.0)) * 4, 27));
         --DDRAM_IN_ADDR     <= std_logic_vector(to_unsigned(integer(round(r * 0.0)) * 8, 27));
         
         uniform(seed1, seed2, r);
         if (r > 0.5) then
            uniform(seed1, seed2, r);
            --nextburst := 2;
            nextburst := 1 + integer(round(r * 1.0));
            DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(nextburst, 4));
            DDRAM_IN_RD       <= '1';
            wait until rising_edge(DDRAM_CLK); 
            while (DDRAM_IN_BUSY = '1') loop
               wait until rising_edge(DDRAM_CLK);
            end loop;
            DDRAM_IN_RD       <= '0';
            nextaddr := to_integer(unsigned(DDRAM_IN_ADDR));
            for i in 1 to nextburst loop
               while (DDRAM_IN_DOUT_READY = '0') loop
                  wait until rising_edge(DDRAM_CLK);
               end loop;
               if (to_unsigned(nextaddr, 32)(2) = '1') then
                  if (DDRAM_IN_DOUT /= shadowdata(nextaddr / 8)(63 downto 32)) then
                     report "wrong read value" severity warning;
                     errorcount <= errorcount + 1;
                  end if;
               else
                  if (DDRAM_IN_DOUT /= shadowdata(nextaddr / 8)(31 downto 0)) then
                     report "wrong read value" severity warning;
                     errorcount <= errorcount + 1;
                  end if;
               end if;
               if (to_unsigned(nextaddr, 32)(2) = '1') then
                  if (DDRAM_IN_DOUT /= ramdata(nextaddr / 8)(63 downto 32)) then
                     report "wrong read value" severity warning;
                     errorcount <= errorcount + 1;
                  end if;
               else
                  if (DDRAM_IN_DOUT /= ramdata(nextaddr / 8)(31 downto 0)) then
                     report "wrong read value" severity warning;
                     errorcount <= errorcount + 1;
                  end if;
               end if;
               nextaddr := nextaddr + 4;
               wait until rising_edge(DDRAM_CLK);
            end loop;
         else
            uniform(seed1, seed2, r);
            --nextburst := 2;
            nextburst := 1 + integer(round(r * 1.0));
            DDRAM_IN_BURSTCNT <= std_logic_vector(to_unsigned(nextburst, 4));
            DDRAM_IN_WE       <= '1';
            wait for 1 ns;
            nextaddr := to_integer(unsigned(DDRAM_IN_ADDR));
            for i in 1 to nextburst loop
               uniform(seed1, seed2, r);
               nextdata := std_logic_vector(to_unsigned(integer(round(r * 40960.0)), 32));
               DDRAM_IN_DIN      <= nextdata;
               if (i = 2) then
                  DDRAM_IN_ADDR <= std_logic_vector(unsigned(DDRAM_IN_ADDR) + 4);
               end if;
               
               if (to_unsigned(nextaddr, 32)(2) = '1') then
                  shadowdata(nextaddr / 8)(63 downto 32) <= nextdata;
               else         
                  shadowdata(nextaddr / 8)(31 downto  0) <= nextdata;
               end if;
               nextaddr := nextaddr + 4;
               wait until rising_edge(DDRAM_CLK); 
               while (DDRAM_IN_BUSY = '1') loop
                  wait until rising_edge(DDRAM_CLK);
               end loop;
            end loop;
            DDRAM_IN_WE       <= '0';
         end if;
         
         wait for 1 ns;
         
      end loop;
      
      wait;
   
   end process;
   
   process
      variable address : integer;
   begin
      DDRAM_OUT_DOUT_READY <= '0';
   
      for i in 0 to 8191 loop
         ramdata(i) <= std_logic_vector(to_unsigned(i + 10, 64));
      end loop;
   
      while (0 = 0) loop
         if (DDRAM_OUT_BUSY = '0') then
            if (DDRAM_OUT_RD = '1') then
               address := to_integer(unsigned(DDRAM_OUT_ADDR)) / 8;
               wait until rising_edge(DDRAM_CLK);
               for i in 1 to to_integer(unsigned(DDRAM_OUT_BURSTCNT)) loop
                  DDRAM_OUT_DOUT_READY <= '1';
                  if (address < 8192) then
                     DDRAM_OUT_DOUT  <= ramdata(address + (i - 1)); 
                  else
                     DDRAM_OUT_DOUT  <= std_logic_vector(to_unsigned(address + 10 + (i - 1), 64));
                  end if;
                  wait until rising_edge(DDRAM_CLK);
               end loop;
               DDRAM_OUT_DOUT_READY <= '0';
            end if;
            
            if (DDRAM_OUT_WE = '1') then
               address := to_integer(unsigned(DDRAM_OUT_ADDR)) / 8;
               if (address < 8192) then
                  if (DDRAM_OUT_BE(7 downto 4) = "1111") then
                     ramdata(to_integer(unsigned(DDRAM_OUT_ADDR)) / 8)(63 downto 32) <= DDRAM_OUT_DIN(63 downto 32);
                  elsif (DDRAM_OUT_BE(3 downto 0) = "1111") then
                     ramdata(to_integer(unsigned(DDRAM_OUT_ADDR)) / 8)(31 downto 0) <= DDRAM_OUT_DIN(31 downto 0);
                  end if;
               end if;
            end if;
         end if;
         
         wait until rising_edge(DDRAM_CLK);
      end loop;
   
   end process;
   
   

end architecture;


