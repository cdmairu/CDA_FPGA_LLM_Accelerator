// =============================================================================
// uart_ctrl.v  --  UART Command Controller
//                  (Gowin/Verilog-2001 clean, no EX3791 truncation warnings)
//
//  PC -> FPGA:  [0x01] [A: N*N*2 bytes int16 LE] [B: N*N*2 bytes int16 LE]
//  FPGA -> PC:  [C: N*N*4 bytes int32 LE] [cycle_count: 4 bytes uint32 LE]
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

localparam NN       = N * N;
localparam AB_BYTES = NN * 2;
localparam C_BYTES  = NN * 4;

// byte_cnt counts 0..AB_BYTES-1  (max 512 for N=16)
// byte_cnt10 counts 0..C_BYTES-1 (max 1024 for N=16)
// Use one guard bit above the required range to avoid +1 truncation.
localparam BCNT_W  = $clog2(AB_BYTES) + 1;  // 10 bits for N=16
localparam BCNT10_W = $clog2(C_BYTES)  + 1;  // 11 bits for N=16

// =====================================================================
// UART RX / TX
// =====================================================================
wire [7:0] rx_data;
wire       rx_valid;

uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
    .clk(clk), .rst_n(rst_n), .rx(uart_rx_pin),
    .data(rx_data), .valid(rx_valid)
);

reg  [7:0] tx_data;
reg        tx_start;
wire       tx_busy;

uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
    .clk(clk), .rst_n(rst_n), .data(tx_data), .start(tx_start),
    .tx(uart_tx_pin), .busy(tx_busy)
);

// =====================================================================
// Matrix byte buffers
// =====================================================================
reg [7:0] A_buf [0:AB_BYTES-1];
reg [7:0] B_buf [0:AB_BYTES-1];

reg signed [16*NN-1:0] A_flat;
reg signed [16*NN-1:0] B_flat;

// =====================================================================
// matmul_core
// =====================================================================
wire                    core_done;
wire [31:0]             core_cycles;
wire signed [32*NN-1:0] C_flat;
reg                     core_start;

matmul_core #(.N(N)) u_core (
    .clk(clk), .rst_n(rst_n),
    .A_flat(A_flat), .B_flat(B_flat),
    .start(core_start), .done(core_done),
    .C_flat(C_flat), .cycle_count(core_cycles)
);

// =====================================================================
// FSM
// =====================================================================
localparam ST_WAIT_CMD   = 4'd0,
           ST_RX_A       = 4'd1,
           ST_RX_B       = 4'd2,
           ST_ASSEMBLE   = 4'd3,
           ST_COMPUTE    = 4'd4,
           ST_TX_C       = 4'd5,
           ST_TX_WAIT_C  = 4'd6,
           ST_TX_CC      = 4'd7,
           ST_TX_WAIT_CC = 4'd8;

reg [3:0]          state;
reg [BCNT_W-1:0]   byte_cnt;
reg [BCNT10_W-1:0] byte_cnt10;
reg [31:0]         latched_cycles;
reg [1:0]          cc_byte_idx;

// Explicit-width increment constants
wire [BCNT_W-1:0]   ONE_BC   = {{(BCNT_W-1){1'b0}},   1'b1};
wire [BCNT10_W-1:0] ONE_BC10 = {{(BCNT10_W-1){1'b0}}, 1'b1};

integer idx_a;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= ST_WAIT_CMD;
        byte_cnt       <= {BCNT_W{1'b0}};
        byte_cnt10     <= {BCNT10_W{1'b0}};
        core_start     <= 1'b0;
        tx_start       <= 1'b0;
        tx_data        <= 8'h00;
        cc_byte_idx    <= 2'd0;
        latched_cycles <= 32'd0;
        A_flat         <= {(16*NN){1'b0}};
        B_flat         <= {(16*NN){1'b0}};
    end else begin
        core_start <= 1'b0;
        tx_start   <= 1'b0;

        case (state)

            ST_WAIT_CMD: begin
                if (rx_valid && rx_data == 8'h01) begin
                    state    <= ST_RX_A;
                    byte_cnt <= {BCNT_W{1'b0}};
                end
            end

            ST_RX_A: begin
                if (rx_valid) begin
                    A_buf[byte_cnt] <= rx_data;
                    if (byte_cnt == (AB_BYTES-1)) begin
                        state    <= ST_RX_B;
                        byte_cnt <= {BCNT_W{1'b0}};
                    end else
                        byte_cnt <= byte_cnt + ONE_BC;
                end
            end

            ST_RX_B: begin
                if (rx_valid) begin
                    B_buf[byte_cnt] <= rx_data;
                    if (byte_cnt == (AB_BYTES-1)) begin
                        state    <= ST_ASSEMBLE;
                        byte_cnt <= {BCNT_W{1'b0}};
                    end else
                        byte_cnt <= byte_cnt + ONE_BC;
                end
            end

            ST_ASSEMBLE: begin
                for (idx_a = 0; idx_a < NN; idx_a = idx_a + 1) begin
                    A_flat[idx_a*16 +: 16] <= {A_buf[idx_a*2+1], A_buf[idx_a*2]};
                    B_flat[idx_a*16 +: 16] <= {B_buf[idx_a*2+1], B_buf[idx_a*2]};
                end
                core_start <= 1'b1;
                state      <= ST_COMPUTE;
            end

            ST_COMPUTE: begin
                if (core_done) begin
                    latched_cycles <= core_cycles;
                    byte_cnt10     <= {BCNT10_W{1'b0}};
                    state          <= ST_TX_C;
                end
            end

            ST_TX_C: begin
                if (!tx_busy) begin
                    tx_data  <= C_flat[(byte_cnt10/4)*32 + (byte_cnt10%4)*8 +: 8];
                    tx_start <= 1'b1;
                    state    <= ST_TX_WAIT_C;
                end
            end

            ST_TX_WAIT_C: begin
                if (!tx_busy && !tx_start) begin
                    if (byte_cnt10 == (C_BYTES-1)) begin
                        cc_byte_idx <= 2'd0;
                        state       <= ST_TX_CC;
                    end else begin
                        byte_cnt10 <= byte_cnt10 + ONE_BC10;
                        state      <= ST_TX_C;
                    end
                end
            end

            ST_TX_CC: begin
                if (!tx_busy) begin
                    tx_data  <= latched_cycles[cc_byte_idx*8 +: 8];
                    tx_start <= 1'b1;
                    state    <= ST_TX_WAIT_CC;
                end
            end

            ST_TX_WAIT_CC: begin
                if (!tx_busy && !tx_start) begin
                    if (cc_byte_idx == 2'd3)
                        state <= ST_WAIT_CMD;
                    else begin
                        cc_byte_idx <= cc_byte_idx + 2'd1;
                        state       <= ST_TX_CC;
                    end
                end
            end

        endcase
    end
end

endmodule
