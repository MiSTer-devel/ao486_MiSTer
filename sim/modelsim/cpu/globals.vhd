library ieee;
use ieee.std_logic_1164.all;

package globals is

  signal COMMAND_FILE_ENDIAN  : std_logic;
  signal COMMAND_FILE_NAME    : string(1 to 1024);
  signal COMMAND_FILE_NAMELEN : integer;
  signal COMMAND_FILE_TARGET  : integer;
  signal COMMAND_FILE_START   : std_logic;
  signal COMMAND_FILE_ACK     : std_logic;
  
end package globals;