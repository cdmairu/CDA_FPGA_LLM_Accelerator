# CDA_FPGA_LLM_Accelerator

Project idea

* * *

## Thesis:

> *This project designs and evaluates a small fixed‑size matrix‑multiplication accelerator on a low‑cost FPGA board (Tang Primer 20K) and compares its performance and resource use against a CPU implementation on an external computer. Because dense matrix multiplication is the core operation in many ML and LLM workloads, the results indicate whether such a cheap FPGA could serve as a practical “helper” for heavy linear‑algebra kernels. Which directly applies to various deployments of both LLMs and Neural Networks in many embedded, IoT, and infrastructural systems worldwide.*

* * *



- Justification:
    - Dense matrix multiplication is the core building block of fully connected and attention layers in modern ML/LLM models.
    
    - Arguing that:
        
        - If even this small FPGA wins on basic GEMM, larger or more optimized designs could serve as helpers for LLM inference on constrained systems.
    - Emphasize this is a first step, not a full LLM accelerator.\
    - If a microcontroller‑class system repeatedly multiplies tiny matrices (e.g., in control, tiny filters, very small neural nets), a dedicated matmul           block like yours could realistically offload that work and free CPU cycles.
        
    - In that context, the matmul IP core (not the UART harness) would be integrated on the same chip or fabric as the CPU.

   In other words: the *core* being desinged (the matmul engine) is absolutely the kind of building block real accelerators use; the small sizes and UART       interface just make it a student‑scale demonstration rather than a production‑scale product.


## High-Level Roadmap:

## Phase 1 – Baseline CPU and Fixed Sizes

1.  Choose matrix sizes:
    
    - Start with 4×4 and 8×8; optionally 16×16.
2.  Implement CPU baseline:
    
    - Small C or Python program that does integer or fixed‑point matrix multiply and measures time (run many iterations and average).
3.  Decide numeric format:
    
    - For simplicity: 16‑bit signed integers with 32‑bit accumulation.

## Phase 2 – FPGA Matrix Multiplier Core (On‑Chip Only)

4.  Implement a **combinational 4×4 or 8×8 matrix multiplier** as in classic student projects.[](http://www.seas.ucla.edu/~baek/FPGA.pdf)
    
    - One multiply‑accumulate tree per output element, or a small systolic structure.
        
    - Use BRAM/registers for A and B; compute C in one or a few cycles.
        
5.  Add a small controller:
    
    - FSM to:
        
        - Load A and B from an input buffer (written by UART).
            
        - Trigger the multiply.
            
        - Store C in an output buffer.
            
6.  Add a cycle counter:
    
    - Count cycles from “start computation” to “done” to get FPGA latency.

## Phase 3 – PC–FPGA Communication

7.  Implement UART receiver/transmitter on FPGA:
    
    - Receive:
        
        - A, B matrices as raw bytes.
            
        - Maybe a single “start” command byte.
            
    - Transmit:
        
        - Result matrix C as raw bytes.
            
        - Optionally the cycle count.
            
8.  Write a Python script on PC:
    
    - Generate random matrices.
        
    - Send them to FPGA over serial.
        
    - Receive C back.
        
    - Verify C vs. CPU result.
        
    - Measure:
        
        - Pure compute time (using cycle counter from FPGA).
            
        - End‑to‑end time including serial overhead (for realism).
            

&nbsp;

* * *

## Mid-Level Roadmap:

## Phase 1 – CPU Baseline

1\. Write a reference CPU matrix‑multiply (Python or C)

For each size N∈{4,8,16}:

4.  - Implement:
        
        - Naive triple‑loop:
            
            - `for i in range(N)`
                
            - `for j in range(N)`
                
            - `for k in range(N)`
                
                - `C[i][j] += A[i][k] * B[k][j]`
    - Use 16‑bit inputs and 32‑bit outputs (e.g., `int16` and `int32` in NumPy, or `int16_t` / `int32_t` in C).
        
        &nbsp;
        
        2\. Add timing on CPU
        
        - In Python:
            
            - Use `time.perf_counter()` or similar, run each matrix multiply many times (e.g., 10,000 iterations) and divide total time by iterations.
        - In C:
            
            - Use `clock_gettime`, `chrono`, or similar.
                
            - &nbsp;
                
                3\. Store baseline results
                
            - - For each size:
                    
                    ```
                    - Average time per multiply on CPU.
                    ```
                    
                    - Keep these numbers in a table for the report.
        
        &nbsp;
        

* * *

## Phase 2 – FPGA Matrix‑Multiplier Core (On‑Chip Only)

## 2.1 Architecture decisions

7.  Choose a microarchitecture per size
    
    For 4×4 and 8×8:
    
    - **Simplest option (fine for this project):**
        
        - Sequential, single‑MAC design:
            
            - Reuse a single multiplier‑adder: compute each `C[i][j]` over N cycles, then move to next element.
                
            - Total cycles ≈ N3 plus overhead.
                
    - **Alternative (still simple but faster):**
        
        - One multiply‑accumulate unit per output element:
            
            - For 4×4: 16 MAC units in parallel.
                
            - For 8×8: 64 MAC units (may be heavy on DSPs/LUTs, so you might start with 4×4 this way, then scale as resources allow).
                
    
    To keep it very manageable, a sequential MAC is usually enough and easier on resources.
    
8.  Memory organization on FPGA
    
    - Store A, B, C in on‑chip memory:
        
        - A: BRAM/regs with N×N 16‑bit elements.
            
        - B: same as A.
            
        - C: N×N 32‑bit elements.
            
    - Use simple address mapping:
        
        - Row‑major: `addr = i*N + j`.

## 3.2 RTL implementation

9.  Implement the core MAC and control FSM
    
    - MAC unit:
        
        - Inputs: 16‑bit `a`, 16‑bit `b`; 32‑bit accumulator `acc`.
            
        - Operation per cycle: `acc_next = acc + a*b`.
            
    - Controller FSM:
        
        - States might include:
            
            - `IDLE`
                
            - `LOAD_AB` (from UART buffers into internal memories)
                
            - `COMPUTE` (nested i, j, k loops implemented as counters)
                
            - `WRITE_C` (to output buffer)
                
            - `DONE`
                
        - In `COMPUTE`:
            
            - Iterate counters i, j, k.
                
            - For each (i, j, k):
                
                - Read `A[i][k]` and `B[k][j]` from on‑chip memory.
                    
                - Feed them into MAC.
                    
                - When `k` completes, write final `C[i][j]` into C memory and move to next (i, j).
                    
10. Add cycle counter
    

- 32‑ or 64‑bit counter register driven by `clk`.
    
- On a `start` signal:
    
    - Zero the counter.
- While in COMPUTE:
    
    - Increment each cycle.
- On completion:
    
    - Latch the final value into a `cycles` register accessible to the UART side, or store alongside C.

11. Simulate

- Write a testbench:
    
    - Hard‑code small A and B for 4×4, known expected C.
        
    - Toggle `start`, wait for `done`.
        
    - Check C contents and cycle count.
        
- Fix any off‑by‑one or address bugs before going to hardware.
    

* * *

## 4\. Phase 3 – PC–FPGA Communication over UART

## 4.1 UART interface on FPGA

12. Implement UART receiver and transmitter

- Use a known UART core (or write a small one) configured to a standard baud rate (e.g., 115200 or higher if reliable).
    
- Expose:
    
    - RX byte stream to a small command parser.
        
    - TX byte stream for sending results back.
        

13. Define a minimal protocol (fixed‑size, no parsing headaches)

For an N×N matrix with 16‑bit entries:

- PC to FPGA:
    
    - Send a “command byte” (e.g., `0x01` = compute).
        
    - Send A:
        
        - N×N entries × 2 bytes each = `N*N*2` bytes.
            
        - Order: row‑major.
            
    - Send B:
        
        - Same size and order.
- FPGA to PC:
    
    - After computation:
        
        - Send C:
            
            - N×N entries × 4 bytes each (32‑bit).
        - Send cycle count:
            
            - 4 or 8 bytes.

You can keep it strictly fixed‑length: FPGA assumes that after the command byte, exactly `N*N*2` bytes for A and then `N*N*2` bytes for B will arrive.

14. Command/receive logic on FPGA

- Simple state machine:
    
    - `WAIT_CMD` → receive 1 byte (command).
        
    - If command == `0x01`:
        
        - Receive A bytes into a BRAM or register file.
            
        - Receive B bytes similarly.
            
        - Assert `start` to the compute core.
            
        - Wait for `done`.
            
        - Then stream out C followed by cycle count via UART TX.
            

* * *

## 4.2 Host (PC) script

15. Python script structure

- Use `pyserial` (or similar) to open the serial port at the same baud rate.
    
- For each matrix size N:
    
    - Generate random A, B in int16.
        
    - Pack them into little‑endian 2‑byte values.
        
    - Send:
        
        - `0x01`
            
        - A bytes
            
        - B bytes
            
    - Read:
        
        - C bytes (N×N×4 bytes).
            
        - Cycle count bytes.
            

16. CPU reference and correctness check

- In the same script:
    
    - Compute `C_cpu = A @ B` using NumPy (int32).
        
    - Compare `C_fpga` and `C_cpu` element‑wise.
        
    - Assert they match; print an error if any mismatch.
        

17. Timing

- FPGA time:
    
    - Use cycle count from FPGA and the known clock frequency of your design (e.g., 50 MHz or whatever you synthesized to).
        
    - `t_fpga = cycles / fclk`.
        
- CPU time:
    
    - Use Python timing (e.g., `time.perf_counter()`) over many iterations or a separate C compiled benchmark.
- Optionally measure:
    
    - End‑to‑end time including UART transfer to show impact of communication overhead.

* * *

## 5\. Evaluation and Reporting

18. Gather performance data

For each N (4, 8, optional 16):

- Record:
    
    - CPU time per GEMM.
        
    - FPGA compute time per GEMM (from cycle counter).
        
    - FPGA end‑to‑end time including UART, if measured.
        
    - Resource usage from synthesis:
        
        - LUTs, registers, BRAMs, DSPs.
    - Max frequency (fclk) achieved by the FPGA design.
        

19. Basic analysis

- Compute speedup:
    
    - `speedup_compute_only = CPU_time / FPGA_compute_time`.
        
    - Optionally: `speedup_end_to_end = CPU_time / FPGA_e2e_time`.
        
- Discuss:
    
    - When does FPGA win strongly (larger N)?
        
    - How communication overhead affects real‑world benefits.
        

* * *
