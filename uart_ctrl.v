// =============================================================================
// uart_ctrl.v  –  UART Command Controller (glues UART ↔ matmul_core)
//
//  Protocol (PC → FPGA):
//    [0x01]                   – command byte (compute)
//    [N*N*2 bytes]            – matrix A, int16 LE, row-major
//    [N*N*2 bytes]            – matrix B, int16 LE, row-major
//
//  Protocol (FPGA → PC):
//    [N*N*4 bytes]            – matrix C, int32 LE, row-major
//    [4 bytes]                – cycle_count, uint32 LE
//
//  The matrix dimension N is fixed at synthesis time.
// =============================================================================
module uart_ctrl #(
    parameter N         = 4,
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin
);

localparam NN    = N * N;
localparam AB_BYTES = NN * 2;   // bytes to receive per matrix (int16)
localparam C_BYTES  = NN * 4;   // bytes to send for result (int32)

// =====================================================================
// UART RX / TX
// =====================================================================
wire [7:0] rx_data;
wire       rx_valid;

uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
    .clk   (clk),
    .rst_n (rst_n),
    .rx    (uart_rx_pin),
    .data  (rx_data),
    .valid (rx_valid)
);

reg  [7:0] tx_data;
reg        tx_start;
wire       tx_busy;

uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
    .clk   (clk),
    .rst_n (rst_n),
    .data  (tx_data),
    .start (tx_start),
    .tx    (uart_tx_pin),
    .busy  (tx_busy)
);

// =====================================================================
// Matrix buffers  (byte-addressable staging registers)
// =====================================================================
// A_buf / B_buf hold bytes as they arrive; assembled into A_flat/B_flat
reg [7:0] A_buf [0:AB_BYTES-1];
reg [7:0] B_buf [0:AB_BYTES-1];

// Assembled flat words fed to matmul_core
reg signed [16*NN-1:0] A_flat;
reg signed [16*NN-1:0] B_flat;

// =====================================================================
// matmul_core instance
// =====================================================================
wire                    core_done;
wire [31:0]             core_cycles;
wire signed [32*NN-1:0] C_flat;
reg                     core_start;

matmul_core #(.N(N)) u_core (
    .clk         (clk),
    .rst_n       (rst_n),
    .A_flat      (A_flat),
    .B_flat      (B_flat),
    .start       (core_start),
    .done        (core_done),
    .C_flat      (C_flat),
    .cycle_count (core_cycles)
);

// =====================================================================
// Top-level FSM
// =====================================================================
localparam  ST_WAIT_CMD  = 4'd0,
            ST_RX_A      = 4'd1,
            ST_RX_B      = 4'd2,
            ST_ASSEMBLE  = 4'd3,
            ST_COMPUTE   = 4'd4,
            ST_TX_C      = 4'd5,
            ST_TX_WAIT_C = 4'd6,
            ST_TX_CC     = 4'd7,
            ST_TX_WAIT_CC= 4'd8;

reg [3:0]  state;
reg [8:0]  byte_cnt;    // up to 256×4 = 1024 bytes, so 10 bits safe
reg [9:0]  byte_cnt10;
integer    gi, gj;

// latch cycle count for transmission
reg [31:0] latched_cycles;
reg [1:0]  cc_byte_idx;  // 0..3

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= ST_WAIT_CMD;
        byte_cnt      <= 0;
        byte_cnt10    <= 0;
        core_start    <= 0;
        tx_start      <= 0;
        tx_data       <= 0;
        cc_byte_idx   <= 0;
        latched_cycles<= 0;
        A_flat        <= 0;
        B_flat        <= 0;
    end else begin
        core_start <= 0;
        tx_start   <= 0;

        case (state)

            // ---------------------------------------------------------
            ST_WAIT_CMD: begin
                if (rx_valid && rx_data == 8'h01) begin
                    state    <= ST_RX_A;
                    byte_cnt <= 0;
                end
            end

            // ---------------------------------------------------------
            // Receive A bytes
            ST_RX_A: begin
                if (rx_valid) begin
                    A_buf[byte_cnt] <= rx_data;
                    if (byte_cnt == AB_BYTES-1) begin
                        state    <= ST_RX_B;
                        byte_cnt <= 0;
                    end else
                        byte_cnt <= byte_cnt + 1;
                end
            end

            // ---------------------------------------------------------
            // Receive B bytes
            ST_RX_B: begin
                if (rx_valid) begin
                    B_buf[byte_cnt] <= rx_data;
                    if (byte_cnt == AB_BYTES-1) begin
                        state <= ST_ASSEMBLE;
                        byte_cnt <= 0;
                    end else
                        byte_cnt <= byte_cnt + 1;
                end
            end

            // ---------------------------------------------------------
            // Assemble byte arrays into flat 16-bit word vectors (LE)
            ST_ASSEMBLE: begin
                // Unroll assembly in a single cycle using a generate-style loop
                // For simulation this synthesises fine for N<=16
                begin : assemble_block
                    integer idx;
                    for (idx = 0; idx < NN; idx = idx + 1) begin
                        A_flat[idx*16 +: 16] <= {A_buf[idx*2+1], A_buf[idx*2]};
                        B_flat[idx*16 +: 16] <= {B_buf[idx*2+1], B_buf[idx*2]};
                    end
                end
                core_start <= 1;
                state      <= ST_COMPUTE;
            end

            // ---------------------------------------------------------
            ST_COMPUTE: begin
                if (core_done) begin
                    latched_cycles <= core_cycles;
                    byte_cnt10     <= 0;
                    state          <= ST_TX_C;
                end
            end

            // ---------------------------------------------------------
            // Stream out C matrix (int32 LE) byte by byte
            ST_TX_C: begin
                if (!tx_busy) begin
                    // extract byte: which int32 word and which byte within it
                    tx_data  <= C_flat[ (byte_cnt10/4)*32 + (byte_cnt10%4)*8 +: 8 ];
                    tx_start <= 1;
                    state    <= ST_TX_WAIT_C;
                end
            end
            ST_TX_WAIT_C: begin
                if (!tx_busy && !tx_start) begin
                    if (byte_cnt10 == C_BYTES-1) begin
                        cc_byte_idx <= 0;
                        state       <= ST_TX_CC;
                    end else begin
                        byte_cnt10 <= byte_cnt10 + 1;
                        state      <= ST_TX_C;
                    end
                end
            end

            // ---------------------------------------------------------
            // Stream out cycle count (uint32 LE)
            ST_TX_CC: begin
                if (!tx_busy) begin
                    tx_data  <= latched_cycles[cc_byte_idx*8 +: 8];
                    tx_start <= 1;
                    state    <= ST_TX_WAIT_CC;
                end
            end
            ST_TX_WAIT_CC: begin
                if (!tx_busy && !tx_start) begin
                    if (cc_byte_idx == 2'd3) begin
                        state <= ST_WAIT_CMD;  // ready for next command
                    end else begin
                        cc_byte_idx <= cc_byte_idx + 1;
                        state       <= ST_TX_CC;
                    end
                end
            end

        endcase
    end
end

endmodule
