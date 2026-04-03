// =============================================================================
// top.v  –  Top-level for Tang Primer 20K  (Gowin/Verilog-2001 clean)
// =============================================================================
module top #(
    parameter N         = 4,
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx,
    output wire led
);

// Heartbeat counter – widened to 25 bits so +1 never truncates into 24 bits
reg [24:0] hb_cnt;
reg        hb_led;
assign led = hb_led;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hb_cnt <= 25'd0;
        hb_led <= 1'b0;
    end else begin
        if (hb_cnt == 25'd13_500_000) begin
            hb_cnt <= 25'd0;
            hb_led <= ~hb_led;
        end else
            hb_cnt <= hb_cnt + 25'd1;
    end
end

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
