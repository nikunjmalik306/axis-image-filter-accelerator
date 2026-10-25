# ==============================================================================
# File: Makefile
# Description: Multi-Tool build and verification Makefile for macOS / Linux
# ==============================================================================

SHELL := /bin/bash
export PATH := /opt/homebrew/bin:$(PATH)

IVERILOG ?= $(shell which iverilog 2>/dev/null || echo /opt/homebrew/bin/iverilog)
VVP      ?= $(shell which vvp 2>/dev/null || echo /opt/homebrew/bin/vvp)
YOSYS    ?= $(shell which yosys 2>/dev/null || echo /opt/homebrew/bin/yosys)
GTKWAVE  ?= $(shell which gtkwave 2>/dev/null || echo /opt/homebrew/bin/gtkwave)
PYTHON   ?= $(shell which python3 2>/dev/null || echo /usr/bin/python3)

RTL_DIR = ../rtl
TB_DIR  = ../tb
SW_DIR  = ../sw
SYN_DIR = ../syn

PKG_SRCS = $(RTL_DIR)/image_filter_pkg.sv
RTL_SRCS = \
	$(RTL_DIR)/icg_cell.sv \
	$(RTL_DIR)/line_buffer_2d.sv \
	$(RTL_DIR)/conv3x3_engine.sv \
	$(RTL_DIR)/axis_image_filter_top.sv

TB_SRCS = $(TB_DIR)/tb_axis_filter_top.sv

SIM_BIN = sim_axis_filter.vvp
VCD_FILE = axis_filter_trace.vcd

.PHONY: all golden sim wave synth clean

all: golden sim

golden:
	@echo "==> Running Python Golden Model to generate input & expected hex..."
	$(PYTHON) $(SW_DIR)/golden_model.py

sim: golden
	@echo "==> Compiling SystemVerilog with Icarus Verilog..."
	$(IVERILOG) -g2012 -o $(SIM_BIN) $(PKG_SRCS) $(RTL_SRCS) $(TB_SRCS)
	@echo "==> Running Simulation..."
	$(VVP) $(SIM_BIN)

wave:
	@if [ -f "$(VCD_FILE)" ]; then \
		echo "==> Opening $(VCD_FILE) in GTKWave..."; \
		$(GTKWAVE) $(VCD_FILE) & \
	else \
		echo "ERROR: Run 'make sim' first."; \
	fi

synth:
	@echo "==> Synthesizing RTL with Yosys..."
	cd $(SYN_DIR) && $(YOSYS) -s synth.ys > yosys_synth.log 2>&1
	@echo "==> Yosys Synthesis complete. Log saved to syn/yosys_synth.log"
	@grep -A 30 "=== axis_image_filter_top ===" $(SYN_DIR)/yosys_synth.log || tail -n 35 $(SYN_DIR)/yosys_synth.log

clean:
	rm -f $(SIM_BIN) $(VCD_FILE) input_pixels.hex expected_pixels.hex expected_mode*.hex
	rm -f $(SYN_DIR)/axis_image_filter_synth.v $(SYN_DIR)/yosys_synth.log
