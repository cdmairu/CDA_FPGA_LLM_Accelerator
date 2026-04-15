"""
fpga_host.py
============
PC-side host script for the FPGA matrix-multiplication accelerator.

Usage:
    python fpga_host.py --port /dev/ttyUSB0 --N 4
    python fpga_host.py --port COM3 --N 8 --baud 115200 --iters 20

Protocol summary
----------------
PC → FPGA:
    1 byte  : command (0x01 = compute)
    N*N*2 bytes : matrix A, int16 little-endian, row-major
    N*N*2 bytes : matrix B, int16 little-endian, row-major

FPGA → PC:
    N*N*4 bytes : matrix C, int32 little-endian, row-major
    4 bytes     : cycle_count, uint32 little-endian
"""

import argparse
import struct
import sys
import time
import numpy as np

try:
    import serial
except ImportError:
    print("pyserial not found.  Install with:  pip install pyserial")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Protocol helpers
# ---------------------------------------------------------------------------
CMD_COMPUTE = 0x01


def pack_matrix_int16(mat: np.ndarray) -> bytes:
    """Flatten an N×N int16 ndarray to little-endian bytes."""
    assert mat.dtype == np.int16
    return mat.flatten(order="C").tobytes()  # already LE on x86


def unpack_matrix_int32(data: bytes, N: int) -> np.ndarray:
    """Parse N*N*4 bytes → N×N int32 ndarray."""
    count = N * N
    values = struct.unpack(f"<{count}i", data)
    return np.array(values, dtype=np.int32).reshape(N, N)


def unpack_uint32(data: bytes) -> int:
    return struct.unpack("<I", data)[0]


# ---------------------------------------------------------------------------
# Single transaction: send A, B → receive C, cycles
# ---------------------------------------------------------------------------
def fpga_matmul(ser: serial.Serial, A: np.ndarray, B: np.ndarray, N: int):
    """
    Send one compute request to the FPGA and return (C_fpga, cycle_count).
    Raises RuntimeError on timeout or data length mismatch.
    """
    # Build payload
    payload = bytes([CMD_COMPUTE]) + pack_matrix_int16(A) + pack_matrix_int16(B)
    ser.write(payload)

    # Receive C  (N*N*4 bytes)
    c_bytes = N * N * 4
    rx = ser.read(c_bytes)
    if len(rx) != c_bytes:
        raise RuntimeError(f"Expected {c_bytes} bytes for C, got {len(rx)}")

    # Receive cycle count (4 bytes)
    cc_bytes = ser.read(4)
    if len(cc_bytes) != 4:
        raise RuntimeError(f"Expected 4 bytes for cycle count, got {len(cc_bytes)}")

    C_fpga = unpack_matrix_int32(rx, N)
    cycles = unpack_uint32(cc_bytes)
    return C_fpga, cycles


# ---------------------------------------------------------------------------
# Correctness check
# ---------------------------------------------------------------------------
def verify(A: np.ndarray, B: np.ndarray, C_fpga: np.ndarray) -> bool:
    C_cpu = A.astype(np.int32) @ B.astype(np.int32)
    if not np.array_equal(C_fpga, C_cpu):
        # Print first mismatch
        diff = np.where(C_fpga != C_cpu)
        r, c = diff[0][0], diff[1][0]
        print(f"  MISMATCH at [{r},{c}]: FPGA={C_fpga[r,c]}  CPU={C_cpu[r,c]}")
        return False
    return True


# ---------------------------------------------------------------------------
# Benchmark loop
# ---------------------------------------------------------------------------
def run_benchmark(ser: serial.Serial, N: int, iterations: int, fclk_hz: float):
    rng = np.random.default_rng(0)
    total_cycles = 0
    t_e2e_start = time.perf_counter()
    errors = 0

    for i in range(iterations):
        import math

        max_val = int(math.sqrt((2**31 - 1) / N)) - 1
        A = rng.integers(-max_val, max_val, size=(N, N)).astype(np.int16)
        B = rng.integers(-max_val, max_val, size=(N, N)).astype(np.int16)

        C_fpga, cycles = fpga_matmul(ser, A, B, N)
        total_cycles += cycles

        if not verify(A, B, C_fpga):
            errors += 1
            print(f"  Iteration {i} FAILED")

    t_e2e_end = time.perf_counter()

    avg_cycles = total_cycles / iterations
    fpga_us = avg_cycles / fclk_hz * 1e6
    e2e_us = (t_e2e_end - t_e2e_start) / iterations * 1e6

    return {
        "N": N,
        "iterations": iterations,
        "errors": errors,
        "avg_cycles": avg_cycles,
        "fpga_us": fpga_us,
        "e2e_us": e2e_us,
    }


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def print_report(res: dict, cpu_naive_us: float, cpu_numpy_us: float):
    N = res["N"]
    print("\n" + "=" * 62)
    print(f"  N = {N}   ({res['iterations']} iterations,  errors={res['errors']})")
    print("-" * 62)
    print(f"  FPGA compute time (cycle count)  : {res['fpga_us']:>10.3f} µs")
    print(f"  FPGA end-to-end  (with UART)     : {res['e2e_us']:>10.3f} µs")
    print(f"  CPU naive triple-loop            : {cpu_naive_us:>10.3f} µs")
    print(f"  CPU NumPy int32                  : {cpu_numpy_us:>10.3f} µs")
    if res["fpga_us"] > 0:
        sp_compute = cpu_naive_us / res["fpga_us"]
        sp_e2e = cpu_naive_us / res["e2e_us"]
        print(f"  Speedup vs naive (compute only)  : {sp_compute:>10.2f}x")
        print(f"  Speedup vs naive (end-to-end)    : {sp_e2e:>10.2f}x")
    print("=" * 62)


# ---------------------------------------------------------------------------
# CPU baseline (run locally)
# ---------------------------------------------------------------------------
def cpu_baseline(N: int, iterations: int = 5000):
    rng = np.random.default_rng(42)
    import math

    max_val = int(math.sqrt((2**31 - 1) / N)) - 1
    A = rng.integers(-max_val, max_val, size=(N, N)).astype(np.int16)
    B = rng.integers(-max_val, max_val, size=(N, N)).astype(np.int16)
    A32, B32 = A.astype(np.int32), B.astype(np.int32)
    A_list, B_list = A.tolist(), B.tolist()

    # Naive
    def naive():
        C = [[0] * N for _ in range(N)]
        for i in range(N):
            for j in range(N):
                s = 0
                for k in range(N):
                    s += int(A_list[i][k]) * int(B_list[k][j])
                C[i][j] = s
        return C

    t0 = time.perf_counter()
    for _ in range(iterations):
        naive()
    naive_us = (time.perf_counter() - t0) / iterations * 1e6

    t0 = time.perf_counter()
    for _ in range(iterations):
        A32 @ B32
    numpy_us = (time.perf_counter() - t0) / iterations * 1e6

    return naive_us, numpy_us


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="FPGA MatMul Host")
    parser.add_argument(
        "--port", required=True, help="Serial port, e.g. /dev/ttyUSB0 or COM3"
    )
    parser.add_argument(
        "--N", type=int, default=4, choices=[4, 8, 16], help="Matrix dimension"
    )
    parser.add_argument(
        "--baud", type=int, default=115200, help="Baud rate (must match FPGA)"
    )
    parser.add_argument(
        "--iters", type=int, default=10, help="Number of test iterations"
    )
    parser.add_argument(
        "--fclk", type=float, default=27e6, help="FPGA clock frequency in Hz"
    )
    parser.add_argument(
        "--timeout", type=float, default=5.0, help="Serial read timeout in seconds"
    )
    args = parser.parse_args()

    N = args.N
    print(f"Connecting to {args.port} at {args.baud} baud …")
    try:
        ser = serial.Serial(args.port, baudrate=args.baud, timeout=args.timeout)
    except serial.SerialException as e:
        print(f"Error opening port: {e}")
        sys.exit(1)

    time.sleep(0.2)  # let UART settle
    ser.reset_input_buffer()

    print(f"Running {args.iters} iterations  (N={N}) …")
    try:
        res = run_benchmark(ser, N, args.iters, args.fclk)
    except RuntimeError as e:
        print(f"Communication error: {e}")
        ser.close()
        sys.exit(1)
    finally:
        ser.close()

    print("Computing CPU baseline …")
    cpu_iters = max(1000, args.iters * 100)
    naive_us, numpy_us = cpu_baseline(N, cpu_iters)

    print_report(res, naive_us, numpy_us)

    if res["errors"] == 0:
        print("\n✓  All results verified correct.")
    else:
        print(f"\n✗  {res['errors']} iterations had incorrect results!")
        sys.exit(1)


if __name__ == "__main__":
    main()

# Example run command: py fpga_host.py --port COM6 --N 4 --baud 115200 --iters 10 --fclk 27000000 --timeout 5
