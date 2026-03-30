"""
fpga_sim.py
===========
Simulates the FPGA accelerator in Python so you can test the host script
end-to-end without real hardware.

Run the simulator in one terminal, then run fpga_host.py against it:

    Terminal 1:  python fpga_sim.py --port /tmp/fpga_sim  (Linux/macOS with socat)
                 python fpga_sim.py --port COM4            (Windows with com0com)

    Terminal 2:  python fpga_host.py --port /tmp/fpga_host --N 4 --iters 5

For Linux/macOS, create a virtual serial pair first:
    socat -d -d PTY,raw,echo=0,link=/tmp/fpga_sim PTY,raw,echo=0,link=/tmp/fpga_host

The simulator reads A and B, computes C = A @ B with int32, and returns
the result with a fake cycle count (N³ cycles, mimicking sequential MAC).
"""

import argparse
import struct
import sys
import numpy as np

try:
    import serial
except ImportError:
    print("pyserial not found.  pip install pyserial")
    sys.exit(1)

CMD_COMPUTE = 0x01


def read_exact(ser, n):
    buf = b""
    while len(buf) < n:
        chunk = ser.read(n - len(buf))
        if not chunk:
            raise RuntimeError(f"Timeout: expected {n} bytes, got {len(buf)}")
        buf += chunk
    return buf


def simulate(port: str, baud: int, N: int):
    NN = N * N
    print(f"FPGA Simulator ready on {port}  (N={N})")
    ser = serial.Serial(port, baudrate=baud, timeout=10)

    try:
        while True:
            # Wait for command byte
            cmd_b = read_exact(ser, 1)
            cmd = cmd_b[0]

            if cmd != CMD_COMPUTE:
                print(f"Unknown command 0x{cmd:02X}, ignoring")
                continue

            # Receive A
            a_bytes = read_exact(ser, NN * 2)
            A = np.frombuffer(a_bytes, dtype="<i2").reshape(N, N)

            # Receive B
            b_bytes = read_exact(ser, NN * 2)
            B = np.frombuffer(b_bytes, dtype="<i2").reshape(N, N)

            print(f"  Computing {N}×{N} matmul …", end=" ")

            # Compute result (same semantics as FPGA: int32 accumulation)
            C = A.astype(np.int32) @ B.astype(np.int32)

            # Fake cycle count  (sequential MAC: N³ cycles plus overhead)
            fake_cycles = N ** 3 + N * N + N  # rough sequential model

            # Send C
            c_bytes = C.flatten(order="C").astype("<i4").tobytes()
            ser.write(c_bytes)

            # Send cycle count
            ser.write(struct.pack("<I", fake_cycles))
            print(f"done. cycles={fake_cycles}")

    except KeyboardInterrupt:
        print("\nSimulator stopped.")
    finally:
        ser.close()


def main():
    parser = argparse.ArgumentParser(description="FPGA MatMul Simulator")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--N",   type=int, default=4, choices=[4, 8, 16])
    args = parser.parse_args()
    simulate(args.port, args.baud, args.N)


if __name__ == "__main__":
    main()
