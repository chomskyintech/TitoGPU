`default_nettype none
module tito_systolic_axi4lite_system #(
 parameter integer N=4, K=4, DATA_W=8, AXI_DATA_W=32, ACC_W=32, ADDR_W=32,
 parameter integer MEM_ADDR_W=(N*K>1?$clog2(N*K):1), RESULT_ADDR_W=(N*N>1?$clog2(N*N):1),
 parameter integer BURST_LEN_W=(N*K>1?$clog2(N*K+1):1), TILE_COUNT_W=8, ID_W=4,
 parameter integer PACKED_INGRESS=0
)(
 input wire clk, resetb,
 input wire [ADDR_W-1:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
 input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb, input wire s_axi_wvalid, output wire s_axi_wready,
 output wire [1:0] s_axi_bresp, output wire s_axi_bvalid, input wire s_axi_bready,
 input wire [ADDR_W-1:0] s_axi_araddr, input wire s_axi_arvalid, output wire s_axi_arready,
 output wire [31:0] s_axi_rdata, output wire [1:0] s_axi_rresp, output wire s_axi_rvalid, input wire s_axi_rready,
 output wire [ID_W-1:0] m_axi_awid, output wire [ADDR_W-1:0] m_axi_awaddr, output wire [7:0] m_axi_awlen,
 output wire [2:0] m_axi_awsize, output wire [1:0] m_axi_awburst, output wire m_axi_awvalid, input wire m_axi_awready,
 output wire [AXI_DATA_W-1:0] m_axi_wdata, output wire [AXI_DATA_W/8-1:0] m_axi_wstrb,
 output wire m_axi_wlast, output wire m_axi_wvalid, input wire m_axi_wready,
 input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready,
 output wire [ID_W-1:0] m_axi_arid, output wire [ADDR_W-1:0] m_axi_araddr, output wire [7:0] m_axi_arlen,
 output wire [2:0] m_axi_arsize, output wire [1:0] m_axi_arburst, output wire m_axi_arvalid, input wire m_axi_arready,
 input wire [ID_W-1:0] m_axi_rid, input wire [AXI_DATA_W-1:0] m_axi_rdata, input wire [1:0] m_axi_rresp,
 input wire m_axi_rlast, input wire m_axi_rvalid, output wire m_axi_rready
);
 wire op_start, op_busy, op_done, op_error, wb_start, wb_ready, wb_busy, wb_done, wb_error;
 wire [ADDR_W-1:0] a_base, b_base, wb_base; wire [TILE_COUNT_W-1:0] tile_count; wire [3:0] wb_error_code;
 tito_systolic_axi4lite_control #(.ADDR_W(ADDR_W),.TILE_COUNT_W(TILE_COUNT_W)) regs(
 .clk(clk),.resetb(resetb),.s_axi_awaddr(s_axi_awaddr),.s_axi_awvalid(s_axi_awvalid),.s_axi_awready(s_axi_awready),
 .s_axi_wdata(s_axi_wdata),.s_axi_wstrb(s_axi_wstrb),.s_axi_wvalid(s_axi_wvalid),.s_axi_wready(s_axi_wready),
 .s_axi_bresp(s_axi_bresp),.s_axi_bvalid(s_axi_bvalid),.s_axi_bready(s_axi_bready),
 .s_axi_araddr(s_axi_araddr),.s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
 .s_axi_rdata(s_axi_rdata),.s_axi_rresp(s_axi_rresp),.s_axi_rvalid(s_axi_rvalid),.s_axi_rready(s_axi_rready),
 .op_start(op_start),.a_base_addr(a_base),.b_base_addr(b_base),.op_tile_count(tile_count),
 .op_busy(op_busy),.op_done(op_done),.op_error(op_error),.writeback_start(wb_start),.writeback_base_addr(wb_base),
 .writeback_start_ready(wb_ready),.writeback_busy(wb_busy),.writeback_done(wb_done),.writeback_error(wb_error),.writeback_error_code(wb_error_code));
 tito_systolic_axi4_double_buffered_accelerator #(.N(N),.K(K),.DATA_W(DATA_W),.AXI_DATA_W(AXI_DATA_W),.ACC_W(ACC_W),
 .ADDR_W(ADDR_W),.MEM_ADDR_W(MEM_ADDR_W),.RESULT_ADDR_W(RESULT_ADDR_W),.BURST_LEN_W(BURST_LEN_W),.TILE_COUNT_W(TILE_COUNT_W),.ID_W(ID_W),.PACKED_INGRESS(PACKED_INGRESS)) accel(
 .clk(clk),.resetb(resetb),.op_start(op_start),.a_base_addr(a_base),.b_base_addr(b_base),.op_tile_count(tile_count),
 .op_busy(op_busy),.op_done(op_done),.op_error(op_error),.result_rd_en(1'b0),.result_rd_addr({RESULT_ADDR_W{1'b0}}),
 .result_rd_data(),.result_rd_valid(),.result_rd_ready(),.writeback_start(wb_start),.writeback_base_addr(wb_base),
 .writeback_start_ready(wb_ready),.writeback_busy(wb_busy),.writeback_done(wb_done),.writeback_error(wb_error),.writeback_error_code(wb_error_code),
 .m_axi_awid(m_axi_awid),.m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),.m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),
 .m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),.m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),
 .m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready),
 .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),.m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),
 .m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),.m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),
 .m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready));
 initial if(AXI_DATA_W!=32 || ACC_W!=32) $error("System requires 32-bit AXI data and 32-bit accumulators");
endmodule
`default_nettype wire
