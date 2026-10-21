`default_nettype none

// Single-outstanding AXI4 read-channel adapter for TitoGPU's generic read frontend.
// Generic addresses are DATA_W-bit beat addresses; AXI addresses are byte addresses.
// This is an AXI4 read-channel subset: one outstanding burst, fixed ARID=0,
// no writes, no IDs in the generic-side contract, and no burst splitting.
module tito_systolic_axi4_read_adapter #(
    parameter integer ADDR_W = 32,
    parameter integer DATA_W = 32,
    parameter integer LEN_W = 8,
    parameter integer ID_W = 4,
    parameter integer BYTE_SHIFT = (DATA_W >= 8 ? $clog2(DATA_W/8) : 0)
) (
    input  wire                  clk,
    input  wire                  resetb,

    input  wire                  rd_req_valid,
    output wire                  rd_req_ready,
    input  wire [ADDR_W-1:0]     rd_req_addr,
    input  wire [LEN_W-1:0]      rd_req_len,

    output wire                  rd_data_valid,
    input  wire                  rd_data_ready,
    output wire [DATA_W-1:0]     rd_data,
    output wire                  rd_data_last,
    output wire                  rd_error,

    output wire [ID_W-1:0]       m_axi_arid,
    output wire [ADDR_W-1:0]     m_axi_araddr,
    output wire [7:0]             m_axi_arlen,
    output wire [2:0]             m_axi_arsize,
    output wire [1:0]             m_axi_arburst,
    output wire                  m_axi_arvalid,
    input  wire                  m_axi_arready,

    input  wire [ID_W-1:0]       m_axi_rid,
    input  wire [DATA_W-1:0]     m_axi_rdata,
    input  wire [1:0]             m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready
);
    localparam integer BYTE_LANES = DATA_W / 8;
    localparam [1:0] AXI_RESP_OKAY = 2'b00;

    reg read_active;
    wire r_handshake;
    wire r_bad;

    // AXI4 encodes burst length as beats-minus-one and addresses in bytes.
    // This adapter expects DATA_W to be a power-of-two number of bits >= 8.
    assign m_axi_arid    = {ID_W{1'b0}};
    assign m_axi_araddr  = rd_req_addr << BYTE_SHIFT;
    assign m_axi_arlen   = rd_req_len - 1'b1;
    assign m_axi_arsize  = BYTE_SHIFT[2:0];
    assign m_axi_arburst = 2'b01; // INCR
    assign m_axi_arvalid = rd_req_valid && !read_active;
    assign rd_req_ready  = m_axi_arready && !read_active;

    assign r_bad = (m_axi_rresp != AXI_RESP_OKAY) || (m_axi_rid != {ID_W{1'b0}});
    // Consume an error response even if the local datapath is backpressured;
    // the generic frontend sees rd_error and enters its fatal state.
    assign m_axi_rready = read_active && (rd_data_ready || (m_axi_rvalid && r_bad));
    assign rd_data_valid = m_axi_rvalid && read_active && !r_bad;
    assign rd_data = m_axi_rdata;
    assign rd_data_last = m_axi_rlast;
    assign rd_error = m_axi_rvalid && read_active && r_bad;
    assign r_handshake = m_axi_rvalid && m_axi_rready;

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            read_active <= 1'b0;
        end else begin
            if (m_axi_arvalid && m_axi_arready)
                read_active <= 1'b1;
            if (r_handshake && m_axi_rlast)
                read_active <= 1'b0;
        end
    end

    // Guard common integration mistakes at elaboration/simulation time.
    initial begin
        if (DATA_W < 8 || (DATA_W % 8) != 0 || ((BYTE_LANES & (BYTE_LANES-1)) != 0)) begin
            $error("DATA_W must be a power-of-two number of bits and a whole number of bytes");
            $finish;
        end
        if (BYTE_SHIFT > 7) begin
            $error("AXI4 ARSIZE cannot represent this DATA_W");
            $finish;
        end
    end
endmodule

`default_nettype wire
