`default_nettype none

// Small behavioral dual-bank scratchpad for bring-up. Each bank stores
// signed INT8 matrix elements in row-major order. Synthesis may map these
// arrays to registers; a technology SRAM macro is not inferred or guaranteed.
module tito_systolic_scratchpad #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer A_DEPTH = N*K,
    parameter integer B_DEPTH = K*N,
    parameter integer ADDR_W = (A_DEPTH > B_DEPTH ? $clog2(A_DEPTH) : $clog2(B_DEPTH))
) (
    input  wire                         clk,
    input  wire                         wr_en,
    input  wire                         wr_bank, // 0 = A, 1 = B
    input  wire [ADDR_W-1:0]            wr_addr,
    input  wire [DATA_W-1:0]            wr_data,
    output wire [N*K*DATA_W-1:0]        a_matrix,
    output wire [K*N*DATA_W-1:0]        b_matrix
);
    reg [DATA_W-1:0] a_mem [0:A_DEPTH-1];
    reg [DATA_W-1:0] b_mem [0:B_DEPTH-1];

    always @(posedge clk) begin
        if (wr_en) begin
            if (!wr_bank) begin
                if (wr_addr < A_DEPTH)
                    a_mem[wr_addr] <= wr_data;
            end else begin
                if (wr_addr < B_DEPTH)
                    b_mem[wr_addr] <= wr_data;
            end
        end
    end

    genvar ga;
    genvar gb;
    generate
        for (ga = 0; ga < A_DEPTH; ga = ga + 1) begin : gen_a_out
            assign a_matrix[(ga*DATA_W) +: DATA_W] = a_mem[ga];
        end
        for (gb = 0; gb < B_DEPTH; gb = gb + 1) begin : gen_b_out
            assign b_matrix[(gb*DATA_W) +: DATA_W] = b_mem[gb];
        end
    endgenerate
endmodule

`default_nettype wire
