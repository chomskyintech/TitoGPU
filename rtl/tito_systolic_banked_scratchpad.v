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
    integer r, c, idx;

    always @(posedge clk) begin
        if (wr_en) begin
            if (!wr_bank) begin
                if (wr_addr < N*K) begin
                    r = wr_addr / K;
                    idx = wr_addr % K;
                    a_mem[r][idx] <= wr_data;
                end
            end else begin
                if (wr_addr < N*K) begin
                    idx = wr_addr / N;
                    c = wr_addr % N;
                    b_mem[c][idx] <= wr_data;
                end
            end
        end
    end

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            a_rd_data <= {(N*DATA_W){1'b0}};
            b_rd_data <= {(N*DATA_W){1'b0}};
        end else if (rd_en) begin
            for (r = 0; r < N; r = r + 1)
                a_rd_data[r*DATA_W +: DATA_W] <=
                    a_mem[r][a_rd_addr[r*K_ADDR_W +: K_ADDR_W]];
            for (c = 0; c < N; c = c + 1)
                b_rd_data[c*DATA_W +: DATA_W] <=
                    b_mem[c][b_rd_addr[c*K_ADDR_W +: K_ADDR_W]];
        end
    end
endmodule

`default_nettype wire
