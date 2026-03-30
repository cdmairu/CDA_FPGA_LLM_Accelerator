"""
analyze_results.py
==================
Reads benchmark results (JSON or entered manually) and produces:
  - Summary table
  - Bar chart: FPGA compute vs CPU naive vs CPU NumPy
  - Speedup curve vs N

Usage (after running fpga_host.py and saving results):
    python analyze_results.py --results results.json

Or run in demo mode with synthetic numbers:
    python analyze_results.py --demo
"""

import argparse
import json
import sys

try:
    import numpy as np
    import matplotlib.pyplot as plt
    HAS_PLOT = True
except ImportError:
    HAS_PLOT = False
    print("matplotlib not found – table-only mode.  pip install matplotlib")


# ---------------------------------------------------------------------------
# Demo / synthetic data (representative numbers for a 27 MHz design)
# ---------------------------------------------------------------------------
DEMO_DATA = {
    "fclk_hz": 27_000_000,
    "results": [
        {
            "N": 4,
            "avg_cycles":  64 + 16 + 4,   # N³ + N² + N ≈ sequential overhead
            "fpga_us":     None,           # computed below
            "e2e_us":      None,
            "cpu_naive_us": 3.8,
            "cpu_numpy_us": 0.9,
        },
        {
            "N": 8,
            "avg_cycles":  512 + 64 + 8,
            "fpga_us":     None,
            "e2e_us":      None,
            "cpu_naive_us": 42.0,
            "cpu_numpy_us": 1.1,
        },
        {
            "N": 16,
            "avg_cycles":  4096 + 256 + 16,
            "fpga_us":     None,
            "e2e_us":      None,
            "cpu_naive_us": 580.0,
            "cpu_numpy_us": 2.5,
        },
    ]
}

# estimate e2e: UART adds ~10 bytes/baud overhead per byte * (2*N²*2 + N²*4 + 5) bytes
def estimate_e2e(fpga_us: float, N: int, baud: int = 115200) -> float:
    bytes_total = 1 + N*N*2 + N*N*2 + N*N*4 + 4   # cmd + A + B + C + cc
    uart_us = bytes_total * 10 / baud * 1e6
    return fpga_us + uart_us


def fill_computed(data: dict):
    fclk = data["fclk_hz"]
    for r in data["results"]:
        if r["fpga_us"] is None:
            r["fpga_us"] = r["avg_cycles"] / fclk * 1e6
        if r["e2e_us"] is None:
            r["e2e_us"] = estimate_e2e(r["fpga_us"], r["N"])
    return data


def print_table(data: dict):
    fclk = data["fclk_hz"]
    print("\n" + "=" * 80)
    print(f"  fclk = {fclk/1e6:.1f} MHz")
    print(f"  {'N':>3}  {'Cycles':>8}  {'FPGA(µs)':>10}  {'E2E(µs)':>10}  "
          f"{'CPU-naive(µs)':>14}  {'Speedup-compute':>16}  {'Speedup-E2E':>12}")
    print("-" * 80)
    for r in data["results"]:
        sp_c = r["cpu_naive_us"] / r["fpga_us"] if r["fpga_us"] else 0
        sp_e = r["cpu_naive_us"] / r["e2e_us"]  if r["e2e_us"]  else 0
        print(f"  {r['N']:>3}  {r['avg_cycles']:>8.0f}  {r['fpga_us']:>10.3f}  "
              f"{r['e2e_us']:>10.3f}  {r['cpu_naive_us']:>14.3f}  "
              f"{sp_c:>16.2f}x  {sp_e:>12.2f}x")
    print("=" * 80 + "\n")


def plot_results(data: dict):
    if not HAS_PLOT:
        return

    results = data["results"]
    Ns       = [r["N"]            for r in results]
    fpga_us  = [r["fpga_us"]      for r in results]
    e2e_us   = [r["e2e_us"]       for r in results]
    naive_us = [r["cpu_naive_us"] for r in results]
    numpy_us = [r["cpu_numpy_us"] for r in results]
    sp_c     = [n/f for n, f in zip(naive_us, fpga_us)]
    sp_e     = [n/e for n, e in zip(naive_us, e2e_us)]

    x = np.arange(len(Ns))
    w = 0.18

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
    fig.suptitle("FPGA vs CPU Matrix Multiplication Benchmark", fontsize=14)

    # ---- Left: latency bar chart ----
    bars1 = ax1.bar(x - 1.5*w, fpga_us,  w, label="FPGA compute", color="#2196F3")
    bars2 = ax1.bar(x - 0.5*w, e2e_us,   w, label="FPGA + UART",  color="#64B5F6")
    bars3 = ax1.bar(x + 0.5*w, naive_us, w, label="CPU naive",     color="#F44336")
    bars4 = ax1.bar(x + 1.5*w, numpy_us, w, label="CPU NumPy",     color="#FF9800")

    ax1.set_yscale("log")
    ax1.set_xticks(x)
    ax1.set_xticklabels([f"N={n}" for n in Ns])
    ax1.set_ylabel("Time per multiply (µs)  [log scale]")
    ax1.set_title("Latency Comparison")
    ax1.legend(fontsize=8)
    ax1.yaxis.grid(True, which="both", linestyle="--", alpha=0.5)

    # ---- Right: speedup curve ----
    ax2.plot(Ns, sp_c, "o-",  color="#2196F3", label="FPGA compute-only speedup")
    ax2.plot(Ns, sp_e, "s--", color="#64B5F6", label="FPGA end-to-end speedup")
    ax2.axhline(1.0, color="gray", linestyle=":", label="Breakeven")
    ax2.set_xticks(Ns)
    ax2.set_xlabel("Matrix dimension N")
    ax2.set_ylabel("Speedup vs CPU naive")
    ax2.set_title("Speedup vs Matrix Size")
    ax2.legend(fontsize=8)
    ax2.yaxis.grid(True, linestyle="--", alpha=0.5)

    plt.tight_layout()
    plt.savefig("benchmark_results.png", dpi=150)
    print("Plot saved to benchmark_results.png")
    plt.show()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", help="Path to JSON results file from fpga_host.py")
    parser.add_argument("--demo",    action="store_true", help="Use synthetic demo data")
    args = parser.parse_args()

    if args.demo:
        data = fill_computed(DEMO_DATA)
    elif args.results:
        with open(args.results) as f:
            data = fill_computed(json.load(f))
    else:
        print("Provide --results <file.json> or --demo")
        sys.exit(1)

    print_table(data)
    plot_results(data)


if __name__ == "__main__":
    main()
