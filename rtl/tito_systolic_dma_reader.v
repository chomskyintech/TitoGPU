`default_nettype none

// Single-outstanding external-memory read front-end for the tiled systolic core.
// The memory-side interface is a generic ready/valid request + response contract,
// not an AXI implementation. Addresses are measured in DATA_W-bit beats.
module tito_systolic_dma_reader #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32,
    parameter integer ADDR_W = 32,
    parameter integer MEM_ADDR_W = (N*K > 1 ? $clog2(N*K) : 1),
    parameter integer RESULT_ADDR_W = (N*N > 1 ? $clog2(N*N) : 1),
    parameter integer BURST_LEN_W = (N*K > 1 ? $clog2(N*K+1) : 1),
    parameter integer TILE_COUNT_W = 8
) (
    input  wire                         clk,
    input  wire                         resetb,

    input  wire                         op_start,
    input  wire [ADDR_W-1:0]            a_base_addr,
    input  wire [ADDR_W-1:0]            b_base_addr,
    input  wire [TILE_COUNT_W-1:0]      op_tile_count,
    output wire                         op_busy,
    output reg                          op_done,
    output reg                          op_error,

    output reg                          rd_req_valid,
    input  wire                         rd_req_ready,
    output reg  [ADDR_W-1:0]            rd_req_addr,
    output reg  [BURST_LEN_W-1:0]       rd_req_len,
    input  wire                         rd_data_valid,
    output wire                         rd_data_ready,
    input  wire [DATA_W-1:0]            rd_data,
    input  wire                         rd_data_last,
    input  wire                         rd_error,

    input  wire                         result_rd_en,
    input  wire [RESULT_ADDR_W-1:0]     result_rd_addr,
    output wire [ACC_W-1:0]             result_rd_data,
    output wire                         result_rd_valid
);
    localparam integer TILE_BEATS = N*K;
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_A_DESC     = 4'd1;
    localparam [3:0] ST_A_REQ      = 4'd2;
    localparam [3:0] ST_A_DATA     = 4'd3;
    localparam [3:0] ST_B_DESC     = 4'd4;
    localparam [3:0] ST_B_REQ      = 4'd5;
    localparam [3:0] ST_B_DATA     = 4'd6;
    localparam [3:0] ST_NEXT_TILE  = 4'd7;
    localparam [3:0] ST_DONE       = 4'd8;
    localparam [3:0] ST_ERROR      = 4'd9;

    reg [3:0] state;
    reg [ADDR_W-1:0] a_base_q, b_base_q;
    reg [TILE_COUNT_W-1:0] tile_count_q, tile_index;
    reg [BURST_LEN_W-1:0] beat_count;
    reg burst_desc_valid;
    reg burst_bank;
    reg [MEM_ADDR_W-1:0] burst_base;
    reg [BURST_LEN_W-1:0] burst_len;
    wire burst_desc_ready;
    wire local_data_ready;
    wire local_data_valid;
    wire local_op_busy;
    wire local_op_done;
    wire local_op_error;
    wire core_resetb;

    assign op_busy = (state != ST_IDLE) && (state != ST_DONE) && (state != ST_ERROR);
    assign rd_data_ready = ((state == ST_A_DATA) || (state == ST_B_DATA)) && local_data_ready;
    assign local_data_valid = rd_data_valid && ((state == ST_A_DATA) || (state == ST_B_DATA));
    // Keep the local core reset after a fatal protocol/memory error. Recovery is
    // explicit: external reset is required, so a partial burst cannot remain live.
    assign core_resetb = resetb && (state != ST_ERROR);

    tito_systolic_tiled_burst_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W),
        .BURST_LEN_W(BURST_LEN_W), .TILE_COUNT_W(TILE_COUNT_W)
    ) tiled_core (
        .clk(clk), .resetb(core_resetb),
        .op_start(op_start_internal), .op_tile_count(tile_count_q),
        .op_busy(local_op_busy), .op_done(local_op_done), .op_error(local_op_error),
        .burst_start_valid(burst_desc_valid), .burst_start_ready(burst_desc_ready),
        .burst_bank(burst_bank), .burst_base_addr(burst_base),
        .burst_len(burst_len), .data_valid(local_data_valid),
        .data_ready(local_data_ready), .data(rd_data),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    reg op_start_internal;
    wire expected_last;
    assign expected_last = (beat_count == TILE_BEATS-1);

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            state <= ST_IDLE;
            a_base_q <= {ADDR_W{1'b0}};
            b_base_q <= {ADDR_W{1'b0}};
            tile_count_q <= {TILE_COUNT_W{1'b0}};
            tile_index <= {TILE_COUNT_W{1'b0}};
            beat_count <= {BURST_LEN_W{1'b0}};
            rd_req_valid <= 1'b0;
            rd_req_addr <= {ADDR_W{1'b0}};
            rd_req_len <= {BURST_LEN_W{1'b0}};
            burst_desc_valid <= 1'b0;
            burst_bank <= 1'b0;
            burst_base <= {MEM_ADDR_W{1'b0}};
            burst_len <= TILE_BEATS;
            op_start_internal <= 1'b0;
            op_done <= 1'b0;
            op_error <= 1'b0;
        end else begin
            op_start_internal <= 1'b0;
            op_done <= 1'b0;

            if (local_op_error) begin
                state <= ST_ERROR;
                op_error <= 1'b1;
                rd_req_valid <= 1'b0;
                burst_desc_valid <= 1'b0;
            end else if ((state == ST_A_DATA || state == ST_B_DATA) && rd_error) begin
                state <= ST_ERROR;
                op_error <= 1'b1;
                rd_req_valid <= 1'b0;
                burst_desc_valid <= 1'b0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        op_error <= 1'b0;
                        if (op_start) begin
                            if (op_tile_count == 0) begin
                                op_error <= 1'b1;
                                state <= ST_ERROR;
                            end else begin
                                a_base_q <= a_base_addr;
                                b_base_q <= b_base_addr;
                                tile_count_q <= op_tile_count;
                                tile_index <= {TILE_COUNT_W{1'b0}};
                                op_start_internal <= 1'b1;
                                burst_desc_valid <= 1'b0;
                                rd_req_valid <= 1'b0;
                                state <= ST_A_DESC;
                            end
                        end
                    end
                    ST_A_DESC: begin
                        burst_desc_valid <= 1'b1;
                        burst_bank <= 1'b0;
                        burst_base <= {MEM_ADDR_W{1'b0}};
                        burst_len <= TILE_BEATS;
                        if (burst_desc_valid && burst_desc_ready) begin
                            burst_desc_valid <= 1'b0;
                            rd_req_addr <= a_base_q + tile_index*TILE_BEATS;
                            rd_req_len <= TILE_BEATS;
                            rd_req_valid <= 1'b1;
                            state <= ST_A_REQ;
                        end
                    end
                    ST_A_REQ: begin
                        if (rd_req_valid && rd_req_ready) begin
                            rd_req_valid <= 1'b0;
                            beat_count <= {BURST_LEN_W{1'b0}};
                            state <= ST_A_DATA;
                        end
                    end
                    ST_A_DATA: begin
                        if (rd_data_valid && rd_data_ready) begin
                            if (rd_data_last != expected_last) begin
                                state <= ST_ERROR;
                                op_error <= 1'b1;
                            end else if (expected_last) begin
                                state <= ST_B_DESC;
                            end else begin
                                beat_count <= beat_count + 1'b1;
                            end
                        end
                    end
                    ST_B_DESC: begin
                        burst_desc_valid <= 1'b1;
                        burst_bank <= 1'b1;
                        burst_base <= {MEM_ADDR_W{1'b0}};
                        burst_len <= TILE_BEATS;
                        if (burst_desc_valid && burst_desc_ready) begin
                            burst_desc_valid <= 1'b0;
                            rd_req_addr <= b_base_q + tile_index*TILE_BEATS;
                            rd_req_len <= TILE_BEATS;
                            rd_req_valid <= 1'b1;
                            state <= ST_B_REQ;
                        end
                    end
                    ST_B_REQ: begin
                        if (rd_req_valid && rd_req_ready) begin
                            rd_req_valid <= 1'b0;
                            beat_count <= {BURST_LEN_W{1'b0}};
                            state <= ST_B_DATA;
                        end
                    end
                    ST_B_DATA: begin
                        if (rd_data_valid && rd_data_ready) begin
                            if (rd_data_last != expected_last) begin
                                state <= ST_ERROR;
                                op_error <= 1'b1;
                            end else if (expected_last) begin
                                state <= ST_NEXT_TILE;
                            end else begin
                                beat_count <= beat_count + 1'b1;
                            end
                        end
                    end
                    ST_NEXT_TILE: begin
                        if (local_op_done) begin
                            op_done <= 1'b1;
                            state <= ST_DONE;
                        end else if (tile_index + 1'b1 < tile_count_q) begin
                            // Wait until the tiled sequencer returns to its load
                            // state, then advance the tile index and start A.
                            if (burst_desc_ready) begin
                                tile_index <= tile_index + 1'b1;
                                state <= ST_A_DESC;
                            end
                        end else if (local_op_done) begin
                            op_done <= 1'b1;
                            state <= ST_DONE;
                        end
                    end
                    ST_DONE: begin
                        if (op_start) begin
                            // Start a fresh operation without requiring reset.
                            state <= ST_IDLE;
                        end
                    end
                    ST_ERROR: begin
                        // Fatal transfer/protocol error: reset required to recover.
                        rd_req_valid <= 1'b0;
                        burst_desc_valid <= 1'b0;
                    end
                    default: state <= ST_ERROR;
                endcase
            end
        end
    end
endmodule

`default_nettype wire
