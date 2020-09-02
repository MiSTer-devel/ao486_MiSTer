library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;
use ieee.math_real.all;      

use work.globals.all;

entity etb  is
end entity;

architecture arch of etb is

   signal clk   : std_logic := '1';
   signal rst_n : std_logic := '0';
   signal rst   : std_logic := '0';
   
   signal avm_address       : std_logic_vector(29 downto 0);
   signal avm_writedata     : std_logic_vector(31 downto 0);
   signal avm_byteenable    : std_logic_vector(3 downto 0);
   signal avm_burstcount    : std_logic_vector(3 downto 0);
   signal avm_write         : std_logic;
   signal avm_read          : std_logic;
   signal avm_read_64       : std_logic;
                           
   signal avm_waitrequest   : std_logic := '0';
   signal avm_readdatavalid : std_logic := '0';
   signal avm_readdata      : std_logic_vector(31 downto 0);
   signal avm_readdata_64   : std_logic_vector(63 downto 0);
   
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
   signal DDRAM_IN_DOUT_64     : std_logic_vector(63 downto 0); 
   signal DDRAM_IN_DOUT_READY  : std_logic; 
   signal DDRAM_IN_BURSTCNT    : std_logic_vector(3 downto 0); 
   signal DDRAM_IN_ADDR        : std_logic_vector(31 downto 0); 
   signal DDRAM_IN_RD          : std_logic; 
   signal DDRAM_IN_RD_64       : std_logic; 
   signal DDRAM_IN_DIN         : std_logic_vector(31 downto 0) := (others => '0');
   signal DDRAM_IN_BE          : std_logic_vector(3 downto 0);
   signal DDRAM_IN_WE          : std_logic;
  
   signal mgmt_address         : std_logic_vector(7 downto 0);
   signal mgmt_write           : std_logic;
   signal mgmt_writedata       : std_logic_vector(31 downto 0);
  
   type t_data is array(0 to (2**27)-1) of integer;
   type bit_vector_file is file of bit_vector;
   
   signal tx_command  : std_logic_vector(31 downto 0);
   signal tx_bytes    : integer range 0 to 4;
   signal tx_enable   : std_logic := '0';
   
   signal cpuopt_enable : std_logic := '0';
   

begin

   clk   <= not clk after 5 ns;
   rst   <= not rst_n;
   
   process
      variable idlecnt  : integer := 0;
   begin
      wait until rising_edge(clk);
      if (tx_enable = '1') then
         rst_n         <= not tx_command(0);
         cpuopt_enable <= tx_command(1);
         wait until rising_edge(clk);
         wait until rising_edge(clk);
      end if;
   end process;
   
   --process
   --   variable seed1, seed2 : integer := 999;
   --   variable r : real;
   --   variable cnt : integer;
   --begin
   --
   --   uniform(seed1, seed2, r);
   --   cnt := 1 + integer(round(r * 20.0));
   --   for i in 1 to cnt loop
   --      wait until rising_edge(clk);
   --   end loop;
   --   DDRAM_OUT_BUSY <= not DDRAM_OUT_BUSY;
   --
   --end process;
   

   iao486 : entity work.ao486
   port map
   (
      clk                        => clk,
      rst_n                      => rst_n,
      
	   a20_enable                 => '1',
      cache_disable              => '0',
      
      interrupt_do               => '0',
      interrupt_vector           => (7 downto 0 => '0'),
      interrupt_done             => open,
      
      avm_address                => avm_address      ,
      avm_writedata              => avm_writedata    ,
      avm_byteenable             => avm_byteenable   ,
      avm_burstcount             => avm_burstcount   ,
      avm_write                  => avm_write        ,
      avm_read                   => avm_read         ,
                                                     
      avm_waitrequest            => avm_waitrequest  ,
      avm_readdatavalid          => avm_readdatavalid,
      avm_readdata               => avm_readdata     ,
      
      dma_address                => (23 downto 0 => '0'),
      dma_writedata              => (15 downto 0 => '0'),
      dma_write                  => '0',
      dma_read                   => '0',
      dma_16bit                  => '0',
      
      io_read_data               => (31 downto 0 => '0'),
      io_read_done               => '1',
      io_write_done              => '1'
   );
   
   DDRAM_IN_BURSTCNT <= avm_burstcount;
   DDRAM_IN_ADDR     <= avm_address(29 downto 0) & "00";
   DDRAM_IN_RD       <= avm_read;
   DDRAM_IN_DIN      <= avm_writedata;
   DDRAM_IN_BE       <= avm_byteenable;
   DDRAM_IN_WE       <= avm_write;
   
   avm_waitrequest   <= DDRAM_IN_BUSY;
   avm_readdatavalid <= DDRAM_IN_DOUT_READY;
   avm_readdata      <= DDRAM_IN_DOUT;
   
   
   il2_cache : entity work.l2_cache
   port map
   (
      CLK                  => clk,
      RESET                => rst,
      
      DISABLE              => '0',            
                                          
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
   
   
   iestringprocessor : entity work.estringprocessor
   port map
   (
      ready       => '1',
      tx_command  => tx_command,
      tx_bytes    => tx_bytes,  
      tx_enable   => tx_enable, 
      rx_command  => x"00000000",
      rx_valid    => '1'
   );
    
   process
      variable address : integer;
      
      variable data : t_data := (others => 0);
      
      variable readmodifywrite : std_logic_vector(31 downto 0);
      
      file infile             : bit_vector_file;
      variable f_status       : FILE_OPEN_STATUS;
      variable read_byte0     : std_logic_vector(7 downto 0);
      variable read_byte1     : std_logic_vector(7 downto 0);
      variable read_byte2     : std_logic_vector(7 downto 0);
      variable read_byte3     : std_logic_vector(7 downto 0);
      variable next_vector    : bit_vector (3 downto 0);
      variable actual_len     : natural;
      variable targetpos      : integer;
      
      -- copy from std_logic_arith, not used here because numeric std is also included
      function CONV_STD_LOGIC_VECTOR(ARG: INTEGER; SIZE: INTEGER) return STD_LOGIC_VECTOR is
        variable result: STD_LOGIC_VECTOR (SIZE-1 downto 0);
        variable temp: integer;
      begin
   
         temp := ARG;
         for i in 0 to SIZE-1 loop
   
         if (temp mod 2) = 1 then
            result(i) := '1';
         else 
            result(i) := '0';
         end if;
   
         if temp > 0 then
            temp := temp / 2;
         elsif (temp > integer'low) then
            temp := (temp - 1) / 2; -- simulate ASR
         else
            temp := temp / 2; -- simulate ASR
         end if;
        end loop;
   
        return result;  
      end;
      
   begin

      --file_open(f_status, infile, "boot0.rom", read_mode);
      --targetpos := 16#F0000# / 4;
      --while (not endfile(infile)) loop
      --   
      --   read(infile, next_vector, actual_len);  
      --    
      --   read_byte0 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(0)), 8);
      --   read_byte1 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(1)), 8);
      --   read_byte2 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(2)), 8);
      --   read_byte3 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(3)), 8);
      --
      --   if (1 = 0) then -- endianswitch
      --      data(targetpos) := to_integer(signed(read_byte3 & read_byte2 & read_byte1 & read_byte0));
      --   else
      --      data(targetpos) := to_integer(signed(read_byte0 & read_byte1 & read_byte2 & read_byte3));
      --   end if;
      --   targetpos       := targetpos + 1;
      --end loop;
      --file_close(infile);
      --assert false report "boot0.rom loaded" severity note;
      --
      --file_open(f_status, infile, "mov.rom", read_mode);
      --targetpos := 0;
      --while (not endfile(infile)) loop
      --   
      --   read(infile, next_vector, actual_len);  
      --    
      --   read_byte0 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(0)), 8);
      --   read_byte1 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(1)), 8);
      --   read_byte2 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(2)), 8);
      --   read_byte3 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(3)), 8);
      --
      --   if (1 = 0) then -- endianswitch
      --      data(targetpos) := to_integer(signed(read_byte3 & read_byte2 & read_byte1 & read_byte0));
      --   else
      --      data(targetpos) := to_integer(signed(read_byte0 & read_byte1 & read_byte2 & read_byte3));
      --   end if;
      --   targetpos       := targetpos + 1;
      --end loop;
      --file_close(infile);
      --assert false report "mov.rom loaded" severity note;
   
   
      DDRAM_OUT_DOUT_READY <= '0';
   
      while (0 = 0) loop
      
         -- data from file
         COMMAND_FILE_ACK <= '0';
         if COMMAND_FILE_START = '1' then
            
            assert false report "received" severity note;
            assert false report COMMAND_FILE_NAME(1 to COMMAND_FILE_NAMELEN) severity note;
         
            file_open(f_status, infile, COMMAND_FILE_NAME(1 to COMMAND_FILE_NAMELEN), read_mode);
         
            targetpos := COMMAND_FILE_TARGET  / 4;
         
            while (not endfile(infile)) loop
               
               read(infile, next_vector, actual_len);  
               
               read_byte0 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(0)), 8);
               read_byte1 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(1)), 8);
               read_byte2 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(2)), 8);
               read_byte3 := CONV_STD_LOGIC_VECTOR(bit'pos(next_vector(3)), 8);
            
               if (COMMAND_FILE_ENDIAN = '1') then
                  data(targetpos) := to_integer(signed(read_byte3 & read_byte2 & read_byte1 & read_byte0));
               else
                  data(targetpos) := to_integer(signed(read_byte0 & read_byte1 & read_byte2 & read_byte3));
               end if;
               targetpos       := targetpos + 1;
               
            end loop;
         
            file_close(infile);
         
            COMMAND_FILE_ACK <= '1';
         
         end if;
      
         if (DDRAM_OUT_BUSY = '0') then
            if (DDRAM_OUT_RD = '1') then
               address := to_integer(unsigned(DDRAM_OUT_ADDR)) / 4;
               for i in 1 to to_integer(unsigned(DDRAM_OUT_BURSTCNT)) loop
                  DDRAM_OUT_DOUT_READY <= '1';
                  DDRAM_OUT_DOUT <= std_logic_vector(to_signed(data(address + 1), 32)) &
                                    std_logic_vector(to_signed(data(address + 0), 32));
                  wait until rising_edge(clk);
                  address := address + 2;
               end loop;
               DDRAM_OUT_DOUT_READY <= '0';
            end if;
            
            --if (DDRAM_OUT_WE = '1') then
            --   data(address + 1) := to_integer(unsigned(DDRAM_OUT_DIN(31 downto  0)));
            --   data(address + 0) := to_integer(unsigned(DDRAM_OUT_DIN(63 downto 32)));
            --end if;
         end if;
         
         wait until rising_edge(clk);
      end loop;
   
   end process;
   
   
   
end architecture;


