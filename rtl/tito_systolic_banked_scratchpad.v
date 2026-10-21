`default_nettype none

// Banked synchronous-read scratchpad for a square systolic tile.
// A is banked by row; B is banked by column. Each bank has one write port
// (shared through wr_en/wr_bank/wr_addr) and one synchronous read port.
// This is a synthesizable register-array model, not a compiled SRAM macro.
module tito_systolic_banked_scratchpad #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer K_ADDR_W = (K > 1 ? $clog2(K) : 1),
    parameter integer ADDR_W = (N*K > 1 ? $clog2(N*K) : 1)
) (
    input  wire                       clk,
    input  wire                       resetb,
    input  wire                       wr_en,
    input  wire                       wr_bank, // 0 = A, 1 = B
    input  wire [ADDR_W-1:0]          wr_addr,
    input  wire [DATA_W-1:0]          wr_data,
    input  wire                       rd_en,
    input  wire [N*K_ADDR_W-1:0]      a_rd_addr,
    input  wire [N*K_ADDR_W-1:0]      b_rd_addr,
    output reg  [N*DATA_W-1:0]        a_rd_data,
    output reg  [N*DATA_W-1:0]        b_rd_data
);
    reg [DATA_W-1:0] a_mem [0:N-1][0:K-1];
    reg [DATA_W-1:0] b_mem [0:N-1][0:K-1];
    integer wr_row, wr_col, wr_idx;
    integer rd_row, rd_col;

    always @(posedge clk) begin
        if (wr_en) begin
            if (!wr_bank) begin
                if (wr_addr < N*K) begin
                    wr_row = wr_addr / K;
                    wr_idx = wr_addr % K;
                    a_mem[wr_row][wr_idx] <= wr_data;
                end
            end else begin
                if (wr_addr < N*K) begin
                    wr_idx = wr_addr / N;
                    wr_col = wr_addr % N;
                    b_mem[wr_col][wr_idx] <= wr_data;
                end
            end
        end
    end

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            a_rd_data <= {(N*DATA_W){1'b0}};
            b_rd_data <= {(N*DATA_W){1'b0}};
        end else if (rd_en) begin
            for (rd_row = 0; rd_row < N; rd_row = rd_row + 1)
                a_rd_data[rd_row*DATA_W +: DATA_W] <=
                    a_mem[rd_row][a_rd_addr[rd_row*K_ADDR_W +: K_ADDR_W]];
            for (rd_col = 0; rd_col < N; rd_col = rd_col + 1)
                b_rd_data[rd_col*DATA_W +: DATA_W] <=
                    b_mem[rd_col][b_rd_addr[rd_col*K_ADDR_W +: K_ADDR_W]];
        end
    end
endmodule

`default_nettype wire
