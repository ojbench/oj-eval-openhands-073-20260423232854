# Problem 073 - RISC-V CPU (rv32i)

**ACMOJ Problem ID**: 2531

## Introduction

### Background

In this project, you need to design and implement a RISC-V CPU using Verilog HDL (Hardware Description Language). The CPU must support the RV32I instruction set and implement a Tomasulo-based out-of-order execution architecture. Your Verilog code will be verified through software simulation, where the CPU executes test programs and the output is compared against expected results.

This is a hardware design project from the ACM Class at Shanghai Jiao Tong University, based on the [RISCV-CPU project](https://github.com/ACMClassCourses/RISCV-CPU).

## Assignment Description

### Grade Composition

| Grading Component | Percentage |
| :--: | :--: |
| Pass **2531. CPU 2024 (rv32i)** simulation tests | 75% |
| FPGA tests | 10% |
| Code Review | 15% |

## Assignment Requirements

### Project Overview

You must implement a **speculative, out-of-order execution** RISC-V CPU supporting the **RV32I** instruction set using Verilog. The CPU architecture should follow the Tomasulo algorithm with the following stages:

1. **Issue** - Decode instructions and assign to reservation stations
2. **Execute** - Perform computation when operands are ready
3. **Write Result** - Broadcast results via Common Data Bus (CDB)

An **Instruction Cache** must be implemented to ensure instruction-level parallelism.

### Required Instructions (37 total)

`LUI`, `AUIPC`, `JAL`, `JALR`, `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`, `ADDI`, `SLLI`, `SLTI`, `SLTIU`, `XORI`, `SRLI`, `SRAI`, `ORI`, `ANDI`, `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`

### Repository Structure

```
RISCV-CPU/
├── riscv/
│   ├── fpga/           # FPGA interface
│   ├── sim/            # Simulation testbench
│   ├── src/            # HDL source code
│   │   ├── common/     # Provided UART and RAM modules
│   │   └── cpu.v       # CPU core (main file to implement)
│   ├── sys/            # Compilation support files
│   ├── testcase/       # Test programs
│   │   ├── fpga/       # Full test suite
│   │   └── sim/        # Simulation test subset
│   ├── testspace/      # Build output
│   └── Makefile        # Build and test scripts
└── serial/             # Third-party FPGA serial library
```

### Technical Details

- Memory size: 128KB (addresses below 0x20000)
- Special I/O: reading/writing at 0x30000 and 0x30004 for UART communication
- Execution starts from address 0x0000000
- Register file: 32 general-purpose registers (x0-x31)
- The CPU must handle `rdy_in` (ready) and `rst_in` (reset) signals correctly

### Simulation

```bash
cd riscv
make test_sim name=000  # Run first simulation test
```

## Per-Testcase Resource Limits

- **Simulation Time Limit**: varies per test case
- **Language**: Verilog (submitted via git repository)

## Submission Requirements

### OJ Git Repository Submission

Submit a git repository URL containing your Verilog implementation. The OJ will clone your repository and run simulation tests against the provided testbench.

The repository must follow the structure provided in the [RISCV-CPU template](https://github.com/ACMClassCourses/RISCV-CPU), with your implementation primarily in `riscv/src/cpu.v` and additional module files.

### Evaluation Notes

- The evaluation system runs iVerilog simulation against comprehensive test programs
- Test programs are compiled from C source code using the RISC-V toolchain
- Output must exactly match expected results
- Simulation timeout indicates the CPU is too slow or has infinite loops

### Academic Integrity

If any violations are found during evaluation or code review, your final score may be significantly reduced or become **0 points**.
