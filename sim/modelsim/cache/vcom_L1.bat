RMDIR /s /q work
MKDIR work

vmap altera_mf altera_mf

vlib work

vlog -O0 ../../../rtl/common/simple_ram.v ^
../../../rtl/common/simple_fifo.v ^
../../../rtl/common/simple_fifo_mlab.v ^
../../../rtl/common/simple_mult.v

vlog -sv -O0 ../../../rtl/cache/l1_icache.v

vcom -O5 -vopt -quiet -work work ^
tb_L1.vhd

