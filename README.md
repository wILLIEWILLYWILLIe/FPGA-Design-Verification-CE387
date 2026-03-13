# FPGA-Design-Verification-CE387

[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)](https://en.wikipedia.org/wiki/SystemVerilog)
[![FPGA-Flow](https://img.shields.io/badge/Flow-FPGA%20Design-green.svg)]()
[![UVM-Verified](https://img.shields.io/badge/Methodology-UVM-blueviolet.svg)]()
[![Course-CE387](https://img.shields.io/badge/Course-CE387-red.svg)]()

This repository contains homework assignments and projects for the **CE387 - Real-Time Digital Systems Design and Verification with FPGAs** course.

## 📚 Homework Assignments

| Assignment | Description | PDF Link |
| :--- | :--- | :--- |
| **HW1** | Fibonacci Generator | [Assignment PDF](HW/HW1/FPGA_HW1.pdf) |
| **HW2** | Matrix Multiplication | [Assignment PDF](HW/HW2/FPGA_HW2.pdf) |
| **HW3** | Advanced FSM & Motion Detection | [Assignment PDF](HW/HW3/FPGA_HW3.pdf) |
| **HW4** | Edge Detection & UVM Intro | [Assignment PDF](HW/HW4/FPGA_HW4.pdf) |
| **HW5** | UDP Implementation & UVM | [Assignment PDF](HW/HW5/FPGA_HW5.pdf) |
| **HW6** | CORDIC Algorithm Implementation | [Assignment PDF](HW/HW6/FPGA_HW6.pdf) |
| **HW7** | Pipelined 16-point FFT Processor | [Assignment PDF](HW/HW7/FPGA_HW7.pdf) |
| **HW8** | Neural Network (MNIST Classifier) | [Assignment PDF](HW/HW8/FPGA_HW8.pdf) |

## 🛠️ Toolchain & Technologies

The following industry-standard EDA tools and environments are utilized throughout the course:

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
  - **Cadence Innovus**: Place & Route (P&R) and GDSII generation.
- **Project Tracking**: Design notes, timing optimization logs, and area/power reports.

## 🏗️ Repository Structure

The repository is organized by homework assignment, typically following this layout:
- `sv/`: SystemVerilog source files (RTL).
- `sim/`: Simulation files (ModelSim/Xcelium).
- `syn/`: Synthesis scripts and outcome (Synplify Pro/Cadence Genus).
- `uvm/`: UVM verification environments (for later assignments).
- `source/`: Reference input data, labels, and golden test vectors.
- `FPGA_HW<n>.pdf`: Detailed assignment description and requirements for each HW.

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
