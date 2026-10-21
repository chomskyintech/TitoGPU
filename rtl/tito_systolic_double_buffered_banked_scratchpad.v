`default_nettype none

// Two independent A/B tile sets. One buffer may feed compute while the other
// is filled through the single write port. This is a register-array model,
// not a compiled SRAM macro.
module tito_systolic_double_buffered_banked_scratchpad #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer K_ADDR_W = (K > 1 ? $clog2(K) : 1),
    parameter integer ADDR_W = (N*K > 1 ? $clog2(N*K) : 1)
) (
    input  wire                       clk,
    input  wire                       resetb,
    input  wire                       wr_en,
    input  wire                       wr_buffer, // 0 or 1
    input  wire                       wr_bank,   // 0 = A, 1 = B
    input  wire [ADDR_W-1:0]          wr_addr,
    input  wire [DATA_W-1:0]          wr_data,
    input  wire                       rd_en,
    input  wire                       rd_buffer,
    input  wire [N*K_ADDR_W-1:0]      a_rd_addr,
    input  wire [N*K_ADDR_W-1:0]      b_rd_addr,
    output reg  [N*DATA_W-1:0]        a_rd_data,
    output reg  [N*DATA_W-1:0]        b_rd_data
);
    reg [DATA_W-1:0] a0_mem [0:N-1][0:K-1];
    reg [DATA_W-1:0] b0_mem [0:N-1][0:K-1];
    reg [DATA_W-1:0] a1_mem [0:N-1][0:K-1];
    reg [DATA_W-1:0] b1_mem [0:N-1][0:K-1];
    integer wr_row, wr_col, wr_idx;
    integer rd_row, rd_col;

    always @(posedge clk) begin
        if (wr_en && wr_addr < N*K) begin
            if (!wr_bank) begin
                wr_row = wr_addr / K;
                wr_idx = wr_addr % K;
                if (!wr_buffer)
                    a0_mem[wr_row][wr_idx] <= wr_data;
                else
                    a1_mem[wr_row][wr_idx] <= wr_data;
            end else begin
                wr_idx = wr_addr / N;
                wr_col = wr_addr % N;
                if (!wr_buffer)
                    b0_mem[wr_col][wr_idx] <= wr_data;
                else
                    b1_mem[wr_col][wr_idx] <= wr_data;
            end
        end
    end

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            a_rd_data <= {(N*DATA_W){1'b0}};
            b_rd_data <= {(N*DATA_W){1'b0}};
        end else if (rd_en) begin
            for (rd_row = 0; rd_row < N; rd_row = rd_row + 1) begin
                if (!rd_buffer)
                    a_rd_data[rd_row*DATA_W +: DATA_W] <=
                        a0_mem[rd_row][a_rd_addr[rd_row*K_ADDR_W +: K_ADDR_W]];
                else
                    a_rd_data[rd_row*DATA_W +: DATA_W] <=
                        a1_mem[rd_row][a_rd_addr[rd_row*K_ADDR_W +: K_ADDR_W]];
            end
            for (rd_col = 0; rd_col < N; rd_col = rd_col + 1) begin
                if (!rd_buffer)
                    b_rd_data[rd_col*DATA_W +: DATA_W] <=
                        b0_mem[rd_col][b_rd_addr[rd_col*K_ADDR_W +: K_ADDR_W]];
                else
                    b_rd_data[rd_col*DATA_W +: DATA_W] <=
                        b1_mem[rd_col][b_rd_addr[rd_col*K_ADDR_W +: K_ADDR_W]];
            end
        end
    end
endmodule

`default_nettype wire
