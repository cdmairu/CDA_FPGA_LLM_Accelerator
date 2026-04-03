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

1. In the top toolbar, click Run Synthesis, then click Place & Route
2. Tools --> Programmer
3. Plug in USB cable from computer to USB-JTAG port --> Program/Configure
4. Flip DIP switch #1 to ON to enable the core board: [picture](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html#Dock-ext-board-not-work)
5. Settings:
   1. Series: GW2A
   2. Device: GW2A-18C
   3. Access Mode: External Flash Mode
   4. Operation: exFlash Erase,Program thru GAO-Bridge
   5. FS File: point to `/impl/pnr/[PROJECT_NAME].fs`
6. Click the Program/Configure button in the top toolbar
