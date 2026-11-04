# Systolic Array FPGA — Verification & Linting Makefile
# Simulation/waveforms: Verilator (--binary --trace) + GTKWave
# Quartus compile check: Verilator strict lint-only (IEEE 1800-2009)

# ------------------------------------------------------------------ Tools
VERILATOR := verilator
GTKWAVE   := gtkwave

# ------------------------------------------------------------- Directories
RTL_DIR   := rtl
TB_DIR    := tb
SYN_DIR   := syn
OBJ_DIR   := obj_dir

# ---------------------------------------------------------------- Sources
RTL_SRCS  := $(wildcard $(RTL_DIR)/*.sv)

# Auto-discover every testbench under tb/ (any depth):
# a file counts as a TB if its basename matches tb*.sv or *_tb.sv.
TB_FILES  := $(shell find $(TB_DIR) -name 'tb*.sv' -o -name '*_tb.sv' 2>/dev/null)

# Select which TB to run with:  make sim TB=tb_top   (default: first discovered)
TB        ?= $(notdir $(basename $(firstword $(TB_FILES))))
TB_SRC    := $(strip $(foreach f,$(TB_FILES),$(if $(filter $(TB),$(notdir $(basename $(f)))),$(f))))

# The top module name is read from the selected TB file (first `module` decl),
# since a file's basename need not equal its module name.
TB_TOP     = $(shell grep -m1 -oE '^[[:space:]]*module[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' $(TB_SRC) | awk '{print $$2}')

# Per-TB build dir and waveform so different TBs never clobber each other.
SIM_DIR    = $(OBJ_DIR)/$(TB)
SIM_BIN    = $(SIM_DIR)/V$(TB_TOP)
WAVE       = $(TB_DIR)/$(TB).vcd

# -------------------------------------------------------------- Flags
# Simulation: --binary builds a runnable exe, --trace enables VCD dumping.
SIM_FLAGS  := --binary --trace -Wall -Wno-UNUSEDSIGNAL -Wno-BLKSEQ \
              -Wno-INITIALDLY -Wno-fatal -I$(RTL_DIR)

# Quartus-strict lint-only proxy (IEEE 1800-2009, the standard Quartus Lite uses).
TOP_RTL    ?= Systolic_Array
QLINT_FLAGS := --lint-only -Wall -Wpedantic --language 1800-2009 \
               -Wno-UNUSEDSIGNAL -I$(RTL_DIR)

# ============================================================================
.PHONY: all help list check-tb compile sim wave lint-quartus check-qsf clean

all: lint-quartus sim

help:
	@echo "======================================================================"
	@echo " Systolic Array Verification Makefile (Verilator + GTKWave)"
	@echo "======================================================================"
	@echo " make list               - List all auto-discovered testbenches"
	@echo " make compile TB=<name>  - Build the Verilator sim binary for one TB"
	@echo " make sim TB=<name>      - Compile + run sim, dump tb/<TB>.vcd"
	@echo " make wave TB=<name>     - Run sim (if needed) + open VCD in GTKWave"
	@echo " make lint-quartus       - Verilator strict IEEE 1800-2009 lint (Quartus proxy)"
	@echo " make clean              - Remove obj_dir/ and generated .vcd files"
	@echo "----------------------------------------------------------------------"
	@echo " Default TB (first discovered): $(TB)"
	@echo " Select another:  make wave TB=tb_top"
	@echo "======================================================================"

# ---------------------------------------------------- List discovered TBs
list:
	@echo ">>> [DISCOVER] Testbenches found under $(TB_DIR)/:"
	@for f in $(TB_FILES); do \
		name=$$(basename $$f .sv); \
		top=$$(grep -m1 -oE '^[[:space:]]*module[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' $$f | awk '{print $$2}'); \
		printf "   %-24s (top module: %s)  ->  %s\n" "$$name" "$$top" "$$f"; \
	done
	@echo "   Run with: make sim TB=<name>   or   make wave TB=<name>"

# ---------------------------------------------------- Validate TB selection
check-tb:
	@if [ -z "$(TB_SRC)" ]; then \
		echo "  [ERROR] No testbench matches TB=$(TB)."; \
		echo "          Run 'make list' to see available testbenches."; \
		exit 1; \
	fi

# ------------------------------------------- Compile TB into a Verilator exe
compile: check-tb
	@echo ">>> [COMPILE] Building $(TB) (top=$(TB_TOP)) -> $(SIM_BIN)"
	@mkdir -p $(SIM_DIR)
	$(VERILATOR) $(SIM_FLAGS) --Mdir $(SIM_DIR) $(RTL_SRCS) $(TB_SRC) \
		--top-module $(TB_TOP) --exe --main
	@echo ">>> [PASS] Built $(SIM_BIN)"

# ------------------------------------------- Run sim and dump per-TB VCD
sim: compile
	@echo ">>> [SIM] Running $(TB_TOP)..."
	./$(SIM_BIN) +WAVE=$(WAVE)
	@echo ">>> [WAVE] VCD written to $(WAVE)"

# ------------------------------------------- Open waveform in GTKWave
wave: sim
	@echo ">>> [GTKWAVE] Opening $(WAVE)..."
	$(GTKWAVE) $(WAVE) >/dev/null 2>&1 &

# ======================================================= Quartus compile proxy
lint-quartus: check-qsf
	@echo ">>> [QUARTUS-LINT] Checking RTL against IEEE 1800-2009 standard..."
	$(VERILATOR) $(QLINT_FLAGS) $(RTL_SRCS) --top-module $(TOP_RTL)
	@echo ">>> [PASS] Quartus-strict lint passed!"

# Verify every file in rtl/ is registered inside syn/Top.qsf
check-qsf:
	@echo ">>> [QSF-CHECK] Verifying all rtl/*.sv files are listed in $(SYN_DIR)/Top.qsf..."
	@if [ -f $(SYN_DIR)/Top.qsf ]; then \
		missing=0; \
		for f in $(notdir $(RTL_SRCS)); do \
			if ! grep -q "$$f" $(SYN_DIR)/Top.qsf; then \
				echo "  [WARNING] $$f is missing from $(SYN_DIR)/Top.qsf!"; \
				missing=1; \
			fi; \
		done; \
		if [ $$missing -eq 0 ]; then \
			echo ">>> [PASS] All RTL files are registered in $(SYN_DIR)/Top.qsf."; \
		fi; \
	else \
		echo "  [INFO] $(SYN_DIR)/Top.qsf not found; skipping QSF manifest check."; \
	fi

# ============================================================== Clean
clean:
	@echo ">>> [CLEAN] Removing $(OBJ_DIR)/ and .vcd files..."
	rm -rf $(OBJ_DIR) $(TB_DIR)/*.vcd *.vcd
