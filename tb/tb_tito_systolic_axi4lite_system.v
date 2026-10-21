`timescale 1ns/1ps
`default_nettype none
module tb_tito_systolic_axi4lite_system;
 localparam ADDR_W=32, AXI_DATA_W=32, ID_W=2;
 reg clk=0, resetb=0;
 reg [ADDR_W-1:0] awaddr=0, araddr=0; reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
 reg [31:0] wdata=0; reg [3:0] wstrb=0;
 wire awready,wready,bvalid,arready,rvalid; wire [1:0] bresp,rresp; wire [31:0] rdata;
 wire [ID_W-1:0] awid,arid; wire [ADDR_W-1:0] awaddr_m,araddr_m;
 wire [7:0] awlen,arlen; wire [2:0] awsize,arsize; wire [1:0] awburst,arburst;
 wire awvalid_m,wlast,wvalid_m,bready_m,arvalid_m,rready_m;
 wire [31:0] wdata_m; wire [3:0] wstrb_m; wire [ID_W-1:0] rid; wire [31:0] rdata_m;
 wire [1:0] bresp_m,rresp_m; wire bvalid_m,arready_m,rlast,rvalid_m;
 reg awready_m=0,wready_m=0,bvalid_m_q=0,arready_m_q=0,rvalid_m_q=0;
 reg [1:0] bresp_m_q=0,rresp_m_q=0; reg [ID_W-1:0] rid_q=0;
 reg [31:0] rdata_m_q=0; reg rlast_q=0;
 reg [7:0] mem [0:4095];
 reg [ADDR_W-1:0] rd_base,wr_base; reg [7:0] rd_len,wr_len,rd_index,wr_index;
 reg rd_active=0,wr_addr_seen=0,wr_resp_pending=0;
 reg inject_next_bresp_error=0;
 integer i,cycles;
 assign bvalid_m=bvalid_m_q; assign arready_m=arready_m_q; assign rvalid_m=rvalid_m_q;
 assign bresp_m=bresp_m_q; assign rresp_m=rresp_m_q; assign rid=rid_q; assign rdata_m=rdata_m_q; assign rlast=rlast_q;
 always #5 clk=~clk;
 tito_systolic_axi4lite_system #(.ADDR_W(ADDR_W),.AXI_DATA_W(AXI_DATA_W),.ACC_W(32),.ID_W(ID_W)) dut(
 .clk(clk),.resetb(resetb),.s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
 .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
 .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
 .m_axi_awid(awid),.m_axi_awaddr(awaddr_m),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),.m_axi_awvalid(awvalid_m),.m_axi_awready(awready_m),
 .m_axi_wdata(wdata_m),.m_axi_wstrb(wstrb_m),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid_m),.m_axi_wready(wready_m),
 .m_axi_bresp(bresp_m),.m_axi_bvalid(bvalid_m),.m_axi_bready(bready_m),.m_axi_arid(arid),.m_axi_araddr(araddr_m),.m_axi_arlen(arlen),
 .m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_arvalid(arvalid_m),.m_axi_arready(arready_m),.m_axi_rid(rid),.m_axi_rdata(rdata_m),
 .m_axi_rresp(rresp_m),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid_m),.m_axi_rready(rready_m));

 // Small byte-addressed memory model. AXI reads return four packed INT8 bytes;
 // writes store the 32-bit accumulator word at the requested byte address.
 always @(posedge clk or negedge resetb) begin
  if(!resetb) begin
   awready_m<=0; wready_m<=0; arready_m_q<=0; rvalid_m_q<=0; bvalid_m_q<=0;
   rd_active<=0; wr_addr_seen<=0; wr_resp_pending<=0; rd_index<=0; wr_index<=0;
   rd_base<=0; rd_len<=0; wr_base<=0; wr_len<=0; rlast_q<=0; rresp_m_q<=0; bresp_m_q<=0; rid_q<=0; rdata_m_q<=0;
  end else begin
   awready_m<=1; wready_m<=1; arready_m_q<=1;
   if(arvalid_m && arready_m_q) begin
    if(rd_active) $fatal(1,"unexpected overlapping AXI read address");
    if(arsize!=2 || arburst!=1 || arid!=0) $fatal(1,"bad AR fields");
    rd_active<=1; rd_base<=araddr_m; rd_len<=arlen; rd_index<=0; rvalid_m_q<=0;
   end else if(rd_active && rvalid_m_q && rready_m) begin
    if(rlast_q) begin rd_active<=0; rvalid_m_q<=0; end
    else begin
     rd_index<=rd_index+1'b1;
     rdata_m_q<={mem[rd_base+(rd_index+1'b1)*4+3],mem[rd_base+(rd_index+1'b1)*4+2],mem[rd_base+(rd_index+1'b1)*4+1],mem[rd_base+(rd_index+1'b1)*4]};
     rid_q<=0; rresp_m_q<=0; rlast_q<=((rd_index+1'b1)==rd_len); rvalid_m_q<=1;
    end
   end else if(rd_active && !rvalid_m_q) begin
    rdata_m_q<={mem[rd_base+rd_index*4+3],mem[rd_base+rd_index*4+2],mem[rd_base+rd_index*4+1],mem[rd_base+rd_index*4]};
    rid_q<=0; rresp_m_q<=0; rlast_q<=(rd_index==rd_len); rvalid_m_q<=1;
   end
   if(awvalid_m && awready_m) begin
    if(awsize!=2 || awburst!=1 || awid!=0) $fatal(1,"bad AW fields");
    wr_base<=awaddr_m; wr_len<=awlen; wr_index<=0; wr_addr_seen<=1;
   end
   if(wvalid_m && wready_m) begin
    if(!(wr_addr_seen || (awvalid_m && awready_m))) $fatal(1,"W beat accepted before AW in this simple memory model");
    for(integer lane=0;lane<4;lane=lane+1) if(wstrb_m[lane])
     mem[(awvalid_m && awready_m ? awaddr_m : wr_base)+(awvalid_m && awready_m ? 0 : wr_index)*4+lane]<=wdata_m[lane*8 +: 8];
    if(wlast) begin wr_addr_seen<=0; wr_resp_pending<=1; end
    else wr_index<= (awvalid_m && awready_m) ? 1 : wr_index+1'b1;
   end
   if(wr_resp_pending && !bvalid_m_q) begin
    bvalid_m_q<=1;
    if(inject_next_bresp_error) begin bresp_m_q<=2'b10; inject_next_bresp_error<=0; end
    else bresp_m_q<=0;
    wr_resp_pending<=0;
   end
   if(bvalid_m_q && bready_m) bvalid_m_q<=0;
  end
 end

 task axil_write(input [31:0] addr,input [31:0] data);
  begin
   @(negedge clk); awaddr=addr[ADDR_W-1:0]; awvalid=1; wdata=data; wstrb=4'hf; wvalid=1;
   while(!(awready && wready)) @(negedge clk);
   @(negedge clk); awvalid=0; wvalid=0;
   cycles=0; while(!bvalid && cycles<100) begin @(negedge clk); cycles=cycles+1; end
   if(!bvalid || bresp!=0) $fatal(1,"AXI-Lite write response failure at %h",addr);
   bready=1; @(negedge clk); bready=0;
  end
 endtask
 task axil_read(input [31:0] addr,output [31:0] data);
  begin
   @(negedge clk); araddr=addr[ADDR_W-1:0]; arvalid=1;
   while(!arready) @(negedge clk);
   @(negedge clk); arvalid=0;
   cycles=0; while(!rvalid && cycles<100) begin @(negedge clk); cycles=cycles+1; end
   if(!rvalid || rresp!=0) $fatal(1,"AXI-Lite read response failure at %h",addr);
   data=rdata; rready=1; @(negedge clk); rready=0;
  end
 endtask
 reg [31:0] status;
 initial begin
  for(i=0;i<4096;i=i+1) mem[i]=0;
  // A = identity; B = 1..16 in row-major order.
  for(i=0;i<16;i=i+1) begin
   mem[16'h0100+i]=((i/4)==(i%4)) ? 8'd1 : 8'd0;
   mem[16'h0200+i]=i+1;
  end
  repeat(4) @(negedge clk); resetb=1;
  axil_write('h08,'h0100); axil_write('h0C,'h0200); axil_write('h10,1); axil_write('h14,'h0300);
  axil_write('h00,1);
  cycles=0; status=0;
  while(!status[1] && !status[2] && cycles<5000) begin axil_read('h04,status); cycles=cycles+1; end
  if(!status[1] || status[2]) $fatal(1,"compute did not complete successfully, STATUS=%h",status);
  axil_write('h04,'h00000002); // clear compute done before checking writeback event
  axil_write('h00,2);
  cycles=0; status=0;
  while(!status[9] && !status[10] && cycles<5000) begin axil_read('h04,status); cycles=cycles+1; end
  if(!status[9] || status[10]) $fatal(1,"writeback did not complete successfully, STATUS=%h",status);
  for(i=0;i<16;i=i+1) begin
   if({mem['h0300+i*4+3],mem['h0300+i*4+2],mem['h0300+i*4+1],mem['h0300+i*4]} !== i+1)
    $fatal(1,"result mismatch at word %0d: got %h%h%h%h",i,mem['h0300+i*4+3],mem['h0300+i*4+2],mem['h0300+i*4+1],mem['h0300+i*4]);
  end
  $display("PASS: AXI-Lite configured compute and writeback; 16 external-memory results match reference");

  // Inject a one-shot AXI SLVERR on the next write response. Software must see
  // the latched writeback-error status and the documented error code.
  axil_write('h04,'h00000200); // clear prior writeback-done latch (STATUS bit 9)
  inject_next_bresp_error=1;
  axil_write('h00,2);
  cycles=0; status=0;
  while(!status[10] && !status[9] && cycles<5000) begin axil_read('h04,status); cycles=cycles+1; end
  if(!status[10] || status[9]) $fatal(1,"writeback SLVERR not reflected in STATUS: %h",status);
  axil_read('h18,status);
  if(status[3:0]!==4'd6) $fatal(1,"expected BRESP error code 6, got %h",status);
  $display("PASS: AXI SLVERR is visible through sticky STATUS and ERROR_CODE");

  axil_write('h04,'h00000400); // clear writeback-error latch and error code
  axil_read('h04,status);
  if(status[10]) $fatal(1,"writeback error W1C did not clear STATUS");
  axil_read('h18,status);
  if(status[3:0]!==0) $fatal(1,"error code did not clear with writeback-error W1C");
  $display("PASS: software can clear writeback error status and code without reset");
  $finish;
 end
 initial begin #300000; $fatal(1,"timeout"); end
endmodule
`default_nettype wire
