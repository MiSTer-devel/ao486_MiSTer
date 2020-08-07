library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;

use work.globals.all;
    
entity estringprocessor  is
   generic
   (
      clk_speed : integer := 50000000
   );
   port 
   (
      ready       : in  std_logic;
      tx_command  : out std_logic_vector(31 downto 0);
      tx_bytes    : out integer range 0 to 4;
      tx_enable   : out std_logic := '0';
      rx_command  : in  std_logic_vector(31 downto 0);
      rx_valid    : in  std_logic
   );
end entity;

architecture arch of estringprocessor is

   constant proc_busadr   : integer := 28;
   constant proc_buswidth : integer := 32;

   constant clk_period : time := (1000000000 / clk_speed) * 1 ns;
   
   signal string_command    : string(1 to 3);
   
   type t_internal_variables is array(0 to 256) of integer;
   signal internal_variables : t_internal_variables := (others => 0);
   
   type r_thread_record is record
      id          : integer;
      waittime    : integer;
      waitcommand : line;
   end record;
   
   type t_thread_buffers is array(0 to 255) of r_thread_record;
   
   
   procedure find_id 
   (
      variable  t_buf : inout t_thread_buffers;
      variable  id    : in    integer;
      variable  slot  : out   integer
   ) is
   begin
      for i in 0 to 255 loop
         if (t_buf(i).id = id) then
            slot := i;
            exit;
         elsif (t_buf(i).id = -1) then
            t_buf(i).id := id;
            slot := i;
            exit;
         end if;
      end loop;
   end procedure;
   
   
   
begin

   
   process
       
      file infile             : text;
      file outfile            : text;
      variable f_status       : FILE_OPEN_STATUS;
      variable newdat         : LINE;
      variable endfound       : boolean;
      variable buf            : LINE;
      variable run            : boolean := true;
      
      variable line_out       : line;
      variable debugline_out  : line;
      variable command        : string(1 to 3);
      
      variable dev_null_str3  : string (1 to 3);
      variable dev_null_str6  : string (1 to 6);
      variable OK             : boolean := FALSE;
      variable para_int1      : integer;
      variable para_int2      : integer;
      variable para_int3      : integer;
      variable para_int4      : integer;
      
      variable address        : integer;
      variable data           : integer;
      variable count          : integer;
      
      variable thread_buffers : t_thread_buffers := (others => (-1, 0, null));
      
      variable freerun : boolean := false;
        
   begin
   
      file_open(f_status, outfile, "input.txt", write_mode);
      file_close(outfile);
      file_open(f_status, outfile, "output.txt", write_mode);
      file_close(outfile);
     
      file_open(f_status, infile, "input.txt", read_mode);

      wait for 1000 ns;
      
      while (run) loop
     
         if not endfile(infile) then
            
            endfound := false;
            buf := null;
            while (endfound = false) loop
               if not endfile(infile) then
                  readline(infile,newdat);
                  for i in 1 to newdat'length loop
                     write(buf, newdat(i to i));
                     if (newdat(i to i) = "&") then
                        endfound := true;
                     end if;
                  end loop;
               end if;
            end loop;
           
            command := buf(1 to 3);
            string_command <= command;
            
            line_out := null;
            buf(buf'length) := ' ';
            write(line_out, buf(1 to buf'length));
            write(line_out, string'("# "));
            
            if (command(1 to 3) = String'("set")) then
               -- command
               Read(buf, dev_null_str6);
               -- command nr
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- process id
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- target for reading
               Read(buf, para_int2, OK);
               Read(buf, dev_null_str3);
               -- count
               Read(buf, count, OK);
               Read(buf, dev_null_str3);
               -- address in target space
               Read(buf, address, OK);
               Read(buf, dev_null_str3);
              
               -- write address
               if (ready = '0') then
                  wait until ready = '1';
               end if;
               tx_command <= "0000" & std_logic_vector(to_unsigned(address,proc_busadr));
               if (count > 1) then
                  tx_command(31) <= '1';
               end if;
               tx_bytes   <= 4;
               tx_enable  <= '1';
               wait for clk_period*2;
               tx_enable <= '0';
               
               -- write block size
               if (count > 1) then
                  if (ready = '0') then
                     wait until ready = '1';
                  end if;
                  tx_command <= std_logic_vector(to_unsigned(count - 1,32));
                  tx_bytes   <= 4;
                  tx_enable  <= '1';
                  wait for clk_period*2;
                  tx_enable <= '0';
               end if;
                  
               for i in 1 to count loop
               
                  -- value to write
                  Read(buf, data, OK);
                  if (i < count) then
                     Read(buf, dev_null_str3);
                  end if;
               
                  -- write data
                  if (ready = '0') then
                     wait until ready = '1';
                  end if;
                  tx_command <= std_logic_vector(to_signed(data,proc_buswidth));
                  tx_bytes   <= 4;
                  tx_enable <= '1';
                  wait for clk_period*2;
                  tx_enable <= '0';
                  wait for 20*clk_period; -- this is required, because there is no answer for write commands
                  
                  address := address + 1;
                  
               end loop;
               
               write(line_out, string'("&"));
               file_open(f_status, outfile, "output.txt", append_mode);
               writeline(outfile, line_out);
               file_close(outfile);
            end if;
            
            if (command(1 to 3) = String'("get")) then
               -- command
               Read(buf, dev_null_str6);
               -- command nr
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- process id
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- target for reading
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- count
               Read(buf, count, OK);
               Read(buf, dev_null_str3);
               -- address in target space
               Read(buf, address, OK);
               
               -- write address
               if (ready = '0') then
                  wait until ready = '1';
               end if;
               tx_command <= "0100" & std_logic_vector(to_unsigned(address,proc_busadr));
               if (count > 1) then
                  tx_command(31) <= '1';
               end if;
               tx_bytes   <= 4;
               tx_enable  <= '1';
               wait for clk_period*2;
               tx_enable <= '0';
               
               -- write block size
               if (count > 1) then
                  if (ready = '0') then
                     wait until ready = '1';
                  end if;
                  tx_command <= std_logic_vector(to_unsigned(count - 1,32));
                  tx_bytes   <= 4;
                  tx_enable  <= '1';
                  wait for clk_period*2;
                  tx_enable <= '0';
               end if;
               
               for i in 1 to count loop
                  
                  if (rx_valid = '0') then
                     wait until rx_valid = '1';
                  end if;
                  data := to_integer(signed(rx_command(31 downto 0)));
                  wait until rx_valid = '0';
                  
                  write(line_out, data);
                  write(line_out, string'("#"));
                  
                  address := address + 1;
                  
               end loop;
               
               write(line_out, string'("&"));
               file_open(f_status, outfile, "output.txt", append_mode);
               writeline(outfile, line_out);
               file_close(outfile);
            end if;
            
            if (command(1 to 3) = String'("fil")) then
               -- command
               Read(buf, dev_null_str6);
               -- command nr
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- process id
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- endianess
               Read(buf, para_int2, OK);
               Read(buf, dev_null_str3);
               -- address in target space
               Read(buf, address, OK);
               Read(buf, dev_null_str3);

               COMMAND_FILE_NAME <= (others => ' ');
               COMMAND_FILE_NAME(1 to buf'length) <= buf(1 to buf'length);
               COMMAND_FILE_NAMELEN <= buf'length;
               COMMAND_FILE_TARGET <= address;
               if (para_int2 = 1) then
                  COMMAND_FILE_ENDIAN <= '1';
               else
                  COMMAND_FILE_ENDIAN <= '0';
               end if;
               COMMAND_FILE_START  <= '1';
               wait until COMMAND_FILE_ACK = '1';
               COMMAND_FILE_START  <= '0';
               wait for 20 ns;
               
               write(line_out, string'("&"));
               file_open(f_status, outfile, "output.txt", append_mode);
               writeline(outfile, line_out);
               file_close(outfile);
            end if;
            
            if (command(1 to 3) = String'("brk")) then
               run := false;
            end if;
            
            if (command(1 to 3) = String'("wtn")) then
               -- command
               Read(buf, dev_null_str6);
               -- command nr
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- process id
               Read(buf, para_int1, OK);
               Read(buf, dev_null_str3);
               -- time to wait
               Read(buf, para_int2, OK);
               
               
               write(line_out, string'("&"));
               if (para_int2 = -1) then
                  freerun := true;
                  find_id(thread_buffers, para_int1, para_int3);
                  thread_buffers(para_int3).waittime := 2;
                  thread_buffers(para_int3).waitcommand := line_out;
               else
                  find_id(thread_buffers, para_int1, para_int3);
                  thread_buffers(para_int3).waittime := para_int2;
                  thread_buffers(para_int3).waitcommand := line_out;
               end if;
               
            end if;
            
            wait for 1 ps;
          
         end if;

         OK := false;
         for i in 0 to 255 loop
            if (thread_buffers(i).id /= -1) then
               if (thread_buffers(i).waittime = 1) then
                  file_open(f_status, outfile, "output.txt", append_mode);
                  writeline(outfile, thread_buffers(i).waitcommand);
                  file_close(outfile);
               end if;
               if (thread_buffers(i).waittime > 0) then
                  OK := true;
                  thread_buffers(i).waittime := thread_buffers(i).waittime - 1;
               end if;
            end if;
         end loop;
         
         if (OK = true or freerun = true) then
            wait for 1 ns;
         end if;
         
      end loop;
      
      file_close(infile);

      wait;
           
   end process; 
   
   
   
   
end architecture;















