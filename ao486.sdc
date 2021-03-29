derive_pll_clocks
derive_clock_uncertainty

set clk_sys   {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}
set clk_uart1 {*|pll|pll_inst|altera_pll_i|*[1].*|divclk}
set clk_mpu   {*|pll|pll_inst|altera_pll_i|*[2].*|divclk}
set clk_opl   {*|pll|pll_inst|altera_pll_i|*[3].*|divclk}
set clk_vga   {*|pll|pll_inst|altera_pll_i|*[4].*|divclk}
set clk_uart2 {*|pll|pll_inst|altera_pll_i|*[5].*|divclk}

set_false_path -from [get_clocks $clk_sys]   -to [get_clocks $clk_vga]
set_false_path -from [get_clocks $clk_vga]   -to [get_clocks $clk_sys]

set_false_path -from [get_clocks $clk_sys]   -to [get_clocks $clk_opl]
set_false_path -from [get_clocks $clk_opl]   -to [get_clocks $clk_sys]

set_false_path -from [get_clocks $clk_sys]   -to [get_clocks $clk_uart1]
set_false_path -from [get_clocks $clk_uart1] -to [get_clocks $clk_sys]
set_false_path -from [get_clocks $clk_sys]   -to [get_clocks $clk_uart2]
set_false_path -from [get_clocks $clk_uart2] -to [get_clocks $clk_sys]

set_false_path -from [get_clocks $clk_sys]   -to [get_clocks $clk_mpu]
set_false_path -from [get_clocks $clk_mpu]   -to [get_clocks $clk_sys]

set_multicycle_path -from {emu:emu|reset*} -setup 2
set_multicycle_path -from {emu:emu|reset*} -hold 1
