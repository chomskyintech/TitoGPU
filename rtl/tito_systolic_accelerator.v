`default_nettype none

// Bring-up accelerator wrapper: software/testbench writes A and B matrices
// into local scratchpad banks, then starts the systolic matrix engine.
module tito_systolic_accelerator #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32,
    parameter integer A_DEPTH = N*K,
    parameter integer B_DEPTH = K*N,
    parameter integer ADDR_W = (A_DEPTH > B_DEPTH ? $clog2(A_DEPTH) : $clog2(B_DEPTH))
) (
    input  wire                         clk,
    input  wire                         resetb,
    input  wire                         wr_en,
    input  wire                         wr_bank,
    input  wire [ADDR_W-1:0]            wr_addr,
    input  wire [DATA_W-1:0]            wr_data,
    input  wire                         start,
    output wire [N*N*ACC_W-1:0]         accum_out,
    output wire                         busy,
    output wire                         done
);
    wire [N*K*DATA_W-1:0] a_matrix;
    wire [K*N*DATA_W-1:0] b_matrix;

    tito_systolic_scratchpad #(
        .N(N), .K(K), .DATA_W(DATA_W),
        .A_DEPTH(A_DEPTH), .B_DEPTH(B_DEPTH), .ADDR_W(ADDR_W)
    ) scratchpad (
        .clk(clk), .wr_en(wr_en), .wr_bank(wr_bank),
        .wr_addr(wr_addr), .wr_data(wr_data),
        .a_matrix(a_matrix), .b_matrix(b_matrix)
    );

    tito_systolic_matmul #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W)
    ) matmul (
        .clk(clk), .resetb(resetb), .start(start),
        .a_matrix(a_matrix), .b_matrix(b_matrix),
        .accum_out(accum_out), .busy(busy), .done(done)
    );
endmodule

`default_nettype wire
