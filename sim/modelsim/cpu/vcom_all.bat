RMDIR /s /q work
MKDIR work

vmap altera_mf altera_mf

vlib work

vlog -O0 ../../../rtl/common/simple_ram.v ^
../../../rtl/common/simple_fifo.v ^
../../../rtl/common/simple_fifo_mlab.v ^
../../../rtl/common/simple_mult.v

vlog -O0 +incdir+./../../../rtl/ao486/  ../../../rtl/ao486/memory/avalon_mem.v ^
../../../rtl/ao486/memory/icache.v ^
../../../rtl/ao486/memory/link_dcacheread.v ^
../../../rtl/ao486/memory/link_dcachewrite.v ^
../../../rtl/ao486/memory/memory.v ^
../../../rtl/ao486/memory/memory_read.v ^
../../../rtl/ao486/memory/memory_write.v ^
../../../rtl/ao486/memory/prefetch.v ^
../../../rtl/ao486/memory/prefetch_control.v ^
../../../rtl/ao486/memory/prefetch_fifo.v ^
../../../rtl/ao486/memory/tlb.v ^
../../../rtl/ao486/memory/tlb_memtype.v ^
../../../rtl/ao486/memory/tlb_regs.v

vlog -O0 +incdir+./../../../rtl/ao486/ ../../../rtl/ao486/pipeline/condition.v ^
../../../rtl/ao486/pipeline/decode.v ^
../../../rtl/ao486/pipeline/decode_commands.v ^
../../../rtl/ao486/pipeline/decode_prefix.v ^
../../../rtl/ao486/pipeline/decode_ready.v ^
../../../rtl/ao486/pipeline/decode_regs.v ^
../../../rtl/ao486/pipeline/execute.v ^
../../../rtl/ao486/pipeline/execute_commands.v ^
../../../rtl/ao486/pipeline/execute_divide.v ^
../../../rtl/ao486/pipeline/execute_multiply.v ^
../../../rtl/ao486/pipeline/execute_offset.v ^
../../../rtl/ao486/pipeline/execute_shift.v ^
../../../rtl/ao486/pipeline/fetch.v ^
../../../rtl/ao486/pipeline/microcode.v ^
../../../rtl/ao486/pipeline/microcode_commands.v ^
../../../rtl/ao486/pipeline/pipeline.v ^
../../../rtl/ao486/pipeline/read.v ^
../../../rtl/ao486/pipeline/read_commands.v ^
../../../rtl/ao486/pipeline/read_debug.v ^
../../../rtl/ao486/pipeline/read_effective_address.v ^
../../../rtl/ao486/pipeline/read_mutex.v ^
../../../rtl/ao486/pipeline/read_segment.v ^
../../../rtl/ao486/pipeline/write.v ^
../../../rtl/ao486/pipeline/write_commands.v ^
../../../rtl/ao486/pipeline/write_debug.v ^
../../../rtl/ao486/pipeline/write_register.v ^
../../../rtl/ao486/pipeline/write_stack.v ^
../../../rtl/ao486/pipeline/write_string.v

vlog -sv -O0 ../../../rtl/cache/l2_cache.v ^
../../../rtl/cache/l1_icache.v

vlog -vlog01compat -O0 ^
../../../rtl/ao486/exception.v ^
../../../rtl/ao486/global_regs.v ^
../../../rtl/ao486/ao486.v

vcom -O5 -2008 -vopt -quiet -work work ^
cpu_export.vhd

vcom -O5 -vopt -quiet -work work ^
globals.vhd ^
stringprocessor.vhd ^
tb.vhd

