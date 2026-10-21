`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_tiled_burst_accelerator;
    localparam integer N=4, K=4, DATA_W=8, ACC_W=32;
    localparam integer MEM_ADDR_W=4, RESULT_ADDR_W=4, BURST_LEN_W=5, TILE_COUNT_W=4;

    reg clk, resetb;
    reg op_start;
    reg [TILE_COUNT_W-1:0] op_tile_count;
    wire op_busy, op_done, op_error;
    reg burst_start_valid, burst_bank, data_valid;
    reg [MEM_ADDR_W-1:0] burst_base_addr;
    reg [BURST_LEN_W-1:0] burst_len;
    reg [DATA_W-1:0] data;
    wire burst_start_ready, data_ready;
    reg result_rd_en;
    reg [RESULT_ADDR_W-1:0] result_rd_addr;
    wire [ACC_W-1:0] result_rd_data;
    wire result_rd_valid;

    integer a_ref [0:N-1][0:K-1];
    integer b_ref [0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];
    integer i,j,k,t,checks,cycles,beats_sent;

    tito_systolic_tiled_burst_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W),
        .BURST_LEN_W(BURST_LEN_W), .TILE_COUNT_W(TILE_COUNT_W)
    ) dut (
        .clk(clk), .resetb(resetb),
        .op_start(op_start), .op_tile_count(op_tile_count),
        .op_busy(op_busy), .op_done(op_done), .op_error(op_error),
        .burst_start_valid(burst_start_valid), .burst_start_ready(burst_start_ready),
        .burst_bank(burst_bank), .burst_base_addr(burst_base_addr),
        .burst_len(burst_len), .data_valid(data_valid), .data_ready(data_ready),
        .data(data), .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    always #5 clk=~clk;

    task start_burst;
        input bank;
        input integer length;
        begin
            @(negedge clk);
            burst_bank=bank;
            burst_base_addr=0;
            burst_len=length;
            burst_start_valid=1;
            while (!burst_start_ready) @(negedge clk);
            @(negedge clk);
            burst_start_valid=0;
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
            beats_sent=beats_sent+1;
            if ((beats_sent % 4)==0) $display("INFO: accepted producer beat %0d at %0t",beats_sent,$time);
        end
    endtask

    task load_a;
        begin
            start_burst(1'b0,N*K);
            for (i=0;i<N;i=i+1)
                for (k=0;k<K;k=k+1)
                    send_beat(a_ref[i][k]);
        end
    endtask

    task load_b;
        begin
            start_burst(1'b1,N*K);
            for (k=0;k<K;k=k+1)
                for (j=0;j<N;j=j+1)
                    send_beat(b_ref[k][j]);
        end
    endtask

    initial begin
        clk=0; resetb=0;
        op_start=0; op_tile_count=0;
        burst_start_valid=0; burst_bank=0; burst_base_addr=0; burst_len=0;
        data_valid=0; data=0; result_rd_en=0; result_rd_addr=0;
        checks=0; cycles=0; beats_sent=0;

        repeat(3) @(negedge clk);
        resetb=1;

        // A zero tile count must be rejected without entering busy state.
        @(negedge clk); op_start=1; op_tile_count=0;
        @(negedge clk); op_start=0;
        if (!op_error || op_busy) begin
            $display("FAIL: zero tile count was not rejected");
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
                    expected[i][j]=expected[i][j]+
                        2*a_ref[i][k]*b_ref[k][j];
            end

        // The controller must launch both tiles itself and accumulate tile 2.
        @(negedge clk); op_tile_count=2; op_start=1;
        @(negedge clk); op_start=0;
        if (!op_busy) begin
            $display("FAIL: operation did not enter busy state");
            $fatal(1);
        end

        for (t=0;t<2;t=t+1) begin
            $display("INFO: loading tile %0d A",t);
            load_a();
            $display("INFO: loading tile %0d B",t);
            load_b();
            $display("INFO: submitted tile %0d operands at time %0t",t,$time);
        end

        cycles=0;
        while (!op_done && cycles<1000) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (!op_done || op_busy || op_error) begin
            $display("FAIL: tiled operation did not complete cleanly");
            $fatal(1);
        end

        for (i=0;i<N;i=i+1)
            for (j=0;j<N;j=j+1) begin
                @(negedge clk);
                result_rd_en=1; result_rd_addr=i*N+j;
                @(negedge clk);
                if (!result_rd_valid || $signed(result_rd_data) !== expected[i][j]) begin
                    $display("FAIL tiled result[%0d,%0d]: got %0d expected %0d",
                        i,j,$signed(result_rd_data),expected[i][j]);
                    $fatal(1);
                end
                checks=checks+1;
            end

        @(negedge clk); result_rd_en=0;
        $display("PASS: autonomous two-tile burst schedule and %0d accumulated matrix results (%0d wait cycles)",
            checks,cycles);
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT: tiled burst accelerator state=%0d busy=%b core_busy=%b core_done=%b a_loaded=%b b_loaded=%b remaining=%0d index=%0d ready=%b data_ready=%b child_active=%b child_count=%0d child_len=%0d child_bank=%b desc_valid=%b", dut.state,op_busy,dut.core_busy,dut.core_done,dut.a_loaded,dut.b_loaded,dut.tiles_remaining,dut.tile_index,burst_start_ready,data_ready,dut.burst_core.burst_active,dut.burst_core.burst_count,dut.burst_core.burst_len_q,dut.burst_core.burst_bank_q,burst_start_valid);
        $fatal(1);
    end
endmodule

`default_nettype wire
