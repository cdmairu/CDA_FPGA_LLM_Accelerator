// =============================================================================
// matmul_core.v  –  Parameterized Sequential Matrix Multiplier
//
//  Supports N = 4, 8, or 16 (set via parameter).
//  One multiply-accumulate unit; iterates over i, j, k counters.
//  Latency ≈ N³ clock cycles.
//
//  Inputs  A, B : N×N signed 16-bit matrices (flattened, row-major)
//  Output  C    : N×N signed 32-bit matrix   (flattened, row-major)
// =============================================================================
module matmul_core #(
    parameter N = 4                     // matrix dimension
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // matrix data ports (registered externally, just read here)
    input  wire signed [16*N*N-1:0]    A_flat,   // [row*N+col] × 16 bits
    input  wire signed [16*N*N-1:0]    B_flat,

    // control
    input  wire                         start,
    output reg                          done,

    // result
    output reg  signed [32*N*N-1:0]    C_flat,

    // performance counter
    output reg  [31:0]                  cycle_count
);

localparam NN = N * N;
localparam IDX_W = $clog2(N);  // bit width for i/j/k counters

// ------------- internal memories -------------
reg signed [15:0] A_mem [0:NN-1];
reg signed [15:0] B_mem [0:NN-1];
reg signed [31:0] C_mem [0:NN-1];

// ------------- counters ----------------------
reg [IDX_W-1:0] ci, cj, ck;
reg signed [31:0] acc;

// ------------- FSM ---------------------------
localparam IDLE    = 3'd0,
           LOAD    = 3'd1,
           COMPUTE = 3'd2,
           WRITEC  = 3'd3,
           FINISH  = 3'd4;

reg [2:0] state;
reg [6:0] load_idx;   // up to N*N = 256 max → needs 8 bits for N=16

// ------------- helper integer for loads ------
integer gi, gj;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= IDLE;
        done        <= 0;
        ci          <= 0;
        cj          <= 0;
        ck          <= 0;
        acc         <= 0;
        load_idx    <= 0;
        cycle_count <= 0;
    end else begin
        done <= 0;
        case (state)

            // -------------------------------------------------
            IDLE: begin
                if (start) begin
                    state    <= LOAD;
                    load_idx <= 0;
                end
            end

            // -------------------------------------------------
            // Copy A_flat / B_flat into local memories
            // (one element per cycle to keep timing clean)
            LOAD: begin
                A_mem[load_idx] <= A_flat[load_idx*16 +: 16];
                B_mem[load_idx] <= B_flat[load_idx*16 +: 16];
                if (load_idx == NN-1) begin
                    state        <= COMPUTE;
                    ci           <= 0;
                    cj           <= 0;
                    ck           <= 0;
                    acc          <= 0;
                    cycle_count  <= 0;
                    // zero C_mem
                    for (gi = 0; gi < N; gi = gi + 1)
                        for (gj = 0; gj < N; gj = gj + 1)
                            C_mem[gi*N+gj] <= 0;
                end else
                    load_idx <= load_idx + 1;
            end

            // -------------------------------------------------
            // Sequential MAC:  acc += A[i][k] * B[k][j]
            COMPUTE: begin
                cycle_count <= cycle_count + 1;
                acc <= acc + (A_mem[ci*N + ck] * B_mem[ck*N + cj]);

                if (ck == N-1) begin
                    // inner loop done → write C[i][j]
                    C_mem[ci*N + cj] <= acc + (A_mem[ci*N + ck] * B_mem[ck*N + cj]);
                    ck  <= 0;
                    acc <= 0;
                    if (cj == N-1) begin
                        cj <= 0;
                        if (ci == N-1) begin
                            state <= WRITEC;
                            load_idx <= 0;
                        end else
                            ci <= ci + 1;
                    end else
                        cj <= cj + 1;
                end else begin
                    ck <= ck + 1;
                end
            end

            // -------------------------------------------------
            // Flatten C_mem back into C_flat (one element per cycle)
            WRITEC: begin
                C_flat[load_idx*32 +: 32] <= C_mem[load_idx];
                if (load_idx == NN-1)
                    state <= FINISH;
                else
                    load_idx <= load_idx + 1;
            end

            // -------------------------------------------------
            FINISH: begin
                done  <= 1;
                state <= IDLE;
            end

        endcase
    end
end

endmodule
