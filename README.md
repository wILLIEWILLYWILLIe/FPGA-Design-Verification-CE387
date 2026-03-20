# FPGA-Design-Verification-CE387

[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)](https://en.wikipedia.org/wiki/SystemVerilog)
[![FPGA-Flow](https://img.shields.io/badge/Flow-FPGA%20Design-green.svg)](https://en.wikipedia.org/wiki/Field-programmable_gate_array)
[![UVM-Verified](https://img.shields.io/badge/Methodology-UVM-blueviolet.svg)](https://en.wikipedia.org/wiki/Universal_Verification_Methodology)
[![Precision](https://img.shields.io/badge/Tool-Precision-orange.svg)](https://www.siemens.com/en-us/products/ic/precision/)
[![Synplify](https://img.shields.io/badge/Tool-Synplify-purple.svg)](https://www.synopsys.com/implementation-and-signoff/fpga-based-design/synplify.html)
<!-- [![Course-CE387](https://img.shields.io/badge/Course-CE387-red.svg)]() -->

This repository contains homework assignments and projects for the **CE387 - Real-Time Digital Systems Design and Verification with FPGAs** course.

### 1. Homework Assignments

| Assignment | Description | Folder Location | PDF Link |
| :--- | :--- | :--- | :--- |
| **HW1** | Fibonacci Generator | [`HW/HW1`](HW/HW1) | [Assignment PDF](HW/HW1/FPGA_HW1.pdf) |
| **HW2** | Matrix Multiplication | [`HW/HW2`](HW/HW2) | [Assignment PDF](HW/HW2/FPGA_HW2.pdf) |
| **HW3** | Advanced FSM & Motion Detection | [`HW/HW3`](HW/HW3) | [Assignment PDF](HW/HW3/FPGA_HW3.pdf) |
| **HW4** | Edge Detection & UVM Intro | [`HW/HW4`](HW/HW4) | [Assignment PDF](HW/HW4/FPGA_HW4.pdf) |
| **HW5** | UDP Implementation & UVM | [`HW/HW5`](HW/HW5) | [Assignment PDF](HW/HW5/FPGA_HW5.pdf) |
| **HW6** | CORDIC Algorithm Implementation | [`HW/HW6`](HW/HW6) | [Assignment PDF](HW/HW6/FPGA_HW6.pdf) |
| **HW7** | Pipelined 16-point FFT Processor | [`HW/HW7`](HW/HW7) | [Assignment PDF](HW/HW7/FPGA_HW7.pdf) |
| **HW8** | Neural Network (MNIST Classifier) | [`HW/HW8`](HW/HW8) | [Assignment PDF](HW/HW8/FPGA_HW8.pdf) |

## 🛠️ Toolchain & Technologies

The following industry-standard EDA tools and environments are utilized throughout the course:

- **Hardware Platform**:
  - The designs are targeted for the following hardware platform:
  - **FPGA Model**: Intel Cyclone IV E EP4CE115
- **Languages & Methodology**: 
  - **SystemVerilog** (IEEE 1800-2017) for Design & Verification.
  - **UVM** (Universal Verification Methodology) for structured testbenches.
  - **C/C++ & Python** for reference modeling and test vector generation.
- **Simulation**: 
  - **Mentor Graphics ModelSim**: Standard RTL/Gate-level simulation.
  - **Cadence Xcelium (xrun)**: High-performance parallel simulation.
- **Synthesis & Physical Design**:
  - **Synopsys Synplify Pro**: FPGA-specific synthesis.
  - **Cadence Genus**: ASIC Logic Synthesis.
- **Project Tracking**: Design notes, timing optimization logs, and area/power reports.

## 🚀 Getting Started

### Environment Setup
To initialize the EDA tool environment on the server, source the `myenv` script from the repository root:
```bash
source myenv
```
This script sets up paths for ModelSim, Synplify Pro, and QuestaSim.

## 🏗️ Repository Structure

The repository is organized by homework assignment, typically following this layout:
- `sv/`: SystemVerilog source files (RTL).
- `sim/`: Simulation files (ModelSim/Xcelium).
- `syn/`: Synthesis scripts and outcome (Synplify Pro/Cadence Genus).
- `uvm/`: UVM verification environments (for later assignments).
- `source/`: Reference input data, labels, and golden test vectors.

## 📦 Archive
Previous course materials (Lectures and Demos) have been moved to the [**`archive`**](https://github.com/wILLIEWILLYWILLIe/NU_CE387_FGFAs/tree/archive?tab=readme-ov-file) branch to keep the main branch focused on assignment implementations.

## 🛠️ Usage

### Simulation
Navigate to the `sim` directory within each homework folder and use ModelSim or Xcelium.

Example for HW4:
```bash
cd HW/HW4/edge_detect/sim
vsim -c -do <script.do>
```
- `vsim`: Invokes the ModelSim simulator.
- `-c`: Runs in command-line mode (no GUI).
- `-do <script.do>`: Executes the specified Tcl script.

### Synthesis
Navigate to the `syn` directory within each homework folder and use Synplify Pro.

Example for HW5:
```bash
cd HW/HW5/imp/syn
synplify_pro -batch <project.prj>
```
