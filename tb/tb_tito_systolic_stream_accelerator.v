`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_stream_accelerator;
    localparam integer N = 4;
    localparam integer K = 4;
    localparam integer DATA_W = 8;
    localparam integer ACC_W = 32;
    localparam integer ADDR_W = 4;

    reg clk, resetb, wr_en, wr_bank, start;
    reg [ADDR_W-1:0] wr_addr;
    reg [DATA_W-1:0] wr_data;
    wire [N*N*ACC_W-1:0] accum_out;
    wire busy, done;

    integer a_ref [0:N-1][0:K-1];
    integer b_ref [0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];
    integer i, j, k, checks, cycles;

    tito_systolic_stream_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W), .ADDR_W(ADDR_W)
    ) dut (
        .clk(clk), .resetb(resetb),
        .wr_en(wr_en), .wr_bank(wr_bank), .wr_addr(wr_addr), .wr_data(wr_data),
        .start(start), .accum_out(accum_out), .busy(busy), .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        clk=0; resetb=0; wr_en=0; wr_bank=0; wr_addr=0; wr_data=0;
        start=0; checks=0; cycles=0;
        repeat (3) @(negedge clk);
        resetb=1;

        // Deterministic signed matrices, including negative operands.
        for (i = 0; i < N; i = i + 1) begin
            for (k = 0; k < K; k = k + 1)
                a_ref[i][k] = ((i*7 + k*3) % 15) - 7;
        end
        for (k = 0; k < K; k = k + 1) begin
            for (j = 0; j < N; j = j + 1)
                b_ref[k][j] = ((k*5 + j*2) % 13) - 6;
        end
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                expected[i][j] = 0;
                for (k = 0; k < K; k = k + 1)
                    expected[i][j] = expected[i][j] + a_ref[i][k]*b_ref[k][j];
            end
        end

        // A write address is row*K+k. B write address is k*N+column.
        // The hardware maps these linear addresses into row/column banks.
        for (i = 0; i < N; i = i + 1) begin
            for (k = 0; k < K; k = k + 1) begin
                @(negedge clk);
                wr_en=1; wr_bank=0; wr_addr=i*K+k; wr_data=a_ref[i][k];
            end
        end
        @(negedge clk);
        wr_en=0;
        for (k = 0; k < K; k = k + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                @(negedge clk);
                wr_en=1; wr_bank=1; wr_addr=k*N+j; wr_data=b_ref[k][j];
            end
        end
        @(negedge clk);
        wr_en=0; wr_addr=0; wr_data=0;

        @(negedge clk);
        start=1;
        @(negedge clk);
        start=0;
        if (!busy) begin
            $display("FAIL: streaming accelerator busy did not assert after start");
            $fatal(1);
        end

        cycles=0;
        while (!done && cycles < 200) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (!done) begin
            $display("FAIL: streaming accelerator timed out");
            $fatal(1);
        end

        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                checks=checks+1;
                if ($signed(accum_out[((i*N+j)*ACC_W) +: ACC_W]) !== expected[i][j]) begin
                    $display("FAIL streaming matmul PE(%0d,%0d): got %0d expected %0d",
                        i, j, $signed(accum_out[((i*N+j)*ACC_W) +: ACC_W]),
                        expected[i][j]);
                    $fatal(1);
                end
            end
        end

        @(negedge clk);
        if (busy) begin
            $display("FAIL: busy remained asserted after done");
            $fatal(1);
        end
        $display("PASS: banked streaming accelerator (%0d outputs, %0d cycles)",
            checks, cycles);
        $finish;
    end

    initial begin
        #20000;
        $display("TIMEOUT: banked streaming accelerator test");
        $fatal(1);
    end
endmodule

`default_nettype wire
