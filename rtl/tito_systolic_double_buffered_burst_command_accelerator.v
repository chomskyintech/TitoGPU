`default_nettype none

// Burst ingress for a double-buffered command accelerator. The descriptor
// selects the inactive tile buffer; data beats may arrive while the other
// buffer is being computed.
module tito_systolic_double_buffered_burst_command_accelerator #(
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
    input  wire                         burst_buffer,
    input  wire                         burst_bank,
    input  wire [MEM_ADDR_W-1:0]        burst_base_addr,
    input  wire [BURST_LEN_W-1:0]       burst_len,
    input  wire                         data_valid,
    output wire                         data_ready,
    input  wire [DATA_W-1:0]            data,
    input  wire                         packed_data_valid,
    output wire                         packed_data_ready,
    input  wire [4*DATA_W-1:0]          packed_data,
    input  wire [3:0]                   packed_data_mask,

    output reg                          burst_done,
    output reg                          burst_error,

    input  wire                         cmd_start,
    input  wire                         cmd_accumulate,
    input  wire                         cmd_buffer,
    output wire                         busy,
    output wire                         done,

    input  wire                         result_rd_en,
    input  wire [RESULT_ADDR_W-1:0]     result_rd_addr,
    output wire [ACC_W-1:0]             result_rd_data,
    output wire                         result_rd_valid
);
    reg burst_active;
    reg burst_buffer_q;
    reg burst_bank_q;
    reg [MEM_ADDR_W-1:0] burst_base_q;
    reg [BURST_LEN_W-1:0] burst_len_q;
    reg [BURST_LEN_W-1:0] burst_count;

    wire mem_wr_ready;
    wire pack_wr_ready;
    wire mem_wr_en;
    wire pack_wr_en;
    wire packed_handshake;
    wire [2:0] packed_lane_count;
    wire [MEM_ADDR_W-1:0] pack_wr_base;
    wire [MEM_ADDR_W-1:0] mem_wr_addr;
    wire mem_wr_buffer = burst_active ? burst_buffer_q : burst_buffer;

    assign burst_start_ready = !burst_active && mem_wr_ready && !cmd_start;
    assign data_ready = burst_active && mem_wr_ready && !packed_data_valid;
    assign packed_data_ready = burst_active && pack_wr_ready && !data_valid;
    assign mem_wr_en = data_valid && data_ready;
    assign pack_wr_en = packed_data_valid && packed_data_ready;
    assign packed_handshake = pack_wr_en;
    assign packed_lane_count = {2'b0,packed_data_mask[0]} + {2'b0,packed_data_mask[1]} +
                               {2'b0,packed_data_mask[2]} + {2'b0,packed_data_mask[3]};
    assign mem_wr_addr = burst_base_q + burst_count;
    assign pack_wr_base = burst_base_q + burst_count;

    tito_systolic_double_buffered_command_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W)
    ) command_core (
        .clk(clk), .resetb(resetb),
        .mem_wr_en(mem_wr_en), .mem_wr_ready(mem_wr_ready),
        .mem_wr_buffer(mem_wr_buffer), .mem_wr_bank(burst_bank_q),
        .mem_wr_addr(mem_wr_addr), .mem_wr_data(data),
        .pack_wr_en(pack_wr_en), .pack_wr_ready(pack_wr_ready),
        .pack_wr_buffer(mem_wr_buffer), .pack_wr_bank(burst_bank_q),
        .pack_wr_base(pack_wr_base), .pack_wr_data(packed_data), .pack_wr_mask(packed_data_mask),
        .cmd_start(cmd_start), .cmd_accumulate(cmd_accumulate),
        .cmd_buffer(cmd_buffer), .busy(busy), .done(done),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            burst_active <= 1'b0;
            burst_buffer_q <= 1'b0;
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
                    burst_buffer_q <= burst_buffer;
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

            if (packed_handshake) begin
                if ((packed_lane_count == 0) ||
                    (burst_count + packed_lane_count > burst_len_q)) begin
                    burst_active <= 1'b0;
                    burst_error <= 1'b1;
                end else if (burst_count + packed_lane_count == burst_len_q) begin
                    burst_active <= 1'b0;
                    burst_done <= 1'b1;
                end else begin
                    burst_count <= burst_count + packed_lane_count;
                end
            end
        end
    end
endmodule

`default_nettype wire
