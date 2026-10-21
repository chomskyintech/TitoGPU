`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_axi4_result_writeback;
    localparam ADDR_W=16, DATA_W=32, N=2, RESULT_ADDR_W=2;
    reg clk, resetb;
    reg start_valid;
    wire start_ready, busy, done, error;
    reg [ADDR_W-1:0] result_base_addr;
    wire [3:0] error_code;
    wire result_rd_en;
    wire [RESULT_ADDR_W-1:0] result_rd_addr;
    reg [DATA_W-1:0] result_rd_data;
    reg result_rd_valid;
    wire [3:0] awid;
    wire [ADDR_W-1:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid;
    reg awready;
    wire [DATA_W-1:0] wdata;
    wire [3:0] wstrb;
    wire wlast, wvalid;
    reg wready;
    reg [1:0] bresp;
    reg bvalid;
    wire bready;
    reg [31:0] result_mem[0:3];
    reg [31:0] output_mem[0:3];
    integer aw_count, w_count, cycle_count, i, rd_count;
    reg b_handshake_seen;

    tito_systolic_axi4_result_writeback #(.N(N),.DATA_W(DATA_W),.ADDR_W(ADDR_W)) dut (
        .clk(clk),.resetb(resetb),.start_valid(start_valid),.start_ready(start_ready),
        .result_base_addr(result_base_addr),.busy(busy),.done(done),.error(error),
        .error_code(error_code),.result_rd_en(result_rd_en),.result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data),.result_rd_valid(result_rd_valid),
        .m_axi_awid(awid),.m_axi_awaddr(awaddr),.m_axi_awlen(awlen),
        .m_axi_awsize(awsize),.m_axi_awburst(awburst),.m_axi_awvalid(awvalid),
        .m_axi_awready(awready),.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),
        .m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
        .m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready)
    );
    always #5 clk=~clk;

    // Model the accelerator's one-cycle synchronous result-memory read port.
    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            result_rd_data<=0;
            result_rd_valid<=0;
        end else begin
            result_rd_valid<=result_rd_en;
            if (result_rd_en) result_rd_data<=result_mem[result_rd_addr];
        end
    end

    // Capture external-memory write beats at accepted W handshakes.
    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            aw_count<=0; w_count<=0; rd_count<=0; b_handshake_seen<=0;
        end else begin
            if (result_rd_en) rd_count<=rd_count+1;
            if (awvalid && awready) begin
                aw_count<=aw_count+1;
                if (awid!==0 || awaddr!==16'h0100 || awlen!==3 ||
                    awsize!==2 || awburst!==2'b01)
                    $fatal(1,"FAIL: wrong AW payload");
            end
            if (wvalid && wready) begin
                output_mem[w_count]<=wdata;
                if (wstrb!==4'hf || wlast!==(w_count==3))
                    $fatal(1,"FAIL: bad WSTRB/WLAST at beat %0d",w_count);
                w_count<=w_count+1;
            end
            if (bvalid && bready) b_handshake_seen<=1;
        end
    end

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task reset_dut;
        begin
            @(negedge clk); resetb=0;
            start_valid=0; result_base_addr=0; awready=0; wready=0;
            bresp=0; bvalid=0; aw_count=0; w_count=0; rd_count=0; cycle_count=0;
            repeat(3) @(negedge clk);
            resetb=1;
            @(negedge clk);
        end
    endtask

    initial begin
        clk=0; resetb=0; start_valid=0; result_base_addr=0;
        awready=0; wready=0; bresp=0; bvalid=0;
        result_rd_data=0; result_rd_valid=0;
        result_mem[0]=32'h0000000A;
        result_mem[1]=32'hFFFFFFFE;
        result_mem[2]=32'h12345678;
        result_mem[3]=32'h80000000;
        for (i=0;i<4;i=i+1) output_mem[i]=0;
        reset_dut();

        @(negedge clk); result_base_addr=16'h0100; start_valid=1;
        if (!start_ready) $fatal(1,"FAIL: writeback start not ready");
        tick();
        @(negedge clk); start_valid=0;

        // Deliberately allow W to progress before AW, then release AW later.
        wready=1;
        repeat(3) begin
            tick();
            if (done) $fatal(1,"FAIL: done before B response");
        end
        awready=1;
        while (aw_count<1 || w_count<4) begin
            tick();
            cycle_count=cycle_count+1;
            if (cycle_count>100) $fatal(1,"FAIL: timed out transferring result words");
        end
        @(negedge clk); awready=0; wready=0;
        if (output_mem[0]!==result_mem[0] || output_mem[1]!==result_mem[1] ||
            output_mem[2]!==result_mem[2] || output_mem[3]!==result_mem[3])
            $fatal(1,"FAIL: external write data did not match result memory");

        repeat(3) begin
            tick();
            if (!bready || done) $fatal(1,"FAIL: response wait state incorrect");
        end
        @(negedge clk); bresp=0; bvalid=1;
        tick();
        @(negedge clk); bvalid=0;
        repeat(2) tick();
        if (!done || error || busy || !b_handshake_seen || rd_count!=4 || dut.stream_buf_valid) begin
            $display("DEBUG: done=%b error=%b busy=%b b_handshake_seen=%b writer_done=%b writer_error=%b rd_count=%0d buf_valid=%b",done,error,busy,b_handshake_seen,dut.writer_done,dut.writer_error,rd_count,dut.stream_buf_valid);
            $fatal(1,"FAIL: writeback completion status incorrect");
        end
        $display("PASS: synchronous result reads written byte-for-byte through AXI W channel");
        $display("PASS: AXI result writeback waits for successful B handshake");

        reset_dut();
        @(negedge clk); result_base_addr=16'h0FFD; start_valid=1;
        tick();
        @(negedge clk); start_valid=0;
        if (!error || error_code!==4'd2 || awvalid)
            $fatal(1,"FAIL: unaligned result writeback command not rejected");
        $display("PASS: result writeback rejects unaligned output address");
        $display("PASS: result writeback adapter regression");
        $finish;
    end

    initial begin
        #30000;
        $display("TIMEOUT");
        $fatal(1);
    end
endmodule

`default_nettype wire
