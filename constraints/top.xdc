## Clock (100 MHz)
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

## Reset (btnC - middle button)
set_property PACKAGE_PIN U18 [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]

## UART pins (map to Basys3 Pmod header pins you actually wire to USB-UART)
set_property PACKAGE_PIN A18 [get_ports uart_tx]
set_property PACKAGE_PIN B18 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## LED (Basys3 has 16 LEDs; map your led5 to one of them, e.g. LED0)
set_property PACKAGE_PIN U16 [get_ports led16]
set_property IOSTANDARD LVCMOS33 [get_ports led16]

## BASYS 3 board has quad-SPI
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
