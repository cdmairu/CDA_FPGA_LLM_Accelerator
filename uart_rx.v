// =============================================================================
// uart_rx.v  –  UART Receiver  (Gowin/Verilog-2001 clean)
// 8N1, configurable baud via CLK_FREQ / BAUD_RATE parameters
//
// Fix vs original:
//   - clk_cnt widened to 18 bits
//   - bit_idx widened to 4 bits
//   - All increments explicitly masked to target width (eliminates EX3791)
// =============================================================================
module uart_rx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);

localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
localparam HALF_BIT     = CLKS_PER_BIT / 2;

localparam IDLE  = 2'd0,
           START = 2'd1,
           DATA  = 2'd2,
           STOP  = 2'd3;

reg [1:0]  state;
reg [17:0] clk_cnt;   // 18-bit
reg [3:0]  bit_idx;   // 4-bit
reg [7:0]  shift;

// Double-flop synchroniser
reg rx_sync0, rx_sync1;
always @(posedge clk) begin
    rx_sync0 <= rx;
    rx_sync1 <= rx_sync0;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state   <= IDLE;
        clk_cnt <= 18'd0;
        bit_idx <= 4'd0;
        shift   <= 8'd0;
        data    <= 8'd0;
        valid   <= 1'b0;
    end else begin
        valid <= 1'b0;
        case (state)
            IDLE: begin
                if (!rx_sync1) begin          // falling edge → start bit
                    state   <= START;
                    clk_cnt <= 18'd1;
                end
            end
            START: begin
                if (clk_cnt == HALF_BIT[17:0]) begin
                    if (!rx_sync1) begin       // confirmed start bit
                        state   <= DATA;
                        clk_cnt <= 18'd1;
                        bit_idx <= 4'd0;
                    end else
                        state <= IDLE;         // glitch, abort
                end else
                    clk_cnt <= clk_cnt + 18'd1;
            end
            DATA: begin
                if (clk_cnt == CLKS_PER_BIT[17:0]) begin
                    shift   <= {rx_sync1, shift[7:1]};  // LSB first
                    clk_cnt <= 18'd1;
                    if (bit_idx == 4'd7) begin
                        state   <= STOP;
                        bit_idx <= 4'd0;
                    end else
                        bit_idx <= bit_idx + 4'd1;
                end else
                    clk_cnt <= clk_cnt + 18'd1;
            end
            STOP: begin
                if (clk_cnt == CLKS_PER_BIT[17:0]) begin
                    data    <= shift;
                    valid   <= 1'b1;
                    state   <= IDLE;
                    clk_cnt <= 18'd0;
                end else
                    clk_cnt <= clk_cnt + 18'd1;
            end
        endcase
    end
end

endmodule
