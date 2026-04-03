// =============================================================================
// matmul_core.v  --  Parameterized Sequential Matrix Multiplier
//                    (Gowin/Verilog-2001 clean, no EX3791 truncation warnings)
//
//  N = 4, 8, or 16.  Latency ~= N^3 clock cycles.
//  Inputs  A, B : N x N signed 16-bit, flattened row-major
//  Output  C    : N x N signed 32-bit, flattened row-major
// =============================================================================
module matmul_core #(
    parameter N = 4
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire signed [16*N*N-1:0]  A_flat,
    input  wire signed [16*N*N-1:0]  B_flat,
    input  wire                       start,
    output reg                        done,
    output reg  signed [32*N*N-1:0]  C_flat,
    output reg  [31:0]                cycle_count
);

localparam NN = N * N;

// i/j/k counters: need $clog2(N)+1 bits so the counter can hold N-1
// and the +1 increment expression does not overflow the register width.
// N=4 -> 3 bits, N=8 -> 4 bits, N=16 -> 5 bits
localparam IDX_W = $clog2(N) + 1;

// load_idx counts 0..NN-1.  Use $clog2(NN)+1 bits for the same reason.
// N=4 -> 5 bits (NN=16), N=8 -> 7 bits (NN=64), N=16 -> 9 bits (NN=256)
localparam LIDX_W = $clog2(NN) + 1;

reg signed [15:0]     A_mem [0:NN-1];
reg signed [15:0]     B_mem [0:NN-1];
reg signed [31:0]     C_mem [0:NN-1];

reg [IDX_W-1:0]       ci, cj, ck;
reg signed [31:0]     acc;

localparam IDLE    = 3'd0,
           LOAD    = 3'd1,
           COMPUTE = 3'd2,
           WRITEC  = 3'd3,
           FINISH  = 3'd4;

reg [2:0]             state;
reg [LIDX_W-1:0]      load_idx;

integer gi, gj;

// One-bit constant in the right width for clean increments
wire [IDX_W-1:0]  ONE_IDX  = {{(IDX_W-1){1'b0}},  1'b1};
wire [LIDX_W-1:0] ONE_LIDX = {{(LIDX_W-1){1'b0}}, 1'b1};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= IDLE;
        done        <= 1'b0;
        ci          <= {IDX_W{1'b0}};
        cj          <= {IDX_W{1'b0}};
        ck          <= {IDX_W{1'b0}};
        acc         <= 32'd0;
        load_idx    <= {LIDX_W{1'b0}};
        cycle_count <= 32'd0;
    end else begin
        done <= 1'b0;
        case (state)

            IDLE: begin
                if (start) begin
                    state    <= LOAD;
                    load_idx <= {LIDX_W{1'b0}};
                end
            end

            LOAD: begin
                A_mem[load_idx] <= A_flat[load_idx*16 +: 16];
                B_mem[load_idx] <= B_flat[load_idx*16 +: 16];
                if (load_idx == (NN-1)) begin
                    state       <= COMPUTE;
                    ci          <= {IDX_W{1'b0}};
                    cj          <= {IDX_W{1'b0}};
                    ck          <= {IDX_W{1'b0}};
                    acc         <= 32'd0;
                    cycle_count <= 32'd0;
                    for (gi = 0; gi < N; gi = gi + 1)
                        for (gj = 0; gj < N; gj = gj + 1)
                            C_mem[gi*N+gj] <= 32'd0;
                end else
                    load_idx <= load_idx + ONE_LIDX;
            end

            COMPUTE: begin
                cycle_count <= cycle_count + 32'd1;
                acc <= acc + (A_mem[ci*N + ck] * B_mem[ck*N + cj]);

                if (ck == (N-1)) begin
                    C_mem[ci*N + cj] <= acc + (A_mem[ci*N + ck] * B_mem[ck*N + cj]);
                    ck  <= {IDX_W{1'b0}};
                    acc <= 32'd0;
                    if (cj == (N-1)) begin
                        cj <= {IDX_W{1'b0}};
                        if (ci == (N-1)) begin
                            state    <= WRITEC;
                            load_idx <= {LIDX_W{1'b0}};
                        end else
                            ci <= ci + ONE_IDX;
                    end else
                        cj <= cj + ONE_IDX;
                end else
                    ck <= ck + ONE_IDX;
            end

            WRITEC: begin
                C_flat[load_idx*32 +: 32] <= C_mem[load_idx];
                if (load_idx == (NN-1))
                    state <= FINISH;
                else
                    load_idx <= load_idx + ONE_LIDX;
            end

            FINISH: begin
                done  <= 1'b1;
                state <= IDLE;
            end

        endcase
    end
end

endmodule
