`default_nettype none

// Streaming-memory systolic accelerator prototype.
// Operands are read from N row-banked A memories and N column-banked B
// memories. Only per-bank addresses/data cross the memory interface; complete
// matrices are not routed as wide buses into the scheduler.
module tito_systolic_double_buffered_stream_accelerator #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32,
    parameter integer K_ADDR_W = (K > 1 ? $clog2(K) : 1),
    parameter integer ADDR_W = (N*K > 1 ? $clog2(N*K) : 1)
) (
    input  wire                       clk,
    input  wire                       resetb,
    input  wire                       wr_en,
    input  wire                       wr_buffer, // tile buffer being filled
    input  wire                       rd_buffer, // tile buffer currently computing
    input  wire                       wr_bank, // 0 = A, 1 = B
    input  wire [ADDR_W-1:0]          wr_addr,
    input  wire [DATA_W-1:0]          wr_data,
    input  wire                       start,
    output wire [N*N*ACC_W-1:0]       accum_out,
    output wire                       busy,
    output reg                        done
);
    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_CLEAR = 3'd1;
    localparam [2:0] ST_FEED  = 3'd2;
    localparam [2:0] ST_DRAIN = 3'd3;
    localparam [2:0] ST_DONE  = 3'd4;

    reg [2:0] state;
    integer feed_cycle;
    integer drain_cycle;
    integer row_idx, col_idx, reduction_idx;

    reg rd_en;
    reg [N*K_ADDR_W-1:0] a_rd_addr;
    reg [N*K_ADDR_W-1:0] b_rd_addr;
    reg [N-1:0] a_valid_next, b_valid_next;
    reg [N-1:0] a_valid_q, b_valid_q;
    reg clear_mac;

    wire [N*DATA_W-1:0] a_rd_data;
    wire [N*DATA_W-1:0] b_rd_data;

    assign busy = (state != ST_IDLE);

    always @* begin
        rd_en = 1'b0;
        a_rd_addr = {(N*K_ADDR_W){1'b0}};
        b_rd_addr = {(N*K_ADDR_W){1'b0}};
        a_valid_next = {N{1'b0}};
        b_valid_next = {N{1'b0}};
        clear_mac = (state == ST_CLEAR);

        if (state == ST_FEED) begin
            rd_en = 1'b1;
            // Read A[r][t-r] and B[t-c][c] from independently banked rows/columns.
            for (row_idx = 0; row_idx < N; row_idx = row_idx + 1) begin
                reduction_idx = feed_cycle - row_idx;
                if ((reduction_idx >= 0) && (reduction_idx < K)) begin
                    a_valid_next[row_idx] = 1'b1;
                    a_rd_addr[row_idx*K_ADDR_W +: K_ADDR_W] = reduction_idx;
                end
            end
            for (col_idx = 0; col_idx < N; col_idx = col_idx + 1) begin
                reduction_idx = feed_cycle - col_idx;
                if ((reduction_idx >= 0) && (reduction_idx < K)) begin
                    b_valid_next[col_idx] = 1'b1;
                    b_rd_addr[col_idx*K_ADDR_W +: K_ADDR_W] = reduction_idx;
                end
            end
        end
    end

    tito_systolic_double_buffered_banked_scratchpad #(
        .N(N), .K(K), .DATA_W(DATA_W),
        .K_ADDR_W(K_ADDR_W), .ADDR_W(ADDR_W)
    ) scratchpad (
        .clk(clk), .resetb(resetb),
        .wr_en(wr_en), .wr_buffer(wr_buffer), .wr_bank(wr_bank), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_en(rd_en), .rd_buffer(rd_buffer), .a_rd_addr(a_rd_addr), .b_rd_addr(b_rd_addr),
        .a_rd_data(a_rd_data), .b_rd_data(b_rd_data)
    );

    // The synchronous scratchpad data and its valid bits have one-cycle latency.
    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            a_valid_q <= {N{1'b0}};
            b_valid_q <= {N{1'b0}};
        end else if (clear_mac) begin
            a_valid_q <= {N{1'b0}};
            b_valid_q <= {N{1'b0}};
        end else begin
            a_valid_q <= a_valid_next;
            b_valid_q <= b_valid_next;
        end
    end

    tito_systolic_mac #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) mac_array (
        .clk(clk), .resetb(resetb), .clear(clear_mac), .enable(1'b1),
        .a_valid(a_valid_q), .b_valid(b_valid_q),
        .a_in(a_rd_data), .b_in(b_rd_data), .accum_out(accum_out)
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
                    if (drain_cycle >= (N + 2))
                        state <= ST_DONE;
                    else
                        drain_cycle <= drain_cycle + 1;
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
