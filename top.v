// =============================================================================
// top.v  –  Top-level for Tang Primer 20K
//
//  Board details (GW2A-18):
//    - 27 MHz on-board oscillator on pin IO_LOC "4"  (check your .cst)
//    - Active-low reset button
//    - UART via on-board USB-UART bridge
//
//  Change N to 8 or 16 for larger matrices (resynthesize).
// =============================================================================
module top #(
    parameter N         = 4,          // <-- change to 8 or 16
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,          // 27 MHz oscillator
    input  wire rst_n,        // active-low button
    input  wire uart_rx,
    output wire uart_tx,
    output wire led            // heartbeat LED
);

// Simple heartbeat: toggle every ~0.5 s
reg [23:0] hb_cnt;
reg        hb_led;
assign led = hb_led;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hb_cnt <= 0;
        hb_led <= 0;
    end else begin
        hb_cnt <= hb_cnt + 1;
        if (hb_cnt == 24'd13_500_000) begin
            hb_cnt <= 0;
            hb_led <= ~hb_led;
        end
    end
end

// Main controller
uart_ctrl #(
    .N        (N),
    .CLK_FREQ (CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) u_ctrl (
    .clk         (clk),
    .rst_n       (rst_n),
    .uart_rx_pin (uart_rx),
    .uart_tx_pin (uart_tx)
);

endmodule
