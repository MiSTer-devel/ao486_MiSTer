
module system (
	clk_clk,
	clk_sys_clk,
	cpu_reset_reset,
	ddram_address,
	ddram_read,
	ddram_waitrequest,
	ddram_readdata,
	ddram_write,
	ddram_writedata,
	ddram_readdatavalid,
	ddram_byteenable,
	ddram_burstcount,
	disk_op_read,
	disk_op_write,
	disk_result_ok,
	disk_result_error,
	disk_op_device,
	mem_waitrequest,
	mem_readdata,
	mem_readdatavalid,
	mem_burstcount,
	mem_writedata,
	mem_address,
	mem_write,
	mem_read,
	mem_byteenable,
	mem_debugaccess,
	pll_reset_reset,
	ps2_kbclk_in,
	ps2_kbdat_in,
	ps2_kbclk_out,
	ps2_kbdat_out,
	ps2_mouseclk_in,
	ps2_mousedat_in,
	ps2_mouseclk_out,
	ps2_mousedat_out,
	ps2_misc_a20_enable,
	ps2_misc_reset_n,
	qsys_reset_reset,
	sound_sample_l,
	sound_sample_r,
	sound_fm_mode,
	sound_mpu_midi_in,
	sound_mpu_midi_out,
	sound_joystick_0,
	sound_joystick_1,
	speaker_enable,
	speaker_out,
	uart_h_cts_n,
	uart_h_rts_n,
	uart_h_dsr_n,
	uart_h_dcd_n,
	uart_h_ri_n,
	uart_h_dtr_n,
	uart_h_out1_n,
	uart_h_out2_n,
	uart_s_sin,
	uart_s_sout,
	uart_s_sout_oe,
	vga_clock,
	vga_blank_n,
	vga_hsync,
	vga_vsync,
	vga_r,
	vga_g,
	vga_b);	

	input		clk_clk;
	output		clk_sys_clk;
	input		cpu_reset_reset;
	output	[31:0]	ddram_address;
	output		ddram_read;
	input		ddram_waitrequest;
	input	[63:0]	ddram_readdata;
	output		ddram_write;
	output	[63:0]	ddram_writedata;
	input		ddram_readdatavalid;
	output	[7:0]	ddram_byteenable;
	output	[7:0]	ddram_burstcount;
	output		disk_op_read;
	output		disk_op_write;
	input		disk_result_ok;
	input		disk_result_error;
	output		disk_op_device;
	output		mem_waitrequest;
	output	[31:0]	mem_readdata;
	output		mem_readdatavalid;
	input	[0:0]	mem_burstcount;
	input	[31:0]	mem_writedata;
	input	[31:0]	mem_address;
	input		mem_write;
	input		mem_read;
	input	[3:0]	mem_byteenable;
	input		mem_debugaccess;
	input		pll_reset_reset;
	input		ps2_kbclk_in;
	input		ps2_kbdat_in;
	output		ps2_kbclk_out;
	output		ps2_kbdat_out;
	input		ps2_mouseclk_in;
	input		ps2_mousedat_in;
	output		ps2_mouseclk_out;
	output		ps2_mousedat_out;
	output		ps2_misc_a20_enable;
	output		ps2_misc_reset_n;
	input		qsys_reset_reset;
	output	[15:0]	sound_sample_l;
	output	[15:0]	sound_sample_r;
	input		sound_fm_mode;
	input		sound_mpu_midi_in;
	output		sound_mpu_midi_out;
	input	[11:0]	sound_joystick_0;
	input	[11:0]	sound_joystick_1;
	output		speaker_enable;
	output		speaker_out;
	input		uart_h_cts_n;
	output		uart_h_rts_n;
	input		uart_h_dsr_n;
	input		uart_h_dcd_n;
	input		uart_h_ri_n;
	output		uart_h_dtr_n;
	output		uart_h_out1_n;
	output		uart_h_out2_n;
	input		uart_s_sin;
	output		uart_s_sout;
	output		uart_s_sout_oe;
	output		vga_clock;
	output		vga_blank_n;
	output		vga_hsync;
	output		vga_vsync;
	output	[7:0]	vga_r;
	output	[7:0]	vga_g;
	output	[7:0]	vga_b;
endmodule
