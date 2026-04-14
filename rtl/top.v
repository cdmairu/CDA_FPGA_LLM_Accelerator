// =============================================================================
// top.v  --  Matrix-Multiply over UART  (v2 – bug fixes)
//
// Protocol (host → FPGA):
//   1 byte  : command  = 0xAB
//   N*N*2   : matrix A, signed 16-bit, row-major, little-endian
//   N*N*2   : matrix B, signed 16-bit, row-major, little-endian
//
// Protocol (FPGA → host):
//   N*N*4   : matrix C, signed 32-bit, row-major, little-endian
//   4 bytes : cycle_count (uint32, little-endian)
//
// Tested parameters: CLK_FRE=27 (Tang Primer 20K), BAUD=115200, N=4
// =============================================================================
module top #(
    parameter integer CLK_FRE   = 27,
    parameter integer BAUD_RATE = 115200,
    parameter integer N         = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx
);

// ---------------------------------------------------------------------------
// Derived sizes
// ---------------------------------------------------------------------------
localparam integer NN       = N * N;
localparam integer A_BYTES  = NN * 2;
localparam integer B_BYTES  = NN * 2;
localparam integer C_BYTES  = NN * 4;
localparam integer TOTAL_TX = C_BYTES + 4;   // C + cycle_count

localparam integer RX_IDX_W = $clog2(A_BYTES + 1) + 1;
localparam integer TX_IDX_W = $clog2(TOTAL_TX + 1) + 1;

// ---------------------------------------------------------------------------
// UART RX
// ---------------------------------------------------------------------------
wire [7:0] rx_data;
wire       rx_data_valid;
reg        rx_data_ready;

// ---------------------------------------------------------------------------
// UART TX
// ---------------------------------------------------------------------------
reg  [7:0] tx_data;
reg        tx_data_valid;
wire       tx_data_ready;
wire       tx_busy;

// ---------------------------------------------------------------------------
// matmul_core
// ---------------------------------------------------------------------------
reg  signed [16*NN-1:0] A_flat;
reg  signed [16*NN-1:0] B_flat;
reg                      mm_start;
wire                     mm_done;
wire signed [32*NN-1:0] C_flat;
wire [31:0]              cycle_count;

// ---------------------------------------------------------------------------
// Byte buffers
// ---------------------------------------------------------------------------
reg [7:0] A_buf  [0 : A_BYTES-1];
reg [7:0] B_buf  [0 : B_BYTES-1];
reg [7:0] tx_buf [0 : TOTAL_TX-1];

// ---------------------------------------------------------------------------
// FSM states
// ---------------------------------------------------------------------------
localparam [2:0]
    S_IDLE    = 3'd0,
    S_RECV_A  = 3'd1,
    S_RECV_B  = 3'd2,
    S_COMPUTE = 3'd3,
    S_PACK    = 3'd4,   // latch tx_buf (1 clock) — THEN transition to S_SEND
    S_SEND    = 3'd5;

reg [2:0]          state;
reg [RX_IDX_W-1:0] rx_idx;
reg [TX_IDX_W-1:0] tx_idx;

integer gi;

// ---------------------------------------------------------------------------
// Build A_flat / B_flat combinatorially from byte buffers (little-endian)
// ---------------------------------------------------------------------------
always @(*) begin : assemble_flat
    integer k;
    for (k = 0; k < NN; k = k + 1) begin
        A_flat[k*16 +: 16] = {A_buf[k*2+1], A_buf[k*2]};
        B_flat[k*16 +: 16] = {B_buf[k*2+1], B_buf[k*2]};
    end
end

// ---------------------------------------------------------------------------
// Main FSM
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= S_IDLE;
        rx_idx        <= {RX_IDX_W{1'b0}};
        tx_idx        <= {TX_IDX_W{1'b0}};
        mm_start      <= 1'b0;
        tx_data       <= 8'd0;
        tx_data_valid <= 1'b0;
        rx_data_ready <= 1'b1;
        for (gi = 0; gi < A_BYTES;  gi = gi+1) A_buf[gi]  <= 8'd0;
        for (gi = 0; gi < B_BYTES;  gi = gi+1) B_buf[gi]  <= 8'd0;
        for (gi = 0; gi < TOTAL_TX; gi = gi+1) tx_buf[gi] <= 8'd0;
    end else begin
        mm_start <= 1'b0;  // single-cycle pulse default

        case (state)

            // ----------------------------------------------------------------
            // Wait for the 0xAB command byte
            // ----------------------------------------------------------------
            S_IDLE: begin
                rx_data_ready <= 1'b1;
                tx_data_valid <= 1'b0;
                if (rx_data_valid && rx_data == 8'hAB) begin
                    state  <= S_RECV_A;
                    rx_idx <= {RX_IDX_W{1'b0}};
                end
            end

            // ----------------------------------------------------------------
            // Collect A matrix bytes
            // ----------------------------------------------------------------
            S_RECV_A: begin
                rx_data_ready <= 1'b1;
                if (rx_data_valid) begin
                    A_buf[rx_idx] <= rx_data;
                    if (rx_idx == A_BYTES-1) begin
                        state  <= S_RECV_B;
                        rx_idx <= {RX_IDX_W{1'b0}};
                    end else begin
                        rx_idx <= rx_idx + 1'b1;
                    end
                end
            end

            // ----------------------------------------------------------------
            // Collect B matrix bytes, then kick off compute
            // ----------------------------------------------------------------
            S_RECV_B: begin
                rx_data_ready <= 1'b1;
                if (rx_data_valid) begin
                    B_buf[rx_idx] <= rx_data;
                    if (rx_idx == B_BYTES-1) begin
                        rx_data_ready <= 1'b0;
                        mm_start      <= 1'b1;   // one-cycle pulse
                        state         <= S_COMPUTE;
                    end else begin
                        rx_idx <= rx_idx + 1'b1;
                    end
                end
            end

            // ----------------------------------------------------------------
            // Wait for matmul_core to finish
            // ----------------------------------------------------------------
            S_COMPUTE: begin
                if (mm_done) begin
                    state <= S_PACK;
                end
            end

            // ----------------------------------------------------------------
            // ONE clock cycle to latch C_flat → tx_buf via non-blocking assigns.
            // S_SEND runs the NEXT clock, by which time tx_buf[] is stable.
            // ----------------------------------------------------------------
            S_PACK: begin : pack_tx
                integer k;
                for (k = 0; k < NN; k = k+1) begin
                    tx_buf[k*4+0] <= C_flat[k*32    +: 8];
                    tx_buf[k*4+1] <= C_flat[k*32+8  +: 8];
                    tx_buf[k*4+2] <= C_flat[k*32+16 +: 8];
                    tx_buf[k*4+3] <= C_flat[k*32+24 +: 8];
                end
                tx_buf[C_BYTES+0] <= cycle_count[ 7: 0];
                tx_buf[C_BYTES+1] <= cycle_count[15: 8];
                tx_buf[C_BYTES+2] <= cycle_count[23:16];
                tx_buf[C_BYTES+3] <= cycle_count[31:24];
                tx_idx        <= {TX_IDX_W{1'b0}};
                tx_data_valid <= 1'b0;
                state         <= S_SEND;  // tx_buf readable next cycle
            end

            // ----------------------------------------------------------------
            // Stream tx_buf over UART.
            //
            // uart_tx handshake:
            //   • Assert tx_data + tx_data_valid
            //   • Wait for tx_data_ready == 1  (uart_tx accepted the byte)
            //   • Deassert tx_data_valid, then load next byte
            // ----------------------------------------------------------------
            S_SEND: begin
                if (tx_data_valid) begin
                    // Holding a byte — release when uart_tx accepts it
                    if (tx_data_ready) begin
                        tx_data_valid <= 1'b0;
                    end
                end else begin
                    // Free to load next byte
                    if (tx_idx < TOTAL_TX) begin
                        tx_data       <= tx_buf[tx_idx];
                        tx_data_valid <= 1'b1;
                        tx_idx        <= tx_idx + 1'b1;
                    end else begin
                        // Done — back to idle
                        state         <= S_IDLE;
                        rx_data_ready <= 1'b1;
                    end
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

// ---------------------------------------------------------------------------
// Sub-module instantiations
// ---------------------------------------------------------------------------
uart_rx #(
    .CLK_FRE  (CLK_FRE),
    .BAUD_RATE(BAUD_RATE)
) u_uart_rx (
    .clk          (clk),
    .rst_n        (rst_n),
    .rx_data      (rx_data),
    .rx_data_valid(rx_data_valid),
    .rx_data_ready(rx_data_ready),
    .rx_pin       (uart_rx)
);

uart_tx #(
    .CLK_FRE  (CLK_FRE),
    .BAUD_RATE(BAUD_RATE)
) u_uart_tx (
    .clk          (clk),
    .rst_n        (rst_n),
    .tx_data      (tx_data),
    .tx_data_valid(tx_data_valid),
    .tx_data_ready(tx_data_ready),
    .tx_pin       (uart_tx),
    .tx_busy      (tx_busy)
);

matmul_core #(
    .N(N)
) u_matmul (
    .clk        (clk),
    .rst_n      (rst_n),
    .A_flat     (A_flat),
    .B_flat     (B_flat),
    .start      (mm_start),
    .done       (mm_done),
    .C_flat     (C_flat),
    .cycle_count(cycle_count)
);

endmodule