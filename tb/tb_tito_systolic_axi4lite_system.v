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
 integer i,cycles,read_burst_count,bus_cycle,phase_start_cycle,compute_observed_cycles,writeback_observed_cycles;
 integer mem_gap=2,r_gap_count=0;
 integer aw_stall_cycles=0,w_stall_cycles=0,ar_stall_cycles=0,r_stall_cycles=0,b_stall_cycles=0,r_gap_idle_cycles=0;
 integer internal_op_start_cycle=-1,internal_op_done_cycle=-1,internal_op_cycles=0;
 integer compute_ar_handshakes=0,compute_r_beats=0,compute_r_gap_idle=0,compute_r_stalls=0;
 integer compute_core_busy_cycles=0,compute_noncore_busy_cycles=0;
 integer compute_r_beats_while_mac_busy=0,compute_read_active_while_mac_busy=0;
 integer wb_aw_handshakes=0,wb_w_beats=0,wb_b_responses=0,wb_w_stalls=0,wb_b_wait_cycles=0;
 reg internal_op_started=0,wb_perf_started=0;
 reg prev_aw_stall=0,prev_w_stall=0,prev_ar_stall=0,prev_r_stall=0,prev_b_stall=0;
 reg [ADDR_W+ID_W+13-1:0] prev_aw_payload,prev_ar_payload;
 reg [31:0] prev_wdata,prev_rdata;
 reg [3:0] prev_wstrb;
 reg prev_wlast,prev_rlast;
 reg [ID_W+1:0] prev_b_payload,prev_r_payload;
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

 // Simulation-only observation of the accelerator's internal operation boundary.
 // This deliberately bypasses AXI-Lite polling to separate engine latency from
 // software-visible command-to-status latency; it is not a software interface.
 always @(posedge clk or negedge resetb) begin
  if(!resetb) begin
   internal_op_start_cycle=-1;
   internal_op_done_cycle=-1;
   internal_op_cycles=0;
   internal_op_started=0; wb_perf_started=0;
   compute_ar_handshakes=0; compute_r_beats=0; compute_r_gap_idle=0; compute_r_stalls=0;
   compute_core_busy_cycles=0; compute_noncore_busy_cycles=0;
    compute_r_beats_while_mac_busy=0; compute_read_active_while_mac_busy=0;
   wb_aw_handshakes=0; wb_w_beats=0; wb_b_responses=0; wb_w_stalls=0; wb_b_wait_cycles=0;
  end else begin
   if(dut.op_start) begin
    internal_op_start_cycle=bus_cycle;
    internal_op_started=1;
    compute_ar_handshakes=0; compute_r_beats=0; compute_r_gap_idle=0; compute_r_stalls=0;
    compute_core_busy_cycles=0; compute_noncore_busy_cycles=0;
    $display("TRACE-START: cycle=%0d reader_state=%0d",bus_cycle,dut.accel.frontend.state);
   end
   // Trace the scheduling boundary: external read bursts, local buffer-load
   // completion, compute start/done, and the reader's transition to next tile.
   // These are testbench-only observations, not hardware debug outputs.
   if(internal_op_started && dut.op_busy) begin
    if(arvalid_m && arready_m_q)
     $display("TRACE-AR: cycle=%0d addr=%h len=%0d reader_state=%0d tile_index=%0d",bus_cycle,araddr_m,arlen,dut.accel.frontend.state,dut.accel.frontend.tile_index);
    if(rvalid_m_q && rready_m && rlast_q)
     $display("TRACE-RLAST: cycle=%0d addr=%h reader_state=%0d tile_index=%0d tiled_state=%0d load_index=%0d compute_index=%0d",bus_cycle,rd_base,dut.accel.frontend.state,dut.accel.frontend.tile_index,dut.accel.frontend.tiled_core.state,dut.accel.frontend.tiled_core.load_index,dut.accel.frontend.tiled_core.compute_index);
    if(dut.accel.frontend.tiled_core.burst_done)
     $display("TRACE-LOAD-DONE: cycle=%0d bank=%0d load_index=%0d a_loaded=%b b_loaded=%b pair_loaded_now=%b reader_state=%0d",bus_cycle,dut.accel.frontend.tiled_core.active_burst_bank,dut.accel.frontend.tiled_core.load_index,dut.accel.frontend.tiled_core.a_loaded,dut.accel.frontend.tiled_core.b_loaded,dut.accel.frontend.tiled_core.pair_loaded_now,dut.accel.frontend.state);
    if(dut.accel.frontend.tiled_core.pair_loaded_now)
     $display("TRACE-PAIR-READY: cycle=%0d load_index=%0d compute_index=%0d compute_done_q=%b core_done=%b next_ready_q=%b reader_state=%0d",bus_cycle,dut.accel.frontend.tiled_core.load_index,dut.accel.frontend.tiled_core.compute_index,dut.accel.frontend.tiled_core.compute_done_q,dut.accel.frontend.tiled_core.core_done,dut.accel.frontend.tiled_core.next_ready_q,dut.accel.frontend.state);
    if(dut.accel.frontend.tiled_core.cmd_start)
     $display("TRACE-COMPUTE-START: cycle=%0d tile=%0d buffer=%0d tiled_state=%0d",bus_cycle,dut.accel.frontend.tiled_core.compute_index,dut.accel.frontend.tiled_core.cmd_buffer_q,dut.accel.frontend.tiled_core.state);
    if(dut.accel.frontend.tiled_core.core_done)
     $display("TRACE-COMPUTE-DONE: cycle=%0d tile=%0d load_index=%0d a_loaded=%b b_loaded=%b next_ready=%b",bus_cycle,dut.accel.frontend.tiled_core.compute_index,dut.accel.frontend.tiled_core.load_index,dut.accel.frontend.tiled_core.a_loaded,dut.accel.frontend.tiled_core.b_loaded,dut.accel.frontend.tiled_core.next_ready_q);
   end
   if(dut.op_busy) begin
    if(dut.accel.frontend.tiled_core.burst_core.command_core.compute_core.busy) begin
     compute_core_busy_cycles=compute_core_busy_cycles+1;
     if(rvalid_m_q && rready_m) compute_r_beats_while_mac_busy=compute_r_beats_while_mac_busy+1;
     if(rd_active) compute_read_active_while_mac_busy=compute_read_active_while_mac_busy+1;
    end else compute_noncore_busy_cycles=compute_noncore_busy_cycles+1;
    if(arvalid_m && arready_m_q) compute_ar_handshakes=compute_ar_handshakes+1;
    if(rvalid_m_q && rready_m) compute_r_beats=compute_r_beats+1;
    if(rd_active && !rvalid_m_q && r_gap_count>0) compute_r_gap_idle=compute_r_gap_idle+1;
    if(rvalid_m_q && !rready_m) compute_r_stalls=compute_r_stalls+1;
   end
   if(dut.wb_start) begin
    wb_perf_started=1;
    wb_aw_handshakes=0; wb_w_beats=0; wb_b_responses=0; wb_w_stalls=0; wb_b_wait_cycles=0;
   end
   if(dut.wb_busy || dut.wb_start) begin
    if(awvalid_m && awready_m) wb_aw_handshakes=wb_aw_handshakes+1;
    if(wvalid_m && wready_m) wb_w_beats=wb_w_beats+1;
    if(bvalid_m_q && bready_m) wb_b_responses=wb_b_responses+1;
    if(wvalid_m && !wready_m) wb_w_stalls=wb_w_stalls+1;
    if(!wvalid_m && !awvalid_m && !bvalid_m_q) wb_b_wait_cycles=wb_b_wait_cycles+1;
   end
   if(dut.op_done && internal_op_started) begin
    internal_op_done_cycle=bus_cycle;
    internal_op_cycles=internal_op_done_cycle-internal_op_start_cycle;
    $display("PERF-INTERNAL: accelerator op_start-to-op_done latency=%0d AXI memory-model cycles",internal_op_cycles);
    $display("PERF-COMPUTE-PHASE: MAC-core-busy=%0d non-core-operation=%0d cycles; AR handshakes=%0d R beats=%0d R-beats-while-MAC-busy=%0d read-active-while-MAC-busy=%0d cycles; R-gap-idle=%0d R-stalls=%0d cycles",compute_core_busy_cycles,compute_noncore_busy_cycles,compute_ar_handshakes,compute_r_beats,compute_r_beats_while_mac_busy,compute_read_active_while_mac_busy,compute_r_gap_idle,compute_r_stalls);
    internal_op_started=0;
   end
  end
 end

 // Small byte-addressed memory model. AXI reads return four packed INT8 bytes;
 // writes store the 32-bit accumulator word at the requested byte address.
 always @(posedge clk or negedge resetb) begin
  if(!resetb) begin
   awready_m<=0; wready_m<=0; arready_m_q<=0; rvalid_m_q<=0; bvalid_m_q<=0;
   rd_active<=0; wr_addr_seen<=0; wr_resp_pending<=0; rd_index<=0; wr_index<=0; r_gap_count<=0;
   rd_base<=0; rd_len<=0; wr_base<=0; wr_len<=0; rlast_q<=0; rresp_m_q<=0; bresp_m_q<=0; rid_q<=0; rdata_m_q<=0; read_burst_count<=0; bus_cycle<=0;
   prev_aw_stall<=0; prev_w_stall<=0; prev_ar_stall<=0; prev_r_stall<=0; prev_b_stall<=0;
   aw_stall_cycles<=0; w_stall_cycles<=0; ar_stall_cycles<=0; r_stall_cycles<=0; b_stall_cycles<=0; r_gap_idle_cycles<=0;
  end else begin
   bus_cycle<=bus_cycle+1;
   if(awvalid_m && !awready_m) aw_stall_cycles<=aw_stall_cycles+1;
   if(wvalid_m && !wready_m) w_stall_cycles<=w_stall_cycles+1;
   if(arvalid_m && !arready_m_q) ar_stall_cycles<=ar_stall_cycles+1;
   if(rvalid_m_q && !rready_m) r_stall_cycles<=r_stall_cycles+1;
   if(bvalid_m_q && !bready_m) b_stall_cycles<=b_stall_cycles+1;
   if(rd_active && !rvalid_m_q && r_gap_count>0) r_gap_idle_cycles<=r_gap_idle_cycles+1;
   // Deterministic READY gaps exercise independent AXI channel handshakes.
   awready_m <= (bus_cycle % 4 != 1);
   wready_m <= (bus_cycle % 5 != 2);
   arready_m_q <= (bus_cycle % 4 != 0);

   // Check VALID and payload stability after any cycle stalled by READY.
   if(prev_aw_stall && (!awvalid_m || {awid,awaddr_m,awlen,awsize,awburst} !== prev_aw_payload))
    $fatal(1,"AXI AW payload/VALID changed while stalled");
   if(prev_w_stall && (!wvalid_m || {wdata_m,wstrb_m,wlast} !== {prev_wdata,prev_wstrb,prev_wlast}))
    $fatal(1,"AXI W payload/VALID changed while stalled");
   if(prev_ar_stall && (!arvalid_m || {arid,araddr_m,arlen,arsize,arburst} !== prev_ar_payload))
    $fatal(1,"AXI AR payload/VALID changed while stalled");
   if(prev_r_stall && (!rvalid_m_q || {rid_q,rresp_m_q,rdata_m_q,rlast_q} !== {prev_r_payload,prev_rdata,prev_rlast}))
    $fatal(1,"AXI R payload/VALID changed while stalled");
   if(prev_b_stall && (!bvalid_m_q || bresp_m_q !== prev_b_payload[1:0]))
    $fatal(1,"AXI B payload/VALID changed while stalled");
   prev_aw_stall <= awvalid_m && !awready_m;
   prev_aw_payload <= {awid,awaddr_m,awlen,awsize,awburst};
   prev_w_stall <= wvalid_m && !wready_m;
   prev_wdata <= wdata_m; prev_wstrb <= wstrb_m; prev_wlast <= wlast;
   prev_ar_stall <= arvalid_m && !arready_m_q;
   prev_ar_payload <= {arid,araddr_m,arlen,arsize,arburst};
   prev_r_stall <= rvalid_m_q && !rready_m;
   prev_r_payload <= {rid_q,rresp_m_q};
   prev_rdata <= rdata_m_q; prev_rlast <= rlast_q;
   prev_b_stall <= bvalid_m_q && !bready_m;
   prev_b_payload <= {ID_W'(0),bresp_m_q};
   if(arvalid_m && arready_m_q) begin
    if(rd_active) $fatal(1,"unexpected overlapping AXI read address");
    if(arsize!=2 || arburst!=1 || arid!=0) $fatal(1,"bad AR fields");
    if(arlen!=8'd3) $fatal(1,"expected four-beat AXI read burst, ARLEN=%0d",arlen);
    case(read_burst_count)
     0: if(araddr_m!=32'h0100) $fatal(1,"expected A tile 0 at 0x100, got %h",araddr_m);
     1: if(araddr_m!=32'h0200) $fatal(1,"expected B tile 0 at 0x200, got %h",araddr_m);
     2: if(araddr_m!=32'h0110) $fatal(1,"expected A tile 1 at 0x110, got %h",araddr_m);
     3: if(araddr_m!=32'h0210) $fatal(1,"expected B tile 1 at 0x210, got %h",araddr_m);
     default: $fatal(1,"unexpected extra input read burst #%0d at %h",read_burst_count,araddr_m);
    endcase
    read_burst_count<=read_burst_count+1;
    rd_active<=1; rd_base<=araddr_m; rd_len<=arlen; rd_index<=0; r_gap_count<=0; rvalid_m_q<=0;
   end else if(rd_active && rvalid_m_q && rready_m) begin
    if(rlast_q) begin rd_active<=0; rvalid_m_q<=0; end
    else begin
     rd_index<=rd_index+1'b1;
     r_gap_count<=mem_gap;
     rvalid_m_q<=0;
    end
   end else if(rd_active && !rvalid_m_q && r_gap_count>0) begin
    r_gap_count<=r_gap_count-1;
   end else if(rd_active && !rvalid_m_q) begin
    r_gap_count<=mem_gap;
    rdata_m_q<={mem[rd_base+rd_index*4+3],mem[rd_base+rd_index*4+2],mem[rd_base+rd_index*4+1],mem[rd_base+rd_index*4]};
    rid_q<=0; rresp_m_q<=0; rlast_q<=(rd_index==rd_len); rvalid_m_q<=1;
   end
   if(awvalid_m && awready_m) begin
    if(awsize!=2 || awburst!=1 || awid!=0) $fatal(1,"bad AW fields");
    if(awaddr_m[1:0]!=0 || (awaddr_m[11:0]+((awlen+1)*4)>4096)) $fatal(1,"invalid or 4KiB-crossing write burst");
    wr_base<=awaddr_m; wr_len<=awlen; wr_index<=0; wr_addr_seen<=1;
   end
   if(wvalid_m && wready_m) begin
    if(!(wr_addr_seen || (awvalid_m && awready_m))) $fatal(1,"W beat accepted before AW in this simple memory model");
    if(wlast !== (((awvalid_m && awready_m) ? 0 : wr_index) == ((awvalid_m && awready_m) ? awlen : wr_len)))
     $fatal(1,"WLAST mismatch: index=%0d AWLEN=%0d WLAST=%b",(awvalid_m && awready_m) ? 0 : wr_index,(awvalid_m && awready_m) ? awlen : wr_len,wlast);
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
  if(!$value$plusargs("MEM_GAP=%d",mem_gap)) mem_gap=2;
  if(mem_gap<0 || mem_gap>20) $fatal(1,"MEM_GAP must be between 0 and 20, got %0d",mem_gap);
  $display("CONFIG: top-level AXI R-channel inter-beat MEM_GAP=%0d cycles",mem_gap);
  for(i=0;i<4096;i=i+1) mem[i]=0;
  // Two K tiles: both A tiles are identity. B0=1..16 and B1=10..25,
  // so the accumulated result A0*B0 + A1*B1 is 11..41.
  for(i=0;i<16;i=i+1) begin
   mem[16'h0100+i]=((i/4)==(i%4)) ? 8'd1 : 8'd0;
   mem[16'h0110+i]=((i/4)==(i%4)) ? 8'd1 : 8'd0;
   mem[16'h0200+i]=i+1;
   mem[16'h0210+i]=i+10;
  end
  repeat(4) @(negedge clk); resetb=1;
  axil_write('h08,'h0100); axil_write('h0C,'h0200); axil_write('h10,2); axil_write('h14,'h0300);
  phase_start_cycle=bus_cycle;
  axil_write('h00,1);
  // A second start while compute is active must be rejected and latched.
  axil_write('h00,1);
  axil_read('h04,status);
  if(!status[31]) $fatal(1,"busy compute command was not rejected in STATUS");
  axil_write('h04,'h80000000); // W1C command-rejected status
  axil_read('h04,status);
  if(status[31]) $fatal(1,"command-rejected W1C did not clear status");
  cycles=0; status=0;
  while(!status[1] && !status[2] && cycles<5000) begin axil_read('h04,status); cycles=cycles+1; end
  if(!status[1] || status[2]) $fatal(1,"compute did not complete successfully, STATUS=%h",status);
  compute_observed_cycles=bus_cycle-phase_start_cycle;
  $display("PERF: software-observed compute command-to-status latency=%0d AXI memory-model cycles",compute_observed_cycles);
  axil_write('h04,'h00000002); // clear compute done before checking writeback event
  phase_start_cycle=bus_cycle;
  axil_write('h00,2);
  cycles=0; status=0;
  while(!status[9] && !status[10] && cycles<5000) begin axil_read('h04,status); cycles=cycles+1; end
  if(!status[9] || status[10]) $fatal(1,"writeback did not complete successfully, STATUS=%h",status);
  writeback_observed_cycles=bus_cycle-phase_start_cycle;
  $display("PERF: software-observed writeback command-to-status latency=%0d AXI memory-model cycles",writeback_observed_cycles);
  $display("PERF-WRITEBACK-PHASE: AW handshakes=%0d W beats=%0d B responses=%0d W-stalls=%0d non-channel-active cycles=%0d",wb_aw_handshakes,wb_w_beats,wb_b_responses,wb_w_stalls,wb_b_wait_cycles);
  for(i=0;i<16;i=i+1) begin
   if({mem['h0300+i*4+3],mem['h0300+i*4+2],mem['h0300+i*4+1],mem['h0300+i*4]} !== (i*2+11))
    $fatal(1,"multi-tile result mismatch at word %0d: expected %0d got %h%h%h%h",i,(i*2+11),mem['h0300+i*4+3],mem['h0300+i*4+2],mem['h0300+i*4+1],mem['h0300+i*4]);
  end
  $display("PASS: AXI-Lite launched two K tiles; four input bursts and 16 accumulated results match reference");

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
  $display("PERF-STALLS: AW=%0d W=%0d AR=%0d R=%0d B=%0d response-gap-idle=%0d cycles",aw_stall_cycles,w_stall_cycles,ar_stall_cycles,r_stall_cycles,b_stall_cycles,r_gap_idle_cycles);
  $finish;
 end
 initial begin #300000; $fatal(1,"timeout"); end
endmodule
`default_nettype wire
