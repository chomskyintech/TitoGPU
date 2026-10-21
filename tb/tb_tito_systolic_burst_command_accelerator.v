`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_burst_command_accelerator;
    localparam integer N=4, K=4, DATA_W=8, ACC_W=32;
    localparam integer MEM_ADDR_W=4, RESULT_ADDR_W=4, BURST_LEN_W=5;

    reg clk, resetb;
    reg burst_start_valid, burst_bank, data_valid;
    reg [MEM_ADDR_W-1:0] burst_base_addr;
    reg [BURST_LEN_W-1:0] burst_len;
    reg [DATA_W-1:0] data;
    wire burst_start_ready, data_ready, burst_done, burst_error;
    reg cmd_start, cmd_accumulate, result_rd_en;
    reg [RESULT_ADDR_W-1:0] result_rd_addr;
    wire busy, done, result_rd_valid;
    wire [ACC_W-1:0] result_rd_data;

    integer a_ref [0:N-1][0:K-1];
    integer b_ref [0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];
    integer i,j,k,checks,cycles;

    tito_systolic_burst_command_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W),
        .BURST_LEN_W(BURST_LEN_W)
    ) dut (
        .clk(clk), .resetb(resetb),
        .burst_start_valid(burst_start_valid), .burst_start_ready(burst_start_ready),
        .burst_bank(burst_bank), .burst_base_addr(burst_base_addr),
        .burst_len(burst_len), .data_valid(data_valid), .data_ready(data_ready),
        .data(data), .burst_done(burst_done), .burst_error(burst_error),
        .cmd_start(cmd_start), .cmd_accumulate(cmd_accumulate),
        .busy(busy), .done(done),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    always #5 clk=~clk;

    task start_burst;
        input bank;
        input integer base;
        input integer length;
        begin
            @(negedge clk);
            burst_bank=bank;
            burst_base_addr=base;
            burst_len=length;
            burst_start_valid=1;
            while (!burst_start_ready) @(negedge clk);
            @(negedge clk);
            burst_start_valid=0;
            if (burst_error) begin
                $display("FAIL: valid burst descriptor rejected");
                $fatal(1);
            end
        end
    endtask

    task send_beat;
        input [DATA_W-1:0] value;
        begin
            @(negedge clk);
            data=value;
            data_valid=1;
            while (!data_ready) @(negedge clk);
            @(negedge clk);
            data_valid=0;
        end
    endtask

    initial begin
        clk=0; resetb=0;
        burst_start_valid=0; burst_bank=0; burst_base_addr=0; burst_len=0;
        data_valid=0; data=0; cmd_start=0; cmd_accumulate=0;
        result_rd_en=0; result_rd_addr=0; checks=0; cycles=0;
        repeat(3) @(negedge clk);
        resetb=1;

        // Invalid zero-length descriptors must be rejected cleanly.
        @(negedge clk);
        burst_start_valid=1; burst_len=0; burst_base_addr=0; burst_bank=0;
        while (!burst_start_ready) @(negedge clk);
        @(negedge clk);
        burst_start_valid=0;
        if (!burst_error || !burst_start_ready) begin
            $display("FAIL: invalid burst did not report error and return idle");
            $fatal(1);
        end

        for (i=0;i<N;i=i+1)
            for (k=0;k<K;k=k+1)
                a_ref[i][k]=((i*7+k*3)%15)-7;
        for (k=0;k<K;k=k+1)
            for (j=0;j<N;j=j+1)
                b_ref[k][j]=((k*5+j*2)%13)-6;
        for (i=0;i<N;i=i+1)
            for (j=0;j<N;j=j+1) begin
                expected[i][j]=0;
                for (k=0;k<K;k=k+1)
                    expected[i][j]=expected[i][j]+a_ref[i][k]*b_ref[k][j];
            end

        // A single 16-beat burst loads the row-major A tile.
        start_burst(0,0,N*K);
        for (i=0;i<N;i=i+1)
            for (k=0;k<K;k=k+1)
                send_beat(a_ref[i][k]);
        if (!burst_done) begin
            $display("FAIL: A burst did not pulse burst_done");
            $fatal(1);
        end

        // B is a separate burst to bank 1, also in row-major K-by-N order.
        start_burst(1,0,N*K);
        for (k=0;k<K;k=k+1)
            for (j=0;j<N;j=j+1)
                send_beat(b_ref[k][j]);
        if (!burst_done) begin
            $display("FAIL: B burst did not pulse burst_done");
            $fatal(1);
        end

        @(negedge clk); cmd_start=1;
        @(negedge clk); cmd_start=0;
        cycles=0;
        while (!done && cycles<400) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (!done || busy) begin
            $display("FAIL: burst-loaded matrix command timed out");
            $fatal(1);
        end

        for (i=0;i<N;i=i+1)
            for (j=0;j<N;j=j+1) begin
                @(negedge clk);
                result_rd_en=1; result_rd_addr=i*N+j;
                @(negedge clk);
                if (!result_rd_valid || $signed(result_rd_data) !== expected[i][j]) begin
                    $display("FAIL burst result[%0d,%0d]: got %0d expected %0d",
                        i,j,$signed(result_rd_data),expected[i][j]);
                    $fatal(1);
                end
                checks=checks+1;
            end
        @(negedge clk); result_rd_en=0;
        $display("PASS: burst loader, invalid descriptor rejection, and %0d matrix results (%0d compute cycles)",
            checks,cycles);
        $finish;
    end

    initial begin
        #50000;
        $display("TIMEOUT: burst command accelerator");
        $fatal(1);
    end
endmodule

`default_nettype wire
