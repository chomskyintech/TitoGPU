`timescale 1ns/1ps
`default_nettype none

// Controller regression: reset/relaunch, cycle clamp, busy-write and busy-start protection; registered outputs are sampled after NBA updates.
module tb_cgra_controller;
    reg clk, resetb;
    reg cfg_we;
    reg [1:0] cfg_pe;
    reg [2:0] cfg_context;
    reg [31:0] cfg_wdata;
    reg [3:0] run_cycles;
    reg start;
    reg [31:0] ext0, ext1, ext2, ext3, ext4, ext5, ext6, ext7;
    wire busy, done;
    wire [2:0] cycle_index;
    wire [31:0] result0, result1, result2, result3;
    integer checks;
    integer done_count;

    localparam OP_PASSA = 4'hb;
    localparam OP_PASSB = 4'hc;
    localparam SRC_EXT0 = 4'd1;
    localparam SRC_EXT1 = 4'd2;

    cgra_top dut (
        .clk(clk), .resetb(resetb),
        .cfg_we(cfg_we), .cfg_pe(cfg_pe), .cfg_context(cfg_context), .cfg_wdata(cfg_wdata),
        .run_cycles(run_cycles), .start(start),
        .ext0(ext0), .ext1(ext1), .ext2(ext2), .ext3(ext3),
        .ext4(ext4), .ext5(ext5), .ext6(ext6), .ext7(ext7),
        .busy(busy), .done(done), .cycle_index(cycle_index),
        .result0(result0), .result1(result1), .result2(result2), .result3(result3)
    );

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (!resetb) done_count <= 0;
        else if (done) done_count <= done_count + 1;
    end

    function [31:0] context_word;
        input [3:0] op;
        input [3:0] src_a;
        input [3:0] src_b;
        begin
            context_word = {19'd0, 1'b1, src_b, src_a, op};
        end
    endfunction

    task write_cfg;
        input [2:0] index;
        input [31:0] value;
        begin
            @(negedge clk);
            cfg_pe = 0;
            cfg_context = index;
            cfg_wdata = value;
            cfg_we = 1;
            @(negedge clk);
            cfg_we = 0;
        end
    endtask

    task launch;
        input [3:0] cycles;
        input [31:0] value0;
        input [31:0] value1;
        begin
            @(negedge clk);
            run_cycles = cycles;
            ext0 = value0;
            ext1 = value1;
            start = 1;
            @(negedge clk);
            start = 0;
        end
    endtask

    initial begin
        clk=0; resetb=0; cfg_we=0; cfg_pe=0; cfg_context=0; cfg_wdata=0;
        run_cycles=1; start=0;
        ext0=0; ext1=0; ext2=0; ext3=0; ext4=0; ext5=0; ext6=0; ext7=0;
        checks=0; done_count=0;

        repeat (3) @(negedge clk);
        resetb=1;
        write_cfg(0, context_word(OP_PASSA, SRC_EXT0, SRC_EXT1));

        // Zero cycles is clamped to one. Also verify a normal completion.
        launch(0, 32'd42, 32'd99);
        wait(done === 1'b1);
        #1;
        checks=checks+1;
        if (busy !== 1'b0 || result0 !== 32'd42) begin
            $display("FAIL run_cycles=0: busy=%b result0=%0d", busy, result0);
            $fatal(1);
        end
        @(posedge clk);
        #1;
        checks=checks+1;
        if (done !== 1'b0) begin
            $display("FAIL done was not a one-cycle pulse");
            $fatal(1);
        end

        // During a two-cycle run, configuration writes and new starts must be ignored.
        launch(2, 32'd11, 32'd77);
        wait(busy === 1'b1);
        @(negedge clk);
        cfg_pe=0;
        cfg_context=0;
        cfg_wdata=context_word(OP_PASSB, SRC_EXT0, SRC_EXT1);
        cfg_we=1;
        start=1;
        @(negedge clk);
        cfg_we=0;
        start=0;
        wait(done === 1'b1);
        #1;
        checks=checks+1;
        if (result0 !== 32'd11 || busy !== 1'b0) begin
            $display("FAIL busy write/start protection: result0=%0d busy=%b", result0, busy);
            $fatal(1);
        end
        @(negedge clk);

        // If the attempted write had been accepted, this would return ext1 (88), not ext0 (13).
        launch(1, 32'd13, 32'd88);
        wait(done === 1'b1);
        #1;
        checks=checks+1;
        if (result0 !== 32'd13) begin
            $display("FAIL config changed during busy run: expected 13 got %0d", result0);
            $fatal(1);
        end

        @(negedge clk);
        checks=checks+1;
        if (done_count !== 3) begin
            $display("FAIL expected 3 completion pulses, got %0d", done_count);
            $fatal(1);
        end
        $display("PASS: CGRA controller tests (%0d checks, %0d completions)", checks, done_count);
        $finish;
    end

    initial begin
        #5000;
        $display("TIMEOUT: CGRA controller tests");
        $fatal(1);
    end
endmodule

`default_nettype wire
