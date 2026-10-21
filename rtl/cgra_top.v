`default_nettype none

module cgra_top (
    input  wire        clk,
    input  wire        resetb,

    input  wire        cfg_we,
    input  wire [1:0]  cfg_pe,
    input  wire [2:0]  cfg_context,
    input  wire [31:0] cfg_wdata,

    input  wire [3:0]  run_cycles,
    input  wire        start,

    input  wire [31:0] ext0,
    input  wire [31:0] ext1,
    input  wire [31:0] ext2,
    input  wire [31:0] ext3,
    input  wire [31:0] ext4,
    input  wire [31:0] ext5,
    input  wire [31:0] ext6,
    input  wire [31:0] ext7,

    output reg         busy,
    output reg         done,
    output reg  [2:0]  cycle_index,

    output wire [31:0] result0,
    output wire [31:0] result1,
    output wire [31:0] result2,
    output wire [31:0] result3
);

reg [31:0] context_mem0 [0:7];
reg [31:0] context_mem1 [0:7];
reg [31:0] context_mem2 [0:7];
reg [31:0] context_mem3 [0:7];

reg [31:0] in0;
reg [31:0] in1;
reg [31:0] in2;
reg [31:0] in3;
reg [31:0] in4;
reg [31:0] in5;
reg [31:0] in6;
reg [31:0] in7;
reg [3:0]  cycles_latched;

wire [31:0] current_ctx0 = context_mem0[cycle_index];
wire [31:0] current_ctx1 = context_mem1[cycle_index];
wire [31:0] current_ctx2 = context_mem2[cycle_index];
wire [31:0] current_ctx3 = context_mem3[cycle_index];

integer i;
always @(posedge clk or negedge resetb) begin
    if (!resetb) begin
        busy <= 1'b0;
        done <= 1'b0;
        cycle_index <= 3'd0;
        cycles_latched <= 4'd1;
        in0 <= 32'd0;
        in1 <= 32'd0;
        in2 <= 32'd0;
        in3 <= 32'd0;
        in4 <= 32'd0;
        in5 <= 32'd0;
        in6 <= 32'd0;
        in7 <= 32'd0;

        for (i = 0; i < 8; i = i + 1) begin
            context_mem0[i] <= 32'd0;
            context_mem1[i] <= 32'd0;
            context_mem2[i] <= 32'd0;
            context_mem3[i] <= 32'd0;
        end
    end else begin
        done <= 1'b0;

        if (cfg_we && !busy) begin
            case (cfg_pe)
                2'd0: context_mem0[cfg_context] <= cfg_wdata;
                2'd1: context_mem1[cfg_context] <= cfg_wdata;
                2'd2: context_mem2[cfg_context] <= cfg_wdata;
                2'd3: context_mem3[cfg_context] <= cfg_wdata;
            endcase
        end

        if (start && !busy) begin
            busy <= 1'b1;
            cycle_index <= 3'd0;
            cycles_latched <= (run_cycles == 0) ? 4'd1 :
                              (run_cycles > 8)  ? 4'd8 : run_cycles;
            in0 <= ext0;
            in1 <= ext1;
            in2 <= ext2;
            in3 <= ext3;
            in4 <= ext4;
            in5 <= ext5;
            in6 <= ext6;
            in7 <= ext7;
        end else if (busy) begin
            if ({1'b0, cycle_index} + 4'd1 >= cycles_latched) begin
                busy <= 1'b0;
                done <= 1'b1;
            end else begin
                cycle_index <= cycle_index + 3'd1;
            end
        end
    end
end

cgra_array array (
    .clk(clk),
    .resetb(resetb),
    .clear(start && !busy),
    .step(busy),
    .ctx0(current_ctx0),
    .ctx1(current_ctx1),
    .ctx2(current_ctx2),
    .ctx3(current_ctx3),
    .ext0(in0), .ext1(in1), .ext2(in2), .ext3(in3),
    .ext4(in4), .ext5(in5), .ext6(in6), .ext7(in7),
    .pe0_result(result0),
    .pe1_result(result1),
    .pe2_result(result2),
    .pe3_result(result3)
);

endmodule

`default_nettype wire
