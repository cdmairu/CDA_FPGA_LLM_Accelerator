"""
cpu_baseline.py
===============
Measures pure-CPU matrix-multiplication performance for N ∈ {4, 8, 16}.

Two implementations are timed:
  1. Pure Python naive triple-loop (slow, but exactly mirrors what the FPGA does)
  2. NumPy int32 (fast reference, useful for wall-clock comparison)

Run:
    python cpu_baseline.py
"""

import time
import numpy as np

# ---------------------------------------------------------------------------
# Naive Python triple-loop  (mirrors the FPGA sequential MAC exactly)
# ---------------------------------------------------------------------------
def matmul_naive(A, B, N):
    """C = A @ B using plain Python loops, int32 accumulation."""
    C = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            acc = 0
            for k in range(N):
                acc += int(A[i][k]) * int(B[k][j])
            C[i][j] = acc
    return C


# ---------------------------------------------------------------------------
# Benchmark helper
# ---------------------------------------------------------------------------
def benchmark(N: int, iterations: int = 1000):
    rng = np.random.default_rng(42)

    import math
    # Bound values so N*(max)^2 fits in int32
    max_val = int(math.sqrt((2**31 - 1) / N)) - 1
    A_np = rng.integers(-max_val, max_val, size=(N, N)).astype(np.int16)
    B_np = rng.integers(-max_val, max_val, size=(N, N)).astype(np.int16)
    A_list = A_np.tolist()
    B_list = B_np.tolist()

    # ---- Naive Python ----
    t0 = time.perf_counter()
    for _ in range(iterations):
        C_naive = matmul_naive(A_list, B_list, N)
    t1 = time.perf_counter()
    naive_us = (t1 - t0) / iterations * 1e6

    # ---- NumPy int32 ----
    A32 = A_np.astype(np.int32)
    B32 = B_np.astype(np.int32)
    t0 = time.perf_counter()
    for _ in range(iterations):
        C_np = A32 @ B32
    t1 = time.perf_counter()
    numpy_us = (t1 - t0) / iterations * 1e6

    # Verify they match
    C_naive_np = np.array(C_naive, dtype=np.int32)
    assert np.array_equal(C_naive_np, C_np), "Mismatch between naive and NumPy!"

    return naive_us, numpy_us


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    sizes = [4, 8, 16]
    iterations = {4: 50_000, 8: 10_000, 16: 2_000}

    print("=" * 60)
    print(f"{'N':>4}  {'Naive (µs)':>12}  {'NumPy (µs)':>12}  {'Speedup':>10}")
    print("-" * 60)

    results = {}
    for N in sizes:
        iters = iterations[N]
        naive_us, numpy_us = benchmark(N, iters)
        speedup = naive_us / numpy_us
        print(f"{N:>4}  {naive_us:>12.3f}  {numpy_us:>12.3f}  {speedup:>10.1f}x")
        results[N] = {"naive_us": naive_us, "numpy_us": numpy_us}

    print("=" * 60)
    print("\nNote: 'Naive' is the baseline to compare against FPGA.")
    print("FPGA compute time = cycle_count / fclk_hz * 1e6  [µs]\n")

    return results


if __name__ == "__main__":
    main()
