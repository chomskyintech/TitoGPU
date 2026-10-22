`timescale 1ns/1ps
`default_nettype none

// End-to-end regression for a matrix reduction larger than the local K tile.
// K_TOTAL=9 is processed as three K=4 commands; the final tile is zero-padded.
module tb_tito_systolic_k_tiling;
    localparam integer N = 4;
    localparam integer K_TILE = 4;
    localparam integer K_TOTAL = 9;
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

    integer expected [0:N-1][0:N-1];
    integer tile, i, j, k, global_k, value_a, value_b, cycles, checks;

    tito_systolic_command_accelerator #(
        .N(N), .K(K_TILE), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W)
    ) dut (
        .clk(clk), .resetb(resetb),
        .mem_wr_en(mem_wr_en), .mem_wr_ready(mem_wr_ready), .mem_wr_bank(mem_wr_bank),
        .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data),
        .cmd_start(cmd_start), .cmd_accumulate(cmd_accumulate),
        .busy(busy), .done(done),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    always #5 clk = ~clk;

    function integer a_value;
        input integer row;
        input integer reduction_index;
        begin
            a_value = ((row*3 + reduction_index*2) % 11) - 5;
        end
    endfunction

    function integer b_value;
        input integer reduction_index;
        input integer column;
        begin
            b_value = ((reduction_index*5 + column*3) % 9) - 4;
        end
    endfunction

    task run_command;
        input integer accumulate;
        begin
            @(negedge clk);
            cmd_accumulate = (accumulate != 0);
            cmd_start = 1'b1;
            @(negedge clk);
            cmd_start = 1'b0;
            cycles = 0;
            while (!done && cycles < 500) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!done || busy) begin
                $display("FAIL: K tile command timed out or busy did not clear (tile=%0d)", tile);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk=0; resetb=0; mem_wr_en=0; mem_wr_bank=0; mem_wr_addr=0;
        mem_wr_data=0; cmd_start=0; cmd_accumulate=0;
        result_rd_en=0; result_rd_addr=0; checks=0; cycles=0; tile=0;
        repeat (3) @(negedge clk);
        resetb=1;

        // Independent reference for a 4x9 by 9x4 multiplication.
        for (i=0; i<N; i=i+1) begin
            for (j=0; j<N; j=j+1) begin
                expected[i][j]=0;
                for (k=0; k<K_TOTAL; k=k+1)
                    expected[i][j] = expected[i][j] + a_value(i,k)*b_value(k,j);
            end
        end

        // Load and execute three local tiles. Tile 0 replaces results; tiles
        // 1 and 2 add their partial sums. Invalid positions in tile 2 are zero.
        for (tile=0; tile<3; tile=tile+1) begin
            for (i=0; i<N; i=i+1) begin
                for (k=0; k<K_TILE; k=k+1) begin
                    @(negedge clk);
                    global_k = tile*K_TILE + k;
                    value_a = (global_k < K_TOTAL) ? a_value(i,global_k) : 0;
                    mem_wr_en=1; mem_wr_bank=0; mem_wr_addr=i*K_TILE+k;
                    mem_wr_data=value_a;
                end
            end
            for (k=0; k<K_TILE; k=k+1) begin
                for (j=0; j<N; j=j+1) begin
                    @(negedge clk);
                    global_k = tile*K_TILE + k;
                    value_b = (global_k < K_TOTAL) ? b_value(global_k,j) : 0;
                    mem_wr_en=1; mem_wr_bank=1; mem_wr_addr=k*N+j;
                    mem_wr_data=value_b;
                end
            end
            @(negedge clk);
            mem_wr_en=0; mem_wr_addr=0; mem_wr_data=0;
            run_command(tile != 0);
        end

        for (i=0; i<N; i=i+1) begin
            for (j=0; j<N; j=j+1) begin
                @(negedge clk);
                result_rd_en=1; result_rd_addr=i*N+j;
                @(negedge clk);
                if (!result_rd_valid || $signed(result_rd_data) !== expected[i][j]) begin
                    $display("FAIL K-tiled result[%0d,%0d]: got %0d expected %0d",
                        i,j,$signed(result_rd_data),expected[i][j]);
                    $fatal(1);
                end
                checks=checks+1;
            end
        end
        @(negedge clk);
        result_rd_en=0;

        // Repeat the identical matrix operation without resetting result_mem.
        // The first tile must replace prior results; otherwise this second pass
        // would double the previously completed output matrix.
        for (tile=0; tile<3; tile=tile+1) begin
            for (i=0; i<N; i=i+1) begin
                for (k=0; k<K_TILE; k=k+1) begin
                    @(negedge clk);
                    global_k = tile*K_TILE + k;
                    value_a = (global_k < K_TOTAL) ? a_value(i,global_k) : 0;
                    mem_wr_en=1; mem_wr_bank=0; mem_wr_addr=i*K_TILE+k;
                    mem_wr_data=value_a;
                end
            end
            for (k=0; k<K_TILE; k=k+1) begin
                for (j=0; j<N; j=j+1) begin
                    @(negedge clk);
                    global_k = tile*K_TILE + k;
                    value_b = (global_k < K_TOTAL) ? b_value(global_k,j) : 0;
                    mem_wr_en=1; mem_wr_bank=1; mem_wr_addr=k*N+j;
                    mem_wr_data=value_b;
                end
            end
            @(negedge clk);
            mem_wr_en=0; mem_wr_addr=0; mem_wr_data=0;
            run_command(tile != 0);
        end

        for (i=0; i<N; i=i+1) begin
            for (j=0; j<N; j=j+1) begin
                @(negedge clk);
                result_rd_en=1; result_rd_addr=i*N+j;
                @(negedge clk);
                if (!result_rd_valid || $signed(result_rd_data) !== expected[i][j]) begin
                    $display("FAIL repeated K-tiled result[%0d,%0d]: got %0d expected %0d",
                        i,j,$signed(result_rd_data),expected[i][j]);
                    $fatal(1);
                end
                checks=checks+1;
            end
        end
        @(negedge clk);
        result_rd_en=0;
        $display("PASS: K-dimension tiling K_TOTAL=%0d across 3 tiles, repeated operation, %0d output checks",
            K_TOTAL, checks);
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT: K-dimension tiling test");
        $fatal(1);
    end
endmodule

`default_nettype wire
