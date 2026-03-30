// =============================================================================
// uart_tx.v  –  UART Transmitter  (Gowin/Verilog-2001 clean)
// 8N1, configurable baud via CLK_FREQ / BAUD_RATE parameters
//
// Fix vs original:
//   - clk_cnt widened to 18 bits (handles CLK/BAUD up to ~262143)
//   - bit_idx widened to 4 bits (eliminates 4→3 truncation warning)
//   - All increments explicitly masked to their target width so Gowin
//     does not warn about expression-size truncation (EX3791)
// =============================================================================
module uart_tx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       start,
    output reg        tx,
    output reg        busy
);

localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

localparam IDLE  = 2'd0,
           START = 2'd1,
           DATA  = 2'd2,
           STOP  = 2'd3;

reg [1:0]  state;
reg [17:0] clk_cnt;   // 18-bit: handles up to 262143 clocks/bit
reg [3:0]  bit_idx;   // 4-bit: 0-7, no truncation on +1
reg [7:0]  shift;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state   <= IDLE;
        tx      <= 1'b1;
        busy    <= 1'b0;
        clk_cnt <= 18'd0;
        bit_idx <= 4'd0;
        shift   <= 8'd0;
    end else begin
        case (state)
            IDLE: begin
                tx   <= 1'b1;
                busy <= 1'b0;
                if (start) begin
                    shift   <= data;
                    state   <= START;
                    clk_cnt <= 18'd1;
                    busy    <= 1'b1;
                end
            end
            START: begin
                tx <= 1'b0;
                if (clk_cnt == CLKS_PER_BIT[17:0]) begin
                    state   <= DATA;
                    clk_cnt <= 18'd1;
                    bit_idx <= 4'd0;
                end else
                    clk_cnt <= clk_cnt + 18'd1;
            end
            DATA: begin
                tx <= shift[0];
                if (clk_cnt == CLKS_PER_BIT[17:0]) begin
                    shift   <= {1'b0, shift[7:1]};
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
                tx <= 1'b1;
                if (clk_cnt == CLKS_PER_BIT[17:0]) begin
                    state   <= IDLE;
                    clk_cnt <= 18'd0;
                    busy    <= 1'b0;
                end else
                    clk_cnt <= clk_cnt + 18'd1;
            end
        endcase
    end
end

endmodule
