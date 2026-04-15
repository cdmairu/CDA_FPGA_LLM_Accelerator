// =============================================================================
// uart_ctrl.v  --  UART Command Controller (binary matmul protocol)
//
//  PC -> FPGA:  [0x01] [A: N*N*2 bytes int16 LE] [B: N*N*2 bytes int16 LE]
//  FPGA -> PC:  [C: N*N*4 bytes int32 LE] [cycle_count: 4 bytes uint32 LE]
//
//  Designed to work with repo uart_rx.v / uart_tx.v (Sipeed-style handshake)
// =============================================================================
module uart_ctrl #(
    parameter integer N           = 4,
    parameter integer CLK_FREQ_HZ = 27_000_000,
    parameter integer BAUD_RATE   = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin
);

    localparam integer NN = N * N;

    // Sipeed UART expects MHz
    localparam integer CLK_FRE = CLK_FREQ_HZ / 1_000_000;

    // -------------------------------------------------------------------------
    // UART RX
    // -------------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_data_valid;
    wire       rx_data_ready;

    // Always ready in this simple controller
    assign rx_data_ready = 1'b1;

    uart_rx #(
        .CLK_FRE   (CLK_FRE),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx_data       (rx_data),
        .rx_data_valid (rx_data_valid),
        .rx_data_ready (rx_data_ready),
        .rx_pin        (uart_rx_pin)
    );

    // -------------------------------------------------------------------------
    // UART TX
    // -------------------------------------------------------------------------
    reg  [7:0] tx_data;
    reg        tx_data_valid;
    wire       tx_data_ready;
    wire       tx_busy;

    uart_tx #(
        .CLK_FRE   (CLK_FRE),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_data       (tx_data),
        .tx_data_valid (tx_data_valid),
        .tx_data_ready (tx_data_ready),
        .tx_pin        (uart_tx_pin),
        .tx_busy       (tx_busy)
    );

    // -------------------------------------------------------------------------
    // matmul_core
    // -------------------------------------------------------------------------
    reg  signed [16*NN-1:0] A_flat;
    reg  signed [16*NN-1:0] B_flat;
    reg                     core_start;

    wire                    core_done;
    wire signed [32*NN-1:0] C_flat;
    wire [31:0]             core_cycles;

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

    // -------------------------------------------------------------------------
    // Receive packing helpers
    // -------------------------------------------------------------------------
    localparam integer EIDX_W = $clog2(NN) + 1; // guard bit
    reg [EIDX_W-1:0] elem_idx;

    reg        rx_half;      // 0 => expecting low byte, 1 => expecting high byte
    reg [7:0]  rx_lo_byte;
    reg        which_matrix; // 0 => A, 1 => B

    // -------------------------------------------------------------------------
    // Transmit counters
    // -------------------------------------------------------------------------
    localparam integer CW_W = $clog2(NN) + 1;
    reg [CW_W-1:0] c_word_idx;
    reg [1:0]      c_byte_idx;

    reg [31:0]     latched_cycles;
    reg [1:0]      cc_byte_idx;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    localparam [3:0]
        ST_WAIT_CMD   = 4'd0,
        ST_RX_AB      = 4'd1,
        ST_START      = 4'd2,
        ST_WAIT_DONE  = 4'd3,
        ST_TX_C       = 4'd4,
        ST_TX_CC      = 4'd5;

    reg [3:0] state;

    // Helper: send one byte when TX ready and we're not already asserting valid
    task automatic try_send_byte;
        input [7:0] b;
        begin
            if (tx_data_ready && !tx_data_valid) begin
                tx_data       <= b;
                tx_data_valid <= 1'b1; // will be cleared next cycle after accept
            end
        end
    endtask

    integer dummy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_WAIT_CMD;

            A_flat        <= {(16*NN){1'b0}};
            B_flat        <= {(16*NN){1'b0}};
            core_start    <= 1'b0;

            elem_idx      <= {EIDX_W{1'b0}};
            rx_half       <= 1'b0;
            rx_lo_byte    <= 8'h00;
            which_matrix  <= 1'b0;

            c_word_idx    <= {CW_W{1'b0}};
            c_byte_idx    <= 2'd0;

            latched_cycles <= 32'd0;
            cc_byte_idx    <= 2'd0;

            tx_data        <= 8'h00;
            tx_data_valid  <= 1'b0;
        end else begin
            // default strobes
            core_start <= 1'b0;

            // clear tx_data_valid after UART accepts the byte
            if (tx_data_valid && tx_data_ready) begin
                tx_data_valid <= 1'b0;
            end

            case (state)
                // ------------------------------------------------------------
                // Wait for CMD = 0x01
                // ------------------------------------------------------------
                ST_WAIT_CMD: begin
                    // reset RX assembly state
                    which_matrix <= 1'b0;           // start with A
                    elem_idx     <= {EIDX_W{1'b0}};
                    rx_half      <= 1'b0;

                    if (rx_data_valid && rx_data == 8'h01) begin
                        state <= ST_RX_AB;
                    end
                end

                // ------------------------------------------------------------
                // Receive A then B as int16 little-endian, directly into flats
                // ------------------------------------------------------------
                ST_RX_AB: begin
                    if (rx_data_valid) begin
                        if (!rx_half) begin
                            rx_lo_byte <= rx_data;
                            rx_half    <= 1'b1;
                        end else begin
                            // second byte => commit 16-bit word
                            if (!which_matrix) begin
                                A_flat[elem_idx*16 +: 16] <= {rx_data, rx_lo_byte};
                            end else begin
                                B_flat[elem_idx*16 +: 16] <= {rx_data, rx_lo_byte};
                            end

                            rx_half <= 1'b0;

                            // advance element index
                            if (elem_idx == (NN-1)) begin
                                if (!which_matrix) begin
                                    // finished A, start B
                                    which_matrix <= 1'b1;
                                    elem_idx     <= {EIDX_W{1'b0}};
                                end else begin
                                    // finished B too
                                    state <= ST_START;
                                end
                            end else begin
                                elem_idx <= elem_idx + {{(EIDX_W-1){1'b0}}, 1'b1};
                            end
                        end
                    end
                end

                // ------------------------------------------------------------
                // Pulse start to matmul_core
                // ------------------------------------------------------------
                ST_START: begin
                    core_start <= 1'b1;

                    // prep TX counters
                    c_word_idx <= {CW_W{1'b0}};
                    c_byte_idx <= 2'd0;

                    state <= ST_WAIT_DONE;
                end

                // ------------------------------------------------------------
                // Wait for core to finish
                // ------------------------------------------------------------
                ST_WAIT_DONE: begin
                    if (core_done) begin
                        latched_cycles <= core_cycles;
                        state          <= ST_TX_C;
                    end
                end

                // ------------------------------------------------------------
                // Send C: NN words, each 4 bytes little-endian
                // ------------------------------------------------------------
                ST_TX_C: begin
                    // Only attempt send when we can (task checks ready/valid)
                    try_send_byte(C_flat[c_word_idx*32 + c_byte_idx*8 +: 8]);

                    // Advance indices only when a byte was accepted
                    if (tx_data_valid && tx_data_ready) begin
                        if (c_byte_idx == 2'd3) begin
                            c_byte_idx <= 2'd0;
                            if (c_word_idx == (NN-1)) begin
                                cc_byte_idx <= 2'd0;
                                state       <= ST_TX_CC;
                            end else begin
                                c_word_idx <= c_word_idx + {{(CW_W-1){1'b0}}, 1'b1};
                            end
                        end else begin
                            c_byte_idx <= c_byte_idx + 2'd1;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Send cycle_count (4 bytes little-endian)
                // ------------------------------------------------------------
                ST_TX_CC: begin
                    try_send_byte(latched_cycles[cc_byte_idx*8 +: 8]);

                    if (tx_data_valid && tx_data_ready) begin
                        if (cc_byte_idx == 2'd3) begin
                            state <= ST_WAIT_CMD;
                        end else begin
                            cc_byte_idx <= cc_byte_idx + 2'd1;
                        end
                    end
                end

                default: state <= ST_WAIT_CMD;
            endcase
        end
    end

endmodule