// =============================================================================
// uart_tx.v  –  UART Transmitter
// 8N1, configurable baud via CLK_FREQ / BAUD_RATE parameters
// =============================================================================
module uart_tx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       start,      // 1-cycle pulse to begin transmission
    output reg        tx,
    output reg        busy        // high while transmitting
);

localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

localparam IDLE  = 2'd0,
           START = 2'd1,
           DATA  = 2'd2,
           STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] clk_cnt;
reg [2:0]  bit_idx;
reg [7:0]  shift;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state   <= IDLE;
        tx      <= 1'b1;
        busy    <= 1'b0;
        clk_cnt <= 0;
        bit_idx <= 0;
        shift   <= 0;
    end else begin
        case (state)
            IDLE: begin
                tx   <= 1'b1;
                busy <= 1'b0;
                if (start) begin
                    shift   <= data;
                    state   <= START;
                    clk_cnt <= 1;
                    busy    <= 1'b1;
                end
            end
            START: begin
                tx <= 1'b0;                    // start bit
                if (clk_cnt == CLKS_PER_BIT) begin
                    state   <= DATA;
                    clk_cnt <= 1;
                    bit_idx <= 0;
                end else clk_cnt <= clk_cnt + 1;
            end
            DATA: begin
                tx <= shift[0];
                if (clk_cnt == CLKS_PER_BIT) begin
                    shift   <= {1'b0, shift[7:1]};
                    clk_cnt <= 1;
                    if (bit_idx == 7) begin
                        state   <= STOP;
                        bit_idx <= 0;
                    end else
                        bit_idx <= bit_idx + 1;
                end else clk_cnt <= clk_cnt + 1;
            end
            STOP: begin
                tx <= 1'b1;                    // stop bit
                if (clk_cnt == CLKS_PER_BIT) begin
                    state   <= IDLE;
                    clk_cnt <= 0;
                    busy    <= 1'b0;
                end else clk_cnt <= clk_cnt + 1;
            end
        endcase
    end
end

endmodule
