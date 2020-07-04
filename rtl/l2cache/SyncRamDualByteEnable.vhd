library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;  

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

entity SyncRamDualByteEnable is
   generic 
   (
      DATA_WIDTH  : natural := 64;
      ADDR_WIDTH  : natural := 6;
      BYTES       : natural := 8
   );
   port 
   (
      clk        : in std_logic;
      
      addr_a     : in  natural range 0 to 2**ADDR_WIDTH - 1;
      datain_a   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
      dataout_a  : out std_logic_vector(DATA_WIDTH-1 downto 0);
      we_a       : in  std_logic := '1';
      be_a       : in  std_logic_vector (BYTES - 1 downto 0);
		            
      addr_b     : in  natural range 0 to 2**ADDR_WIDTH - 1;
      datain_b   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
      dataout_b  : out std_logic_vector(DATA_WIDTH-1 downto 0);
      we_b       : in  std_logic := '1';
      be_b       : in  std_logic_vector (BYTES - 1 downto 0)
   );
end;

architecture rtl of SyncRamDualByteEnable is 

   signal addr_a_slv : std_logic_vector(ADDR_WIDTH-1 downto 0);
   signal addr_b_slv : std_logic_vector(ADDR_WIDTH-1 downto 0);

begin
        
   addr_a_slv <= std_logic_vector(to_unsigned(addr_a, ADDR_WIDTH));
   addr_b_slv <= std_logic_vector(to_unsigned(addr_b, ADDR_WIDTH));
   
   altsyncram_component : altsyncram
   GENERIC MAP (
      address_reg_b => "CLOCK1",
      clock_enable_input_a => "NORMAL",
      clock_enable_input_b => "NORMAL",
      clock_enable_output_a => "BYPASS",
      clock_enable_output_b => "BYPASS",
      indata_reg_b => "CLOCK1",
      intended_device_family => "Cyclone V",
      lpm_type => "altsyncram",
      numwords_a => 2**ADDR_WIDTH,
      numwords_b => 2**ADDR_WIDTH,
      operation_mode => "BIDIR_DUAL_PORT",
      outdata_aclr_a => "NONE",
      outdata_aclr_b => "NONE",
      outdata_reg_a => "UNREGISTERED",
      outdata_reg_b => "UNREGISTERED",
      power_up_uninitialized => "FALSE",
      read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
      read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ",
      init_file => " ", 
      widthad_a => ADDR_WIDTH,
      widthad_b => ADDR_WIDTH,
      width_a => DATA_WIDTH,
      width_b => DATA_WIDTH,
      width_byteena_a => BYTES,
      width_byteena_b => BYTES,
      wrcontrol_wraddress_reg_b => "CLOCK1"
   )
   PORT MAP (
      address_a => addr_a_slv,
      address_b => addr_b_slv,
      clock0 => clk,
      clock1 => clk,
      clocken0 => '1',
      clocken1 => '1',
      data_a => datain_a,
      data_b => datain_b,
      wren_a => we_a,
      wren_b => we_b,
      q_a => dataout_a,
      q_b => dataout_b,
      byteena_a => be_a,
      byteena_b => be_b
   );
  
end rtl;