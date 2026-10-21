`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_mac;
    localparam N = 2;
    localparam DATA_W = 8;
    localparam ACC_W = 32;
    localparam K = 2;

    reg clk, resetb, clear, enable;
    reg [N-1:0] a_valid, b_valid;
    reg [N*DATA_W-1:0] a_in, b_in;
    wire [N*N*ACC_W-1:0] accum_out;
    reg signed [7:0] matrix_a [0:N-1][0:K-1];
    reg signed [7:0] matrix_b [0:K-1][0:N-1];
    integer i, j, t;
    integer checks;

    tito_systolic_mac #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .resetb(resetb), .clear(clear), .enable(enable),
        .a_valid(a_valid), .b_valid(b_valid), .a_in(a_in), .b_in(b_in),
        .accum_out(accum_out)
    );

    always #5 clk = ~clk;

    task run_and_check;
        input signed [31:0] expected00;
        input signed [31:0] expected01;
        input signed [31:0] expected10;
        input signed [31:0] expected11;
        begin
            @(negedge clk);
            clear = 1'b1;
            @(negedge clk);
            clear = 1'b0;

            // Feed row/column streams skewed by row/column index.
            for (t = 0; t < K + N - 1; t = t + 1) begin
                @(negedge clk);
                a_valid = 0;
                b_valid = 0;
                a_in = 0;
                b_in = 0;
                for (i = 0; i < N; i = i + 1) begin
                    if ((t >= i) && ((t-i) < K)) begin
                        a_valid[i] = 1'b1;
                        a_in[i*DATA_W +: DATA_W] = matrix_a[i][t-i];
                    end
                end
                for (j = 0; j < N; j = j + 1) begin
                    if ((t >= j) && ((t-j) < K)) begin
                        b_valid[j] = 1'b1;
                        b_in[j*DATA_W +: DATA_W] = matrix_b[t-j][j];
                    end
                end
            end

            // Stop injecting, then drain the remaining registered values.
            @(negedge clk);
            a_valid = 0;
            b_valid = 0;
            a_in = 0;
            b_in = 0;
            repeat (N+1) @(negedge clk);
            #1;
            checks = checks + 1;
            if (($signed(accum_out[0*ACC_W +: ACC_W]) !== expected00) ||
                ($signed(accum_out[1*ACC_W +: ACC_W]) !== expected01) ||
                ($signed(accum_out[2*ACC_W +: ACC_W]) !== expected10) ||
                ($signed(accum_out[3*ACC_W +: ACC_W]) !== expected11)) begin
                $display("FAIL systolic outputs got [%0d %0d; %0d %0d], expected [%0d %0d; %0d %0d]",
                    $signed(accum_out[0*ACC_W +: ACC_W]),
                    $signed(accum_out[1*ACC_W +: ACC_W]),
                    $signed(accum_out[2*ACC_W +: ACC_W]),
                    $signed(accum_out[3*ACC_W +: ACC_W]),
                    expected00, expected01, expected10, expected11);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk=0; resetb=0; clear=0; enable=1;
        a_valid=0; b_valid=0; a_in=0; b_in=0;
        checks=0;
        repeat (3) @(negedge clk);
        resetb=1;

        matrix_a[0][0]=1; matrix_a[0][1]=2;
        matrix_a[1][0]=3; matrix_a[1][1]=4;
        matrix_b[0][0]=5; matrix_b[0][1]=6;
        matrix_b[1][0]=7; matrix_b[1][1]=8;
        run_and_check(19, 22, 43, 50);

        matrix_a[0][0]=-1; matrix_a[0][1]=2;
        matrix_a[1][0]=-3; matrix_a[1][1]=4;
        matrix_b[0][0]=5; matrix_b[0][1]=-6;
        matrix_b[1][0]=7; matrix_b[1][1]=8;
        run_and_check(9, 22, 13, 50);

        // Exercise the signed INT8 endpoints and verify products are sign-extended
        // before accumulation into the 32-bit result.
        matrix_a[0][0]=-128; matrix_a[0][1]=-128;
        matrix_a[1][0]=127;  matrix_a[1][1]=-128;
        matrix_b[0][0]=-128; matrix_b[0][1]=127;
        matrix_b[1][0]=127;  matrix_b[1][1]=-128;
        run_and_check(128, 128, -32512, 32513);

        $display("PASS: systolic MAC matrix tests (%0d matrices)", checks);
        $finish;
    end

    initial begin
        #5000;
        $display("TIMEOUT: systolic MAC tests");
        $fatal(1);
    end
endmodule

`default_nettype wire
