`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_matmul;
    localparam integer N = 4;
    localparam integer K = 4;
    localparam integer DATA_W = 8;
    localparam integer ACC_W = 32;

    reg clk, resetb, start;
    reg [N*K*DATA_W-1:0] a_matrix;
    reg [K*N*DATA_W-1:0] b_matrix;
    wire [N*N*ACC_W-1:0] accum_out;
    wire busy, done;

    integer a_ref [0:N-1][0:K-1];
    integer b_ref [0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];
    integer i, j, k, checks, cycles;

    tito_systolic_matmul #(.N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .resetb(resetb), .start(start),
        .a_matrix(a_matrix), .b_matrix(b_matrix),
        .accum_out(accum_out), .busy(busy), .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        clk=0; resetb=0; start=0;
        a_matrix=0; b_matrix=0; checks=0; cycles=0;
        repeat (3) @(negedge clk);
        resetb=1;

        // Deterministic signed matrices, including negative operands.
        for (i = 0; i < N; i = i + 1) begin
            for (k = 0; k < K; k = k + 1) begin
                a_ref[i][k] = ((i*7 + k*3) % 15) - 7;
                a_matrix[((i*K+k)*DATA_W) +: DATA_W] = a_ref[i][k];
            end
        end
        for (k = 0; k < K; k = k + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                b_ref[k][j] = ((k*5 + j*2) % 13) - 6;
                b_matrix[((k*N+j)*DATA_W) +: DATA_W] = b_ref[k][j];
            end
        end
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                expected[i][j] = 0;
                for (k = 0; k < K; k = k + 1)
                    expected[i][j] = expected[i][j] + a_ref[i][k]*b_ref[k][j];
            end
        end

        // One-cycle start pulse; the scheduler clears, feeds, drains, and completes.
        @(negedge clk);
        start=1;
        @(negedge clk);
        start=0;
        if (!busy) begin
            $display("FAIL: busy did not assert after start");
            $fatal(1);
        end

        cycles=0;
        while (!done && cycles < 200) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (!done) begin
            $display("FAIL: scheduler timed out");
            $fatal(1);
        end

        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                checks = checks + 1;
                if ($signed(accum_out[((i*N+j)*ACC_W) +: ACC_W]) !== expected[i][j]) begin
                    $display("FAIL matmul PE(%0d,%0d): got %0d expected %0d",
                        i, j, $signed(accum_out[((i*N+j)*ACC_W) +: ACC_W]),
                        expected[i][j]);
                    $fatal(1);
                end
            end
        end

        @(negedge clk);
        if (busy) begin
            $display("FAIL: busy remained asserted after completion");
            $fatal(1);
        end
        $display("PASS: scheduled N4 matmul (%0d output checks, %0d cycles to done)",
            checks, cycles);
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT: scheduled matmul test");
        $fatal(1);
    end
endmodule

`default_nettype wire
