// =============================================================================
// top.v  –  Top-level for Tang Primer 20K (UART matmul protocol)
// =============================================================================
module top #(
    parameter integer N           = 4,
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115200
)(
    input  wire clk,
    input  wire btnC,
    input  wire uart_rx,
    output wire uart_tx,
    output wire led16
);

    // Heartbeat (100 MHz => toggle about 1 Hz)
    localparam integer HALF_PERIOD_COUNT = (CLK_FREQ_HZ / 2) - 1;

    // BASYS 3 buttons are typically active-high signals
    wire rst_n = ~btnC;

    reg [$clog2(CLK_FREQ_HZ / 2)-1:0] cnt;
    reg led_r;
    assign led16 = led_r;

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

    uart_ctrl #(
        .N           (N),
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) u_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .uart_rx_pin (uart_rx),
        .uart_tx_pin (uart_tx)
    );

endmodule