# CDA FPGA LLM Accelerator — Matrix Multiplication Demo

A complete FPGA-based matrix-multiplication accelerator targeting the
**Tang Primer 20K** (GW2A-18, Gowin toolchain) with a PC host Python stack.

---

## Repository Layout

```text
fpga_matmul/
├── rtl/
│   ├── uart_rx.v        — UART receiver (8N1, parameterised baud)
│   ├── uart_tx.v        — UART transmitter
│   ├── matmul_core.v    — Parameterised sequential MAC engine (N=4/8/16)
│   ├── uart_ctrl.v      — Protocol controller (glues UART ↔ matmul_core)
│   └── top.v            — Chip top-level (clock, LED heartbeat)
├── sim/
│   ├── tb_matmul_core.v — Self-checking testbench for matmul_core
│   └── tb_uart.v        — UART TX→RX loopback testbench
├── constraints/
│   ├── top.cst          — Physical pin constraints (Gowin)
│   └── top.sdc          — Timing constraints
└── host/
    ├── cpu_baseline.py  — Measure CPU-only matmul time
    ├── fpga_host.py     — Send matrices to FPGA, verify, benchmark
    ├── fpga_sim.py      — Software FPGA simulator (no hardware needed)
    └── analyze_results.py — Tables + plots from benchmark data
```

---

## Quick Start

### 1. Install Gowin EDA

- Go to <https://www.gowinsemi.com/en/support/download_eda>
- ~~Click the "Software for Linux" tab~~
- Download the Education version (no license is required)
- Accept licenses and install USB drivers

### 2. Simulate (no hardware)

```bash
# Install Icarus Verilog
sudo apt install iverilog   # Ubuntu / WSL

# Compile and run matmul testbench
cd sim
iverilog -o sim_matmul tb_matmul_core.v ../rtl/matmul_core.v
vvp sim_matmul

# Compile and run UART loopback testbench
iverilog -o sim_uart tb_uart.v ../rtl/uart_rx.v ../rtl/uart_tx.v
vvp sim_uart
```

Expected output:
```
--- Test 1: I x B ---   cycles=84
--- Test 2: 1s x 1s --- cycles=84
ALL TESTS PASSED
```

### 3. Synthesise (Gowin IDE)

1. Create a new project for device [`GW2A-LV18PG256C8/I7`](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html).
2. Right click `GW2A-LV18PG256C8/I7` --> Add Files...
3. Add all `rtl/*.v` files.  Copy them into the source directory (else the path is really long and hard to read in the Design window)
4. Add `constraints/top.cst` and `constraints/top.sdc`.
5. **To change matrix size**: open `top.v` and change `parameter N = 4` to `8` or `16`.
6. In the top toolbar, click Run Synthesis, then Place & Route
7. Tools --> Programmer
8. Plug in USB cable from computer to USB-JTAG port

Check the synthesis report for:
- LUT count
- DSP block count
- Max frequency (should be well above 27 MHz for N=4/8)

### 4. Run CPU Baseline

```bash
cd host
pip install numpy
python cpu_baseline.py
```

### 5. Run with Real FPGA

```bash
pip install pyserial numpy
python fpga_host.py --port /dev/ttyUSB0 --N 4 --iters 20
```

Common ports:
- Linux: `/dev/ttyUSB0` or `/dev/ttyACM0`
- macOS: `/dev/cu.usbserial-XXXX`
- Windows: `COM3` (check Device Manager)

### 6. Run with Software Simulator (no hardware)

```bash
# Linux/macOS – create virtual serial pair
sudo apt install socat
socat -d -d PTY,raw,echo=0,link=/tmp/fpga_sim PTY,raw,echo=0,link=/tmp/fpga_host &

# Terminal 1
python fpga_sim.py --port /tmp/fpga_sim --N 4

# Terminal 2
python fpga_host.py --port /tmp/fpga_host --N 4 --iters 5
```

### 7. Analyze and Plot Results

```bash
python analyze_results.py --demo          # synthetic data
python analyze_results.py --results my_results.json  # your data
```

---

## Design Notes

### FPGA Architecture

```
PC ──UART──► [uart_rx] ──bytes──► [uart_ctrl FSM]
                                        │
                              ┌─────────┴──────────┐
                              │   matmul_core       │
                              │  (sequential MAC)   │
                              │  Latency ≈ N³ clks  │
                              └─────────┬──────────┘
                                        │
PC ◄──UART── [uart_tx] ◄──bytes── [uart_ctrl FSM]
```

**matmul_core** iterates three nested counters (i, j, k) and feeds one
`A[i][k] * B[k][j]` into a 32-bit accumulator each clock cycle.
Total compute cycles ≈ N³ + N² (write-back overhead).

### Protocol

| Direction | Content                        | Size    |
| --------- | ------------------------------ | ------- |
| PC → FPGA | Command byte `0x01`            | 1 B     |
| PC → FPGA | Matrix A (int16 LE, row-major) | N×N×2 B |
| PC → FPGA | Matrix B (int16 LE, row-major) | N×N×2 B |
| FPGA → PC | Matrix C (int32 LE, row-major) | N×N×4 B |
| FPGA → PC | Cycle count (uint32 LE)        | 4 B     |

### Expected Performance (27 MHz clock, 115200 baud)

| N   | FPGA cycles | FPGA time | UART overhead | CPU naive |
| --- | ----------- | --------- | ------------- | --------- |
| 4   | ~84         | ~3.1 µs   | ~3.0 ms       | ~4 µs     |
| 8   | ~584        | ~21.6 µs  | ~9.4 ms       | ~42 µs    |
| 16  | ~4368       | ~162 µs   | ~36 ms        | ~580 µs   |

> **Note:** UART dominates end-to-end time. The *compute-only* speedup (from
> the cycle counter) is what shows the FPGA advantage. A higher baud rate
> (e.g. 921600) or SPI/parallel bus would make end-to-end competitive too.

### Scaling to N=16

N=16 requires 256 MAC units or 4096 sequential cycles.  
With a sequential design the resource usage stays minimal (~100 LUTs, a few
BRAMs, 1 DSP). Synthesis at 27 MHz should close timing easily.

For the DSP-parallel design (16 MACs in parallel), you'd need 16–64 DSP18
blocks – the GW2A-18 has 48, so N=4 parallel fits comfortably.

---

## Troubleshooting

| Symptom                | Likely cause      | Fix                                    |
| ---------------------- | ----------------- | -------------------------------------- |
| No RX data from FPGA   | Wrong port / baud | Check Device Manager / `dmesg`         |
| Mismatched results     | Byte-order bug    | Verify LE packing in host script       |
| Simulation hangs       | Off-by-one in FSM | Check `N-1` comparisons in matmul_core |
| Synthesis fails timing | Clock too high    | Lower to 27 MHz (already default)      |
| LED not blinking       | Wrong pin in .cst | Check board schematic                  |

---

## Dependencies

**Hardware:** Tang Primer 20K, USB cable, PC with Gowin IDE.

**Python:** `numpy`, `pyserial`, `matplotlib` (optional for plots).

```bash
pip install numpy pyserial matplotlib
```

**Simulation:** [Icarus Verilog](https://github.com/steveicarus/iverilog) (free, cross-platform).

## Reference

- [TangPrimer-20K-example](https://github.com/sipeed/TangPrimer-20K-example)

### Useful VS Code Extensions

- .cst file syntax highlighting: `wxhenry.fpga-file-support`
- .v file syntax highlighting: `mshr-h.veriloghdl`
