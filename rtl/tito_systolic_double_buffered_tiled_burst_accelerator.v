`default_nettype none

// Ping-pong K-tile controller. While one buffer computes, the next tile's
// A/B bursts may fill the other buffer. It launches the next compute as soon
// as both the prior compute and next-tile load have completed.
module tito_systolic_double_buffered_tiled_burst_accelerator #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32,
    parameter integer MEM_ADDR_W = (N*K > 1 ? $clog2(N*K) : 1),
    parameter integer RESULT_ADDR_W = (N*N > 1 ? $clog2(N*N) : 1),
    parameter integer BURST_LEN_W = (N*K > 1 ? $clog2(N*K+1) : 1),
    parameter integer TILE_COUNT_W = 8
) (
    input  wire                         clk,
    input  wire                         resetb,

    input  wire                         op_start,
    input  wire [TILE_COUNT_W-1:0]      op_tile_count,
    output wire                         op_busy,
    output reg                          op_done,
    output reg                          op_error,

    input  wire                         burst_start_valid,
    output wire                         burst_start_ready,
    input  wire                         burst_bank,
    input  wire [MEM_ADDR_W-1:0]        burst_base_addr,
    input  wire [BURST_LEN_W-1:0]       burst_len,
    input  wire                         data_valid,
    output wire                         data_ready,
    input  wire [DATA_W-1:0]            data,

    input  wire                         result_rd_en,
    input  wire [RESULT_ADDR_W-1:0]     result_rd_addr,
    output wire [ACC_W-1:0]             result_rd_data,
    output wire                         result_rd_valid
);
    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_LOAD_FIRST = 3'd1;
    localparam [2:0] ST_RUN        = 3'd2;
    localparam [2:0] ST_WAIT_FINAL = 3'd3;
    localparam [2:0] ST_ERROR      = 3'd4;

    reg [2:0] state;
    reg [TILE_COUNT_W-1:0] tile_count_q;
    reg [TILE_COUNT_W-1:0] load_index;
    reg [TILE_COUNT_W-1:0] compute_index;
    reg a_loaded, b_loaded;
    reg active_burst_bank;
    reg cmd_start;
    reg cmd_buffer_q;
    reg compute_done_q;
    reg next_ready_q;

    wire cmd_accumulate = (compute_index != 0);
    wire burst_start_ready_core;
    wire burst_done;
    wire burst_error;
    wire core_busy;
    wire core_done;
    wire core_resetb;
    wire [MEM_ADDR_W-1:0] burst_base_unused;
    wire [BURST_LEN_W-1:0] burst_len_unused;

    assign op_busy = (state != ST_IDLE) && (state != ST_ERROR);
    assign core_resetb = resetb && (state != ST_ERROR);

    assign burst_start_ready = ((state == ST_LOAD_FIRST) ||
        ((state == ST_RUN) && (load_index < tile_count_q))) &&
        burst_start_ready_core &&
        !(burst_bank ? b_loaded : a_loaded) && !burst_done;
    wire burst_start_valid_core;
    assign burst_start_valid_core = burst_start_valid && burst_start_ready;

    tito_systolic_double_buffered_burst_command_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W),
        .BURST_LEN_W(BURST_LEN_W)
    ) burst_core (
        .clk(clk), .resetb(core_resetb),
        .burst_start_valid(burst_start_valid_core),
        .burst_start_ready(burst_start_ready_core),
        .burst_buffer(load_index[0]), .burst_bank(burst_bank),
        .burst_base_addr(burst_base_addr), .burst_len(burst_len),
        .data_valid(data_valid), .data_ready(data_ready), .data(data),
        .burst_done(burst_done), .burst_error(burst_error),
        .cmd_start(cmd_start), .cmd_accumulate(cmd_accumulate),
        .cmd_buffer(cmd_buffer_q), .busy(core_busy), .done(core_done),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    wire a_loaded_now = a_loaded || (burst_done && !active_burst_bank);
    wire b_loaded_now = b_loaded || (burst_done && active_burst_bank);
    wire pair_loaded_now = a_loaded_now && b_loaded_now;

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            state <= ST_IDLE;
            tile_count_q <= {TILE_COUNT_W{1'b0}};
            load_index <= {TILE_COUNT_W{1'b0}};
            compute_index <= {TILE_COUNT_W{1'b0}};
            a_loaded <= 1'b0;
            b_loaded <= 1'b0;
            active_burst_bank <= 1'b0;
            cmd_start <= 1'b0;
            cmd_buffer_q <= 1'b0;
            compute_done_q <= 1'b0;
            next_ready_q <= 1'b0;
            op_done <= 1'b0;
            op_error <= 1'b0;
        end else begin
            cmd_start <= 1'b0;
            op_done <= 1'b0;

            if (burst_start_valid && burst_start_ready)
                active_burst_bank <= burst_bank;

            if (burst_error) begin
                state <= ST_ERROR;
                op_error <= 1'b1;
                a_loaded <= 1'b0;
                b_loaded <= 1'b0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        op_error <= 1'b0;
                        if (op_start) begin
                            if (op_tile_count == 0) begin
                                op_error <= 1'b1;
                                state <= ST_ERROR;
                            end else begin
                                tile_count_q <= op_tile_count;
                                load_index <= {TILE_COUNT_W{1'b0}};
                                compute_index <= {TILE_COUNT_W{1'b0}};
                                a_loaded <= 1'b0;
                                b_loaded <= 1'b0;
                                compute_done_q <= 1'b0;
                                next_ready_q <= 1'b0;
                                state <= ST_LOAD_FIRST;
                            end
                        end
                    end
                    ST_LOAD_FIRST: begin
                        if (burst_done) begin
                            if (active_burst_bank) b_loaded <= 1'b1;
                            else a_loaded <= 1'b1;
                        end
                        if (pair_loaded_now) begin
                            cmd_start <= 1'b1;
                            cmd_buffer_q <= load_index[0];
                            compute_index <= load_index;
                            compute_done_q <= 1'b0;
                            if (tile_count_q > 1) begin
                                load_index <= {{(TILE_COUNT_W-1){1'b0}},1'b1};
                                a_loaded <= 1'b0;
                                b_loaded <= 1'b0;
                                next_ready_q <= 1'b0;
                                state <= ST_RUN;
                            end else begin
                                state <= ST_WAIT_FINAL;
                            end
                        end
                    end
                    ST_RUN: begin
                        if (burst_done) begin
                            if (active_burst_bank) b_loaded <= 1'b1;
                            else a_loaded <= 1'b1;
                        end
                        if (pair_loaded_now)
                            next_ready_q <= 1'b1;
                        if (core_done)
                            compute_done_q <= 1'b1;

                        if ((compute_done_q || core_done) &&
                            (next_ready_q || pair_loaded_now)) begin
                            cmd_start <= 1'b1;
                            cmd_buffer_q <= load_index[0];
                            compute_index <= load_index;
                            compute_done_q <= 1'b0;
                            next_ready_q <= 1'b0;
                            a_loaded <= 1'b0;
                            b_loaded <= 1'b0;
                            if (load_index + 1'b1 < tile_count_q) begin
                                load_index <= load_index + 1'b1;
                                state <= ST_RUN;
                            end else begin
                                state <= ST_WAIT_FINAL;
                            end
                        end
                    end
                    ST_WAIT_FINAL: begin
                        if (core_done) begin
                            op_done <= 1'b1;
                            state <= ST_IDLE;
                            a_loaded <= 1'b0;
                            b_loaded <= 1'b0;
                        end
                    end
                    ST_ERROR: begin
                        a_loaded <= 1'b0;
                        b_loaded <= 1'b0;
                    end
                    default: state <= ST_ERROR;
                endcase
            end
        end
    end
endmodule

`default_nettype wire
