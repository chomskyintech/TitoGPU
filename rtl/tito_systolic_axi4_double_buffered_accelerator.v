`default_nettype none

// End-to-end wrapper for a double-buffered tiled accelerator with 32-bit AXI
// reads, multi-burst result writeback, and explicit writeback status reporting.
module tito_systolic_axi4_double_buffered_accelerator #(
    parameter integer N = 4,
    parameter integer K = 4,
    parameter integer DATA_W = 8,
    parameter integer AXI_DATA_W = 32,
    parameter integer ACC_W = 32,
    parameter integer ADDR_W = 32,
    parameter integer MEM_ADDR_W = (N*K > 1 ? $clog2(N*K) : 1),
    parameter integer RESULT_ADDR_W = (N*N > 1 ? $clog2(N*N) : 1),
    parameter integer BURST_LEN_W = (N*K > 1 ? $clog2(N*K+1) : 1),
    parameter integer TILE_COUNT_W = 8,
    parameter integer ID_W = 4
) (
    input  wire                         clk,
    input  wire                         resetb,
    input  wire                         op_start,
    input  wire [ADDR_W-1:0]            a_base_addr,
    input  wire [ADDR_W-1:0]            b_base_addr,
    input  wire [TILE_COUNT_W-1:0]      op_tile_count,
    output wire                         op_busy,
    output wire                         op_done,
    output wire                         op_error,

    input  wire                         result_rd_en,
    input  wire [RESULT_ADDR_W-1:0]     result_rd_addr,
    output wire [ACC_W-1:0]             result_rd_data,
    output wire                         result_rd_valid,
    output wire                         result_rd_ready,

    input  wire                         writeback_start,
    input  wire [ADDR_W-1:0]            writeback_base_addr,
    output wire                         writeback_start_ready,
    output wire                         writeback_busy,
    output wire                         writeback_done,
    output wire                         writeback_error,
    output wire [3:0]                   writeback_error_code,

    output wire [ID_W-1:0]              m_axi_awid,
    output wire [ADDR_W-1:0]            m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire                         m_axi_awvalid,
    input  wire                         m_axi_awready,
    output wire [AXI_DATA_W-1:0]        m_axi_wdata,
    output wire [AXI_DATA_W/8-1:0]      m_axi_wstrb,
    output wire                         m_axi_wlast,
    output wire                         m_axi_wvalid,
    input  wire                         m_axi_wready,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output wire                         m_axi_bready,

    output wire [ID_W-1:0]              m_axi_arid,
    output wire [ADDR_W-1:0]            m_axi_araddr,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire                         m_axi_arvalid,
    input  wire                         m_axi_arready,
    input  wire [ID_W-1:0]              m_axi_rid,
    input  wire [AXI_DATA_W-1:0]        m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready
);
    wire rd_req_valid, rd_req_ready;
    wire [ADDR_W-1:0] rd_req_addr;
    wire [BURST_LEN_W-1:0] rd_req_len;
    wire rd_data_valid, rd_data_ready, rd_data_last, rd_error;
    wire [DATA_W-1:0] rd_data;

    wire [ACC_W-1:0] core_result_rd_data;
    wire core_result_rd_valid, core_result_rd_en;
    wire [RESULT_ADDR_W-1:0] core_result_rd_addr;
    wire wb_result_rd_en;
    wire [RESULT_ADDR_W-1:0] wb_result_rd_addr;
    wire wb_internal_start_ready;
    wire wb_start_valid;
    wire wb_error_unused;

    // The host port has priority if a host read and writeback start coincide.
    // During writeback, host reads are not accepted; result_rd_ready makes the
    // ownership rule explicit to new clients.
    assign result_rd_ready = !writeback_busy &&
                             !(writeback_start && wb_internal_start_ready && !result_rd_en);
    assign writeback_start_ready = wb_internal_start_ready && !result_rd_en;
    assign wb_start_valid = writeback_start && writeback_start_ready;
    assign core_result_rd_en = writeback_busy ? wb_result_rd_en :
                               (result_rd_en && result_rd_ready);
    assign core_result_rd_addr = writeback_busy ? wb_result_rd_addr : result_rd_addr;
    assign result_rd_data = core_result_rd_data;
    assign result_rd_valid = core_result_rd_valid && !writeback_busy;

    tito_systolic_double_buffered_dma_reader #(
        .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W), .ADDR_W(ADDR_W),
        .MEM_ADDR_W(MEM_ADDR_W), .RESULT_ADDR_W(RESULT_ADDR_W),
        .BURST_LEN_W(BURST_LEN_W), .TILE_COUNT_W(TILE_COUNT_W)
    ) frontend (
        .clk(clk), .resetb(resetb),
        .op_start(op_start), .a_base_addr(a_base_addr), .b_base_addr(b_base_addr),
        .op_tile_count(op_tile_count), .op_busy(op_busy), .op_done(op_done), .op_error(op_error),
        .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready),
        .rd_req_addr(rd_req_addr), .rd_req_len(rd_req_len),
        .rd_data_valid(rd_data_valid), .rd_data_ready(rd_data_ready),
        .rd_data(rd_data), .rd_data_last(rd_data_last), .rd_error(rd_error),
        .result_rd_en(core_result_rd_en), .result_rd_addr(core_result_rd_addr),
        .result_rd_data(core_result_rd_data), .result_rd_valid(core_result_rd_valid)
    );

    tito_systolic_axi4_read_adapter #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .AXI_DATA_W(AXI_DATA_W),
        .LEN_W(BURST_LEN_W), .ID_W(ID_W)
    ) axi_read (
        .clk(clk), .resetb(resetb),
        .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready),
        .rd_req_addr(rd_req_addr), .rd_req_len(rd_req_len),
        .rd_data_valid(rd_data_valid), .rd_data_ready(rd_data_ready),
        .rd_data(rd_data), .rd_data_last(rd_data_last), .rd_error(rd_error),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    tito_systolic_axi4_result_writeback #(
        .N(N), .DATA_W(ACC_W), .ADDR_W(ADDR_W),
        .RESULT_ADDR_W(RESULT_ADDR_W), .ID_W(ID_W)
    ) result_writeback (
        .clk(clk), .resetb(resetb),
        .start_valid(wb_start_valid), .start_ready(wb_internal_start_ready),
        .result_base_addr(writeback_base_addr),
        .busy(writeback_busy), .done(writeback_done), .error(writeback_error),
        .error_code(writeback_error_code),
        .result_rd_en(wb_result_rd_en), .result_rd_addr(wb_result_rd_addr),
        .result_rd_data(core_result_rd_data), .result_rd_valid(core_result_rd_valid),
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

    initial begin
        if (ACC_W != AXI_DATA_W)
            $error("Initial integrated writeback requires ACC_W == AXI_DATA_W");
    end
endmodule

`default_nettype wire
