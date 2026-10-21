// Minimal AXI4-Lite control/status register bank for TitoGPU.
// 32-bit data bus, independent AW/W capture, single outstanding B and R responses.
`default_nettype none
module tito_systolic_axi4lite_control #(
    parameter integer ADDR_W=32,
    parameter integer TILE_COUNT_W=8,
    parameter [31:0] VERSION=32'h0001_0000
) (
    input wire clk, resetb,
    input wire [ADDR_W-1:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [ADDR_W-1:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,
    output reg op_start,
    output reg [ADDR_W-1:0] a_base_addr,
    output reg [ADDR_W-1:0] b_base_addr,
    output reg [TILE_COUNT_W-1:0] op_tile_count,
    input wire op_busy,
    input wire op_done,
    input wire op_error,
    output reg writeback_start,
    output reg [ADDR_W-1:0] writeback_base_addr,
    input wire writeback_start_ready,
    input wire writeback_busy,
    input wire writeback_done,
    input wire writeback_error,
    input wire [3:0] writeback_error_code
);
    localparam [7:0] REG_CONTROL=8'h00, REG_STATUS=8'h04,
                     REG_A_BASE=8'h08, REG_B_BASE=8'h0C,
                     REG_TILE_COUNT=8'h10, REG_WB_BASE=8'h14,
                     REG_ERROR_CODE=8'h18, REG_VERSION=8'h1C;
    localparam [1:0] RESP_OKAY=2'b00, RESP_DECERR=2'b11;

    reg awaddr_hold, wdata_hold;
    reg [ADDR_W-1:0] awaddr_q;
    reg [31:0] wdata_q;
    reg [3:0] wstrb_q;
    reg op_done_latched, op_error_latched;
    reg wb_done_latched, wb_error_latched, command_rejected;
    reg [3:0] last_error_code;
    reg prev_op_done, prev_op_error, prev_wb_done, prev_wb_error;

    wire aw_handshake, w_handshake, ar_handshake;
    wire write_fire;
    wire [ADDR_W-1:0] write_addr_now;
    wire [31:0] write_data_now;
    wire [3:0] write_strb_now;
    reg [31:0] read_data_now;
    reg read_addr_valid;

    assign s_axi_awready=!awaddr_hold && !s_axi_bvalid;
    assign s_axi_wready=!wdata_hold && !s_axi_bvalid;
    assign s_axi_arready=!s_axi_rvalid;
    assign aw_handshake=s_axi_awvalid && s_axi_awready;
    assign w_handshake=s_axi_wvalid && s_axi_wready;
    assign ar_handshake=s_axi_arvalid && s_axi_arready;
    assign write_fire=!s_axi_bvalid &&
                      (awaddr_hold || aw_handshake) &&
                      (wdata_hold || w_handshake);
    assign write_addr_now=awaddr_hold ? awaddr_q : s_axi_awaddr;
    assign write_data_now=wdata_hold ? wdata_q : s_axi_wdata;
    assign write_strb_now=wdata_hold ? wstrb_q : s_axi_wstrb;

    always @* begin
        read_data_now=32'h0;
        case (s_axi_araddr[7:0])
            REG_CONTROL: read_data_now=32'h0;
            REG_STATUS: begin
                read_data_now[0]=op_busy;
                read_data_now[1]=op_done_latched;
                read_data_now[2]=op_error_latched;
                read_data_now[8]=writeback_busy;
                read_data_now[9]=wb_done_latched;
                read_data_now[10]=wb_error_latched;
                read_data_now[31]=command_rejected;
            end
            REG_A_BASE: read_data_now=a_base_addr;
            REG_B_BASE: read_data_now=b_base_addr;
            REG_TILE_COUNT: read_data_now=op_tile_count;
            REG_WB_BASE: read_data_now=writeback_base_addr;
            REG_ERROR_CODE: read_data_now={28'b0,last_error_code};
            REG_VERSION: read_data_now=VERSION;
            default: read_data_now=32'h0;
        endcase
    end

    always @* begin
        read_addr_valid=(s_axi_araddr[1:0]==2'b00) &&
            ((s_axi_araddr[7:0]==REG_CONTROL) ||
             (s_axi_araddr[7:0]==REG_STATUS) ||
             (s_axi_araddr[7:0]==REG_A_BASE) ||
             (s_axi_araddr[7:0]==REG_B_BASE) ||
             (s_axi_araddr[7:0]==REG_TILE_COUNT) ||
             (s_axi_araddr[7:0]==REG_WB_BASE) ||
             (s_axi_araddr[7:0]==REG_ERROR_CODE) ||
             (s_axi_araddr[7:0]==REG_VERSION));
    end

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            awaddr_hold<=0; wdata_hold<=0; awaddr_q<=0;
            wdata_q<=0; wstrb_q<=0;
            s_axi_bresp<=RESP_OKAY; s_axi_bvalid<=0;
            s_axi_rdata<=0; s_axi_rresp<=RESP_OKAY; s_axi_rvalid<=0;
            op_start<=0; a_base_addr<=0; b_base_addr<=0; op_tile_count<=1;
            writeback_start<=0; writeback_base_addr<=0;
            op_done_latched<=0; op_error_latched<=0;
            wb_done_latched<=0; wb_error_latched<=0; command_rejected<=0;
            last_error_code<=0;
            prev_op_done<=0; prev_op_error<=0;
            prev_wb_done<=0; prev_wb_error<=0;
        end else begin
            op_start<=0;
            writeback_start<=0;
            prev_op_done<=op_done;
            prev_op_error<=op_error;
            prev_wb_done<=writeback_done;
            prev_wb_error<=writeback_error;
            if (op_done && !prev_op_done) op_done_latched<=1;
            if (op_error && !prev_op_error) op_error_latched<=1;
            if (writeback_done && !prev_wb_done) wb_done_latched<=1;
            if (writeback_error && !prev_wb_error) begin
                wb_error_latched<=1;
                last_error_code<=writeback_error_code;
            end

            if (aw_handshake) begin
                awaddr_hold<=1;
                awaddr_q<=s_axi_awaddr;
            end
            if (w_handshake) begin
                wdata_hold<=1;
                wdata_q<=s_axi_wdata;
                wstrb_q<=s_axi_wstrb;
            end

            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if (write_fire) begin
                awaddr_hold<=0;
                wdata_hold<=0;
                s_axi_bvalid<=1;
                s_axi_bresp<=RESP_OKAY;
                if (write_addr_now[1:0]!=2'b00)
                    s_axi_bresp<=RESP_DECERR;
                else begin
                    case (write_addr_now[7:0])
                        REG_CONTROL: begin
                            if (write_strb_now[0] &&
                                (write_data_now[0] || write_data_now[1])) begin
                                if (write_data_now[0] && write_data_now[1])
                                    command_rejected<=1;
                                else if (write_data_now[0]) begin
                                    if (!op_busy && !writeback_busy)
                                        op_start<=1;
                                    else
                                        command_rejected<=1;
                                end else if (write_data_now[1]) begin
                                    if (writeback_start_ready && !op_busy)
                                        writeback_start<=1;
                                    else
                                        command_rejected<=1;
                                end
                            end
                        end
                        REG_STATUS: begin
                            if (write_strb_now[0]) begin
                                if (write_data_now[1]) op_done_latched<=0;
                                if (write_data_now[2]) op_error_latched<=0;
                            end
                            if (write_strb_now[1]) begin
                                if (write_data_now[9]) wb_done_latched<=0;
                                if (write_data_now[10]) begin
                                    wb_error_latched<=0;
                                    last_error_code<=0;
                                end
                            end
                            if (write_strb_now[3] && write_data_now[31])
                                command_rejected<=0;
                        end
                        REG_A_BASE: begin
                            if (write_strb_now[0]) a_base_addr[7:0]<=write_data_now[7:0];
                            if (write_strb_now[1]) a_base_addr[15:8]<=write_data_now[15:8];
                            if (write_strb_now[2]) a_base_addr[23:16]<=write_data_now[23:16];
                            if (write_strb_now[3]) a_base_addr[31:24]<=write_data_now[31:24];
                        end
                        REG_B_BASE: begin
                            if (write_strb_now[0]) b_base_addr[7:0]<=write_data_now[7:0];
                            if (write_strb_now[1]) b_base_addr[15:8]<=write_data_now[15:8];
                            if (write_strb_now[2]) b_base_addr[23:16]<=write_data_now[23:16];
                            if (write_strb_now[3]) b_base_addr[31:24]<=write_data_now[31:24];
                        end
                        REG_TILE_COUNT: begin
                            if (write_strb_now[0]) op_tile_count[7:0]<=write_data_now[7:0];
                        end
                        REG_WB_BASE: begin
                            if (write_strb_now[0]) writeback_base_addr[7:0]<=write_data_now[7:0];
                            if (write_strb_now[1]) writeback_base_addr[15:8]<=write_data_now[15:8];
                            if (write_strb_now[2]) writeback_base_addr[23:16]<=write_data_now[23:16];
                            if (write_strb_now[3]) writeback_base_addr[31:24]<=write_data_now[31:24];
                        end
                        REG_ERROR_CODE, REG_VERSION: s_axi_bresp<=RESP_DECERR;
                        default: s_axi_bresp<=RESP_DECERR;
                    endcase
                end
            end

            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if (ar_handshake) begin
                s_axi_rvalid<=1;
                s_axi_rdata<=read_data_now;
                s_axi_rresp<=read_addr_valid ? RESP_OKAY : RESP_DECERR;
            end
        end
    end

    initial begin
        if (ADDR_W<32) $error("ADDR_W must be at least 32 bits for the current register map");
        if (TILE_COUNT_W!=8)
            $error("The initial register map uses an 8-bit tile-count field");
    end
endmodule
`default_nettype wire
