`default_nettype none

// Parameterized signed INT8 systolic MAC array prototype.
// A operands enter from the left, one stream per row; B operands enter
// from the top, one stream per column. The source streams must be skewed
// by row/column so matching reduction terms meet at each processing element.
module tito_systolic_mac #(
    parameter integer N = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32
) (
    input  wire                       clk,
    input  wire                       resetb,
    input  wire                       clear,
    input  wire                       enable,
    input  wire [N-1:0]               a_valid,
    input  wire [N-1:0]               b_valid,
    input  wire [N*DATA_W-1:0]        a_in,
    input  wire [N*DATA_W-1:0]        b_in,
    output wire [N*N*ACC_W-1:0]       accum_out
);

    reg signed [DATA_W-1:0] a_pipe [0:N-1][0:N-1];
    reg signed [DATA_W-1:0] b_pipe [0:N-1][0:N-1];
    reg                     a_valid_pipe [0:N-1][0:N-1];
    reg                     b_valid_pipe [0:N-1][0:N-1];
    reg signed [ACC_W-1:0]  accum [0:N-1][0:N-1];

    integer i;
    integer j;

    function signed [ACC_W-1:0] sign_extend_product;
        input signed [DATA_W-1:0] a;
        input signed [DATA_W-1:0] b;
        reg signed [(2*DATA_W)-1:0] product;
        begin
            product = a * b;
            sign_extend_product = {{(ACC_W-(2*DATA_W)){product[(2*DATA_W)-1]}}, product};
        end
    endfunction

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    a_pipe[i][j] <= {DATA_W{1'b0}};
                    b_pipe[i][j] <= {DATA_W{1'b0}};
                    a_valid_pipe[i][j] <= 1'b0;
                    b_valid_pipe[i][j] <= 1'b0;
                    accum[i][j] <= {ACC_W{1'b0}};
                end
            end
        end else if (clear) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    a_pipe[i][j] <= {DATA_W{1'b0}};
                    b_pipe[i][j] <= {DATA_W{1'b0}};
                    a_valid_pipe[i][j] <= 1'b0;
                    b_valid_pipe[i][j] <= 1'b0;
                    accum[i][j] <= {ACC_W{1'b0}};
                end
            end
        end else if (enable) begin
            // Activation/left operand stream: shift across each row.
            for (i = 0; i < N; i = i + 1) begin
                a_pipe[i][0] <= a_in[i*DATA_W +: DATA_W];
                a_valid_pipe[i][0] <= a_valid[i];
                for (j = 1; j < N; j = j + 1) begin
                    a_pipe[i][j] <= a_pipe[i][j-1];
                    a_valid_pipe[i][j] <= a_valid_pipe[i][j-1];
                end
            end

            // Weight/top operand stream: shift down each column.
            for (j = 0; j < N; j = j + 1) begin
                b_pipe[0][j] <= b_in[j*DATA_W +: DATA_W];
                b_valid_pipe[0][j] <= b_valid[j];
                for (i = 1; i < N; i = i + 1) begin
                    b_pipe[i][j] <= b_pipe[i-1][j];
                    b_valid_pipe[i][j] <= b_valid_pipe[i-1][j];
                end
            end

            // Multiply-accumulate uses the aligned values already in each PE.
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    if (a_valid_pipe[i][j] && b_valid_pipe[i][j])
                        accum[i][j] <= accum[i][j] +
                            sign_extend_product(a_pipe[i][j], b_pipe[i][j]);
                end
            end
        end
    end

    genvar row;
    genvar col;
    generate
        for (row = 0; row < N; row = row + 1) begin : gen_rows
            for (col = 0; col < N; col = col + 1) begin : gen_cols
                assign accum_out[((row*N+col)*ACC_W) +: ACC_W] = accum[row][col];
            end
        end
    endgenerate

endmodule

`default_nettype wire
