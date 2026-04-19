"""
plot_results_final.py
=====================
Generates all figures for the FPGA Matrix Multiplication Accelerator report.
Reads directly from FPGA_runs.csv. Automatically includes Zybo Z7-20 data
once those rows are populated by Grant Lee.

Usage:
    python plot_results_final.py

Output files (300 DPI, publication-ready):
    fig1_fpga_compute_vs_cpu.png
    fig2_e2e_latency.png
    fig3_uart_breakdown.png
    fig4_speedup.png
    fig5_cpu_numpy_vs_naive.png
    fig6_scaling_trend.png
    fig7_uart_pct_stacked.png
    fig8_combined_summary.png
"""

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import pandas as pd
import numpy as np

# ── Matplotlib style ──────────────────────────────────────────────────────────
plt.rcParams.update({
    'font.family': 'DejaVu Sans',
    'axes.spines.top': False,
    'axes.spines.right': False,
    'axes.grid': True,
    'grid.alpha': 0.25,
    'grid.linestyle': '--',
    'figure.dpi': 100,
})

# ── Board color / marker palette ─────────────────────────────────────────────
BOARD_STYLE = {
    'GOWIN GW2A':      {'color': '#1f77b4', 'marker': 'o', 'hatch': ''},
    'BASYS 3 Artix-7': {'color': '#ff7f0e', 'marker': 's', 'hatch': '//'},
    'Zybo Z7-20':      {'color': '#2ca02c', 'marker': '^', 'hatch': 'xx'},
}

# ── Load & clean data ─────────────────────────────────────────────────────────
df = pd.read_csv('FPGA_runs.csv', encoding='latin1')
df.columns = [
    'Board', 'N', 'Iters',
    'FPGA_compute', 'FPGA_e2e',
    'CPU_naive', 'CPU_numpy',
    'Speedup', 'UART_overhead', 'Observation'
]
for col in ['N', 'FPGA_compute', 'FPGA_e2e',
            'CPU_naive', 'CPU_numpy', 'Speedup', 'UART_overhead']:
    df[col] = pd.to_numeric(df[col], errors='coerce')

df_valid = df.dropna(subset=['Board', 'N', 'FPGA_compute', 'CPU_naive']).copy()
df_valid['N'] = df_valid['N'].astype(int)

# ── Aggregate summary ─────────────────────────────────────────────────────────
summary = df_valid.groupby(['Board', 'N']).agg(
    fpga_compute_mean=('FPGA_compute', 'mean'),
    fpga_compute_std=('FPGA_compute', 'std'),
    fpga_e2e_mean=('FPGA_e2e', 'mean'),
    fpga_e2e_std=('FPGA_e2e', 'std'),
    cpu_naive_mean=('CPU_naive', 'mean'),
    cpu_naive_std=('CPU_naive', 'std'),
    cpu_numpy_mean=('CPU_numpy', 'mean'),
    cpu_numpy_std=('CPU_numpy', 'std'),
    speedup_mean=('Speedup', 'mean'),
    speedup_std=('Speedup', 'std'),
    uart_mean=('UART_overhead', 'mean'),
    n_samples=('FPGA_compute', 'count'),
).reset_index()
summary['uart_pct']    = summary['uart_mean']         / summary['fpga_e2e_mean'] * 100
summary['compute_pct'] = summary['fpga_compute_mean'] / summary['fpga_e2e_mean'] * 100

boards   = summary['Board'].unique()
ns       = sorted(summary['N'].unique())
x_pos    = np.arange(len(ns))   # [0, 1] for N=4 and N=8

print("=== Summary Statistics ===")
print(summary[['Board','N','fpga_compute_mean','fpga_e2e_mean',
               'cpu_naive_mean','cpu_numpy_mean','speedup_mean',
               'uart_pct','n_samples']].to_string(index=False))

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 1 — FPGA Compute Time vs CPU (log scale line plot)
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))

for board in boards:
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'marker': 'D'})
    ax.errorbar(sub['N'], sub['fpga_compute_mean'],
                yerr=sub['fpga_compute_std'],
                marker=st['marker'], color=st['color'],
                linestyle='-', linewidth=1.8, capsize=5, markersize=7,
                label=f'{board} — FPGA Compute')

# CPU reference lines (board-independent for naive/numpy)
cpu_ref = summary[summary['Board'] == boards[0]].sort_values('N')
ax.errorbar(cpu_ref['N'], cpu_ref['cpu_naive_mean'],
            yerr=cpu_ref['cpu_naive_std'],
            marker='D', color='#d62728', linestyle='--',
            linewidth=1.5, capsize=5, markersize=6,
            label='CPU Naive (triple-loop)')
ax.errorbar(cpu_ref['N'], cpu_ref['cpu_numpy_mean'],
            yerr=cpu_ref['cpu_numpy_std'],
            marker='x', color='#9467bd', linestyle=':',
            linewidth=1.5, capsize=5, markersize=7,
            label='CPU NumPy int32')

ax.set_yscale('log')
ax.set_xlabel('Matrix Size N', fontsize=12)
ax.set_ylabel('Time (µs) — log scale', fontsize=12)
ax.set_title('Fig. 1 — FPGA Compute Time vs CPU Baselines\n'
             '(error bars = 1 std dev, n=30 runs per condition)', fontsize=12)
ax.set_xticks(ns)
ax.legend(fontsize=9)
ax.yaxis.set_major_formatter(mticker.ScalarFormatter())
plt.tight_layout()
plt.savefig('fig1_fpga_compute_vs_cpu.png', dpi=300)
print("Saved: fig1_fpga_compute_vs_cpu.png")
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 2 — End-to-End Latency (UART included) — grouped bar
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 5))

width = 0.25
n_boards = len(boards)
offsets = np.linspace(-(n_boards-1)*width/2, (n_boards-1)*width/2, n_boards)

for i, board in enumerate(boards):
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'hatch': ''})
    vals = sub['fpga_e2e_mean'].values / 1000   # µs → ms
    errs = sub['fpga_e2e_std'].values  / 1000
    bars = ax.bar(x_pos + offsets[i], vals, width,
                  label=board, color=st['color'],
                  hatch=st['hatch'], alpha=0.85,
                  yerr=errs, capsize=4, error_kw={'linewidth': 1.2})

ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=11)
ax.set_xlabel('Matrix Size N', fontsize=12)
ax.set_ylabel('End-to-End Latency (ms)', fontsize=12)
ax.set_title('Fig. 2 — End-to-End Latency Including UART Communication\n'
             '(note: UART dominates >99.9% of total time)', fontsize=12)
ax.legend(fontsize=10)
plt.tight_layout()
plt.savefig('fig2_e2e_latency.png', dpi=300)
print("Saved: fig2_e2e_latency.png")
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 3 — UART Overhead Breakdown (stacked bar, % of total)
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 5))

for i, board in enumerate(boards):
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'hatch': ''})
    compute_pcts = sub['compute_pct'].values
    uart_pcts    = sub['uart_pct'].values
    bx = x_pos + offsets[i]
    ax.bar(bx, compute_pcts, width, label=f'{board} — Compute',
           color=st['color'], alpha=0.95)
    ax.bar(bx, uart_pcts, width, bottom=compute_pcts,
           label=f'{board} — UART', color=st['color'],
           alpha=0.35, hatch='//')

ax.axhline(100, color='black', linewidth=0.5, linestyle=':')
ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=11)
ax.set_ylim(0, 108)
ax.set_ylabel('Percentage of Total End-to-End Time (%)', fontsize=11)
ax.set_title('Fig. 3 — Time Breakdown: FPGA Compute vs UART Overhead\n'
             '(solid = compute, hatched = UART; not visible at this scale)', fontsize=12)
ax.legend(fontsize=8, ncol=2)
plt.tight_layout()
plt.savefig('fig3_uart_breakdown.png', dpi=300)
print("Saved: fig3_uart_breakdown.png")
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 3b — UART Breakdown in µs (absolute, log scale) — more informative
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 5))

for i, board in enumerate(boards):
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'hatch': ''})
    bx = x_pos + offsets[i]
    ax.bar(bx, sub['fpga_compute_mean'].values, width,
           label=f'{board} — Compute',
           color=st['color'], alpha=0.95)
    ax.bar(bx, sub['uart_mean'].values, width,
           bottom=sub['fpga_compute_mean'].values,
           label=f'{board} — UART',
           color=st['color'], alpha=0.35, hatch='//')

ax.set_yscale('log')
ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=11)
ax.set_ylabel('Time (µs) — log scale', fontsize=12)
ax.set_title('Fig. 3b — Absolute Compute vs UART Overhead (log scale)\n'
             '(solid = compute, hatched = UART)', fontsize=12)
ax.legend(fontsize=8, ncol=2)
ax.yaxis.set_major_formatter(mticker.ScalarFormatter())
plt.tight_layout()
plt.savefig('fig3b_uart_breakdown_abs.png', dpi=300)
print("Saved: fig3b_uart_breakdown_abs.png")
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 4 — Compute-Only Speedup over CPU Naive
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))

for i, board in enumerate(boards):
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'hatch': ''})
    bx = x_pos + offsets[i]
    ax.bar(bx, sub['speedup_mean'].values, width,
           label=board, color=st['color'],
           hatch=st['hatch'], alpha=0.85,
           yerr=sub['speedup_std'].values,
           capsize=4, error_kw={'linewidth': 1.2})
    # Annotate values on bars
    for xi, val in zip(bx, sub['speedup_mean'].values):
        ax.text(xi, val + 0.1, f'{val:.1f}×', ha='center',
                fontsize=9, fontweight='bold')

ax.axhline(1.0, color='red', linestyle='--', linewidth=1.2,
           label='Break-even (1×)')
ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=11)
ax.set_ylabel('Speedup vs CPU Naive (compute only)', fontsize=11)
ax.set_title('Fig. 4 — FPGA Compute-Only Speedup over CPU Naive Triple-Loop\n'
             '(excludes UART overhead; based on hardware cycle counter)', fontsize=12)
ax.legend(fontsize=10)
plt.tight_layout()
plt.savefig('fig4_speedup.png', dpi=300)
print("Saved: fig4_speedup.png")
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 5 — CPU Naive vs NumPy comparison
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))

# CPU data is same regardless of board — use first available board
cpu_ref = summary[summary['Board'] == boards[0]].sort_values('N')

bar_w = 0.3
ax.bar(x_pos - bar_w/2, cpu_ref['cpu_naive_mean'].values, bar_w,
       label='CPU Naive (Python triple-loop)',
       color='#d62728', alpha=0.85,
       yerr=cpu_ref['cpu_naive_std'].values, capsize=4)
ax.bar(x_pos + bar_w/2, cpu_ref['cpu_numpy_mean'].values, bar_w,
       label='CPU NumPy int32 (BLAS-optimized)',
       color='#9467bd', alpha=0.85,
       yerr=cpu_ref['cpu_numpy_std'].values, capsize=4)

# Annotate speedup of NumPy over naive
for xi, naive, npy in zip(x_pos,
                           cpu_ref['cpu_naive_mean'].values,
                           cpu_ref['cpu_numpy_mean'].values):
    ratio = naive / npy
    ax.text(xi, naive + 0.5, f'NumPy is\n{ratio:.0f}× faster',
            ha='center', fontsize=8, color='#555555')

ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=11)
ax.set_ylabel('Time (µs)', fontsize=12)
ax.set_title('Fig. 5 — CPU Baseline Comparison: Naive vs NumPy\n'
             '(NumPy uses BLAS; naive is Python triple-loop)', fontsize=12)
ax.legend(fontsize=10)
plt.tight_layout()
plt.savefig('fig5_cpu_naive_vs_numpy.png', dpi=300)
print("Saved: fig5_cpu_naive_vs_numpy.png")
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 6 — Scaling trend: compute time vs N (shows N³ growth)
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))

for board in boards:
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'marker': 'o'})
    ax.plot(sub['N'], sub['fpga_compute_mean'],
            marker=st['marker'], color=st['color'],
            linewidth=2, markersize=8, label=f'{board} — FPGA Compute')

# Plot N³ reference curve scaled to GOWIN at N=4
ref_board_data = summary[summary['Board'] == boards[0]].sort_values('N')
n_ref_val = ref_board_data['N'].values[0]
t_ref_val = ref_board_data['fpga_compute_mean'].values[0]
n_range = np.array(ns)
n_cube_scaled = t_ref_val * (n_range / n_ref_val) ** 3
ax.plot(n_range, n_cube_scaled, 'k--', linewidth=1.2, alpha=0.6, label='O(N³) reference')

ax.plot(cpu_ref['N'], cpu_ref['cpu_naive_mean'],
        marker='D', color='#d62728', linestyle='--',
        linewidth=1.5, markersize=6, label='CPU Naive')

ax.set_xlabel('Matrix Size N', fontsize=12)
ax.set_ylabel('Compute Time (µs)', fontsize=12)
ax.set_title('Fig. 6 — Compute Time Scaling with Matrix Size\n'
             '(dashed line = theoretical O(N³) trend)', fontsize=12)
ax.set_xticks(ns)
ax.legend(fontsize=10)
plt.tight_layout()
plt.savefig('fig6_scaling_trend.png', dpi=300)
print("Saved: fig6_scaling_trend.png")
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 7 — Board comparison: FPGA compute time side-by-side
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))

for i, board in enumerate(boards):
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'hatch': ''})
    bx = x_pos + offsets[i]
    bars = ax.bar(bx, sub['fpga_compute_mean'].values, width,
                  label=board, color=st['color'],
                  hatch=st['hatch'], alpha=0.85,
                  yerr=sub['fpga_compute_std'].values,
                  capsize=4)
    for xi, val in zip(bx, sub['fpga_compute_mean'].values):
        ax.text(xi, val + 0.2, f'{val:.2f}µs', ha='center', fontsize=8)

ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=11)
ax.set_ylabel('FPGA Compute Time (µs)', fontsize=12)
ax.set_title('Fig. 7 — FPGA Compute Time Comparison Across Boards\n'
             '(Basys 3 Artix-7 runs at higher clock → faster per-op)', fontsize=12)
ax.legend(fontsize=10)
plt.tight_layout()
plt.savefig('fig7_board_compute_comparison.png', dpi=300)
print("Saved: fig7_board_compute_comparison.png")
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# FIGURE 8 — Combined 2×2 summary panel (publication figure)
# ─────────────────────────────────────────────────────────────────────────────
fig, axes = plt.subplots(2, 2, figsize=(13, 9))
fig.suptitle('FPGA Matrix Multiplication Accelerator — Performance Summary',
             fontsize=14, fontweight='bold', y=1.01)

# Panel A: Compute time (log)
ax = axes[0, 0]
for board in boards:
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'marker': 'o'})
    ax.errorbar(sub['N'], sub['fpga_compute_mean'],
                yerr=sub['fpga_compute_std'],
                marker=st['marker'], color=st['color'],
                linewidth=1.8, capsize=4, label=board)
ax.errorbar(cpu_ref['N'], cpu_ref['cpu_naive_mean'],
            marker='D', color='#d62728', linestyle='--',
            linewidth=1.5, capsize=4, label='CPU Naive')
ax.set_yscale('log')
ax.set_title('(A) FPGA Compute vs CPU Naive', fontsize=10)
ax.set_ylabel('Time (µs) log scale', fontsize=9)
ax.set_xlabel('N', fontsize=9)
ax.set_xticks(ns)
ax.legend(fontsize=7)
ax.yaxis.set_major_formatter(mticker.ScalarFormatter())

# Panel B: Speedup
ax = axes[0, 1]
for i, board in enumerate(boards):
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'hatch': ''})
    bx = x_pos + offsets[i]
    ax.bar(bx, sub['speedup_mean'].values, width,
           label=board, color=st['color'], alpha=0.85,
           yerr=sub['speedup_std'].values, capsize=3)
ax.axhline(1.0, color='red', linestyle='--', linewidth=1, label='Break-even')
ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=9)
ax.set_title('(B) Compute-Only Speedup over CPU Naive', fontsize=10)
ax.set_ylabel('Speedup (×)', fontsize=9)
ax.legend(fontsize=7)

# Panel C: End-to-end latency (ms)
ax = axes[1, 0]
for i, board in enumerate(boards):
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'hatch': ''})
    bx = x_pos + offsets[i]
    ax.bar(bx, sub['fpga_e2e_mean'].values / 1000, width,
           label=board, color=st['color'], hatch=st['hatch'], alpha=0.85,
           yerr=sub['fpga_e2e_std'].values / 1000, capsize=3)
ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=9)
ax.set_title('(C) End-to-End Latency (UART included)', fontsize=10)
ax.set_ylabel('Latency (ms)', fontsize=9)
ax.legend(fontsize=7)

# Panel D: UART % breakdown
ax = axes[1, 1]
for i, board in enumerate(boards):
    sub = summary[summary['Board'] == board].sort_values('N')
    st  = BOARD_STYLE.get(board, {'color': 'gray', 'hatch': ''})
    bx = x_pos + offsets[i]
    ax.bar(bx, sub['compute_pct'].values, width,
           color=st['color'], alpha=0.95, label=f'{board} Compute')
    ax.bar(bx, sub['uart_pct'].values, width,
           bottom=sub['compute_pct'].values,
           color=st['color'], alpha=0.3, hatch='//')
ax.set_xticks(x_pos)
ax.set_xticklabels([f'N={n}' for n in ns], fontsize=9)
ax.set_title('(D) UART vs Compute Share of End-to-End Time', fontsize=10)
ax.set_ylabel('Percentage (%)', fontsize=9)
ax.set_ylim(0, 108)

for a in axes.flat:
    a.grid(True, alpha=0.2, linestyle='--')
    a.spines['top'].set_visible(False)
    a.spines['right'].set_visible(False)

plt.tight_layout()
plt.savefig('fig8_combined_summary.png', dpi=300, bbox_inches='tight')
print("Saved: fig8_combined_summary.png")
plt.close()

print("\nAll figures saved. Once Zybo Z7-20 data is added to FPGA_runs.csv,")
print("re-run this script — all figures will automatically include the third board.")