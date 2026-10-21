`default_nettype none

// End-to-end wrapper connecting the double-buffered tiled accelerator to an
// AXI4 read-channel subset. The frontend/compute operand width is DATA_W;
// AXI_DATA_W controls the external bus width and lane unpacking. Addresses are bytes.
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
        .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
        .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
    );

    tito_systolic_axi4_read_adapter #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .AXI_DATA_W(AXI_DATA_W), .LEN_W(BURST_LEN_W), .ID_W(ID_W)
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
endmodule

`default_nettype wire
