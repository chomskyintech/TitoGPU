`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_command_accelerator;
    localparam integer N = 4;
    localparam integer K = 4;
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

    integer a_ref [0:N-1][0:K-1];
    integer b_ref [0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];
    integer i, j, k, checks, cycles;

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

    initial begin
        clk=0; resetb=0; mem_wr_en=0; mem_wr_bank=0; mem_wr_addr=0;
        mem_wr_data=0; cmd_start=0; cmd_accumulate=0; result_rd_en=0; result_rd_addr=0;
        checks=0; cycles=0;
        repeat (3) @(negedge clk);
        resetb=1;
        @(negedge clk);
        if (!mem_wr_ready) begin
            $display("FAIL: memory write port should be ready while idle");
            $fatal(1);
        end

        // Signed matrices with deterministic nontrivial values.
        for (i = 0; i < N; i = i + 1)
            for (k = 0; k < K; k = k + 1)
                a_ref[i][k] = ((i*7 + k*3) % 15) - 7;
        for (k = 0; k < K; k = k + 1)
            for (j = 0; j < N; j = j + 1)
                b_ref[k][j] = ((k*5 + j*2) % 13) - 6;
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                expected[i][j] = 0;
                for (k = 0; k < K; k = k + 1)
                    expected[i][j] = expected[i][j] + a_ref[i][k]*b_ref[k][j];
            end

        // Load A[row][k] at row-major address row*K+k.
        for (i = 0; i < N; i = i + 1)
            for (k = 0; k < K; k = k + 1) begin
                @(negedge clk);
                mem_wr_en=1; mem_wr_bank=0; mem_wr_addr=i*K+k;
                mem_wr_data=a_ref[i][k];
            end
        // Load B[k][column] at row-major address k*N+column.
        for (k = 0; k < K; k = k + 1)
            for (j = 0; j < N; j = j + 1) begin
                @(negedge clk);
                mem_wr_en=1; mem_wr_bank=1; mem_wr_addr=k*N+j;
                mem_wr_data=b_ref[k][j];
            end
        @(negedge clk);
        mem_wr_en=0; mem_wr_addr=0; mem_wr_data=0;

        // A command is a one-cycle pulse. done must wait for result writeback.
        @(negedge clk); cmd_start=1;
        @(negedge clk); cmd_start=0;
        if (!busy || mem_wr_ready) begin
            $display("FAIL: command wrapper must assert busy and deassert memory ready after start");
            $fatal(1);
        end

        // While the command is in flight, try to corrupt A[0] and issue
        // another start pulse. Both requests must be ignored while busy.
        @(negedge clk);
        mem_wr_en=1; mem_wr_bank=0; mem_wr_addr=0;
        mem_wr_data=8'd127; cmd_start=1;
        @(negedge clk);
        mem_wr_en=0; cmd_start=0;
        if (!busy) begin
            $display("FAIL: busy dropped after an ignored start pulse");
            $fatal(1);
        end

        cycles=0;
        while (!done && cycles < 300) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (!done) begin
            $display("FAIL: command wrapper timed out before writeback completion");
            $fatal(1);
        end
        if (busy || !mem_wr_ready) begin
            $display("FAIL: busy should deassert and memory ready should assert when done is asserted");
            $fatal(1);
        end

        // Read each result through the synchronous host-facing result port.
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                @(negedge clk);
                result_rd_en=1; result_rd_addr=i*N+j;
                @(negedge clk);
                if (!result_rd_valid) begin
                    $display("FAIL: result read-valid missing at address %0d", i*N+j);
                    $fatal(1);
                end
                checks=checks+1;
                if ($signed(result_rd_data) !== expected[i][j]) begin
                    $display("FAIL result[%0d,%0d] addr %0d: got %0d expected %0d",
                        i, j, i*N+j, $signed(result_rd_data), expected[i][j]);
                    $fatal(1);
                end
            end
        @(negedge clk);
        result_rd_en=0;
        @(negedge clk);
        if (result_rd_valid) begin
            $display("FAIL: result_rd_valid should clear without a read request");
            $fatal(1);
        end

        // A start pulse during WRITEBACK must be ignored. It must not queue
        // a second operation after the current command completes.
        @(negedge clk); cmd_start=1;
        @(negedge clk); cmd_start=0;
        cycles=0;
        while ((dut.state != 2'd2) && cycles < 300) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (dut.state != 2'd2) begin
            $display("FAIL: command never reached WRITEBACK for busy-start test");
            $fatal(1);
        end
        // Avoid the final writeback cycle so the pulse is unambiguously busy.
        if (dut.writeback_idx == N*N-1) @(negedge clk);
        cmd_start=1;
        @(negedge clk); cmd_start=0;
        if (!busy) begin
            $display("FAIL: busy dropped after start pulse during WRITEBACK");
            $fatal(1);
        end
        cycles=0;
        while (!done && cycles < 300) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (!done || busy) begin
            $display("FAIL: writeback command did not complete cleanly");
            $fatal(1);
        end
        repeat (3) begin
            @(negedge clk);
            if (busy || done) begin
                $display("FAIL: start pulse during WRITEBACK queued an unintended command");
                $fatal(1);
            end
        end

        // Launch another operation, then assert reset while it is computing.
        // Reset must abort the in-flight command and allow a clean restart.
        @(negedge clk); cmd_start=1;
        @(negedge clk); cmd_start=0;
        repeat (4) @(negedge clk);
        if (!busy) begin
            $display("FAIL: expected busy before mid-compute reset");
            $fatal(1);
        end
        resetb=0;
        #1;
        if (busy || done || result_rd_valid) begin
            $display("FAIL: reset did not clear command status");
            $fatal(1);
        end
        repeat (2) @(negedge clk);
        resetb=1;

        // Restart from the retained operand memories and verify recovery.
        @(negedge clk); cmd_start=1;
        @(negedge clk); cmd_start=0;
        cycles=0;
        while (!done && cycles < 300) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (!done || busy) begin
            $display("FAIL: accelerator did not recover after reset");
            $fatal(1);
        end
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                @(negedge clk);
                result_rd_en=1; result_rd_addr=i*N+j;
                @(negedge clk);
                if (!result_rd_valid || $signed(result_rd_data) !== expected[i][j]) begin
                    $display("FAIL after reset result[%0d,%0d]: got %0d expected %0d",
                        i, j, $signed(result_rd_data), expected[i][j]);
                    $fatal(1);
                end
                checks=checks+1;
            end
        @(negedge clk); result_rd_en=0;

        $display("PASS: command interface, reset recovery, and result writeback (%0d results, %0d cycles)",
            checks, cycles);
        $finish;
    end

    initial begin
        #30000;
        $display("TIMEOUT: command accelerator test");
        $fatal(1);
    end
endmodule

`default_nettype wire
