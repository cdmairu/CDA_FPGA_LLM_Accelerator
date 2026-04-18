# Instructions

## Install Gowin EDA (Windows)

1. Go to <https://www.gowinsemi.com>
2. Create a free account and login
3. Products --> GOWIN EDA --> Scroll down to Download GOWIN EDA
4. Download the Education (Windows x64) version (no license is required)
5. Accept licenses and install USB drivers

## Setup Project

1. Create a new project for device [`GW2A-LV18PG256C8/I7`](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html).
2. Right click `GW2A-LV18PG256C8/I7` --> Add Files...
3. Add all `rtl/*.v` files.  Copy them into the source directory (else the path is really long and hard to read in the Design window)
4. Add `constraints/top.cst` and `constraints/top.sdc`.

## Program FPGA

1. In the top toolbar, click "Run Synthesis" (LEGO block), then click "Run Place & Route" (four square)
2. Tools --> Programmer
3. Plug in USB cable from computer to USB-JTAG port --> Program/Configure
4. Flip DIP switch #1 to ON to enable the core board: [picture](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html#Dock-ext-board-not-work)
5. Flip DIP switch #5 to ON for the normally high reset switch
6. Settings:
   1. Series: GW2A
   2. Device: GW2A-18
   3. Device Version: C
   4. Access Mode: External Flash Mode
   5. Operation: exFlash Erase,Program thru GAO-Bridge
   6. FS File: point to `/impl/pnr/[PROJECT_NAME].fs`
7. Click the Program/Configure button in the top toolbar

## Get Data from Board

### Matrix Dimension of 4

1. make sure `parameter integer N = 4` in `rtl/top.v` and re-program the board
2. `cd host`
3. `py fpga_host.py --port COM6 --N 4 --baud 115200 --iters 100 --fclk 27000000 --timeout 5`

### Matrix Dimension of 8

1. make sure `parameter integer N = 8` in `rtl/top.v` and re-program the board
2. `cd host`
3. `py fpga_host.py --port COM6 --N 8 --baud 115200 --iters 100 --fclk 27000000 --timeout 5`

### Notes

- `COM6` will match your port number for the Tang Primer 20k FPGA seen in Device Manager --> Ports (COM & LPT) --> USB Serial Port (unplug and replug the board to see which it is)
- the board is not capable of doing a matrix dimension of 16
  - The program would use **16,616** DFFs, but the GW2A‑18 device only has **16,173** DFFs.
  - A DFF is a D-type flip-flop (often shown as “DFF” in FPGA reports). It’s the basic 1‑bit storage element used to build registers in synchronous digital logic.
