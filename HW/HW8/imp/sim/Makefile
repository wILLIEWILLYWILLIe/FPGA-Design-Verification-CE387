# ============================================================
# Makefile for Neural Network Simulation (Cadence Xcelium xrun)
# ============================================================
# Usage:
#   make sim         — Run direct testbench
#   make sim_gui     — Run with waveform GUI
#   make clean       — Remove xcelium artifacts
# ============================================================

SV_DIR   := ../sv

XFLAGS   := -sv -access +rwc -timescale 1ns/1ps -64bit

# Package
PKG      := $(SV_DIR)/nn_pkg.sv

# Source files (order: package → leaf modules → top → testbench)
ALL_SRC  := $(PKG) \
            $(SV_DIR)/fifo.sv \
            $(SV_DIR)/neuron.sv \
            $(SV_DIR)/layer.sv \
            $(SV_DIR)/argmax.sv \
            $(SV_DIR)/nn_top.sv \
            $(SV_DIR)/nn_tb.sv

# -------------------------------------------------------
.PHONY: sim sim_gui clean

# Run direct testbench
sim:
	xrun $(XFLAGS) $(ALL_SRC)

# Run with GUI for waveforms
sim_gui:
	xrun $(XFLAGS) -gui $(ALL_SRC)

# Clean
clean:
	rm -rf xcelium.d INCA_libs xrun.log xrun.history waves.shm *.key
	@echo "Cleaned."
