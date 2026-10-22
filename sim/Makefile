RTL_DIR  := ../rtl
TB_DIR   := ../tb
RTL      := $(wildcard $(RTL_DIR)/*.v)
TOP      ?= tb_pim_mac
LINT_TOP ?= pim_bank_unit
PARAMS   ?=
MODE     ?= random

TESTS        := tb_pim_mac tb_pim_mac_simple tb_pim_simd_mac tb_pim_bank_array tb_pim_bank_unit
LINT_MODULES := $(basename $(notdir $(RTL)))

# TB가 $readmemh로 읽는 hex 파일을 시뮬레이션 직전에 만든다 (생성 파일이라 저장소에 넣지 않음)
GOLDEN   := python3 ../model/golden_gemv.py --banks 1 --K 256 --out .
GEN_tb_pim_bank_array := $(GOLDEN) --M 64
GEN_tb_pim_bank_unit  := $(GOLDEN) --M 4 --mode $(MODE)

sim:
	$(GEN_$(TOP))
	iverilog -g2012 -Wall -I$(RTL_DIR) $(PARAMS) -o $(TOP).vvp $(RTL) $(TB_DIR)/$(TOP).v
	vvp -n $(TOP).vvp $(PLUSARGS)

test:
	@fail=0; for t in $(TESTS); do \
	  r=$$($(MAKE) --no-print-directory -s sim TOP=$$t 2>&1 | grep -E '^(PASS|FAIL)' | tail -1); \
	  printf '%-20s %s\n' $$t "$${r:-FAIL (no result)}"; \
	  [ "$$r" = "PASS" ] || fail=1; \
	done; exit $$fail

wave:
	gtkwave $(TOP).vcd &

lint:
	verilator --lint-only -Wall -DSYNTHESIS -I$(RTL_DIR) $(RTL) --top-module $(LINT_TOP)

lint-all:
	@for m in $(LINT_MODULES); do \
	  printf '%-20s ' $$m; \
	  if verilator --lint-only -Wall -DSYNTHESIS -I$(RTL_DIR) $(RTL) --top-module $$m >/dev/null 2>&1; \
	  then echo "0 warnings"; else echo "WARNING (make lint LINT_TOP=$$m)"; exit 1; fi; \
	done

clean:
	rm -f *.vvp *.vcd *.hex

.PHONY: sim test wave lint lint-all clean
