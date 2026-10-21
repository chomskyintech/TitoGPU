`timescale 1ns/1ps
`default_nettype none

module tb_cgra_pe;
    reg clk;
    reg resetb;
    reg clear;
    reg enable;
    reg [3:0] op;
    reg [31:0] src_a;
    reg [31:0] src_b;
    wire [31:0] result;
    integer checks;
    integer i;
    integer seed;
    reg [3:0] random_op;
    reg [31:0] random_a, random_b;

    localparam OP_NOP   = 4'h0;
    localparam OP_ADD   = 4'h1;
    localparam OP_SUB   = 4'h2;
    localparam OP_MUL8  = 4'h3;
    localparam OP_AND   = 4'h4;
    localparam OP_OR    = 4'h5;
    localparam OP_XOR   = 4'h6;
    localparam OP_MAX   = 4'h7;
    localparam OP_MIN   = 4'h8;
    localparam OP_SHL   = 4'h9;
    localparam OP_SHR   = 4'hA;
    localparam OP_PASSA = 4'hB;
    localparam OP_PASSB = 4'hC;

    cgra_pe dut (
        .clk(clk), .resetb(resetb), .clear(clear), .enable(enable),
        .op(op), .src_a(src_a), .src_b(src_b), .result(result)
    );

    always #5 clk = ~clk;

    function [31:0] reference_result;
        input [3:0] test_op;
        input [31:0] a;
        input [31:0] b;
        reg signed [7:0] signed_a8;
        reg signed [7:0] signed_b8;
        reg signed [15:0] product8;
        begin
            signed_a8 = a[7:0];
            signed_b8 = b[7:0];
            product8 = signed_a8 * signed_b8;
            case (test_op)
                OP_ADD:   reference_result = a + b;
                OP_SUB:   reference_result = a - b;
                OP_MUL8:  reference_result = {{16{product8[15]}}, product8};
                OP_AND:   reference_result = a & b;
                OP_OR:    reference_result = a | b;
                OP_XOR:   reference_result = a ^ b;
                OP_MAX:   reference_result = ($signed(a) >= $signed(b)) ? a : b;
                OP_MIN:   reference_result = ($signed(a) <= $signed(b)) ? a : b;
                OP_SHL:   reference_result = a << b[4:0];
                OP_SHR:   reference_result = $signed(a) >>> b[4:0];
                OP_PASSA: reference_result = a;
                OP_PASSB: reference_result = b;
                default:  reference_result = 32'd0;
            endcase
        end
    endfunction

    task check_op;
        input [3:0] test_op;
        input [31:0] a;
        input [31:0] b;
        input [31:0] expected;
        begin
            @(negedge clk);
            op = test_op;
            src_a = a;
            src_b = b;
            enable = 1'b1;
            @(posedge clk);
            #1;
            checks = checks + 1;
            if (result !== expected) begin
                $display("FAIL op=%h a=%h b=%h expected=%h got=%h",
                         test_op, a, b, expected, result);
                $fatal(1);
            end
        end
    endtask

    task check_hold;
        input [3:0] test_op;
        input enable_value;
        input [31:0] expected;
        begin
            @(negedge clk);
            op = test_op;
            enable = enable_value;
            @(posedge clk);
            #1;
            checks = checks + 1;
            if (result !== expected) begin
                $display("FAIL hold op=%h enable=%b expected=%h got=%h",
                         test_op, enable_value, expected, result);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk = 0;
        resetb = 0;
        clear = 0;
        enable = 0;
        op = OP_NOP;
        src_a = 0;
        src_b = 0;
        checks = 0;
        seed = 32'h54_47_50_55;

        repeat (2) @(negedge clk);
        resetb = 1;
        check_op(OP_ADD, 32'd7, 32'd9, 32'd16);
        check_op(OP_SUB, 32'd7, 32'd9, 32'hffff_fffe);
        check_op(OP_ADD, 32'hffff_ffff, 32'd1, 32'd0);
        check_op(OP_MUL8, 32'd12, 32'd10, 32'd120);
        check_op(OP_MUL8, 32'hffff_fff0, 32'd3, 32'hffff_ffd0); // -16 * 3
        check_op(OP_MUL8, 32'hffff_ff80, 32'd2, 32'hffff_ff00); // -128 * 2
        check_op(OP_MUL8, 32'd127, 32'hffff_ff80, 32'hffff_c080); // 127 * -128
        check_op(OP_AND, 32'hf0f0_aaaa, 32'h0ff0_5555, 32'h00f0_0000);
        check_op(OP_OR, 32'hf000_0000, 32'h0000_00ff, 32'hf000_00ff);
        check_op(OP_XOR, 32'hffff_0000, 32'h0f0f_0f0f, 32'hf0f0_0f0f);
        check_op(OP_MAX, 32'hffff_ffff, 32'd1, 32'd1); // signed -1 < 1
        check_op(OP_MAX, 32'd9, 32'd9, 32'd9);
        check_op(OP_MIN, 32'hffff_ffff, 32'd1, 32'hffff_ffff);
        check_op(OP_MIN, 32'h8000_0000, 32'h7fff_ffff, 32'h8000_0000);
        check_op(OP_SHL, 32'h0000_0001, 32'd31, 32'h8000_0000);
        check_op(OP_SHL, 32'h0000_0003, 32'd2, 32'd12);
        check_op(OP_SHR, 32'hffff_ff80, 32'd2, 32'hffff_ffe0); // arithmetic shift
        check_op(OP_SHR, 32'h7fff_ffff, 32'd4, 32'h07ff_ffff);
        check_op(OP_PASSA, 32'h1234_5678, 32'hdead_beef, 32'h1234_5678);
        check_op(OP_PASSB, 32'h1234_5678, 32'hdead_beef, 32'hdead_beef);

        check_hold(OP_NOP, 1'b1, 32'hdead_beef);
        check_hold(4'hf, 1'b1, 32'hdead_beef); // unsupported opcode holds
        check_hold(OP_ADD, 1'b0, 32'hdead_beef); // disabled PE holds

        @(negedge clk);
        clear = 1'b1;
        @(posedge clk);
        #1;
        checks = checks + 1;
        if (result !== 32'd0) begin
            $display("FAIL clear expected 00000000 got %h", result);
            $fatal(1);
        end
        @(negedge clk);
        clear = 1'b0;

        check_op(OP_ADD, 32'd20, 32'd22, 32'd42);

        // Deterministic pseudo-random differential checks against the reference model (fixed seed).
        for (i = 0; i < 200; i = i + 1) begin
            random_op = (i % 12) + 1;
            random_a = $random(seed);
            random_b = $random(seed);
            check_op(random_op, random_a, random_b,
                     reference_result(random_op, random_a, random_b));
        end

        $display("PASS: CGRA PE unit tests (%0d checks)", checks);
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT: CGRA PE unit tests");
        $fatal(1);
    end
endmodule

`default_nettype wire
