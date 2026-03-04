# CE387 Homework Repository

This repository contains homework assignments and projects for the CE387 - REAL-TIME DIGITAL SYSTEMS DESIGN AND VERIFICATION WITH FPGAS course.

## Structure

The repository is organized by homework assignment:

- **HW/HW1/**: Homework 1
  - `sv/`: SystemVerilog source files
  - `sim/`: Simulation files
  - `syn/`: Synthesis scripts and output
  - `FPGA_HW1.pdf`: Assignment description

- **HW/HW2/**: Homework 2
  - `sv/`: SystemVerilog source files
  - `source/`: Additional source files
  - `sim/`: Simulation files
  - `syn/`: Synthesis scripts and output
  - `FPGA_HW2.pdf`: Assignment description

- **HW/HW3/**: Homework 3
  - `sv/`: SystemVerilog source files
  - `sim/`: Simulation files
  - `syn/`: Synthesis scripts and output
  - `hw3/`: Additional source files (motion detection, opencv demo)
  - `FPGA_HW3.pdf`: Assignment description

- **HW/HW4/**: Homework 4
  - `edge_detect/`: Contains source, simulation, and synthesis files for edge detection
    - `sv/`: SystemVerilog source files
    - `sim/`: Simulation files
    - `syn/`: Synthesis scripts and output
    - `uvm/`: UVM verification environment
  - `FPGA_HW4.pdf`: Assignment description

- **HW/HW5/**: Homework 5
  - `imp/`: Implementation directory
    - `sv/`: SystemVerilog source files
    - `sim/`: Simulation files
    - `syn/`: Synthesis scripts and output
    - `uvm/`: UVM verification environment
  - `udp/`: UDP implementation files
  - `FPGA_HW5.pdf`: Assignment description
  - `HW.tex`: Homework report (LaTeX)

- **HW/HW6/**: Homework 6
  - `imp/`: Implementation directory
    - `sv/`: SystemVerilog source files
    - `sim/`: Simulation files
    - `syn/`: Synthesis scripts and output
    - `uvm/`: UVM verification environment
  - `FPGA_HW6.pdf`: Assignment description
  - `cordic.cpp`: C++ source for CORDIC
  - `cordic_caltime.cpp`: C++ source for time calculation

- **HW/HW7/**: Homework 7 — Pipelined 16-point FFT Processor
  - `imp/`: Implementation directory
    - `sv/`: SystemVerilog source files (`fft_top.sv`, `fft_stage.sv`, `complex_mult.sv`, `fft_bit_reversal.sv`, etc.)
    - `sim/`: Simulation files (`fft_sim.do`, `fft_wave.do`)
    - `syn/`: Synthesis scripts and output
    - `uvm/`: UVM verification environment
    - `source/`: Reference I/O vectors (`fft_in_real.txt`, `fft_out_real.txt`, etc.)
  - `fft_quant.c`: C reference program for generating golden test vectors
  - `hw7.pdf`: Assignment description
  - `note.md`: Design notes and timing optimization history

- **HW/HW8/**: Homework 8 — Neural Network (MNIST Digit Classifier)
  - `imp/`: Implementation directory
    - `sv/`: SystemVerilog source files (`nn_top.sv`, `layer.sv`, `neuron.sv`, `fifo.sv`, `argmax.sv`, `nn_pkg.sv`, `nn_tb.sv`)
    - `sim/`: Simulation files (`nn_sim.do`, `nn_uvm_sim.do`, `nn_uvm_wave.do`, `Makefile`)
    - `syn/`: Synthesis scripts and output (`nn_top.prj`)
    - `uvm/`: UVM verification environment (12 files: `nn_if.sv`, `my_uvm_pkg.sv`, `my_uvm_tb.sv`, `my_uvm_transaction.sv`, `my_uvm_sequence.sv`, `my_uvm_driver.sv`, `my_uvm_monitor.sv`, `my_uvm_scoreboard.sv`, `my_uvm_agent.sv`, `my_uvm_env.sv`, `my_uvm_test.sv`, `my_uvm_globals.sv`)
    - `source/`: Weight/bias hex files and reference I/O (`x_test.txt`, `y_test.txt`)
  - `neural_net/`: C reference model (`neural_net.c`)
  - `hw8.pdf`: Assignment description
  - `note.md`: Design notes, synthesis optimization history, and UVM verification results

- **Demo/**: Demonstration files
  - `week1/`: Week 1 demos
  - `week2/`: Week 2 demos

- **Lecture/**: Lecture slides (PDFs)

## Usage

### Simulation
To run simulations, navigate to the `sim` directory within each homework folder and use ModelSim. Note that for HW4 and HW5, the `sim` directory is located inside a subdirectory.

- **HW1-HW3**: `HW/HW<#>/sim`
- **HW4**: `HW/HW4/edge_detect/sim`
- **HW5**: `HW/HW5/imp/sim`
- **HW6**: `HW/HW6/imp/sim`
- **HW7**: `HW/HW7/imp/sim`
- **HW8**: `HW/HW8/imp/sim`

Example for HW4:
```bash
cd HW/HW4/edge_detect/sim
vsim -c -do <script.do>
```
- `vsim`: Invokes the ModelSim simulator.
- `-c`: Runs in command-line mode (no GUI).
- `-do <script.do>`: Executes the specified Tcl script.

### Synthesis
To run synthesis, navigate to the `syn` directory within each homework folder and use Synplify Pro. Similar to simulation, for HW4 and HW5, this is inside a subdirectory.

- **HW1-HW3**: `HW/HW<#>/syn`
- **HW4**: `HW/HW4/edge_detect/syn`
- **HW5**: `HW/HW5/imp/syn`
- **HW6**: `HW/HW6/imp/syn`
- **HW7**: `HW/HW7/imp/syn`
- **HW8**: `HW/HW8/imp/syn`

Example for HW5:
```bash
cd HW/HW5/imp/syn
synplify_pro -batch <project.prj>
```
- `synplify_pro`: Invokes the Synplify Pro synthesis tool.
- `-batch`: Runs in batch mode (no GUI).
- `<project.prj>`: The project file containing settings to synthesize the design.
