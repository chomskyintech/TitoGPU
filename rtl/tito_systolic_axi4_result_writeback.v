`default_nettype none

// Serializes the synchronous local result-memory read port into a ready/valid
// stream. The AXI write controller splits the stream at legal burst boundaries.
module tito_systolic_axi4_result_writeback #(
    parameter integer N=4,
    parameter integer DATA_W=32,
    parameter integer ADDR_W=32,
    parameter integer RESULT_ADDR_W=(N*N>1 ? $clog2(N*N) : 1),
    parameter integer ID_W=4,
    parameter integer RESULT_BEATS=N*N,
    parameter integer BYTES_PER_BEAT=DATA_W/8
) (
    input wire clk, resetb,
    input wire start_valid, output wire start_ready,
    input wire [ADDR_W-1:0] result_base_addr,
    output wire busy, output reg done, output wire error,
    output wire [3:0] error_code,

    output reg result_rd_en,
    output reg [RESULT_ADDR_W-1:0] result_rd_addr,
    input wire [DATA_W-1:0] result_rd_data,
    input wire result_rd_valid,

    output wire [ID_W-1:0] m_axi_awid,
    output wire [ADDR_W-1:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [DATA_W-1:0] m_axi_wdata,
    output wire [BYTES_PER_BEAT-1:0] m_axi_wstrb,
    output wire m_axi_wlast, m_axi_wvalid,
    input wire m_axi_wready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);
    localparam integer LEN_W=9;
    localparam integer COUNT_W=(RESULT_BEATS>1 ? $clog2(RESULT_BEATS+1) : 1);
    localparam [3:0] ERR_NONE=4'd0, ERR_UNALIGNED=4'd2,
                     ERR_TOO_LONG=4'd3;

    reg active, local_error;
    reg [3:0] local_error_code;
    reg [COUNT_W-1:0] read_index;
    reg read_pending, pending_last;
    reg stream_buf_valid, stream_buf_last;
    reg [DATA_W-1:0] stream_buf_data;

    wire writer_cmd_ready, writer_busy, writer_done, writer_error;
    wire [3:0] writer_error_code;
    wire writer_stream_ready;
    wire [LEN_W-1:0] writer_cmd_beats;
    wire writer_cmd_valid;
    wire start_bad;
    wire stream_handshake;
    wire result_request;

    assign writer_cmd_beats=RESULT_BEATS;
    assign start_ready=!active && writer_cmd_ready;
    assign start_bad=((result_base_addr % BYTES_PER_BEAT)!=0) ||
                     (RESULT_BEATS>256);
    assign writer_cmd_valid=start_valid && start_ready && !start_bad;
    assign error=local_error || writer_error;
    assign error_code=local_error ? local_error_code : writer_error_code;
    assign busy=active;
    assign result_request=active && !read_pending && !stream_buf_valid &&
                          (read_index<RESULT_BEATS) && !writer_error;
    assign stream_handshake=stream_buf_valid && writer_stream_ready;

    always @* begin
        result_rd_en=result_request;
        result_rd_addr=read_index[RESULT_ADDR_W-1:0];
    end

    tito_systolic_axi4_write_adapter #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W), .ID_W(ID_W)
    ) write_master (
        .clk(clk), .resetb(resetb),
        .cmd_valid(writer_cmd_valid), .cmd_ready(writer_cmd_ready),
        .cmd_addr(result_base_addr), .cmd_beats(writer_cmd_beats),
        .stream_valid(stream_buf_valid), .stream_ready(writer_stream_ready),
        .stream_data(stream_buf_data), .stream_last(stream_buf_last),
        .busy(writer_busy), .done(writer_done), .error(writer_error),
        .error_code(writer_error_code),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            active<=0; done<=0; local_error<=0; local_error_code<=ERR_NONE;
            read_index<=0; read_pending<=0; pending_last<=0;
            stream_buf_valid<=0; stream_buf_last<=0; stream_buf_data<=0;
        end else begin
            if (start_valid && start_ready) begin
                done<=0; local_error<=0; local_error_code<=ERR_NONE;
                read_index<=0; read_pending<=0; pending_last<=0;
                stream_buf_valid<=0; stream_buf_last<=0;
                if (start_bad) begin
                    active<=0; local_error<=1;
                    if ((result_base_addr % BYTES_PER_BEAT)!=0)
                        local_error_code<=ERR_UNALIGNED;
                    else if (RESULT_BEATS>256)
                        local_error_code<=ERR_TOO_LONG;
                    else
                        local_error_code<=ERR_TOO_LONG;
                end else begin
                    active<=1;
                end
            end

            if (result_request) begin
                read_pending<=1;
                pending_last<=(read_index==RESULT_BEATS-1);
                read_index<=read_index+1'b1;
            end

            if (active && read_pending && result_rd_valid) begin
                read_pending<=0;
                stream_buf_data<=result_rd_data;
                stream_buf_last<=pending_last;
                stream_buf_valid<=1;
            end

            if (stream_handshake)
                stream_buf_valid<=0;

            if (active && writer_done) begin
                active<=0; done<=1;
            end
            if (active && writer_error) begin
                active<=0; local_error<=1;
                local_error_code<=writer_error_code;
                stream_buf_valid<=0; read_pending<=0;
            end
        end
    end

    initial begin
        if (DATA_W!=32)
            $error("Initial result writeback supports 32-bit result words only");
        if (RESULT_BEATS<1)
            $error("RESULT_BEATS must be positive");
    end
endmodule

`default_nettype wire
