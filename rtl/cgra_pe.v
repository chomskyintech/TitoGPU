`default_nettype none

module cgra_pe (
    input  wire        clk,
    input  wire        resetb,
    input  wire        clear,
    input  wire        enable,
    input  wire [3:0]  op,
    input  wire [31:0] src_a,
    input  wire [31:0] src_b,
    output reg  [31:0] result
);

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

wire signed [7:0]  a8 = src_a[7:0];
wire signed [7:0]  b8 = src_b[7:0];
wire signed [15:0] mul8 = a8 * b8;

reg [31:0] next_result;

always @* begin
    case (op)
        OP_NOP:   next_result = result;
        OP_ADD:   next_result = src_a + src_b;
        OP_SUB:   next_result = src_a - src_b;
        OP_MUL8:  next_result = {{16{mul8[15]}}, mul8};
        OP_AND:   next_result = src_a & src_b;
        OP_OR:    next_result = src_a | src_b;
        OP_XOR:   next_result = src_a ^ src_b;
        OP_MAX:   next_result = ($signed(src_a) >= $signed(src_b)) ? src_a : src_b;
        OP_MIN:   next_result = ($signed(src_a) <= $signed(src_b)) ? src_a : src_b;
        OP_SHL:   next_result = src_a << src_b[4:0];
        OP_SHR:   next_result = $signed(src_a) >>> src_b[4:0];
        OP_PASSA: next_result = src_a;
        OP_PASSB: next_result = src_b;
        default:  next_result = result;
    endcase
end

always @(posedge clk or negedge resetb) begin
    if (!resetb)
        result <= 32'd0;
    else if (clear)
        result <= 32'd0;
    else if (enable)
        result <= next_result;
end

endmodule

`default_nettype wire
