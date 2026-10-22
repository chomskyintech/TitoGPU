`default_nettype none

// DMA-compatible streaming write ingress around the tile command accelerator.
// This module accepts a burst descriptor, then a ready/valid stream of data
// beats. It does not fetch data from external memory itself.
module tito_systolic_burst_command_accelerator #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32,
    parameter integer MEM_ADDR_W = (N*K > 1 ? $clog2(N*K) : 1),
    parameter integer RESULT_ADDR_W = (N*N > 1 ? $clog2(N*N) : 1),
    parameter integer BURST_LEN_W = (N*K > 1 ? $clog2(N*K+1) : 1)
) (
    input  wire                         clk,
    input  wire                         resetb,

    input  wire                         burst_start_valid,
    output wire                         burst_start_ready,
    input  wire                         burst_bank, // 0 = A, 1 = B
    input  wire [MEM_ADDR_W-1:0]        burst_base_addr,
    input  wire [BURST_LEN_W-1:0]       burst_len,
    input  wire                         data_valid,
    output wire                         data_ready,
    input  wire [DATA_W-1:0]            data,

    output reg                          burst_done,
    output reg                          burst_error,

    input  wire                         cmd_start,
    input  wire                         cmd_accumulate,
    output wire                         busy,
    output wire                         done,

    input  wire                         result_rd_en,
    input  wire [RESULT_ADDR_W-1:0]     result_rd_addr,
    output wire [ACC_W-1:0]             result_rd_data,
    output wire                         result_rd_valid
);
    reg burst_active;
    reg burst_bank_q;
    reg [MEM_ADDR_W-1:0] burst_base_q;
    reg [BURST_LEN_W-1:0] burst_len_q;
    reg [BURST_LEN_W-1:0] burst_count;

    wire mem_wr_ready;
    wire mem_wr_en;
    wire [MEM_ADDR_W-1:0] mem_wr_addr;
    wire cmd_start_internal;

    // Do not accept a new burst descriptor on the same cycle as a command.
    assign burst_start_ready = !burst_active && mem_wr_ready && !cmd_start;
    assign data_ready = burst_active && mem_wr_ready;
    assign mem_wr_en = data_valid && data_ready;
    assign mem_wr_addr = burst_base_q + burst_count;
    assign cmd_start_internal = cmd_start && !burst_active;

    tito_systolic_command_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W)
    ) command_core (
        .clk(clk), .resetb(resetb),
        .mem_wr_en(mem_wr_en), .mem_wr_ready(mem_wr_ready),
        .mem_wr_bank(burst_bank_q), .mem_wr_addr(mem_wr_addr), .mem_wr_data(data),
        .cmd_start(cmd_start_internal), .cmd_accumulate(cmd_accumulate),
        .busy(busy), .done(done),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            burst_active <= 1'b0;
            burst_bank_q <= 1'b0;
            burst_base_q <= {MEM_ADDR_W{1'b0}};
            burst_len_q <= {BURST_LEN_W{1'b0}};
            burst_count <= {BURST_LEN_W{1'b0}};
            burst_done <= 1'b0;
            burst_error <= 1'b0;
        end else begin
            burst_done <= 1'b0;
            burst_error <= 1'b0;

            if (burst_start_valid && burst_start_ready) begin
                if ((burst_len == 0) ||
                    (burst_len > N*K) ||
                    (($unsigned(burst_base_addr) + $unsigned(burst_len)) > N*K)) begin
                    burst_error <= 1'b1;
                    burst_active <= 1'b0;
                end else begin
                    burst_active <= 1'b1;
                    burst_bank_q <= burst_bank;
                    burst_base_q <= burst_base_addr;
                    burst_len_q <= burst_len;
                    burst_count <= {BURST_LEN_W{1'b0}};
                end
            end

            if (data_valid && data_ready) begin
                if (burst_count == burst_len_q - 1'b1) begin
                    burst_active <= 1'b0;
                    burst_done <= 1'b1;
                end else begin
                    burst_count <= burst_count + 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
