	component system is
		port (
			clk_clk             : in  std_logic                     := 'X';             -- clk
			clk_sys_clk         : out std_logic;                                        -- clk
			cpu_reset_reset     : in  std_logic                     := 'X';             -- reset
			ddram_address       : out std_logic_vector(31 downto 0);                    -- address
			ddram_read          : out std_logic;                                        -- read
			ddram_waitrequest   : in  std_logic                     := 'X';             -- waitrequest
			ddram_readdata      : in  std_logic_vector(63 downto 0) := (others => 'X'); -- readdata
			ddram_write         : out std_logic;                                        -- write
			ddram_writedata     : out std_logic_vector(63 downto 0);                    -- writedata
			ddram_readdatavalid : in  std_logic                     := 'X';             -- readdatavalid
			ddram_byteenable    : out std_logic_vector(7 downto 0);                     -- byteenable
			ddram_burstcount    : out std_logic_vector(7 downto 0);                     -- burstcount
			disk_op_read        : out std_logic;                                        -- op_read
			disk_op_write       : out std_logic;                                        -- op_write
			disk_result_ok      : in  std_logic                     := 'X';             -- result_ok
			disk_result_error   : in  std_logic                     := 'X';             -- result_error
			disk_op_device      : out std_logic;                                        -- op_device
			mem_waitrequest     : out std_logic;                                        -- waitrequest
			mem_readdata        : out std_logic_vector(31 downto 0);                    -- readdata
			mem_readdatavalid   : out std_logic;                                        -- readdatavalid
			mem_burstcount      : in  std_logic_vector(0 downto 0)  := (others => 'X'); -- burstcount
			mem_writedata       : in  std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			mem_address         : in  std_logic_vector(31 downto 0) := (others => 'X'); -- address
			mem_write           : in  std_logic                     := 'X';             -- write
			mem_read            : in  std_logic                     := 'X';             -- read
			mem_byteenable      : in  std_logic_vector(3 downto 0)  := (others => 'X'); -- byteenable
			mem_debugaccess     : in  std_logic                     := 'X';             -- debugaccess
			pll_reset_reset     : in  std_logic                     := 'X';             -- reset
			ps2_kbclk_in        : in  std_logic                     := 'X';             -- kbclk_in
			ps2_kbdat_in        : in  std_logic                     := 'X';             -- kbdat_in
			ps2_kbclk_out       : out std_logic;                                        -- kbclk_out
			ps2_kbdat_out       : out std_logic;                                        -- kbdat_out
			ps2_mouseclk_in     : in  std_logic                     := 'X';             -- mouseclk_in
			ps2_mousedat_in     : in  std_logic                     := 'X';             -- mousedat_in
			ps2_mouseclk_out    : out std_logic;                                        -- mouseclk_out
			ps2_mousedat_out    : out std_logic;                                        -- mousedat_out
			ps2_misc_a20_enable : out std_logic;                                        -- a20_enable
			ps2_misc_reset_n    : out std_logic;                                        -- reset_n
			qsys_reset_reset    : in  std_logic                     := 'X';             -- reset
			sound_sample_l      : out std_logic_vector(15 downto 0);                    -- sample_l
			sound_sample_r      : out std_logic_vector(15 downto 0);                    -- sample_r
			sound_fm_mode       : in  std_logic                     := 'X';             -- fm_mode
			sound_mpu_midi_in   : in  std_logic                     := 'X';             -- mpu_midi_in
			sound_mpu_midi_out  : out std_logic;                                        -- mpu_midi_out
			sound_joystick_0    : in  std_logic_vector(11 downto 0) := (others => 'X'); -- joystick_0
			sound_joystick_1    : in  std_logic_vector(11 downto 0) := (others => 'X'); -- joystick_1
			speaker_enable      : out std_logic;                                        -- enable
			speaker_out         : out std_logic;                                        -- out
			uart_h_cts_n        : in  std_logic                     := 'X';             -- cts_n
			uart_h_rts_n        : out std_logic;                                        -- rts_n
			uart_h_dsr_n        : in  std_logic                     := 'X';             -- dsr_n
			uart_h_dcd_n        : in  std_logic                     := 'X';             -- dcd_n
			uart_h_ri_n         : in  std_logic                     := 'X';             -- ri_n
			uart_h_dtr_n        : out std_logic;                                        -- dtr_n
			uart_h_out1_n       : out std_logic;                                        -- out1_n
			uart_h_out2_n       : out std_logic;                                        -- out2_n
			uart_s_sin          : in  std_logic                     := 'X';             -- sin
			uart_s_sout         : out std_logic;                                        -- sout
			uart_s_sout_oe      : out std_logic;                                        -- sout_oe
			vga_clock           : out std_logic;                                        -- clock
			vga_blank_n         : out std_logic;                                        -- blank_n
			vga_hsync           : out std_logic;                                        -- hsync
			vga_vsync           : out std_logic;                                        -- vsync
			vga_r               : out std_logic_vector(7 downto 0);                     -- r
			vga_g               : out std_logic_vector(7 downto 0);                     -- g
			vga_b               : out std_logic_vector(7 downto 0)                      -- b
		);
	end component system;

	u0 : component system
		port map (
			clk_clk             => CONNECTED_TO_clk_clk,             --        clk.clk
			clk_sys_clk         => CONNECTED_TO_clk_sys_clk,         --    clk_sys.clk
			cpu_reset_reset     => CONNECTED_TO_cpu_reset_reset,     --  cpu_reset.reset
			ddram_address       => CONNECTED_TO_ddram_address,       --      ddram.address
			ddram_read          => CONNECTED_TO_ddram_read,          --           .read
			ddram_waitrequest   => CONNECTED_TO_ddram_waitrequest,   --           .waitrequest
			ddram_readdata      => CONNECTED_TO_ddram_readdata,      --           .readdata
			ddram_write         => CONNECTED_TO_ddram_write,         --           .write
			ddram_writedata     => CONNECTED_TO_ddram_writedata,     --           .writedata
			ddram_readdatavalid => CONNECTED_TO_ddram_readdatavalid, --           .readdatavalid
			ddram_byteenable    => CONNECTED_TO_ddram_byteenable,    --           .byteenable
			ddram_burstcount    => CONNECTED_TO_ddram_burstcount,    --           .burstcount
			disk_op_read        => CONNECTED_TO_disk_op_read,        --       disk.op_read
			disk_op_write       => CONNECTED_TO_disk_op_write,       --           .op_write
			disk_result_ok      => CONNECTED_TO_disk_result_ok,      --           .result_ok
			disk_result_error   => CONNECTED_TO_disk_result_error,   --           .result_error
			disk_op_device      => CONNECTED_TO_disk_op_device,      --           .op_device
			mem_waitrequest     => CONNECTED_TO_mem_waitrequest,     --        mem.waitrequest
			mem_readdata        => CONNECTED_TO_mem_readdata,        --           .readdata
			mem_readdatavalid   => CONNECTED_TO_mem_readdatavalid,   --           .readdatavalid
			mem_burstcount      => CONNECTED_TO_mem_burstcount,      --           .burstcount
			mem_writedata       => CONNECTED_TO_mem_writedata,       --           .writedata
			mem_address         => CONNECTED_TO_mem_address,         --           .address
			mem_write           => CONNECTED_TO_mem_write,           --           .write
			mem_read            => CONNECTED_TO_mem_read,            --           .read
			mem_byteenable      => CONNECTED_TO_mem_byteenable,      --           .byteenable
			mem_debugaccess     => CONNECTED_TO_mem_debugaccess,     --           .debugaccess
			pll_reset_reset     => CONNECTED_TO_pll_reset_reset,     --  pll_reset.reset
			ps2_kbclk_in        => CONNECTED_TO_ps2_kbclk_in,        --        ps2.kbclk_in
			ps2_kbdat_in        => CONNECTED_TO_ps2_kbdat_in,        --           .kbdat_in
			ps2_kbclk_out       => CONNECTED_TO_ps2_kbclk_out,       --           .kbclk_out
			ps2_kbdat_out       => CONNECTED_TO_ps2_kbdat_out,       --           .kbdat_out
			ps2_mouseclk_in     => CONNECTED_TO_ps2_mouseclk_in,     --           .mouseclk_in
			ps2_mousedat_in     => CONNECTED_TO_ps2_mousedat_in,     --           .mousedat_in
			ps2_mouseclk_out    => CONNECTED_TO_ps2_mouseclk_out,    --           .mouseclk_out
			ps2_mousedat_out    => CONNECTED_TO_ps2_mousedat_out,    --           .mousedat_out
			ps2_misc_a20_enable => CONNECTED_TO_ps2_misc_a20_enable, --   ps2_misc.a20_enable
			ps2_misc_reset_n    => CONNECTED_TO_ps2_misc_reset_n,    --           .reset_n
			qsys_reset_reset    => CONNECTED_TO_qsys_reset_reset,    -- qsys_reset.reset
			sound_sample_l      => CONNECTED_TO_sound_sample_l,      --      sound.sample_l
			sound_sample_r      => CONNECTED_TO_sound_sample_r,      --           .sample_r
			sound_fm_mode       => CONNECTED_TO_sound_fm_mode,       --           .fm_mode
			sound_mpu_midi_in   => CONNECTED_TO_sound_mpu_midi_in,   --           .mpu_midi_in
			sound_mpu_midi_out  => CONNECTED_TO_sound_mpu_midi_out,  --           .mpu_midi_out
			sound_joystick_0    => CONNECTED_TO_sound_joystick_0,    --           .joystick_0
			sound_joystick_1    => CONNECTED_TO_sound_joystick_1,    --           .joystick_1
			speaker_enable      => CONNECTED_TO_speaker_enable,      --    speaker.enable
			speaker_out         => CONNECTED_TO_speaker_out,         --           .out
			uart_h_cts_n        => CONNECTED_TO_uart_h_cts_n,        --     uart_h.cts_n
			uart_h_rts_n        => CONNECTED_TO_uart_h_rts_n,        --           .rts_n
			uart_h_dsr_n        => CONNECTED_TO_uart_h_dsr_n,        --           .dsr_n
			uart_h_dcd_n        => CONNECTED_TO_uart_h_dcd_n,        --           .dcd_n
			uart_h_ri_n         => CONNECTED_TO_uart_h_ri_n,         --           .ri_n
			uart_h_dtr_n        => CONNECTED_TO_uart_h_dtr_n,        --           .dtr_n
			uart_h_out1_n       => CONNECTED_TO_uart_h_out1_n,       --           .out1_n
			uart_h_out2_n       => CONNECTED_TO_uart_h_out2_n,       --           .out2_n
			uart_s_sin          => CONNECTED_TO_uart_s_sin,          --     uart_s.sin
			uart_s_sout         => CONNECTED_TO_uart_s_sout,         --           .sout
			uart_s_sout_oe      => CONNECTED_TO_uart_s_sout_oe,      --           .sout_oe
			vga_clock           => CONNECTED_TO_vga_clock,           --        vga.clock
			vga_blank_n         => CONNECTED_TO_vga_blank_n,         --           .blank_n
			vga_hsync           => CONNECTED_TO_vga_hsync,           --           .hsync
			vga_vsync           => CONNECTED_TO_vga_vsync,           --           .vsync
			vga_r               => CONNECTED_TO_vga_r,               --           .r
			vga_g               => CONNECTED_TO_vga_g,               --           .g
			vga_b               => CONNECTED_TO_vga_b                --           .b
		);

