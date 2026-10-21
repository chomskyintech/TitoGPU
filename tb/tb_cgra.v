`timescale 1ns/1ps
`default_nettype none

module tb_cgra;

reg clk;
reg resetb;
reg cfg_we;
reg [1:0] cfg_pe;
reg [2:0] cfg_context;
reg [31:0] cfg_wdata;
reg [3:0] run_cycles;
reg start;
reg [31:0] ext0, ext1, ext2, ext3, ext4, ext5, ext6, ext7;

wire busy;
wire done;
wire [2:0] cycle_index;
wire [31:0] result0, result1, result2, result3;

localparam OP_ADD  = 4'h1;
localparam OP_MUL8 = 4'h3;

localparam SRC_EXT0 = 4'd1;
localparam SRC_EXT1 = 4'd2;
localparam SRC_EXT2 = 4'd3;
localparam SRC_EXT3 = 4'd4;
localparam SRC_EXT4 = 4'd5;
localparam SRC_EXT5 = 4'd6;
localparam SRC_EXT6 = 4'd7;
localparam SRC_EXT7 = 4'd8;
localparam SRC_PE0  = 4'd9;
localparam SRC_PE1  = 4'd10;
localparam SRC_PE2  = 4'd11;
localparam SRC_PE3  = 4'd12;

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

function [31:0] make_context;
    input enable;
    input [3:0] op;
    input [3:0] src_a;
    input [3:0] src_b;
    begin
        make_context = {19'd0, enable, src_b, src_a, op};
    end
endfunction

task write_context;
    input [1:0] pe;
    input [2:0] context;
    input [31:0] value;
    begin
        @(negedge clk);
        cfg_pe = pe;
        cfg_context = context;
        cfg_wdata = value;
        cfg_we = 1'b1;
        @(negedge clk);
        cfg_we = 1'b0;
    end
endtask

task run_dot_product;
    input signed [7:0] a0;
    input signed [7:0] b0;
    input signed [7:0] a1;
    input signed [7:0] b1;
    input signed [7:0] a2;
    input signed [7:0] b2;
    input signed [7:0] a3;
    input signed [7:0] b3;
    input signed [31:0] expected;
    begin
        ext0 = {{24{a0[7]}}, a0};
        ext1 = {{24{b0[7]}}, b0};
        ext2 = {{24{a1[7]}}, a1};
        ext3 = {{24{b1[7]}}, b1};
        ext4 = {{24{a2[7]}}, a2};
        ext5 = {{24{b2[7]}}, b2};
        ext6 = {{24{a3[7]}}, a3};
        ext7 = {{24{b3[7]}}, b3};

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        @(posedge done);
        #1;
        if ($signed(result0) !== expected) begin
            $display("FAIL: expected %0d, got %0d", expected, $signed(result0));
            $fatal(1);
        end else begin
            $display("PASS: dot product = %0d", $signed(result0));
        end
    end
endtask

initial begin
    clk = 1'b0;
    resetb = 1'b0;
    cfg_we = 1'b0;
    cfg_pe = 2'd0;
    cfg_context = 3'd0;
    cfg_wdata = 32'd0;
    run_cycles = 4'd3;
    start = 1'b0;
    ext0 = 0; ext1 = 0; ext2 = 0; ext3 = 0;
    ext4 = 0; ext5 = 0; ext6 = 0; ext7 = 0;

    repeat (4) @(negedge clk);
    resetb = 1'b1;

    // Context 0: four parallel signed INT8 multiplies.
    write_context(2'd0, 3'd0, make_context(1'b1, OP_MUL8, SRC_EXT0, SRC_EXT1));
    write_context(2'd1, 3'd0, make_context(1'b1, OP_MUL8, SRC_EXT2, SRC_EXT3));
    write_context(2'd2, 3'd0, make_context(1'b1, OP_MUL8, SRC_EXT4, SRC_EXT5));
    write_context(2'd3, 3'd0, make_context(1'b1, OP_MUL8, SRC_EXT6, SRC_EXT7));

    // Context 1: reduce four products to two partial sums.
    write_context(2'd0, 3'd1, make_context(1'b1, OP_ADD, SRC_PE0, SRC_PE1));
    write_context(2'd1, 3'd1, make_context(1'b1, OP_ADD, SRC_PE2, SRC_PE3));

    // Context 2: final reduction into PE0.
    write_context(2'd0, 3'd2, make_context(1'b1, OP_ADD, SRC_PE0, SRC_PE1));

    run_dot_product(8'sd3, 8'sd4,
                    8'sd5, 8'sd6,
                   -8'sd2, 8'sd7,
                    8'sd8, -8'sd1,
                    32'sd20);

    run_dot_product(8'sd1, 8'sd2,
                    8'sd3, 8'sd4,
                    8'sd5, 8'sd6,
                    8'sd7, 8'sd8,
                    32'sd100);

    $display("CGRA smoke test complete");
    $finish;
end

initial begin
    #5000;
    $display("TIMEOUT");
    $fatal(1);
end

endmodule

`default_nettype wire
