create_clock -period "50.0 MHz" [get_ports FPGA_CLK1_50]
create_clock -period "50.0 MHz" [get_ports FPGA_CLK2_50]
create_clock -period "50.0 MHz" [get_ports FPGA_CLK3_50]
create_clock -period "100.0 MHz" [get_pins -compatibility_mode *|h2f_user0_clk] 
create_clock -period 10.0 [get_pins -compatibility_mode spi|sclk_out] -name spi_sck

derive_pll_clocks

create_generated_clock -source [get_pins -compatibility_mode {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] \
                      -name HDMI_CLK [get_ports HDMI_TX_CLK]

derive_clock_uncertainty

set_clock_groups -asynchronous \
   -group [get_clocks { emu|u0|pll_0|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
   -group [get_clocks { emu|u0|pll_0|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] \
   -group [get_clocks { emu|u0|pll_0|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] \
   -group [get_clocks { pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] \
   -group [get_clocks { *|h2f_user0_clk}] \
   -group [get_clocks { FPGA_CLK1_50 FPGA_CLK2_50 FPGA_CLK3_50}]

set_output_delay -max -clock HDMI_CLK 2.0ns [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]
set_output_delay -min -clock HDMI_CLK -1.5ns [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]

set_false_path -from {*} -to [get_registers {wcalc[*] hcalc[*]}]


# Put constraints on input ports
set_false_path -from [get_ports {KEY*}] -to *
set_false_path -from [get_ports {BTN_*}] -to *

# Put constraints on output ports
set_false_path -from * -to [get_ports {LED_*}]
set_false_path -from * -to [get_ports {VGA_*}]
set_false_path -from * -to [get_ports {AUDIO_SPDIF}]
set_false_path -from * -to [get_ports {AUDIO_L}]
set_false_path -from * -to [get_ports {AUDIO_R}]
