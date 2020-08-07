Tested with Modelsim 10.5

- compile with vcom_all.bat. Make sure you have altera_mf library in folder, generated from quartus
- run modelsim with vsim_start.bat
- run all

Simulation will now wait for input from outside

Run Luascript asm_code.lua with "lua asm_code.lua" from folder lua_tests

It will generate a pseudo random asm code, build binary with FASM, upload it into the testbench and let the cpu run it
Fake boot0.rom will jump the cpu to address 0, where the FASM output is written to.


CPU Export in pipeline will write a log with every register change for every instruction.
This can be used to compare(with a diff tool) original behavior to any changes made.
