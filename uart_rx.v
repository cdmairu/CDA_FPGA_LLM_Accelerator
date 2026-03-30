// =============================================================================
// uart_rx.v  –  UART Receiver
// 8N1, configurable baud via CLK_FREQ / BAUD_RATE parameters
// =============================================================================
module uart_rx #(
    parameter CLK_FREQ  = 27_000_000,   // Tang Primer 20K on-board oscillator
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid       // 1-cycle pulse when a byte is ready
);

localparam CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
localparam HALF_BIT      = CLKS_PER_BIT / 2;

// ---------------- state machine ----------------
localparam IDLE  = 2'd0,
           START = 2'd1,
           DATA  = 2'd2,
           STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] clk_cnt;
reg [2:0]  bit_idx;
reg [7:0]  shift;

// double-flop synchroniser on rx
reg rx_sync0, rx_sync1;
always @(posedge clk) begin
    rx_sync0 <= rx;
    rx_sync1 <= rx_sync0;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state   <= IDLE;
        clk_cnt <= 0;
        bit_idx <= 0;
        shift   <= 0;
        data    <= 0;
        valid   <= 0;
    end else begin
        valid <= 0;
        case (state)
            IDLE: begin
                if (!rx_sync1) begin          // falling edge = start bit
                    state   <= START;
                    clk_cnt <= 1;
                end
            end
            START: begin
                if (clk_cnt == HALF_BIT) begin
                    if (!rx_sync1) begin       // still low → real start bit
                        state   <= DATA;
                        clk_cnt <= 1;
                        bit_idx <= 0;
                    end else begin
                        state <= IDLE;         // glitch, abort
                    end
                end else clk_cnt <= clk_cnt + 1;
            end
            DATA: begin
                if (clk_cnt == CLKS_PER_BIT) begin
                    shift   <= {rx_sync1, shift[7:1]};  // LSB first
                    clk_cnt <= 1;
                    if (bit_idx == 7) begin
                        state <= STOP;
                        bit_idx <= 0;
                    end else
                        bit_idx <= bit_idx + 1;
                end else clk_cnt <= clk_cnt + 1;
            end
            STOP: begin
                if (clk_cnt == CLKS_PER_BIT) begin
                    data    <= shift;
                    valid   <= 1;
                    state   <= IDLE;
                    clk_cnt <= 0;
                end else clk_cnt <= clk_cnt + 1;
            end
        endcase
    end
end

endmodule
