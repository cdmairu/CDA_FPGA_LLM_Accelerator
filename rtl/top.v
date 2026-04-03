// =============================================================================
// top.v  –  Top-level for Tang Primer 20K  (Gowin/Verilog-2001 clean)
// =============================================================================
module top #(
    parameter N         = 4,
    parameter CLK_FREQ_HZ  = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire uart_rx,
    output wire uart_tx,
    input  wire rst_n,  // button S1
    output wire led5
);

    // Half-period count: toggle every 0.5 seconds
    localparam integer HALF_PERIOD_COUNT = (CLK_FREQ_HZ/2) - 1;

    reg [$clog2(CLK_FREQ_HZ/2)-1:0] cnt;
    reg led_r;

    assign led5 = led_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt   <= 0;
            led_r <= 1'b0;
        end else begin
            if (cnt == HALF_PERIOD_COUNT) begin
                cnt   <= 0;
                led_r <= ~led_r;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

// consider updating to use TangPrimer 20K example UART code instead?
// https://github.com/sipeed/TangPrimer-20K-example/blob/main/UART/src/uart_top.v
uart_ctrl #(
    .N        (N),
    .CLK_FREQ (CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
) u_ctrl (
    .clk         (clk),
    .rst_n       (rst_n),
    .uart_rx_pin (uart_rx),
    .uart_tx_pin (uart_tx)
);

endmodule
