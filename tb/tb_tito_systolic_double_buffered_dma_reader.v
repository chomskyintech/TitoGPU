`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_double_buffered_dma_reader;
    localparam integer N=4, K=4, DATA_W=8, ACC_W=32;
    localparam integer ADDR_W=16, MEM_ADDR_W=4, RESULT_ADDR_W=4;
    localparam integer BURST_LEN_W=5, TILE_COUNT_W=4;

    reg clk, resetb;
    reg op_start;
    reg [ADDR_W-1:0] a_base_addr, b_base_addr;
    reg [TILE_COUNT_W-1:0] op_tile_count;
    wire op_busy, op_done, op_error;
    wire rd_req_valid;
    reg rd_req_ready;
    wire [ADDR_W-1:0] rd_req_addr;
    wire [BURST_LEN_W-1:0] rd_req_len;
    reg rd_data_valid;
    wire rd_data_ready;
    reg [DATA_W-1:0] rd_data;
    reg rd_data_last, rd_error;
    reg result_rd_en;
    reg [RESULT_ADDR_W-1:0] result_rd_addr;
    wire [ACC_W-1:0] result_rd_data;
    wire result_rd_valid;

    reg bad_last_mode;
    reg mem_active;
    reg [ADDR_W-1:0] mem_addr_q;
    reg [BURST_LEN_W-1:0] mem_len_q, mem_index;
    integer a_ref [0:1][0:N-1][0:K-1];
    integer b_ref [0:1][0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];
    integer i,j,k,t,checks,cycles,request_count,overlap_seen;
    integer response_beats, request_backpressure_cycles;
    integer compute_busy_cycles, compute_idle_cycles, memory_active_cycles, prefetch_beats_while_compute_busy;
    integer mem_gap_cfg, mem_gap_countdown;
    integer signed mem_value;

    tito_systolic_double_buffered_dma_reader #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W), .ADDR_W(ADDR_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W),
        .BURST_LEN_W(BURST_LEN_W), .TILE_COUNT_W(TILE_COUNT_W)
    ) dut (
        .clk(clk), .resetb(resetb),
        .op_start(op_start), .a_base_addr(a_base_addr), .b_base_addr(b_base_addr),
        .op_tile_count(op_tile_count), .op_busy(op_busy), .op_done(op_done), .op_error(op_error),
        .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready),
        .rd_req_addr(rd_req_addr), .rd_req_len(rd_req_len),
        .rd_data_valid(rd_data_valid), .rd_data_ready(rd_data_ready),
        .rd_data(rd_data), .rd_data_last(rd_data_last), .rd_error(rd_error),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    always #5 clk=~clk;

    function integer signed operand_value;
        input [ADDR_W-1:0] base;
        input integer index;
        integer tile, row, col;
        begin
            if (base >= 200) begin
                tile=(base-200)/16;
                row=index/4; col=index%4;
                operand_value=((tile*3 + row*5 + col*2)%11)-5;
            end else begin
                tile=(base-100)/16;
                row=index/4; col=index%4;
                operand_value=((tile*4 + row*3 + col*7)%13)-6;
            end
        end
    endfunction

    // One outstanding request; response data remains stable until accepted.
    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            mem_active <= 1'b0;
            mem_addr_q <= 0;
            mem_len_q <= 0;
            mem_index <= 0;
            mem_gap_countdown <= 0;
            rd_data_valid <= 1'b0;
            rd_data <= 0;
            rd_data_last <= 1'b0;
            request_count <= 0;
            response_beats <= 0;
            request_backpressure_cycles <= 0;
            prefetch_beats_while_compute_busy <= 0;
        end else begin
            rd_req_ready <= (cycles % 4 != 1);
            if (rd_req_valid && !rd_req_ready)
                request_backpressure_cycles <= request_backpressure_cycles + 1;
            if (rd_req_valid && rd_req_ready) begin
                if (mem_active) begin
                    $display("FAIL: received overlapping read request");
                    $fatal(1);
                end
                mem_active <= 1'b1;
                mem_addr_q <= rd_req_addr;
                mem_len_q <= rd_req_len;
                mem_index <= 0;
                mem_gap_countdown <= mem_gap_cfg;
                rd_data_valid <= 1'b0;
                request_count <= request_count + 1;
            end
            if (rd_req_valid && rd_req_ready && request_count >= 2 && dut.tiled_core.core_busy)
                overlap_seen <= 1'b1;

            if (rd_data_valid && rd_data_ready) begin
                response_beats <= response_beats + 1;
                if (request_count >= 3 && dut.tiled_core.core_busy)
                    prefetch_beats_while_compute_busy <= prefetch_beats_while_compute_busy + 1;
                if (rd_data_last) begin
                    mem_active <= 1'b0;
                    rd_data_valid <= 1'b0;
                end else begin
                    mem_index <= mem_index + 1'b1;
                    if (mem_gap_cfg == 0) begin
                        mem_value = operand_value(mem_addr_q,mem_index+1'b1);
                        rd_data <= mem_value[DATA_W-1:0];
                        rd_data_last <= bad_last_mode ? (mem_index+1'b1 == 2) : (mem_index+1'b1 == mem_len_q-1);
                        rd_data_valid <= 1'b1;
                    end else begin
                        rd_data_valid <= 1'b0;
                        mem_gap_countdown <= mem_gap_cfg;
                    end
                end
            end else if (mem_active && !rd_data_valid) begin
                if (mem_gap_countdown > 0) begin
                    mem_gap_countdown <= mem_gap_countdown - 1;
                end else begin
                    mem_value = operand_value(mem_addr_q,mem_index);
                    rd_data <= mem_value[DATA_W-1:0];
                    rd_data_last <= bad_last_mode ? (mem_index == 2) : (mem_index == mem_len_q-1);
                    rd_data_valid <= 1'b1;
                end
            end
        end
    end

    initial begin
        clk=0; resetb=0;
        op_start=0; a_base_addr=100; b_base_addr=200; op_tile_count=2;
        rd_req_ready=0; rd_data_valid=0; rd_data=0; rd_data_last=0; rd_error=0;
        result_rd_en=0; result_rd_addr=0; cycles=0; checks=0; request_count=0; overlap_seen=0; bad_last_mode=0; prefetch_beats_while_compute_busy=0;
        mem_gap_cfg=0; mem_gap_countdown=0;
        if (!$value$plusargs("MEM_GAP=%d",mem_gap_cfg)) mem_gap_cfg=0;
        if (mem_gap_cfg < 0) mem_gap_cfg=0;
        $display("CONFIG: memory response gap=%0d cycles between accepted beats",mem_gap_cfg);
        repeat(3) @(negedge clk);
        resetb=1;

        for (t=0;t<2;t=t+1) begin
            for (i=0;i<N;i=i+1)
                for (k=0;k<K;k=k+1)
                    a_ref[t][i][k]=operand_value(100+t*16,i*K+k);
            for (k=0;k<K;k=k+1)
                for (j=0;j<N;j=j+1)
                    b_ref[t][k][j]=operand_value(200+t*16,k*N+j);
        end
        for (i=0;i<N;i=i+1)
            for (j=0;j<N;j=j+1) begin
                expected[i][j]=0;
                for (t=0;t<2;t=t+1)
                    for (k=0;k<K;k=k+1)
                        expected[i][j]=expected[i][j]+
                            a_ref[t][i][k]*b_ref[t][k][j];
            end

        @(negedge clk); op_start=1;
        @(negedge clk); op_start=0;

        cycles=0;
        compute_busy_cycles=0; compute_idle_cycles=0; memory_active_cycles=0;
        while (!op_done && !op_error && cycles<3000) begin
            @(negedge clk);
            cycles=cycles+1;
            if (dut.tiled_core.core_busy)
                compute_busy_cycles=compute_busy_cycles+1;
            if (op_busy && !dut.tiled_core.core_busy)
                compute_idle_cycles=compute_idle_cycles+1;
            if (mem_active)
                memory_active_cycles=memory_active_cycles+1;
        end
        if (!op_done || op_error || op_busy) begin
            $display("FAIL: DMA operation status done=%b error=%b busy=%b state=%0d",
                op_done,op_error,op_busy,dut.state);
            $fatal(1);
        end
        if (mem_gap_cfg == 0 && !overlap_seen) begin
            $display("FAIL: zero-gap memory model did not overlap next-tile read with compute");
            $fatal(1);
        end
        if (request_count != 4) begin
            $display("FAIL: expected 4 read requests, got %0d",request_count);
            $fatal(1);
        end

        for (i=0;i<N;i=i+1)
            for (j=0;j<N;j=j+1) begin
                @(negedge clk); result_rd_en=1; result_rd_addr=i*N+j;
                @(negedge clk);
                if (!result_rd_valid || $signed(result_rd_data) !== expected[i][j]) begin
                    $display("FAIL result[%0d,%0d]: got %0d expected %0d",
                        i,j,$signed(result_rd_data),expected[i][j]);
                    $fatal(1);
                end
                checks=checks+1;
            end
        @(negedge clk); result_rd_en=0;
        $display("PASS: double-buffered DMA frontend accepted the next-tile request during compute; 4 read requests, %0d matrix outputs (%0d cycles)",
            checks,cycles);
        $display("METRICS: compute_busy_cycles=%0d compute_idle_while_operation_busy=%0d memory_active_cycles=%0d response_beats=%0d request_backpressure_cycles=%0d prefetch_beats_while_compute_busy=%0d",
            compute_busy_cycles,compute_idle_cycles,memory_active_cycles,response_beats,request_backpressure_cycles,prefetch_beats_while_compute_busy);

        // Reset, then inject an early last marker. The frontend must fail closed.
        @(negedge clk); resetb=0; op_start=0;
        repeat(3) @(negedge clk);
        bad_last_mode=1;
        resetb=1;
        @(negedge clk); op_start=1;
        @(negedge clk); op_start=0;
        cycles=0;
        while (!op_error && cycles<500) begin
            @(negedge clk);
            cycles=cycles+1;
        end
        if (!op_error || op_done || op_busy) begin
            $display("FAIL: malformed last marker was not rejected cleanly");
            $fatal(1);
        end
        $display("PASS: early response-last fault detected and local core held in reset");
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT: DMA reader state=%0d tile=%0d beat=%0d req_valid=%b req_ready=%b data_valid=%b data_ready=%b local_busy=%b local_done=%b",
            dut.state,dut.tile_index,dut.beat_count,rd_req_valid,rd_req_ready,rd_data_valid,rd_data_ready,dut.local_op_busy,dut.local_op_done);
        $fatal(1);
    end
endmodule

`default_nettype wire
