RTL_DIR  := ../rtl
TB_DIR   := ../tb
RTL      := $(wildcard $(RTL_DIR)/*.v)
TOP      ?= tb_pim_mac
LINT_TOP ?= pim_top
PARAMS   ?=

sim:
	iverilog -g2012 -Wall -I$(RTL_DIR) $(PARAMS) -o $(TOP).vvp $(RTL) $(TB_DIR)/$(TOP).v
	vvp -n $(TOP).vvp $(PLUSARGS)

wave:
	gtkwave $(TOP).vcd &

lint:
	verilator --lint-only -Wall -DSYNTHESIS -I$(RTL_DIR) $(RTL) --top-module $(LINT_TOP)

clean:
	rm -f *.vvp *.vcd *.hex

.PHONY: sim wave lint clean
