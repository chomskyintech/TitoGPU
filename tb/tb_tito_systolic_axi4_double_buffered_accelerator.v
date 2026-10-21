`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_axi4_double_buffered_accelerator;
    localparam integer N=4, K=4, DATA_W=8, AXI_DATA_W=32, ACC_W=32, ADDR_W=16;
    localparam integer MEM_ADDR_W=4, RESULT_ADDR_W=4, BURST_LEN_W=5, TILE_COUNT_W=4, ID_W=2;

    reg clk, resetb, op_start;
    reg [ADDR_W-1:0] a_base_addr, b_base_addr;
    reg [TILE_COUNT_W-1:0] op_tile_count;
    wire op_busy, op_done, op_error;
    reg result_rd_en;
    reg [RESULT_ADDR_W-1:0] result_rd_addr;
    wire [ACC_W-1:0] result_rd_data;
    wire result_rd_valid;

    wire [ID_W-1:0] m_axi_arid;
    wire [ADDR_W-1:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid;
    reg m_axi_arready;
    reg [ID_W-1:0] m_axi_rid;
    reg [AXI_DATA_W-1:0] m_axi_rdata;
    reg [1:0] m_axi_rresp;
    reg m_axi_rlast, m_axi_rvalid;
    wire m_axi_rready;

    reg mem_active, bad_last_mode;
    reg [ADDR_W-1:0] mem_addr_q;
    reg [7:0] mem_len_q;
    reg [7:0] mem_index;
    integer gap_cfg, gap_countdown, ar_phase, ar_count;
    integer i,j,k,t,cycles,checks;
    integer a_ref [0:1][0:N-1][0:K-1];
    integer b_ref [0:1][0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];
    integer signed mem_value;
    reg [31:0] packed_value;

    tito_systolic_axi4_double_buffered_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .AXI_DATA_W(AXI_DATA_W), .ACC_W(ACC_W), .ADDR_W(ADDR_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W),
        .BURST_LEN_W(BURST_LEN_W), .TILE_COUNT_W(TILE_COUNT_W), .ID_W(ID_W)
    ) dut (
        .clk(clk), .resetb(resetb),
        .op_start(op_start), .a_base_addr(a_base_addr), .b_base_addr(b_base_addr),
        .op_tile_count(op_tile_count), .op_busy(op_busy), .op_done(op_done), .op_error(op_error),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready), .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
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

    function [31:0] packed_beat;
        input [ADDR_W-1:0] base;
        input integer beat_index;
        integer lane;
        integer signed v;
        begin
            packed_beat=0;
            for(lane=0;lane<4;lane=lane+1) begin
                v=operand_value(base,beat_index*4+lane);
                packed_beat[lane*8 +: 8]=v[7:0];
            end
        end
    endfunction

    // Minimal 32-bit AXI memory model: four INT8 values per R beat.
    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            mem_active <= 0;
            mem_addr_q <= 0;
            mem_len_q <= 0;
            mem_index <= 0;
            gap_countdown <= 0;
            ar_phase <= 0;
            m_axi_arready <= 0;
            m_axi_rid <= 0;
            m_axi_rdata <= 0;
            m_axi_rresp <= 0;
            m_axi_rlast <= 0;
            m_axi_rvalid <= 0;
            ar_count <= 0;
        end else begin
            m_axi_arready <= (ar_phase != 1);
            ar_phase <= (ar_phase == 3) ? 0 : ar_phase + 1;
            if (m_axi_arvalid && m_axi_arready) begin
                if (mem_active) begin
                    $display("FAIL: AXI accepted overlapping read addresses");
                    $fatal(1);
                end
                if (m_axi_arid !== 0 || m_axi_arsize !== 2 || m_axi_arburst !== 2'b01) begin
                    $display("FAIL: wrong AXI AR fields");
                    $fatal(1);
                end
                if (m_axi_arlen !== 8'd3) begin
                    $display("FAIL: expected four-beat burst, ARLEN=%0d",m_axi_arlen);
                    $fatal(1);
                end
                case (ar_count)
                    0: if (m_axi_araddr !== 100) $fatal(1,"wrong A0 ARADDR %0d",m_axi_araddr);
                    1: if (m_axi_araddr !== 200) $fatal(1,"wrong B0 ARADDR %0d",m_axi_araddr);
                    2: if (m_axi_araddr !== 116) $fatal(1,"wrong A1 ARADDR %0d",m_axi_araddr);
                    3: if (m_axi_araddr !== 216) $fatal(1,"wrong B1 ARADDR %0d",m_axi_araddr);
                    default: begin end
                endcase
                ar_count <= ar_count + 1;
                mem_active <= 1;
                mem_addr_q <= m_axi_araddr;
                mem_len_q <= m_axi_arlen;
                mem_index <= 0;
                gap_countdown <= gap_cfg;
                m_axi_rvalid <= 0;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rlast) begin
                    mem_active <= 0;
                    m_axi_rvalid <= 0;
                end else begin
                    mem_index <= mem_index + 1'b1;
                    if (gap_cfg == 0) begin
                        m_axi_rdata <= packed_beat(mem_addr_q,mem_index+1);
                        m_axi_rlast <= bad_last_mode ? (mem_index+1 == 1) : (mem_index+1 == mem_len_q);
                        m_axi_rvalid <= 1;
                    end else begin
                        m_axi_rvalid <= 0;
                        gap_countdown <= gap_cfg;
                    end
                end
            end else if (mem_active && !m_axi_rvalid) begin
                if (gap_countdown > 0) begin
                    gap_countdown <= gap_countdown - 1;
                end else begin
                    m_axi_rdata <= packed_beat(mem_addr_q,mem_index);
                    m_axi_rlast <= bad_last_mode ? (mem_index == 1) : (mem_index == mem_len_q);
                    m_axi_rvalid <= 1;
                    m_axi_rresp <= 0;
                    m_axi_rid <= 0;
                end
            end
        end
    end

    task launch_operation;
        begin
            @(negedge clk); op_start=1;
            @(negedge clk); op_start=0;
        end
    endtask

    initial begin
        clk=0; resetb=0; op_start=0;
        a_base_addr=100; b_base_addr=200; op_tile_count=2;
        result_rd_en=0; result_rd_addr=0;
        bad_last_mode=0; gap_cfg=0; cycles=0; checks=0;
        if (!$value$plusargs("MEM_GAP=%d",gap_cfg)) gap_cfg=0;
        if (gap_cfg < 0) gap_cfg=0;
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
                        expected[i][j]=expected[i][j]+a_ref[t][i][k]*b_ref[t][k][j];
            end

        launch_operation();
        cycles=0;
        while (!op_done && !op_error && cycles<3000) begin
            @(negedge clk); cycles=cycles+1;
        end
        if (!op_done || op_error || op_busy) begin
            $display("FAIL: AXI integrated operation status done=%b error=%b busy=%b",
                op_done,op_error,op_busy);
            $fatal(1);
        end
        if (ar_count != 4) begin
            $display("FAIL: expected four AXI bursts, got %0d",ar_count);
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
        $display("PASS: AXI-integrated double-buffered two-tile matmul, %0d outputs, %0d cycles",
            checks,cycles);

        // Restart under reset and verify the upstream reader rejects an early RLAST.
        @(negedge clk); resetb=0; op_start=0;
        repeat(3) @(negedge clk);
        bad_last_mode=1; ar_count=0; resetb=1;
        launch_operation();
        cycles=0;
        while (!op_error && cycles<500) begin
            @(negedge clk); cycles=cycles+1;
        end
        if (!op_error || op_done || op_busy) begin
            $display("FAIL: integrated frontend did not reject early RLAST");
            $fatal(1);
        end
        $display("PASS: AXI-integrated path rejects early RLAST");
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT: state=%0d busy=%b done=%b error=%b",
            dut.frontend.state,op_busy,op_done,op_error);
        $fatal(1);
    end
endmodule

`default_nettype wire
