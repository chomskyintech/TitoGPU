`timescale 1ns/1ps
`default_nettype none
module tb_tito_systolic_axi4_read_adapter_packed;
  reg clk=0, resetb=0, req_valid=0, arready=0, rvalid=0, rlast=0, pready=0;
  reg [31:0] req_addr=0, rdata=0;
  reg [7:0] req_len=0;
  reg [1:0] rresp=0;
  reg [1:0] rid=0;
  wire req_ready, dvalid, dlast, derr, arvalid, rready, pvalid, plast;
  wire [7:0] dbyte;
  wire [31:0] araddr, pdata;
  wire [7:0] arlen;
  wire [2:0] arsize;
  wire [1:0] arburst;
  wire [1:0] arid;
  wire [3:0] pmask;
  always #5 clk=~clk;

  tito_systolic_axi4_read_adapter #(.ADDR_W(32),.DATA_W(8),.AXI_DATA_W(32),
    .LEN_W(8),.ID_W(2),.PACKED_OUTPUT(1)) dut(
    .clk(clk),.resetb(resetb),.rd_req_valid(req_valid),.rd_req_ready(req_ready),
    .rd_req_addr(req_addr),.rd_req_len(req_len),.rd_data_valid(dvalid),
    .rd_data_ready(1'b0),.rd_data(dbyte),.rd_data_last(dlast),.rd_error(derr),
    .packed_data_valid(pvalid),.packed_data_ready(pready),.packed_data(pdata),
    .packed_data_mask(pmask),.packed_data_last(plast),
    .m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),
    .m_axi_arburst(arburst),.m_axi_arvalid(arvalid),.m_axi_arready(arready),
    .m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),
    .m_axi_rvalid(rvalid),.m_axi_rready(rready));

  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    repeat(2) tick(); resetb=1;
    @(negedge clk); req_addr=32'h100; req_len=6; req_valid=1; arready=1;
    #1; if(!arvalid || arlen!=1) $fatal(1,"bad packed-mode AR descriptor");
    tick(); @(negedge clk); req_valid=0; arready=0;
    rdata=32'h44332211; rlast=0; rvalid=1;
    #1; if(!rready) $fatal(1,"first beat not accepted");
    tick(); @(negedge clk); rvalid=0;
    #1; if(!pvalid || pdata!==32'h44332211 || pmask!==4'b1111 || plast)
      $fatal(1,"first packed beat/mask incorrect");
    repeat(2) begin tick(); if(!pvalid || pdata!==32'h44332211) $fatal(1,"packed payload not stable under stall"); end
    @(negedge clk); pready=1; tick();
    @(negedge clk); pready=0; rdata=32'h88776655; rlast=1; rvalid=1;
    #1; if(!rready) $fatal(1,"second beat not accepted");
    tick(); @(negedge clk); rvalid=0;
    #1; if(!pvalid || pdata!==32'h88776655 || pmask!==4'b0011 || !plast)
      $fatal(1,"partial final packed beat/mask incorrect");
    @(negedge clk); pready=1; tick();
    @(negedge clk); pready=0;
    if(pvalid || derr) $fatal(1,"packed transaction did not retire cleanly");
    $display("PASS: packed AXI read output, backpressure, lane mask and partial final word");
    $finish;
  end
  initial begin #5000; $fatal(1,"timeout"); end
endmodule
`default_nettype wire
