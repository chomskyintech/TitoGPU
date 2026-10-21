`timescale 1ns/1ps
`default_nettype none

// N=4 reference-model regression for signed INT8 systolic MAC.
// Reduction term k is deliberately bubbled on selected runs; both operand
// streams suppress the same k so alignment remains correct at every PE.
module tb_tito_systolic_mac_n4;
    localparam integer N = 4;
    localparam integer K = 4;
    localparam integer DATA_W = 8;
    localparam integer ACC_W = 32;

    reg clk, resetb, clear, enable;
    reg [N-1:0] a_valid, b_valid;
    reg [N*DATA_W-1:0] a_in, b_in;
    wire [N*N*ACC_W-1:0] accum_out;

    reg signed [7:0] matrix_a [0:N-1][0:K-1];
    reg signed [7:0] matrix_b [0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];
    integer i, j, k, t, checks, bubble_mode;

    tito_systolic_mac #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .resetb(resetb), .clear(clear), .enable(enable),
        .a_valid(a_valid), .b_valid(b_valid), .a_in(a_in), .b_in(b_in),
        .accum_out(accum_out)
    );

    always #5 clk = ~clk;

    function integer is_bubble;
        input integer term;
        input integer mode;
        begin
            is_bubble = mode && ((term == 1) || (term == 3));
        end
    endfunction

    task prepare_matrix;
        input integer pattern;
        begin
            for (i = 0; i < N; i = i + 1) begin
                for (k = 0; k < K; k = k + 1) begin
                    if (pattern == 0)
                        matrix_a[i][k] = ((i*7 + k*3) % 15) - 7;
                    else
                        matrix_a[i][k] = ((i*5 + k*4 + 2) % 17) - 8;
                end
            end
            for (k = 0; k < K; k = k + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    if (pattern == 0)
                        matrix_b[k][j] = ((k*5 + j*2) % 13) - 6;
                    else
                        matrix_b[k][j] = ((k*3 + j*7 + 1) % 19) - 9;
                end
            end
        end
    endtask

    task run_and_check;
        input integer mode;
        begin
            bubble_mode = mode;
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    expected[i][j] = 0;
                    for (k = 0; k < K; k = k + 1) begin
                        if (!is_bubble(k, bubble_mode))
                            expected[i][j] = expected[i][j] +
                                ($signed(matrix_a[i][k]) * $signed(matrix_b[k][j]));
                    end
                end
            end

            @(negedge clk);
            clear = 1'b1;
            @(negedge clk);
            clear = 1'b0;

            // Skew each row/column stream so matching k terms meet in each PE.
            for (t = 0; t < K + N - 1; t = t + 1) begin
                @(negedge clk);
                a_valid = 0;
                b_valid = 0;
                a_in = 0;
                b_in = 0;
                for (i = 0; i < N; i = i + 1) begin
                    k = t - i;
                    if ((k >= 0) && (k < K) && !is_bubble(k, bubble_mode)) begin
                        a_valid[i] = 1'b1;
                        a_in[i*DATA_W +: DATA_W] = matrix_a[i][k];
                    end
                end
                for (j = 0; j < N; j = j + 1) begin
                    k = t - j;
                    if ((k >= 0) && (k < K) && !is_bubble(k, bubble_mode)) begin
                        b_valid[j] = 1'b1;
                        b_in[j*DATA_W +: DATA_W] = matrix_b[k][j];
                    end
                end
            end

            @(negedge clk);
            a_valid = 0;
            b_valid = 0;
            a_in = 0;
            b_in = 0;
            repeat (N+2) @(negedge clk);
            #1;

            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    checks = checks + 1;
                    if ($signed(accum_out[((i*N+j)*ACC_W) +: ACC_W]) !== expected[i][j]) begin
                        $display("FAIL N4 mode=%0d PE(%0d,%0d): got %0d expected %0d",
                            mode, i, j,
                            $signed(accum_out[((i*N+j)*ACC_W) +: ACC_W]),
                            expected[i][j]);
                        $fatal(1);
                    end
                end
            end
        end
    endtask

    initial begin
        clk=0; resetb=0; clear=0; enable=1;
        a_valid=0; b_valid=0; a_in=0; b_in=0;
        checks=0; bubble_mode=0;
        repeat (3) @(negedge clk);
        resetb=1;

        // Disabled execution must not inject operands or change accumulators.
        enable=0;
        a_valid={N{1'b1}};
        b_valid={N{1'b1}};
        a_in={N{8'h03}};
        b_in={N{8'h04}};
        repeat (3) @(negedge clk);
        #1;
        for (i = 0; i < N*N; i = i + 1) begin
            if ($signed(accum_out[(i*ACC_W) +: ACC_W]) !== 0) begin
                $display("FAIL: accumulator changed while enable=0");
                $fatal(1);
            end
        end
        a_valid=0; b_valid=0; a_in=0; b_in=0;
        enable=1;

        prepare_matrix(0);
        run_and_check(0);
        prepare_matrix(1);
        run_and_check(1);

        // Clear must erase partial accumulated results and in-flight valids.
        @(negedge clk);
        a_valid={N{1'b1}};
        b_valid={N{1'b1}};
        a_in={N{8'h02}};
        b_in={N{8'h03}};
        @(negedge clk);
        clear=1;
        @(negedge clk);
        clear=0;
        a_valid=0; b_valid=0; a_in=0; b_in=0;
        repeat (N+1) @(negedge clk);
        #1;
        for (i = 0; i < N*N; i = i + 1) begin
            if ($signed(accum_out[(i*ACC_W) +: ACC_W]) !== 0) begin
                $display("FAIL: clear did not zero accumulator %0d", i);
                $fatal(1);
            end
        end

        $display("PASS: N4 systolic MAC reference regression (%0d PE comparisons)", checks);
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT: N4 systolic MAC regression");
        $fatal(1);
    end
endmodule

`default_nettype wire
