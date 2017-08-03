library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sb16_avalon_wrapper is
	port
	(
		csi_clockreset_clk		: in std_logic;
		csi_clockreset_reset	: in std_logic;
                	
		avs_s1_chipselect			: in std_logic;
		avs_s1_address        : in std_logic_vector(4 downto 0);
		avs_s1_writedata			: in std_logic_vector(31 downto 0);
		avs_s1_readdata  			: out std_logic_vector(31 downto 0);
		avs_s1_read					  : in std_logic;
		avs_s1_write					: in std_logic;
		avs_s1_waitrequest_n  : out std_logic;
		ins_irq0_irq          : out std_logic;

    coe_pc_speaker        : in std_logic;

    coe_audio_l         	: out std_logic_vector(15 downto 0);
    coe_audio_r         	: out std_logic_vector(15 downto 0)
	);
end entity sb16_avalon_wrapper;

architecture SYN of sb16_avalon_wrapper is

	component sound_blaster_16 is
	  generic
	  (
	    IO_BASE_ADDR    : std_logic_vector(15 downto 0) := X"0280";
	    DSP_VERSION     : std_logic_vector(15 downto 0) := X"0400"
	  );
	  port
	  (
	    wb_clk_i        : in std_logic;
	    wb_rst_i        : in std_logic;
	    wb_adr_i        : in std_logic_vector(15 downto 1);
	    wb_dat_i        : in std_logic_vector(15 downto 0);
	    wb_dat_o        : out std_logic_vector(15 downto 0);
	    wb_sel_i        : in std_logic_vector(1 downto 0);
	    wb_cyc_i        : in std_logic;
	    wb_stb_i        : in std_logic;
	    wb_we_i         : in std_logic;
	    wb_ack_o        : out std_logic;
	    
	    sb16_io_arena   : out std_logic;
	    
      -- input
      pc_speaker      : in std_logic;
      -- output
	    audio_l         : out std_logic_vector(15 downto 0);
	    audio_r         : out std_logic_vector(15 downto 0)
	  );
	end component sound_blaster_16;

	signal wb_adr_i			: std_logic_vector(15 downto 1) := (others => '0');
	signal wb_sel_i			: std_logic_vector(1 downto 0) := (others => '0');

begin

	-- $0220-$023F
	wb_adr_i <= X"02" & "001" & avs_s1_address(4 downto 1);
	wb_sel_i <= avs_s1_address(0) & not avs_s1_address(0);

	ins_irq0_irq <= '0';

	sb16_inst : sound_blaster_16
	  generic map
	  (
	    IO_BASE_ADDR    => X"0220",
	    DSP_VERSION     => X"0400"
	  )
	  port map
	  (
	    wb_clk_i        => csi_clockreset_clk,
	    wb_rst_i        => csi_clockreset_reset,
	    wb_adr_i        => wb_adr_i,
	    wb_dat_i        => avs_s1_writedata(15 downto 0),
	    wb_dat_o        => avs_s1_readdata(15 downto 0),
	    wb_sel_i        => wb_sel_i,
	    wb_cyc_i        => avs_s1_chipselect,
	    wb_stb_i        => avs_s1_chipselect,
	    wb_we_i         => avs_s1_write,
	    wb_ack_o        => avs_s1_waitrequest_n,
	    
	    sb16_io_arena   => open,

      pc_speaker      => coe_pc_speaker,
      	    
	    audio_l         => coe_audio_l,
	    audio_r         => coe_audio_r
	  );

end SYN;
