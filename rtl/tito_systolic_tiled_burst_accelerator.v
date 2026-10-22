`default_nettype none

// Host-directed operation sequencer for multiple K tiles.
// The host supplies the tile count and streams one A burst and one B burst
// per tile. This module launches compute automatically after both bursts
// complete, uses replace mode for tile 0, and accumulation mode thereafter.
// External-memory reads / AXI transactions remain the host or DMA backend's job.
module tito_systolic_tiled_burst_accelerator #(
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
    localparam [1:0] ST_IDLE       = 2'd0;
    localparam [1:0] ST_LOAD       = 2'd1;
    localparam [1:0] ST_LAUNCH     = 2'd2;
    localparam [1:0] ST_WAIT_COMPUTE = 2'd3;

    reg [1:0] state;
    reg [TILE_COUNT_W-1:0] tile_count_q;
    reg [TILE_COUNT_W-1:0] tiles_remaining;
    reg [TILE_COUNT_W-1:0] tile_index;
    reg a_loaded;
    reg b_loaded;
    reg active_burst_bank;
    reg cmd_start;
    wire cmd_accumulate;
    wire burst_start_ready_core;
    wire burst_done;
    wire burst_error;
    wire core_busy;
    wire core_done;

    assign op_busy = (state != ST_IDLE);
    assign cmd_accumulate = (tile_index != 0);

    // Only accept one burst for each operand bank in the current tile.
    assign burst_start_ready = (state == ST_LOAD) && op_busy &&
        burst_start_ready_core &&
        !(burst_bank ? b_loaded : a_loaded);
    assign data_ready = data_ready_core;

    wire data_ready_core;
    wire burst_start_valid_core;
    assign burst_start_valid_core = burst_start_valid && burst_start_ready;

    tito_systolic_burst_command_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W),
        .BURST_LEN_W(BURST_LEN_W)
    ) burst_core (
        .clk(clk), .resetb(resetb),
        .burst_start_valid(burst_start_valid_core),
        .burst_start_ready(burst_start_ready_core),
        .burst_bank(burst_bank), .burst_base_addr(burst_base_addr),
        .burst_len(burst_len), .data_valid(data_valid),
        .data_ready(data_ready_core), .data(data),
        .burst_done(burst_done), .burst_error(burst_error),
        .cmd_start(cmd_start), .cmd_accumulate(cmd_accumulate),
        .busy(core_busy), .done(core_done),
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            state <= ST_IDLE;
            tile_count_q <= {TILE_COUNT_W{1'b0}};
            tiles_remaining <= {TILE_COUNT_W{1'b0}};
            tile_index <= {TILE_COUNT_W{1'b0}};
            a_loaded <= 1'b0;
            b_loaded <= 1'b0;
            active_burst_bank <= 1'b0;
            cmd_start <= 1'b0;
            op_done <= 1'b0;
            op_error <= 1'b0;
        end else begin
            cmd_start <= 1'b0;
            op_done <= 1'b0;
            op_error <= 1'b0;

            if (burst_start_valid && burst_start_ready)
                active_burst_bank <= burst_bank;

            if (burst_error) begin
                // Abort the whole operation after an invalid operand burst.
                state <= ST_IDLE;
                a_loaded <= 1'b0;
                b_loaded <= 1'b0;
                op_error <= 1'b1;
            end else begin
                case (state)
                    ST_IDLE: begin
                        if (op_start) begin
                            if (op_tile_count == 0) begin
                                op_error <= 1'b1;
                            end else begin
                                tile_count_q <= op_tile_count;
                                tiles_remaining <= op_tile_count;
                                tile_index <= {TILE_COUNT_W{1'b0}};
                                a_loaded <= 1'b0;
                                b_loaded <= 1'b0;
                                state <= ST_LOAD;
                            end
                        end
                    end
                    ST_LOAD: begin
                        if (burst_done) begin
                            if (active_burst_bank)
                                b_loaded <= 1'b1;
                            else
                                a_loaded <= 1'b1;
                        end
                        // Include the burst completing on this cycle when
                        // deciding whether both operands are ready to compute.
                        if ((a_loaded || (burst_done && !active_burst_bank)) &&
                            (b_loaded || (burst_done && active_burst_bank)))
                            state <= ST_LAUNCH;
                    end
                    ST_LAUNCH: begin
                        cmd_start <= 1'b1;
                        state <= ST_WAIT_COMPUTE;
                    end
                    ST_WAIT_COMPUTE: begin
                        if (core_done) begin
                            if (tiles_remaining == 1) begin
                                state <= ST_IDLE;
                                op_done <= 1'b1;
                                tiles_remaining <= {TILE_COUNT_W{1'b0}};
                                a_loaded <= 1'b0;
                                b_loaded <= 1'b0;
                            end else begin
                                tiles_remaining <= tiles_remaining - 1'b1;
                                tile_index <= tile_index + 1'b1;
                                a_loaded <= 1'b0;
                                b_loaded <= 1'b0;
                                state <= ST_LOAD;
                            end
                        end
                    end
                    default: begin
                        state <= ST_IDLE;
                        a_loaded <= 1'b0;
                        b_loaded <= 1'b0;
                    end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
