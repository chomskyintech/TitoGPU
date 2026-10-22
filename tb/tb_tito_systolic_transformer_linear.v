`timescale 1ns/1ps
`default_nettype none

// Exercises the host tile protocol for a 16x16 linear operation using the
// existing 4x4 command wrapper. This is integer GEMM plumbing validation,
// not transformer execution or quantized-model accuracy validation.
module tb_tito_systolic_transformer_linear;
    localparam integer N = 4;
    localparam integer K = 4;
    localparam integer WIDTH = 16;
    localparam integer DATA_W = 8;
    localparam integer ACC_W = 32;
    localparam integer MEM_ADDR_W = 4;
    localparam integer RESULT_ADDR_W = 4;

    reg clk, resetb, mem_wr_en, mem_wr_bank, cmd_start, cmd_accumulate, result_rd_en;
    reg [MEM_ADDR_W-1:0] mem_wr_addr;
    reg [DATA_W-1:0] mem_wr_data;
    reg [RESULT_ADDR_W-1:0] result_rd_addr;
    wire busy, done, result_rd_valid, mem_wr_ready;
    wire [ACC_W-1:0] result_rd_data;

    integer a_full [0:WIDTH-1][0:WIDTH-1];
    integer b_full [0:WIDTH-1][0:WIDTH-1];
    integer expected [0:WIDTH-1][0:WIDTH-1];
    integer row_block, col_block, k_block, i, j, k;
    integer cycles, checks;

    tito_systolic_command_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W)
    ) dut (
        .clk(clk), .resetb(resetb),
        .mem_wr_en(mem_wr_en), .mem_wr_ready(mem_wr_ready), .mem_wr_bank(mem_wr_bank),
        .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data),
        .cmd_start(cmd_start), .cmd_accumulate(cmd_accumulate), .busy(busy), .done(done),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    always #5 clk = ~clk;

    task write_operand;
        input integer bank;
        input integer address;
        input integer value;
        begin
            @(negedge clk);
            while (!mem_wr_ready) @(negedge clk);
            mem_wr_en = 1'b1;
            mem_wr_bank = bank;
            mem_wr_addr = address;
            mem_wr_data = value;
            @(negedge clk);
            mem_wr_en = 1'b0;
        end
    endtask

    task run_tile;
        input integer accumulate;
        begin
            @(negedge clk);
            while (!mem_wr_ready) @(negedge clk);
            cmd_accumulate = accumulate;
            cmd_start = 1'b1;
            @(negedge clk);
            cmd_start = 1'b0;
            cycles = 0;
            while (!done && cycles < 300) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!done || busy) begin
                $display("FAIL: tile command timeout or busy remained asserted");
                $fatal(1);
            end
        end
    endtask

    task check_result;
        input integer address;
        input integer reference_value;
        begin
            @(negedge clk);
            result_rd_en = 1'b1;
            result_rd_addr = address;
            @(negedge clk);
            if (!result_rd_valid) begin
                $display("FAIL: missing result_rd_valid at address %0d", address);
                $fatal(1);
            end
            if ($signed(result_rd_data) !== reference_value) begin
                $display("FAIL: result addr %0d got %0d expected %0d",
                    address, $signed(result_rd_data), reference_value);
                $fatal(1);
            end
            checks = checks + 1;
            result_rd_en = 1'b0;
        end
    endtask

    initial begin
        clk = 0;
        resetb = 0;
        mem_wr_en = 0;
        mem_wr_bank = 0;
        mem_wr_addr = 0;
        mem_wr_data = 0;
        cmd_start = 0;
        cmd_accumulate = 0;
        result_rd_en = 0;
        result_rd_addr = 0;
        checks = 0;
        cycles = 0;

        repeat (3) @(negedge clk);
        resetb = 1;

        // Deterministic signed matrices, with an independent full-size reference.
        for (i = 0; i < WIDTH; i = i + 1)
            for (k = 0; k < WIDTH; k = k + 1)
                a_full[i][k] = ((i*7 + k*3) % 15) - 7;
        for (k = 0; k < WIDTH; k = k + 1)
            for (j = 0; j < WIDTH; j = j + 1)
                b_full[k][j] = ((k*5 + j*2) % 13) - 6;
        for (i = 0; i < WIDTH; i = i + 1)
            for (j = 0; j < WIDTH; j = j + 1) begin
                expected[i][j] = 0;
                for (k = 0; k < WIDTH; k = k + 1)
                    expected[i][j] = expected[i][j] + a_full[i][k]*b_full[k][j];
            end

        // A 16x16 product requires 4x4 output tiles and four K tiles per output tile.
        // Each output tile uses replace mode for K tile 0, then accumulate mode.
        for (row_block = 0; row_block < WIDTH/N; row_block = row_block + 1) begin
            for (col_block = 0; col_block < WIDTH/N; col_block = col_block + 1) begin
                for (k_block = 0; k_block < WIDTH/K; k_block = k_block + 1) begin
                    // A tile layout: local row-major [N,K].
                    for (i = 0; i < N; i = i + 1)
                        for (k = 0; k < K; k = k + 1)
                            write_operand(0, i*K+k, a_full[row_block*N+i][k_block*K+k]);
                    // B tile layout: local row-major [K,N].
                    for (k = 0; k < K; k = k + 1)
                        for (j = 0; j < N; j = j + 1)
                            write_operand(1, k*N+j, b_full[k_block*K+k][col_block*N+j]);

                    run_tile(k_block != 0);
                end

                // Result addresses are local row-major [N,N].
                for (i = 0; i < N; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                        check_result(i*N+j, expected[row_block*N+i][col_block*N+j]);
            end
        end

        @(negedge clk);
        result_rd_en = 0;
        if (checks != WIDTH*WIDTH) begin
            $display("FAIL: checked %0d outputs, expected %0d", checks, WIDTH*WIDTH);
            $fatal(1);
        end
        $display("PASS: 16x16 GEMM via 4x4 output/K tiling (%0d outputs)", checks);
        $finish;
    end
endmodule

`default_nettype wire
