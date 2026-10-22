`default_nettype none

// Simple controller for a single preloaded matrix multiplication.
// Matrices are row-major packed signed INT8 values. This is a bring-up
// scheduler, not yet a DMA/SRAM interface or a reusable tiled command queue.
module tito_systolic_matmul #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32
) (
    input  wire                         clk,
    input  wire                         resetb,
    input  wire                         start,
    input  wire [N*K*DATA_W-1:0]        a_matrix,
    input  wire [K*N*DATA_W-1:0]        b_matrix,
    output wire [N*N*ACC_W-1:0]         accum_out,
    output wire                         busy,
    output reg                          done
);
    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_CLEAR = 3'd1;
    localparam [2:0] ST_FEED  = 3'd2;
    localparam [2:0] ST_DRAIN = 3'd3;
    localparam [2:0] ST_DONE  = 3'd4;

    reg [2:0] state;
    integer feed_cycle;
    integer drain_cycle;

    reg [N-1:0] a_valid;
    reg [N-1:0] b_valid;
    reg [N*DATA_W-1:0] a_in;
    reg [N*DATA_W-1:0] b_in;
    reg clear_mac;

    integer row_idx;
    integer col_idx;
    integer reduction_idx;

    assign busy = (state != ST_IDLE);

    always @* begin
        a_valid = {N{1'b0}};
        b_valid = {N{1'b0}};
        a_in = {(N*DATA_W){1'b0}};
        b_in = {(N*DATA_W){1'b0}};
        clear_mac = 1'b0;

        if (state == ST_CLEAR) begin
            clear_mac = 1'b1;
        end

        if (state == ST_FEED) begin
            // At feed cycle t, row r emits A[r][t-r] and column c emits
            // B[t-c][c]. The skew aligns each matching reduction term.
            for (row_idx = 0; row_idx < N; row_idx = row_idx + 1) begin
                reduction_idx = feed_cycle - row_idx;
                if ((reduction_idx >= 0) && (reduction_idx < K)) begin
                    a_valid[row_idx] = 1'b1;
                    a_in[row_idx*DATA_W +: DATA_W] =
                        a_matrix[((row_idx*K + reduction_idx)*DATA_W) +: DATA_W];
                end
            end
            for (col_idx = 0; col_idx < N; col_idx = col_idx + 1) begin
                reduction_idx = feed_cycle - col_idx;
                if ((reduction_idx >= 0) && (reduction_idx < K)) begin
                    b_valid[col_idx] = 1'b1;
                    b_in[col_idx*DATA_W +: DATA_W] =
                        b_matrix[((reduction_idx*N + col_idx)*DATA_W) +: DATA_W];
                end
            end
        end
    end

    tito_systolic_mac #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) mac_array (
        .clk(clk),
        .resetb(resetb),
        .clear(clear_mac),
        .enable(1'b1),
        .a_valid(a_valid),
        .b_valid(b_valid),
        .a_in(a_in),
        .b_in(b_in),
        .accum_out(accum_out)
    );

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            state <= ST_IDLE;
            feed_cycle <= 0;
            drain_cycle <= 0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        feed_cycle <= 0;
                        drain_cycle <= 0;
                        state <= ST_CLEAR;
                    end
                end
                ST_CLEAR: begin
                    feed_cycle <= 0;
                    state <= ST_FEED;
                end
                ST_FEED: begin
                    if (feed_cycle >= (K + N - 2)) begin
                        drain_cycle <= 0;
                        state <= ST_DRAIN;
                    end else begin
                        feed_cycle <= feed_cycle + 1;
                    end
                end
                ST_DRAIN: begin
                    if (drain_cycle >= (N + 1)) begin
                        state <= ST_DONE;
                    end else begin
                        drain_cycle <= drain_cycle + 1;
                    end
                end
                ST_DONE: begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: begin
                    state <= ST_IDLE;
                    feed_cycle <= 0;
                    drain_cycle <= 0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
