`default_nettype none

module cgra_array (
    input  wire        clk,
    input  wire        resetb,
    input  wire        clear,
    input  wire        step,

    input  wire [31:0] ctx0,
    input  wire [31:0] ctx1,
    input  wire [31:0] ctx2,
    input  wire [31:0] ctx3,

    input  wire [31:0] ext0,
    input  wire [31:0] ext1,
    input  wire [31:0] ext2,
    input  wire [31:0] ext3,
    input  wire [31:0] ext4,
    input  wire [31:0] ext5,
    input  wire [31:0] ext6,
    input  wire [31:0] ext7,

    output wire [31:0] pe0_result,
    output wire [31:0] pe1_result,
    output wire [31:0] pe2_result,
    output wire [31:0] pe3_result
);

// Context format:
// [3:0]   operation
// [7:4]   source A selector
// [11:8]  source B selector
// [12]    PE enable
// [31:13] reserved
//
// Source selectors:
// 0 = zero
// 1..8 = ext0..ext7
// 9..12 = PE0..PE3 registered outputs
// 13 = constant one

function [31:0] select_source;
    input [3:0] sel;
    begin
        case (sel)
            4'd0:  select_source = 32'd0;
            4'd1:  select_source = ext0;
            4'd2:  select_source = ext1;
            4'd3:  select_source = ext2;
            4'd4:  select_source = ext3;
            4'd5:  select_source = ext4;
            4'd6:  select_source = ext5;
            4'd7:  select_source = ext6;
            4'd8:  select_source = ext7;
            4'd9:  select_source = pe0_result;
            4'd10: select_source = pe1_result;
            4'd11: select_source = pe2_result;
            4'd12: select_source = pe3_result;
            4'd13: select_source = 32'd1;
            default: select_source = 32'd0;
        endcase
    end
endfunction

wire [31:0] pe0_a = select_source(ctx0[7:4]);
wire [31:0] pe0_b = select_source(ctx0[11:8]);
wire [31:0] pe1_a = select_source(ctx1[7:4]);
wire [31:0] pe1_b = select_source(ctx1[11:8]);
wire [31:0] pe2_a = select_source(ctx2[7:4]);
wire [31:0] pe2_b = select_source(ctx2[11:8]);
wire [31:0] pe3_a = select_source(ctx3[7:4]);
wire [31:0] pe3_b = select_source(ctx3[11:8]);

cgra_pe pe0 (
    .clk(clk), .resetb(resetb), .clear(clear),
    .enable(step && ctx0[12]), .op(ctx0[3:0]),
    .src_a(pe0_a), .src_b(pe0_b), .result(pe0_result)
);

cgra_pe pe1 (
    .clk(clk), .resetb(resetb), .clear(clear),
    .enable(step && ctx1[12]), .op(ctx1[3:0]),
    .src_a(pe1_a), .src_b(pe1_b), .result(pe1_result)
);

cgra_pe pe2 (
    .clk(clk), .resetb(resetb), .clear(clear),
    .enable(step && ctx2[12]), .op(ctx2[3:0]),
    .src_a(pe2_a), .src_b(pe2_b), .result(pe2_result)
);

cgra_pe pe3 (
    .clk(clk), .resetb(resetb), .clear(clear),
    .enable(step && ctx3[12]), .op(ctx3[3:0]),
    .src_a(pe3_a), .src_b(pe3_b), .result(pe3_result)
);

endmodule

`default_nettype wire
