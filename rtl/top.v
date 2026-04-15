// =============================================================================
// top.v  –  Top-level for Tang Primer 20K  (no FIFO version)
// =============================================================================
module top #(
    parameter integer N           = 4,
    parameter integer CLK_FREQ_HZ = 27_000_000,
    parameter integer BAUD_RATE   = 115200
)(
    input  wire clk,
    input  wire uart_rx,
    output wire uart_tx,
    input  wire rst_n,   // switch 5
    output wire led5
);

    // Sipeed UART blocks expect MHz
    localparam integer CLK_FRE = CLK_FREQ_HZ / 1_000_000;

    // ----------------------------------------------------------------
    // Heartbeat LED
    // ----------------------------------------------------------------
    localparam integer HALF_PERIOD_COUNT = (CLK_FREQ_HZ / 2) - 1;

    reg [$clog2(CLK_FREQ_HZ / 2)-1:0] cnt;
    reg led_r;

    assign led5 = led_r;

    // ----------------------------------------------------------------
    // UART RX/TX signals
    // ----------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_data_valid;
    wire       rx_data_ready;

    reg  [7:0] tx_data;
    reg        tx_data_valid;
    wire       tx_data_ready;
    wire       tx_busy;

    // Always ready to accept a received byte in this simple design.
    assign rx_data_ready = 1'b1;

    // ----------------------------------------------------------------
    // Command parser
    // ----------------------------------------------------------------
    reg [7:0] cmd [0:7];
    reg [3:0] cmd_len;

    // ----------------------------------------------------------------
    // Reply generator
    // ----------------------------------------------------------------
    localparam [1:0] REPLY_NONE = 2'd0;
    localparam [1:0] REPLY_PONG = 2'd1;
    localparam [1:0] REPLY_ERR  = 2'd2;
    localparam [1:0] REPLY_SIM  = 2'd3;

    reg [1:0] reply_type;
    reg [5:0] reply_idx;
    reg [5:0] reply_len;
    reg       reply_active;

    integer i;

    function [7:0] to_upper;
        input [7:0] ch;
        begin
            if (ch >= "a" && ch <= "z")
                to_upper = ch - 8'd32;
            else
                to_upper = ch;
        end
    endfunction

    function [7:0] reply_byte;
        input [1:0] rtype;
        input [5:0] idx;
        begin
            case (rtype)
                REPLY_PONG: begin
                    case (idx)
                        6'd0: reply_byte = "P";
                        6'd1: reply_byte = "O";
                        6'd2: reply_byte = "N";
                        6'd3: reply_byte = "G";
                        6'd4: reply_byte = 8'h0D;
                        6'd5: reply_byte = 8'h0A;
                        default: reply_byte = 8'h00;
                    endcase
                end

                REPLY_SIM: begin
                    // Temporary stub response for SIM
                    case (idx)
                        6'd0: reply_byte = "S";
                        6'd1: reply_byte = "I";
                        6'd2: reply_byte = "M";
                        6'd3: reply_byte = 8'h0D;
                        6'd4: reply_byte = 8'h0A;
                        default: reply_byte = 8'h00;
                    endcase
                end

                REPLY_ERR: begin
                    case (idx)
                        6'd0: reply_byte = "E";
                        6'd1: reply_byte = "R";
                        6'd2: reply_byte = "R";
                        6'd3: reply_byte = 8'h0D;
                        6'd4: reply_byte = 8'h0A;
                        default: reply_byte = 8'h00;
                    endcase
                end

                default: begin
                    reply_byte = 8'h00;
                end
            endcase
        end
    endfunction

    // ----------------------------------------------------------------
    // Main logic
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // heartbeat LED
            cnt           <= 0;
            led_r         <= 1'b0;

            // UART
            cmd_len       <= 4'd0;
            for (i = 0; i < 8; i = i + 1)
                cmd[i] <= 8'd0;

            tx_data       <= 8'd0;
            tx_data_valid <= 1'b0;

            reply_type    <= REPLY_NONE;
            reply_idx     <= 6'd0;
            reply_len     <= 6'd0;
            reply_active  <= 1'b0;
        end else begin
            // --------------------------------------------------------
            // Heartbeat LED
            // --------------------------------------------------------
            if (cnt == HALF_PERIOD_COUNT) begin
                cnt   <= 0;
                led_r <= ~led_r;
            end else begin
                cnt <= cnt + 1'b1;
            end

            // --------------------------------------------------------
            // Clear tx_data_valid after UART accepts a byte
            // --------------------------------------------------------
            if (tx_data_valid && tx_data_ready) begin
                tx_data_valid <= 1'b0;
            end

            // --------------------------------------------------------
            // Transmit reply bytes
            // --------------------------------------------------------
            if (reply_active && !tx_data_valid && tx_data_ready) begin
                tx_data       <= reply_byte(reply_type, reply_idx);
                tx_data_valid <= 1'b1;

                if (reply_idx == reply_len - 1'b1) begin
                    reply_idx    <= 6'd0;
                    reply_len    <= 6'd0;
                    reply_type   <= REPLY_NONE;
                    reply_active <= 1'b0;
                end else begin
                    reply_idx <= reply_idx + 1'b1;
                end
            end

            // --------------------------------------------------------
            // Receive and parse commands
            // Only accept new RX bytes when not transmitting a reply.
            // --------------------------------------------------------
            if (!reply_active && rx_data_valid) begin
                // End of line: parse command
                if (rx_data == 8'h0D || rx_data == 8'h0A) begin
                    if (cmd_len != 0) begin
                        // PING -> PONG
                        if (cmd_len == 4 &&
                            to_upper(cmd[0]) == "P" &&
                            to_upper(cmd[1]) == "I" &&
                            to_upper(cmd[2]) == "N" &&
                            to_upper(cmd[3]) == "G") begin
                            reply_type   <= REPLY_PONG;
                            reply_idx    <= 6'd0;
                            reply_len    <= 6'd6;
                            reply_active <= 1'b1;
                        end
                        // SIM -> SIM   (stub for now)
                        else if (cmd_len == 3 &&
                                 to_upper(cmd[0]) == "S" &&
                                 to_upper(cmd[1]) == "I" &&
                                 to_upper(cmd[2]) == "M") begin
                            
                            // TODO; run simulation and return results

                            // reply_type   <= REPLY_SIM;
                            // reply_idx    <= 6'd0;
                            // reply_len    <= 6'd5;
                            // reply_active <= 1'b1;
                        end
                        // Unknown command -> ERR
                        else begin
                            reply_type   <= REPLY_ERR;
                            reply_idx    <= 6'd0;
                            reply_len    <= 6'd5;
                            reply_active <= 1'b1;
                        end
                    end

                    cmd_len <= 4'd0;
                end
                else if (cmd_len < 8) begin
                    cmd[cmd_len] <= rx_data;
                    cmd_len      <= cmd_len + 1'b1;
                end
                else begin
                    // Command too long; ignore extra chars until CR/LF
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // UART RX / TX from Sipeed example
    // ----------------------------------------------------------------
    uart_rx #(
        .CLK_FRE   (CLK_FRE),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx_data       (rx_data),
        .rx_data_valid (rx_data_valid),
        .rx_data_ready (rx_data_ready),
        .rx_pin        (uart_rx)
    );

    uart_tx #(
        .CLK_FRE   (CLK_FRE),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_data       (tx_data),
        .tx_data_valid (tx_data_valid),
        .tx_data_ready (tx_data_ready),
        .tx_pin        (uart_tx),
        .tx_busy       (tx_busy)
    );

endmodule