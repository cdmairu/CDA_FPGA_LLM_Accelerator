import matplotlib.pyplot as plt

# Data from your Excel table
N = [4, 8]

fpga_compute = [2.37, 18.963]
fpga_total = [12674.538, 46001.168]
cpu_naive = [6.560, 44.006]

# Create figure
plt.figure(figsize=(6, 4))

# Plot lines
plt.plot(N, fpga_compute, marker='o', label="FPGA Compute")
plt.plot(N, cpu_naive, marker='o', label="CPU Naive")
plt.plot(N, fpga_total, marker='o', label="FPGA End-to-End")

# Use log scale for better visualization
plt.yscale('log')

# Labels and title
plt.xlabel("Matrix Size (N)")
plt.ylabel("Time (µs)")
plt.title("FPGA vs CPU Matrix Multiplication Performance (Log Scale)")

# Legend and grid
plt.legend()
plt.grid(True)

# Save figure (important for report)
plt.savefig("performance_plot.png", dpi=300)

# Show plot
plt.show()