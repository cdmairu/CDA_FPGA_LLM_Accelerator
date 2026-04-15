#!/usr/bin/env python3

import serial
import time

PORT = "COM6"  # change this to your board's COM port
BAUD = 115200  # must match your FPGA UART design
TIMEOUT = 1.0


def main() -> None:
    with serial.Serial(PORT, BAUD, timeout=TIMEOUT) as ser:
        # optional: give the port a moment to settle
        time.sleep(0.2)

        # send raw bytes
        ser.write(b"PING\r\n")
        ser.flush()

        # read one line back, if your FPGA sends newline-terminated text
        response = ser.readline()
        print("Received:", response)


if __name__ == "__main__":
    main()
