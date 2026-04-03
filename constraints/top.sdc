//==============================================================================
// top.sdc  –  Timing Constraints (Gowin IDE / nextpnr)
//==============================================================================

// 27 MHz primary clock
create_clock -name clk -period 37.037 [get_ports clk]

// False paths on async reset
set_false_path -from [get_ports rst_n]

// Relax UART I/O (multi-cycle, baud-rate level)
set_false_path -from [get_ports uart_rx]
set_false_path -to   [get_ports uart_tx]
