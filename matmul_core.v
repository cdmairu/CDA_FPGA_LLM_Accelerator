// =============================================================================
// tb_matmul_core.v  –  Testbench for matmul_core
//
//  Tests three cases for each supported N:
//    1. Identity × B  → should return B
//    2. Known-value multiply with hand-checked result
//    3. Random-ish values verified by repeated golden model (software loop)
//
//  Run with: iverilog -o sim tb_matmul_core.v matmul_core.v && vvp sim
// =============================================================================
`timescale 1ns/1ps

module tb_matmul_core;

// ---- DUT parameters ----
localparam N   = 4;
localparam NN  = N * N;
localparam CLK = 10; // 10 ns → 100 MHz simulation clock

reg                      clk, rst_n, start;
wire                     done;
wire [31:0]              cycle_count;

reg  signed [16*NN-1:0] A_flat;
reg  signed [16*NN-1:0] B_flat;
wire signed [32*NN-1:0] C_flat;

// ---- instantiate DUT ----
matmul_core #(.N(N)) dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .A_flat      (A_flat),
    .B_flat      (B_flat),
    .start       (start),
    .done        (done),
    .C_flat      (C_flat),
    .cycle_count (cycle_count)
);

// ---- clock ----
initial clk = 0;
always #(CLK/2) clk = ~clk;

// ---- helper tasks ----
integer i, j, k;
integer pass_cnt, fail_cnt;
reg signed [15:0] A_arr [0:NN-1];
reg signed [15:0] B_arr [0:NN-1];
reg signed [31:0] C_exp [0:NN-1];
reg signed [31:0] c_got;

// Pack arrays into flat buses
task pack_AB;
    integer idx;
    begin
        for (idx = 0; idx < NN; idx = idx + 1) begin
            A_flat[idx*16 +: 16] = A_arr[idx];
            B_flat[idx*16 +: 16] = B_arr[idx];
        end
    end
endtask

// Compute golden result
task golden;
    integer ri, rj, rk;
    begin
        for (ri = 0; ri < N; ri = ri + 1)
            for (rj = 0; rj < N; rj = rj + 1) begin
                C_exp[ri*N+rj] = 0;
                for (rk = 0; rk < N; rk = rk + 1)
                    C_exp[ri*N+rj] = C_exp[ri*N+rj] +
                                     ($signed(A_arr[ri*N+rk]) * $signed(B_arr[rk*N+rj]));
            end
    end
endtask

// Fire start pulse and wait for done
task run_and_check;
    input [63:0] test_id;
    integer chk;
    begin
        @(posedge clk); #1;
        start = 1;
        @(posedge clk); #1;
        start = 0;

        // Wait for done with timeout
        begin : wait_done
            integer timeout;
            timeout = 0;
            while (!done) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
                if (timeout > 100000) begin
                    $display("TIMEOUT on test %0d", test_id);
                    disable wait_done;
                end
            end
        end

        // Check results
        golden;
        for (chk = 0; chk < NN; chk = chk + 1) begin
            c_got = C_flat[chk*32 +: 32];
            if (c_got !== C_exp[chk]) begin
                $display("FAIL test=%0d idx=%0d  got=%0d  exp=%0d",
                         test_id, chk, c_got, C_exp[chk]);
                fail_cnt = fail_cnt + 1;
            end else
                pass_cnt = pass_cnt + 1;
        end
        $display("Test %0d: cycles=%0d", test_id, cycle_count);
    end
endtask

// ---- stimulus ----
initial begin
    $dumpfile("tb_matmul_core.vcd");
    $dumpvars(0, tb_matmul_core);
    pass_cnt = 0;
    fail_cnt = 0;

    rst_n = 0; start = 0;
    A_flat = 0; B_flat = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    @(posedge clk); #1;

    // ---- Test 1: Identity × B ----
    $display("--- Test 1: I x B ---");
    for (i = 0; i < N; i = i + 1)
        for (j = 0; j < N; j = j + 1) begin
            A_arr[i*N+j] = (i == j) ? 16'sd1 : 16'sd0;  // identity
            B_arr[i*N+j] = i*N+j;                         // 0,1,2,...
        end
    pack_AB;
    run_and_check(1);

    // ---- Test 2: All-ones × All-ones  (each C[i][j] = N) ----
    $display("--- Test 2: 1s x 1s ---");
    for (i = 0; i < NN; i = i + 1) begin
        A_arr[i] = 16'sd1;
        B_arr[i] = 16'sd1;
    end
    pack_AB;
    run_and_check(2);

    // ---- Test 3: Larger values ----
    $display("--- Test 3: Counted values ---");
    for (i = 0; i < NN; i = i + 1) begin
        A_arr[i] = $signed(i + 1);
        B_arr[i] = $signed(NN - i);
    end
    pack_AB;
    run_and_check(3);

    // ---- Test 4: Negative values ----
    $display("--- Test 4: Mixed negatives ---");
    for (i = 0; i < N; i = i + 1)
        for (j = 0; j < N; j = j + 1) begin
            A_arr[i*N+j] = (i[0]) ? -$signed(i*N+j+1) : $signed(i*N+j+1);
            B_arr[i*N+j] = (j[0]) ? -$signed(j*N+i+1) : $signed(j*N+i+1);
        end
    pack_AB;
    run_and_check(4);

    // ---- Summary ----
    $display("============================");
    $display("PASS: %0d / %0d checks", pass_cnt, pass_cnt+fail_cnt);
    if (fail_cnt == 0) $display("ALL TESTS PASSED");
    else               $display("FAILURES: %0d", fail_cnt);
    $display("============================");
    $finish;
end

endmodule
