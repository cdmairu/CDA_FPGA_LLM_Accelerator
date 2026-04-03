// =============================================================================
// tb_uart.v  –  UART TX→RX loopback testbench (corrected)
//
//  Sends bytes, captures received bytes into rx_log[], checks after all done.
//  Run: iverilog -g2012 -o sim_uart tb_uart.v uart_rx.v uart_tx.v && vvp sim_uart
// =============================================================================
`timescale 1ns/1ps

module tb_uart;

// 100 MHz / 115200 baud  →  ~868 clocks per bit (very stable margins)
localparam CLK_FREQ     = 100_000_000;
localparam BAUD_RATE    = 115_200;
localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868
localparam CLK_HALF_NS  = 5;                       // 10 ns period

reg  clk, rst_n;
reg  [7:0] tx_data;
reg        tx_start;
wire       tx_busy;
wire       uart_line;
wire [7:0] rx_data;
wire       rx_valid;

initial clk = 0;
always #(CLK_HALF_NS) clk = ~clk;

uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
    .clk(clk), .rst_n(rst_n), .data(tx_data), .start(tx_start),
    .tx(uart_line), .busy(tx_busy)
);
uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
    .clk(clk), .rst_n(rst_n), .rx(uart_line),
    .data(rx_data), .valid(rx_valid)
);

// Capture received bytes in a log
reg [7:0] rx_log [0:31];
integer   rx_head;
always @(posedge clk) begin
    if (rx_valid) begin
        rx_log[rx_head] <= rx_data;
        rx_head          <= rx_head + 1;
    end
end

// Send one byte; caller must ensure TX is idle first
task send_byte;
    input [7:0] b;
    begin
        while (tx_busy) @(posedge clk);
        @(posedge clk); #1;
        tx_data  = b;
        tx_start = 1;
        @(posedge clk); #1;
        tx_start = 0;
    end
endtask

integer i, pass_cnt, fail_cnt;
localparam NUM_BYTES = 8;
reg [7:0] expected [0:NUM_BYTES-1];

initial begin
    $dumpfile("tb_uart.vcd");
    $dumpvars(0, tb_uart);

    pass_cnt = 0; fail_cnt = 0; rx_head = 0;
    rst_n = 0; tx_start = 0; tx_data = 0;
    repeat(8) @(posedge clk);
    rst_n = 1;
    repeat(4) @(posedge clk);

    expected[0] = 8'hA5; expected[1] = 8'h01; expected[2] = 8'hFF;
    expected[3] = 8'h00; expected[4] = 8'h7E; expected[5] = 8'h55;
    expected[6] = 8'hAA; expected[7] = 8'h3C;

    for (i = 0; i < NUM_BYTES; i = i + 1)
        send_byte(expected[i]);

    // Wait for TX to finish + full RX stop bit + margin
    while (tx_busy) @(posedge clk);
    repeat(CLKS_PER_BIT * 15) @(posedge clk);

    // Verify
    if (rx_head !== NUM_BYTES) begin
        $display("ERROR: received %0d bytes, expected %0d", rx_head, NUM_BYTES);
        fail_cnt = fail_cnt + NUM_BYTES;
    end else begin
        for (i = 0; i < NUM_BYTES; i = i + 1) begin
            if (rx_log[i] === expected[i]) begin
                $display("PASS [%0d]: 0x%02h", i, rx_log[i]);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL [%0d]: got=0x%02h exp=0x%02h", i, rx_log[i], expected[i]);
                fail_cnt = fail_cnt + 1;
            end
        end
    end

    $display("============================");
    $display("UART loopback  PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("ALL BYTES MATCH");
    $display("============================");
    $finish;
end

endmodule
