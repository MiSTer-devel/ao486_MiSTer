# NE2000 simulation harness (NE2000_AO486_PLAN.md).
#
#   make check      run the whole suite (regression/ + local tb_*.v)
#   make tb_NAME    build and run one local bench
#   make clean

RTL   := ../../../rtl/soc/ne2000
BUILD := build

IVFLAGS := -g2012

LOCAL_TBS := $(patsubst %.v,%,$(wildcard tb_*.v))

.PHONY: all check clean list

all: check

check:
	@sh ./run_regression.sh

list:
	@echo "regression benches:"; ls regression/*_tb.v | xargs -n1 basename
	@echo "local benches:     "; echo $(LOCAL_TBS)

tb_%: tb_%.v
	@mkdir -p $(BUILD)
	iverilog $(IVFLAGS) -o $(BUILD)/$@.vvp -y $(RTL) -y ../../../rtl/soc $<
	@cd $(BUILD) && vvp $@.vvp

clean:
	rm -rf $(BUILD)
