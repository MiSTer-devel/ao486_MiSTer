library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library unisim;
	use unisim.all;
--library simprim;
--   use simprim.all;

entity swtbug_rom is
    Port (
       clk   : in  std_logic;
		 rst   : in  std_logic;
		 cs    : in  std_logic;
		 rw    : in  std_logic;
       addr  : in  std_logic_vector (9 downto 0);
       wdata : in  std_logic_vector (7 downto 0);
       rdata : out std_logic_vector (7 downto 0)
    );
end swtbug_rom;

architecture rtl of swtbug_rom is

   signal we       : std_logic;
   signal reset    : std_logic;
   signal rdata0   : std_logic_vector (7 downto 0);
   signal rdata1   : std_logic_vector (7 downto 0);
   signal ena0     : std_logic;
   signal ena1     : std_logic;

   component RAMB4_S8
    generic (
      INIT_00, INIT_01, INIT_02, INIT_03,
	   INIT_04, INIT_05, INIT_06, INIT_07,
	   INIT_08, INIT_09, INIT_0A, INIT_0B,
      INIT_0C, INIT_0D, INIT_0E, INIT_0F : bit_vector (255 downto 0) :=
         		x"0000000000000000000000000000000000000000000000000000000000000000"
    );

    port (
      clk, we, en, rst : in std_logic;
      addr :  in std_logic_vector(8 downto 0);
      di   :  in std_logic_vector(7 downto 0);
      do   : out std_logic_vector(7 downto 0)
    );
  end component;

begin

  ROM0 : RAMB4_S8
    generic map ( 
    INIT_00 => x"7FF026318129273981618DFA265381678D34E3BD041610006E408D006E00A0FE",
    INIT_01 => x"CF270FA07CF02008082600A100A7092747A07A288D1C8D47A0B70280318D0FA0",
    INIT_02 => x"161B4C8D1648484848538D390DA0FE0EA0B7078D0DA0B70C8DD4E27E318D3F86",
    INIT_03 => x"00A608F88DACE17ED1E17E078B02233981308B0F8444444444390FA0F70FA0FB",
    INIT_04 => x"272081DB8D318D318D0DA0FE348D0DA0CEEF8D9DE1CEBD8D4AE17E39F7260481",
    INIT_05 => x"A6390780402E1681442B11810A2F09814C2B3080CC8D012C205E81E0270D81FA",
    INIT_06 => x"A0FFAC200DA0FF090907262C2042A08EA5202086F38DF58DA3200800A6A48D00",
    INIT_07 => x"2008A0BE40E07E912700A100A70957E0BDBD8D9D224681A12530816D2002200D",
    INIT_08 => x"A7118600A7038639261920022002A100A684E2BD0480CE08E3BDFF8608A0BF49",
    INIT_09 => x"8A8D8C8D8E8D0808A0FE7EE0BD9DE1CE066A056A0226066D3008A0BF012F2000",
    INIT_0A => x"738D0CA07F0AA0FF0480CE42A08E192723E18C12A0FEC8E0BD08A0CE848D868D",
    INIT_0B => x"6E01EECCE0BD072600A1D1E3CE398D7EE0BD9CE1CE47E3BD53E3BD7DE2BD0327",
    INIT_0C => x"150A0D13043153000000150A0D043953006E12A0FEBF20ED26F8E38C08080800",
    INIT_0D => x"0DA0FF00A61655E0BD47E0BD04A0FF47E0BD4020006E06A0FE4C200424000000",
    INIT_0E => x"393303E101E6370AA0FE10A0FF3A203B10200DA0CE7EE0BD9DE1CE2120022711",
    INIT_0F => x"A600A715862826DA8D37313131397F84068DCD20089E2704A0BC0DA0FEC8E0BD"
    )

    port map ( clk => clk,
	            en  => ena0,
				   we  => we,
				   rst => reset,
				   addr(8 downto 0) => addr(8 downto 0),
               di(7 downto 0)   => wdata(7 downto 0),
				   do(7 downto 0)   => rdata0(7 downto 0)
	);

  ROM1 : RAMB4_S8
    generic map ( 
    INIT_00 => x"FE3301A7FA24575700E600E711C62E26C38D37112007270CA0F601A6FB244700",
    INIT_01 => x"DE2013270CA0F6218DF7265A4600690D2A8D5802E704C63A8DFC2B00A63910A0",
    INIT_02 => x"026CFC2A026DC420028DC82A5802E6F7265A460D00A7108D168D006A0AC6238D",
    INIT_03 => x"A7348676E17E17EFE3CE078D108D0AA0FE0BA07F16838DF120F78D026F39026A",
    INIT_04 => x"066FFA2601C504E6258D0BC62E8D14807F3902A7006C01A70786006C3902A703",
    INIT_05 => x"8D04E700247EEF2601C51880F60800A71B80B6062702C50024CE178D9CC61D8D",
    INIT_06 => x"2712A0BC23E1CE582047E3BDF18D7EE0BD09E0CE39FA2614808C09FFFFCE3900",
    INIT_07 => x"A0B614A0FE6BE17E1E8D23E1CE00A73F8616A0B700A614A0FF47E0BD328D081A",
    INIT_08 => x"A0CE0F205A8D3912A0FF24E1CE062723E18C12A0FE43A0B7DA2024E1CE00A716",
    INIT_09 => x"D9E1BD1A8D20C611860CA07352E17E918D248D7EE0BD90E1CE528D0904A0FF49",
    INIT_0A => x"861627D6E1BD75E0BD08C61486042004C612860A2010C613863903A73C860427",
    INIT_0B => x"A0B6CF8D44A0FF02A0FE3900E701A70686028D00E701C60286088D0C8D01CA02",
    INIT_0C => x"BD93E1CE46A0B7038047A0B7048B0F8602251081042644A0F204A0F645A0B005",
    INIT_0D => x"8D30375344A0FFF92646A07A188D44A0FE1D8D1F8D44A0CE248D47A0CE5F7EE0",
    INIT_0E => x"30E152AEE14688E04D00C05AD0E147BFE07E00EB39B32604A0BC0944A0FE330B",
    INIT_0F => x"D0E0A7E18BE100E01EE3450CE04C1AE35069E24FD9E2428FE244CCE24305E04A"
    )

    port map ( clk => clk,
	            en  => ena1,
				   we  => we,
				   rst => reset,
				   addr(8 downto 0) => addr(8 downto 0),
               di(7 downto 0)   => wdata(7 downto 0),
				   do(7 downto 0)   => rdata1(7 downto 0)
	);

my_swtbug : process ( clk, rst, cs, rw, rdata0, rdata1 )
begin
	 if addr(9) = '0' then
      ena0 <= cs;
	   ena1 <= '0';
		rdata <= rdata0;
	 else
      ena0 <= '0';
	   ena1 <= cs;
		rdata <= rdata1;
	 end if;

	 we <= cs and (not rw);
    reset <= '0';

end process my_swtbug;

end;
