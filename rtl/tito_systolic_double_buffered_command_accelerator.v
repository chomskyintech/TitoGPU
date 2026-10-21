`default_nettype none

// Host-facing command wrapper for the banked systolic accelerator.
// A/B are loaded through the existing single-element write port. A one-cycle
// cmd_start pulse launches a tile operation. Results are serialized into a
// local result register bank before done is asserted. Result reads are
// synchronous and result_rd_valid is asserted with the returned data.
module tito_systolic_double_buffered_command_accelerator #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32,
    parameter integer K_ADDR_W = (K > 1 ? $clog2(K) : 1),
    parameter integer MEM_ADDR_W = (N*K > 1 ? $clog2(N*K) : 1),
    parameter integer RESULT_ADDR_W = (N*N > 1 ? $clog2(N*N) : 1)
) (
    input  wire                         clk,
    input  wire                         resetb,
    input  wire                         mem_wr_en, // write-valid: held with address/data until ready
    output wire                         mem_wr_ready,
    input  wire                         mem_wr_buffer, // ping-pong buffer being filled
    input  wire                         mem_wr_bank, // 0 = A, 1 = B
    input  wire [MEM_ADDR_W-1:0]        mem_wr_addr,
    input  wire [DATA_W-1:0]            mem_wr_data,
    input  wire                         cmd_start,
    input  wire                         cmd_accumulate, // 0 = replace outputs; 1 = add this K tile to prior results
    input  wire                         cmd_buffer, // buffer selected for this compute tile
    output wire                         busy,
    output reg                          done,
    input  wire                         result_rd_en,
    input  wire [RESULT_ADDR_W-1:0]     result_rd_addr,
    output reg  [ACC_W-1:0]             result_rd_data,
    output reg                          result_rd_valid
);
    localparam [1:0] ST_IDLE      = 2'd0;
    localparam [1:0] ST_COMPUTE   = 2'd1;
    localparam [1:0] ST_WRITEBACK = 2'd2;

    reg [1:0] state;
    reg core_start;
    reg [RESULT_ADDR_W-1:0] writeback_idx;
    reg accumulate_q;
    reg compute_buffer_q;
    reg [ACC_W-1:0] result_mem [0:N*N-1];
    wire [N*N*ACC_W-1:0] accum_out;
    wire core_busy;
    wire core_done;
    wire core_wr_en;

    assign busy = (state != ST_IDLE);
    // Ready/valid write handshake: writes are accepted only while idle.
    // A DMA or host must hold valid/address/data until mem_wr_ready is high.
    // During compute/writeback, permit writes only to the inactive tile buffer.
    assign mem_wr_ready = (state == ST_IDLE) || (mem_wr_buffer != compute_buffer_q);
    assign core_wr_en = mem_wr_en && mem_wr_ready;

    tito_systolic_double_buffered_stream_accelerator #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .K_ADDR_W(K_ADDR_W), .ADDR_W(MEM_ADDR_W)
    ) compute_core (
        .clk(clk), .resetb(resetb),
        .wr_en(core_wr_en), .wr_buffer(mem_wr_buffer), .rd_buffer(compute_buffer_q), .wr_bank(mem_wr_bank),
        .wr_addr(mem_wr_addr), .wr_data(mem_wr_data),
        .start(core_start), .accum_out(accum_out),
        .busy(core_busy), .done(core_done)
    );

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            state <= ST_IDLE;
            core_start <= 1'b0;
            writeback_idx <= {RESULT_ADDR_W{1'b0}};
            accumulate_q <= 1'b0;
            compute_buffer_q <= 1'b0;
            done <= 1'b0;
            result_rd_data <= {ACC_W{1'b0}};
            result_rd_valid <= 1'b0;
        end else begin
            core_start <= 1'b0;
            done <= 1'b0;
            result_rd_valid <= 1'b0;

            // Result reads are one-cycle synchronous reads. Reads during
            // writeback are allowed, but the address being written that cycle
            // has the usual read-during-write ambiguity and should be avoided.
            if (result_rd_en) begin
                if (result_rd_addr < N*N) begin
                    result_rd_data <= result_mem[result_rd_addr];
                    result_rd_valid <= 1'b1;
                end else begin
                    result_rd_data <= {ACC_W{1'b0}};
                    result_rd_valid <= 1'b1;
                end
            end

            case (state)
                ST_IDLE: begin
                    if (cmd_start) begin
                        core_start <= 1'b1;
                        accumulate_q <= cmd_accumulate;
                        compute_buffer_q <= cmd_buffer;
                        state <= ST_COMPUTE;
                    end
                end
                ST_COMPUTE: begin
                    if (core_done) begin
                        writeback_idx <= {RESULT_ADDR_W{1'b0}};
                        state <= ST_WRITEBACK;
                    end
                end
                ST_WRITEBACK: begin
                    if (accumulate_q)
                        result_mem[writeback_idx] <= result_mem[writeback_idx] +
                            accum_out[writeback_idx*ACC_W +: ACC_W];
                    else
                        result_mem[writeback_idx] <=
                            accum_out[writeback_idx*ACC_W +: ACC_W];
                    if (writeback_idx == N*N-1) begin
                        state <= ST_IDLE;
                        done <= 1'b1;
                    end else begin
                        writeback_idx <= writeback_idx + 1'b1;
                    end
                end
                default: begin
                    state <= ST_IDLE;
                    core_start <= 1'b0;
                    writeback_idx <= {RESULT_ADDR_W{1'b0}};
                end
            endcase
        end
    end
endmodule

`default_nettype wire
