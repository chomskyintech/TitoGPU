`default_nettype none

module tito_systolic_axi4_read_adapter #(
    parameter integer ADDR_W=32, DATA_W=8, AXI_DATA_W=32, LEN_W=8, ID_W=4,
    parameter integer LANES=AXI_DATA_W/DATA_W,
    parameter integer BYTE_SHIFT=(AXI_DATA_W>=8 ? $clog2(AXI_DATA_W/8) : 0),
    parameter integer PACKED_OUTPUT=0
) (
    input wire clk, resetb,
    input wire rd_req_valid, output wire rd_req_ready,
    input wire [ADDR_W-1:0] rd_req_addr,
    input wire [LEN_W-1:0] rd_req_len,
    output wire rd_data_valid, input wire rd_data_ready,
    output wire [DATA_W-1:0] rd_data, output wire rd_data_last, rd_error,
    output wire packed_data_valid, input wire packed_data_ready,
    output wire [AXI_DATA_W-1:0] packed_data,
    output wire [LANES-1:0] packed_data_mask, output wire packed_data_last,
    output wire [ID_W-1:0] m_axi_arid,
    output wire [ADDR_W-1:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen, output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst, output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [ID_W-1:0] m_axi_rid,
    input wire [AXI_DATA_W-1:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp, input wire m_axi_rlast, m_axi_rvalid,
    output wire m_axi_rready
);
    localparam [1:0] AXI_RESP_OKAY=2'b00;
    reg read_active, buffer_valid, error_pending;
    reg [AXI_DATA_W-1:0] buffer_data;
    reg [LEN_W-1:0] logical_len_q, logical_count;
    reg [LEN_W:0] expected_beats_q, axi_beat_count;
    reg [((LANES>1)?$clog2(LANES):1)-1:0] lane_index;
    wire [LEN_W:0] request_beats;
    wire request_bad, request_handshake, r_handshake, logical_handshake;
    wire r_bad, r_last_bad, final_logical_lane;
    wire packed_handshake;
    wire [LEN_W:0] logical_remaining;
    integer lane_i;
    reg [LANES-1:0] packed_mask_comb;

    assign request_beats=(rd_req_len+LANES-1)/LANES;
    assign request_bad=(rd_req_len==0) ||
      ((rd_req_addr & ((AXI_DATA_W/8)-1))!=0) ||
      ((rd_req_addr[11:0]+request_beats*(AXI_DATA_W/8))>4096);
    assign m_axi_arid={ID_W{1'b0}};
    assign m_axi_araddr=rd_req_addr;
    assign m_axi_arlen=request_beats-1'b1;
    assign m_axi_arsize=BYTE_SHIFT[2:0];
    assign m_axi_arburst=2'b01;
    assign m_axi_arvalid=rd_req_valid && !read_active && !request_bad;
    assign rd_req_ready=!read_active && (request_bad || m_axi_arready);
    assign request_handshake=rd_req_valid && rd_req_ready;
    assign r_bad=(m_axi_rresp!=AXI_RESP_OKAY)||(m_axi_rid!={ID_W{1'b0}});
    assign r_last_bad=(m_axi_rlast!=(axi_beat_count==expected_beats_q-1'b1));
    assign m_axi_rready=read_active && !buffer_valid;
    assign r_handshake=m_axi_rvalid && m_axi_rready;
    assign rd_data_valid=buffer_valid && !error_pending && !PACKED_OUTPUT;
    assign rd_data=buffer_data>>(lane_index*DATA_W);
    assign final_logical_lane=(logical_count==logical_len_q-1'b1);
    assign rd_data_last=final_logical_lane;
    assign logical_handshake=rd_data_valid && rd_data_ready;
    assign packed_data_valid=buffer_valid && !error_pending && PACKED_OUTPUT;
    assign packed_data=buffer_data;
    assign logical_remaining=logical_len_q-logical_count;
    always @* begin
      packed_mask_comb={LANES{1'b0}};
      for(lane_i=0; lane_i<LANES; lane_i=lane_i+1)
        if(lane_i<logical_remaining) packed_mask_comb[lane_i]=1'b1;
    end
    assign packed_data_mask=packed_mask_comb;
    assign packed_data_last=(logical_remaining<=LANES);
    assign packed_handshake=packed_data_valid && packed_data_ready;
    assign rd_error=error_pending || (r_handshake && (r_bad || r_last_bad));

    always @(posedge clk or negedge resetb) begin
      if(!resetb) begin
        read_active<=0; buffer_valid<=0; buffer_data<=0; error_pending<=0;
        logical_len_q<=0; logical_count<=0; expected_beats_q<=0;
        axi_beat_count<=0; lane_index<=0;
      end else begin
        if(request_handshake) begin
          if(request_bad) error_pending<=1;
          else begin
            read_active<=1; buffer_valid<=0; logical_len_q<=rd_req_len;
            logical_count<=0; expected_beats_q<=request_beats;
            axi_beat_count<=0; lane_index<=0; error_pending<=0;
          end
        end
        if(r_handshake) begin
          axi_beat_count<=axi_beat_count+1'b1;
          if(r_bad || r_last_bad) begin
            error_pending<=1; read_active<=0; buffer_valid<=0;
          end else begin
            buffer_data<=m_axi_rdata; buffer_valid<=1;
            if(m_axi_rlast) read_active<=0;
          end
          if((axi_beat_count==expected_beats_q-1'b1) && !m_axi_rlast) begin
            error_pending<=1; read_active<=0; buffer_valid<=0;
          end
        end
        if(logical_handshake) begin
          logical_count<=logical_count+1'b1;
          if(final_logical_lane || lane_index==LANES-1) begin
            buffer_valid<=0; lane_index<=0;
          end else lane_index<=lane_index+1'b1;
        end
        if(packed_handshake) begin
          if(logical_remaining>=LANES) logical_count<=logical_count+LANES;
          else logical_count<=logical_count+logical_remaining;
          buffer_valid<=0;
          lane_index<=0;
        end
      end
    end

    initial begin
      if(DATA_W<8 || AXI_DATA_W<DATA_W || (DATA_W%8)!=0 ||
         (AXI_DATA_W%DATA_W)!=0 || ((LANES&(LANES-1))!=0) ||
         (((AXI_DATA_W/8)&((AXI_DATA_W/8)-1))!=0)) begin
        $error("DATA_W must divide AXI_DATA_W into power-of-two byte lanes");
        $finish;
      end
      if(BYTE_SHIFT>7) begin $error("AXI4 ARSIZE cannot represent AXI_DATA_W"); $finish; end
    end
endmodule

`default_nettype wire
