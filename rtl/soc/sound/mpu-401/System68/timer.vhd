--===========================================================================--
--
--  S Y N T H E Z I A B L E    Timer   C O R E
--
--  www.OpenCores.Org - December 2002
--  This core adheres to the GNU public license  
--
-- File name      : timer.vhd
--
-- entity name    : timer
--
-- Purpose        : Implements a 8 bit timer module
--
-- Dependencies   : ieee.Std_Logic_1164
--                  ieee.std_logic_unsigned
--
-- Author         : John E. Kent      
--
--===========================================================================----
--
-- Revision History:
--
-- Date:          Revision         Author
-- ?? Sep 2002    0.1              John Kent
-- Initial version ( 3 timers )
--
-- 6 Sep 2002     1.0              John Kent
-- converted to a single timer 
-- made syncronous with system clock
--
--===========================================================================----
--
-- Register Memory Map
--
-- addr=0 read  down count
-- addr=0 write preset count
-- addr=1 read  status
-- addr=1 write control
--
-- Control register
-- b0 = counter enable
-- b1 = mode (0 = counter, 1 = timer)
-- b7 = interrupt enable
--
-- Status register
-- b6 = timer output
-- b7 = interrupt flag
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity timer is
	port (	
	 clk        : in  std_logic;
    rst        : in  std_logic;
    cs         : in  std_logic;
    rw         : in  std_logic;
    addr       : in  std_logic;
    data_in    : in  std_logic_vector(7 downto 0);
	 data_out   : out std_logic_vector(7 downto 0);
	 irq        : out std_logic;
	 timer_in   : in  std_logic;
	 timer_out  : out std_logic
  );
end;

architecture timer_arch of timer is
signal timer_ctrl  : std_logic_vector(7 downto 0);
signal timer_stat  : std_logic_vector(7 downto 0);
signal timer_reg   : std_logic_vector(7 downto 0);
signal timer_count : std_logic_vector(7 downto 0);
signal timer_int   : std_logic; -- Timer interrupt
signal timer_term  : std_logic; -- Timer terminal count
signal timer_tog   : std_logic; -- Timer output
--
-- control/status register bits
--
constant T_enab   : integer := 0; -- 0=disable, 1=enabled
constant T_mode   : integer := 1; -- 0=counter, 1=timer
constant T_out    : integer := 6; -- 0=disabled, 1=enabled
constant T_irq    : integer := 7; -- 0=disabled, 1-enabled

begin

--------------------------------
--
-- write control registers
--
--------------------------------
timer_write : process( clk, rst, cs, rw, addr, 
                       data_in, timer_reg, timer_ctrl )
begin
  if rst = '1' then
	   timer_reg  <= "00000000";
		timer_ctrl <= "00000000";
  elsif clk'event and clk = '0' then
    if cs = '1' and rw = '0' then
	   if addr='0' then
		  timer_reg  <= data_in;
		  timer_ctrl <= timer_ctrl;
	   else
		  timer_reg  <= timer_reg;
		  timer_ctrl <= data_in;
		end if;
	 else
	   timer_ctrl <= timer_ctrl;
		timer_reg  <= timer_reg;
    end if;
  end if;
end process;

--
-- timer data output mux
--
timer_read : process( addr, timer_count, timer_stat )
begin
  if addr='0' then
    data_out <= timer_count;
  else
    data_out <= timer_stat;
  end if;
end process;


--------------------------------
--
-- Terminal Count
--
--------------------------------
timer_terminal : process( clk, rst, cs, rw, addr, data_in,
                       timer_term, timer_ctrl, timer_count )
begin
  if rst = '1' then
		timer_term <= '0';
  elsif clk'event and clk = '0' then
    if cs = '1' and rw = '0' then
	   if addr='0' then
		  -- Reset terminal count on write to counter
		  timer_term <= '0';	
	   else
		  timer_term <= timer_term;
		end if;
	 else
	   if (timer_ctrl(T_enab) = '1') then
		  if (timer_count = "00000000" ) then
		    -- If timer enabled, set terminal output on zero count
		    timer_term <= '1';
		  elsif timer_ctrl(T_mode) = '0' then
			 -- counter mode, reset on non zero
		    timer_term <= '0';
		  else
			 -- timer mode, keep as is
		    timer_term <= timer_term; 
		  end if; -- timer count
		else
		  timer_term <= timer_term;
		end if; -- timer ctrl
    end if;	-- cs
  end if;  -- rst / clk
end process;


--------------------------------
--
-- counters
--
--------------------------------

timer_counter: process( clk, rst, timer_ctrl, timer_count, timer_in )
variable timer_tmp : std_logic;
begin
  if rst = '1' then
	   timer_count <= "00000000";
		timer_tmp := '0';
  elsif clk'event and clk = '0' then
      if timer_ctrl( T_enab ) = '1' then
		  if timer_in = '0' and timer_tmp = '1' then
		    timer_tmp := '0';
          if timer_count = "00000000" then
		      timer_count <= timer_reg;
		    else
	         timer_count <= timer_count - 1;
		    end if;
		  elsif timer_in = '1' and timer_tmp = '0' then
		    timer_tmp := '1';
	       timer_count <= timer_count;
		  else
		    timer_tmp := timer_tmp;
	       timer_count <= timer_count;
		  end if;
		else
		  timer_tmp := timer_tmp;
	     timer_count <= timer_count;
	   end if; -- timer_ctrl
  end if; -- rst / clk
end process;

--
-- read timer strobe to reset interrupts
--
  timer_interrupt : process( Clk, rst, cs, rw, addr,
                             timer_term, timer_int, timer_count, timer_ctrl )
  begin
    if clk'event and clk = '0' then
	   if rst = '1' then
		  timer_int <= '0';
      elsif cs = '1' and rw = '1' then
	     if addr = '0' then
			 -- reset interrupt on read count
		    timer_int <= '0';
		  else
		    timer_int <= timer_int;
		  end if;
	   else
	     if timer_term = '1' then
		    timer_int <= '1';
		  else
		    timer_int <= timer_int;
	  	  end if;
      end if;
    end if;
  end process;

--
-- read timer strobe to reset interrupts
--
  timer_irq : process( timer_int, timer_ctrl )
  begin
    if timer_ctrl( T_irq ) = '1' then
	   irq <= timer_int;
	 else
	   irq <= '0';
	 end if;
  end process;

  --
  -- timer status register
  --
  timer_status : process( timer_ctrl, timer_int, timer_tog )
  begin
    timer_stat(5 downto 0) <= timer_ctrl(5 downto 0);
	 timer_stat(T_out) <= timer_tog;
    timer_stat(T_irq) <= timer_int;
  end process;

  --
  -- timer output
  --
  timer_output : process( Clk, rst, timer_term, timer_ctrl, timer_tog )
  variable timer_tmp : std_logic; -- tracks change in terminal count
  begin
    if clk'event and clk = '0' then
      if rst = '1' then
	     timer_tog <= '0';
		  timer_tmp := '0';
	   elsif timer_ctrl(T_mode) = '0' then -- free running ?
		  if (timer_term = '1') and (timer_tmp = '0') then
		    timer_tmp := '1';
			 timer_tog <= not timer_tog;
		  elsif (timer_term = '0') and (timer_tmp = '1') then
		    timer_tmp := '0';
			 timer_tog <= timer_tog;
		  else
		    timer_tmp := timer_tmp;
			 timer_tog <= timer_tog;
		  end if;
		else                            -- one shot timer mode, follow terminal count
		  if (timer_term = '1') and (timer_tmp = '0') then
		    timer_tmp := '1';
			 timer_tog <= '1';
		  elsif (timer_term = '0') and (timer_tmp = '1') then
		    timer_tmp := '0';
			 timer_tog <= '0';
		  else
		    timer_tmp := timer_tmp;
			 timer_tog <= timer_tog;
		  end if;
		end if;
	 end if;
    timer_out <= timer_tog and timer_ctrl(T_out);
  end process;

end timer_arch;
	
