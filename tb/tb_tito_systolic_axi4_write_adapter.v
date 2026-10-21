`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_axi4_write_adapter;
    localparam ADDR_W=16, DATA_W=32, LEN_W=9;
    reg clk, resetb;
    reg cmd_valid;
    wire cmd_ready;
    reg [ADDR_W-1:0] cmd_addr;
    reg [LEN_W-1:0] cmd_beats;
    reg stream_valid;
    wire stream_ready;
    reg [DATA_W-1:0] stream_data;
    reg stream_last;
    wire busy, done, error;
    wire [3:0] error_code;
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
    integer writes, cycles;

    tito_systolic_axi4_write_adapter #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.LEN_W(LEN_W)) dut (
        .clk(clk),.resetb(resetb),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr),.cmd_beats(cmd_beats),
        .stream_valid(stream_valid),.stream_ready(stream_ready),
        .stream_data(stream_data),.stream_last(stream_last),
        .busy(busy),.done(done),.error(error),.error_code(error_code),
        .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),
        .m_axi_awburst(awburst),.m_axi_awvalid(awvalid),.m_axi_awready(awready),
        .m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid),.m_axi_wready(wready),
        .m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready)
    );
    always #5 clk=~clk;

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task reset_dut;
        begin
            @(negedge clk); resetb=0;
            cmd_valid=0; cmd_addr=0; cmd_beats=0; stream_valid=0;
            stream_data=0; stream_last=0; awready=0; wready=0;
            bvalid=0; bresp=0;
            repeat(3) @(negedge clk);
            resetb=1;
            @(negedge clk);
        end
    endtask

    task command;
        input [ADDR_W-1:0] addr;
        input [LEN_W-1:0] beats;
        begin
            cmd_addr=addr; cmd_beats=beats; cmd_valid=1;
            #1;
            if (!cmd_ready) $fatal(1,"FAIL: command not ready");
            tick();
            @(negedge clk); cmd_valid=0;
        end
    endtask

    task push_word;
        input [31:0] value;
        input last_value;
        integer wait_count;
        begin
            stream_data=value; stream_last=last_value; stream_valid=1;
            wait_count=0;
            while (!stream_ready && wait_count<20) begin @(negedge clk); wait_count=wait_count+1; end
            if (!stream_ready) $fatal(1,"FAIL: stream did not become ready");
            tick();
            @(negedge clk); stream_valid=0;
        end
    endtask

    initial begin
        clk=0; resetb=0; cmd_valid=0; cmd_addr=0; cmd_beats=0;
        stream_valid=0; stream_data=0; stream_last=0; awready=0; wready=0;
        bvalid=0; bresp=0; writes=0; cycles=0;
        reset_dut();

        // Valid three-beat burst. AW is stalled independently of W.
        command(16'h0100,3);
        repeat(3) begin
            tick();
            if (!awvalid || awaddr!==16'h0100 || awlen!==2 || awsize!==2 ||
                awburst!==2'b01) $fatal(1,"FAIL: AW payload/valid not stable under stall");
        end
        awready=1; tick(); @(negedge clk); awready=0;

        push_word(32'h11223344,0);
        if (!wvalid || wdata!==32'h11223344 || wlast || wstrb!==4'hf)
            $fatal(1,"FAIL: first W beat wrong");
        repeat(2) begin
            tick();
            if (!wvalid || wdata!==32'h11223344 || wlast)
                $fatal(1,"FAIL: W payload changed during backpressure");
        end
        wready=1; tick(); @(negedge clk); wready=0;

        push_word(32'h55667788,0);
        if (!wvalid || wdata!==32'h55667788 || wlast) $fatal(1,"FAIL: second W beat wrong");
        wready=1; tick(); @(negedge clk); wready=0;

        push_word(32'hDEADBEEF,1);
        if (!wvalid || wdata!==32'hDEADBEEF || !wlast) $fatal(1,"FAIL: WLAST not on final beat");
        wready=1; tick(); @(negedge clk); wready=0;
        if (done) $fatal(1,"FAIL: done asserted before B response handshake");
        repeat(2) begin tick(); if (!bready || done) $fatal(1,"FAIL: response wait state incorrect"); end
        bresp=0; bvalid=1; tick(); @(negedge clk); bvalid=0;
        if (!done || error || busy) $fatal(1,"FAIL: successful B response status");
        $display("PASS: independent AW/W stalls, payload stability, WLAST, B response");

        // Error response must not produce done.
        reset_dut();
        command(16'h0200,1);
        awready=1; tick(); @(negedge clk); awready=0;
        push_word(32'hCAFEBABE,1);
        wready=1; tick(); @(negedge clk); wready=0;
        bresp=2'b10; bvalid=1; tick(); @(negedge clk); bvalid=0;
        if (!error || done || error_code!==4'd6) $fatal(1,"FAIL: BRESP error status");
        $display("PASS: SLVERR response is sticky error, not success");

        // Reject malformed commands without issuing AW.
        reset_dut();
        command(16'h0100,0);
        if (!error || error_code!==4'd1 || awvalid) $fatal(1,"FAIL: zero length not rejected");
        reset_dut();
        command(16'h0102,1);
        if (!error || error_code!==4'd2 || awvalid) $fatal(1,"FAIL: unaligned address not rejected");
        reset_dut();
        command(16'h0FFC,2);
        if (!error || error_code!==4'd4 || awvalid) $fatal(1,"FAIL: 4-KiB crossing not rejected");
        reset_dut();
        command(16'h0100,257);
        if (!error || error_code!==4'd3 || awvalid) $fatal(1,"FAIL: >256 beats not rejected");
        $display("PASS: invalid command rejection");
        $display("PASS: AXI write-adapter unit regression");
        $finish;
    end

    initial begin
        #30000;
        $display("TIMEOUT");
        $fatal(1);
    end
endmodule

`default_nettype wire
