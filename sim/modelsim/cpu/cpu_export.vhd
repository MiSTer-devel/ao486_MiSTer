
library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     
use STD.textio.all;

entity cpu_export is
   port 
   (
      clk              : in std_logic;
      rst_n            : in std_logic;
      new_export       : in std_logic;
      commandcount     : out integer;
      
      eax              : std_logic_vector(31 downto 0);
      ebx              : std_logic_vector(31 downto 0);
      ecx              : std_logic_vector(31 downto 0);
      edx              : std_logic_vector(31 downto 0);
      esp              : std_logic_vector(31 downto 0);
      ebp              : std_logic_vector(31 downto 0);
      esi              : std_logic_vector(31 downto 0);
      edi              : std_logic_vector(31 downto 0);
      eip              : std_logic_vector(31 downto 0)
   );
end entity;

architecture arch of cpu_export is

   signal new_export_1 : std_logic := '0';
   
   signal rst_n_1      : std_logic := '1';
     
begin  
 
-- synthesis translate_off
   process
   
      file outfile         : text;
      variable f_status    : FILE_OPEN_STATUS;
      variable line_out    : line;
      variable recordcount : integer := 0;
      
      constant filenamebase    : string := "R:\debug_";
      variable filename        : string(1 to 14);
      
      variable nh : std_logic := '1';
      variable tc      : integer := 0;
      variable testrun : integer := 0;
      
      variable old_eax : std_logic_vector(31 downto 0) := (others => '0');
      variable old_ebx : std_logic_vector(31 downto 0) := (others => '0');
      variable old_ecx : std_logic_vector(31 downto 0) := (others => '0');
      variable old_edx : std_logic_vector(31 downto 0) := (others => '0');
      variable old_esp : std_logic_vector(31 downto 0) := (others => '0');
      variable old_ebp : std_logic_vector(31 downto 0) := (others => '0');
      variable old_esi : std_logic_vector(31 downto 0) := (others => '0');
      variable old_edi : std_logic_vector(31 downto 0) := (others => '0');
      variable old_eip : std_logic_vector(31 downto 0) := (others => '0');

   begin
   
      filename := filenamebase & to_hstring(to_unsigned(testrun, 4)) & ".txt";
      file_open(f_status, outfile, filename, write_mode);

      while (true) loop
         wait until rising_edge(clk);
         
         rst_n_1 <= rst_n;
         if (rst_n = '1' and rst_n_1 = '0') then
            nh := '1';
            tc := 0;
            testrun := testrun + 1;
            
            filename := filenamebase & to_hstring(to_unsigned(testrun, 4)) & ".txt";
            file_close(outfile);
            file_open(f_status, outfile, filename, write_mode);
            file_close(outfile);
            file_open(f_status, outfile, filename, append_mode);
            
         end if; 
         
         new_export_1 <= new_export;
         if (new_export_1 = '1') then

            write(line_out, string'("#")); write(line_out, tc); writeline(outfile, line_out);

            -- cpu 7
            if (nh = '1' or eax /= old_eax) then write(line_out, string'("eax ")); write(line_out, to_hstring(signed(eax))); writeline(outfile, line_out); old_eax := eax; end if;
            if (nh = '1' or ebx /= old_ebx) then write(line_out, string'("ebx ")); write(line_out, to_hstring(signed(ebx))); writeline(outfile, line_out); old_ebx := ebx; end if;
            if (nh = '1' or ecx /= old_ecx) then write(line_out, string'("ecx ")); write(line_out, to_hstring(signed(ecx))); writeline(outfile, line_out); old_ecx := ecx; end if;
            if (nh = '1' or edx /= old_edx) then write(line_out, string'("edx ")); write(line_out, to_hstring(signed(edx))); writeline(outfile, line_out); old_edx := edx; end if;
            if (nh = '1' or esp /= old_esp) then write(line_out, string'("esp ")); write(line_out, to_hstring(signed(esp))); writeline(outfile, line_out); old_esp := esp; end if;
            if (nh = '1' or ebp /= old_ebp) then write(line_out, string'("ebp ")); write(line_out, to_hstring(signed(ebp))); writeline(outfile, line_out); old_ebp := ebp; end if;
            if (nh = '1' or esi /= old_esi) then write(line_out, string'("esi ")); write(line_out, to_hstring(signed(esi))); writeline(outfile, line_out); old_esi := esi; end if;
            if (nh = '1' or edi /= old_edi) then write(line_out, string'("edi ")); write(line_out, to_hstring(signed(edi))); writeline(outfile, line_out); old_edi := edi; end if;
            --if (nh = '1' or eip /= old_eip) then write(line_out, string'("eip ")); write(line_out, to_hstring(signed(eip))); writeline(outfile, line_out); old_eip := eip; end if;
            
            recordcount := recordcount + 1;
            tc          := tc + 1;
            
            if (recordcount mod 1000 = 0) then
               file_close(outfile);
               file_open(f_status, outfile, filename, append_mode);
               recordcount := 0;
            end if;
            
            nh := '0';
         
         end if;
         
         commandcount <= tc;
         
      end loop;
      
   end process;
-- synthesis translate_on

end architecture;





