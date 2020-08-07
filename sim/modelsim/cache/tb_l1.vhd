library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;
use ieee.math_real.all;      

entity etb  is
end entity;

architecture arch of etb is

   constant memsize  : integer := 8192;

   signal CLK        : std_logic := '1';
   signal RESET      : std_logic := '1';
                     
   signal CPU_REQ    : std_logic := '0'; 
   signal CPU_VALID  : std_logic; 
   signal CPU_ADDR   : std_logic_vector(31 downto 0); 
   signal CPU_DONE   : std_logic; 
   signal CPU_DATA   : std_logic_vector(31 downto 0);
                     
   signal MEM_REQ    : std_logic; 
   signal MEM_ADDR   : std_logic_vector(31 downto 0); 
   signal MEM_DONE   : std_logic; 
   signal MEM_DATA   : std_logic_vector(31 downto 0);
   
   signal snoop_addr : std_logic_vector(27 downto 2) := (others => '0');
   signal snoop_data : std_logic_vector(31 downto 0) := (others => '0');
   signal snoop_be   : std_logic_vector( 3 downto 0) := (others => '0');
   signal snoop_we   : std_logic := '0';
   
   type t_ramdata is array(0 to memsize - 1) of std_logic_vector(31 downto 0);
   signal ramdata    : t_ramdata;
   signal shadowram  : t_ramdata;
   
   signal errorcount : integer := 0;
   
   signal block_write : std_logic := '0';

begin

   CLK <= not CLK after 5 ns;
   
   RESET <= '0' after 100 ns;
   
   il1_icache : entity work.l1_icache
   port map
   (
      CLK        => CLK     ,
      RESET      => RESET   ,
      pr_reset   => '0'   ,
                            
      CPU_REQ    => CPU_REQ ,
      CPU_VALID  => CPU_VALID ,
      CPU_ADDR   => CPU_ADDR,
      CPU_DONE   => CPU_DONE,
      CPU_DATA   => CPU_DATA,
                            
      MEM_REQ    => MEM_REQ ,
      MEM_ADDR   => MEM_ADDR,
      MEM_DONE   => MEM_DONE,
      MEM_DATA   => MEM_DATA,
      
      snoop_addr => snoop_addr,
      snoop_data => snoop_data,
      snoop_be   => snoop_be  ,
      snoop_we   => snoop_we  
   ); 
   
   process
      variable seed1, seed2 : integer := 999;
      variable r : real;
      variable nextaddr  : integer;
      variable nextdata  : std_logic_vector(31 downto 0);
   begin
      wait for 1 us; 
   
      -- check first 4
      CPU_ADDR     <= std_logic_vector(to_unsigned(0, CPU_ADDR'length));
      CPU_REQ      <= '1';
      wait until rising_edge(CLK); 
      CPU_REQ      <= '0';
      for i in 0 to 3 loop
         while (CPU_VALID = '0') loop
            wait until rising_edge(CLK);
         end loop;
         if (unsigned(CPU_DATA) /= (10 + i)) then
            report "wrong read value" severity warning;
            errorcount <= errorcount + 1;
         end if;
         wait until rising_edge(CLK);
      end loop;
      
      wait for 10 us;

      -- random tests
      while (1 = 1) loop
      
         for i in 0 to memsize - 1 loop
            shadowram(i) <= ramdata(i);
         end loop;

         uniform(seed1, seed2, r);
         nextaddr     := integer(round(r * real(memsize - 8))) * 4;
         CPU_ADDR     <= std_logic_vector(to_unsigned(nextaddr, CPU_ADDR'length));
         CPU_REQ       <= '1';
         wait until rising_edge(CLK); 
         CPU_REQ       <= '0';
         for i in 0 to 3 loop
            while (CPU_VALID = '0') loop
               wait until rising_edge(CLK);
            end loop;
            if (CPU_DATA /= shadowram(nextaddr / 4)) then
               if (CPU_DATA /= ramdata(nextaddr / 4)) then
                  report "wrong read value" severity warning;
                  errorcount <= errorcount + 1;
               end if;
            end if;
            nextaddr := nextaddr + 4;
            wait until rising_edge(CLK);
         end loop;
         
         wait until rising_edge(CLK);
         
      end loop;
      
      wait;
   
   end process;
   
   process
      variable address : integer;
   begin

      while (0 = 0) loop
         if (MEM_REQ = '1') then
            wait until rising_edge(CLK); 
            address := to_integer(unsigned(MEM_ADDR)) / 4;
            MEM_DONE  <= '1';
            for i in 0 to 7 loop
               MEM_DATA  <= ramdata(address + i); 
               wait until rising_edge(CLK);   
            end loop;
            MEM_DONE <= '0';   
         end if;
         
         wait until rising_edge(CLK);  
         
         if (errorcount > 100000) then
            report "many errors" severity warning;
         end if;
      end loop;
   
   end process;
   
   
   process
      variable seed1, seed2 : integer := 999;
      variable r : real;
      variable nextaddr  : integer;
      variable nextwait  : integer;
      variable nextdata  : std_logic_vector(31 downto 0);
   begin

      for i in 0 to memsize - 1 loop
         ramdata(i) <= std_logic_vector(to_unsigned(i + 10, 32));
      end loop;
      
      wait for 50 us;
   
      while (0 = 0) loop
      
         if (MEM_REQ = '0' and MEM_DONE = '0') then
            snoop_be <= x"F";
         
            uniform(seed1, seed2, r);
            nextaddr := integer(round(r * real(memsize - 1)));
            uniform(seed1, seed2, r);
            nextdata := std_logic_vector(to_unsigned(integer(round(r * 1000.0)), 32));
            snoop_addr   <= std_logic_vector(to_unsigned(nextaddr, snoop_addr'length));
            snoop_data   <= nextdata;
            snoop_we     <= '1'; 
            wait until rising_edge(CLK); 
            wait until rising_edge(CLK); 
            wait until rising_edge(CLK); 
            snoop_we     <= '0'; 
            
            ramdata(nextaddr) <= nextdata;
         end if;
         
         uniform(seed1, seed2, r);
         nextwait := 5 + integer(round(r * 30.0));
         for i in 1 to nextwait loop
            wait until rising_edge(CLK); 
         end loop;

      end loop;
   
   end process;
   

end architecture;


