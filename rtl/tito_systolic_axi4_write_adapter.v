`default_nettype none

// Restricted AXI4 write master with legal burst splitting.
// One command may contain up to 256 full-width beats. Bursts split at 4 KiB boundaries.
module tito_systolic_axi4_write_adapter #(
    parameter integer ADDR_W=32,
    parameter integer DATA_W=32,
    parameter integer LEN_W=9,
    parameter integer ID_W=4,
    parameter integer MAX_BURST_BEATS=256,
    parameter integer BYTES_PER_BEAT=DATA_W/8,
    parameter integer SIZE=$clog2(BYTES_PER_BEAT)
) (
    input wire clk, resetb,
    input wire cmd_valid, output wire cmd_ready,
    input wire [ADDR_W-1:0] cmd_addr,
    input wire [LEN_W-1:0] cmd_beats,
    input wire stream_valid, output wire stream_ready,
    input wire [DATA_W-1:0] stream_data,
    input wire stream_last,
    output reg busy, done, error,
    output reg [3:0] error_code,
    output wire [ID_W-1:0] m_axi_awid,
    output reg [ADDR_W-1:0] m_axi_awaddr,
    output reg [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [DATA_W-1:0] m_axi_wdata,
    output wire [BYTES_PER_BEAT-1:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);
    localparam [3:0] ERR_NONE=4'd0, ERR_ZERO_LEN=4'd1, ERR_UNALIGNED=4'd2,
                     ERR_TOO_LONG=4'd3, ERR_STREAM_LAST=4'd5, ERR_BRESP=4'd6;
    localparam [1:0] RESP_OKAY=2'b00;

    reg active, aw_done;
    reg [LEN_W-1:0] total_remaining, burst_remaining, burst_size;
    reg [DATA_W-1:0] data_q;
    reg data_q_valid, last_q;
    wire aw_handshake, w_handshake, b_handshake, stream_handshake;
    wire expected_stream_last;
    wire [LEN_W-1:0] initial_burst_size;

    function [LEN_W-1:0] calc_burst;
        input [ADDR_W-1:0] addr;
        input [LEN_W-1:0] remaining;
        integer boundary_beats;
        integer selected;
        begin
            boundary_beats=(4096-addr[11:0])/BYTES_PER_BEAT;
            selected=remaining;
            if (selected>MAX_BURST_BEATS) selected=MAX_BURST_BEATS;
            if (selected>boundary_beats) selected=boundary_beats;
            calc_burst=selected;
        end
    endfunction

    assign initial_burst_size=calc_burst(cmd_addr,cmd_beats);
    assign cmd_ready=!active;
    assign m_axi_awid={ID_W{1'b0}};
    assign m_axi_awsize=SIZE[2:0];
    assign m_axi_awburst=2'b01;
    assign m_axi_awvalid=active && !aw_done;
    assign aw_handshake=m_axi_awvalid && m_axi_awready;
    assign stream_ready=active && (total_remaining!=0) && (burst_remaining!=0) &&
                        !data_q_valid && !error;
    assign stream_handshake=stream_valid && stream_ready;
    assign expected_stream_last=(total_remaining==1);
    assign m_axi_wdata=data_q;
    assign m_axi_wstrb={BYTES_PER_BEAT{1'b1}};
    assign m_axi_wlast=last_q;
    assign m_axi_wvalid=data_q_valid && !error;
    assign w_handshake=m_axi_wvalid && m_axi_wready;
    assign m_axi_bready=active && aw_done && (burst_remaining==0) && !data_q_valid;
    assign b_handshake=m_axi_bvalid && m_axi_bready;

    always @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            active<=0; busy<=0; done<=0; error<=0; error_code<=ERR_NONE;
            aw_done<=0; total_remaining<=0; burst_remaining<=0; burst_size<=0;
            m_axi_awaddr<=0; m_axi_awlen<=0; data_q<=0; data_q_valid<=0; last_q<=0;
        end else begin
            done<=0;
            if (cmd_valid && cmd_ready) begin
                error<=0; error_code<=ERR_NONE;
                if (cmd_beats==0 || (cmd_addr % BYTES_PER_BEAT)!=0 ||
                    cmd_beats>MAX_BURST_BEATS || initial_burst_size==0) begin
                    error<=1; active<=0; busy<=0;
                    if (cmd_beats==0) error_code<=ERR_ZERO_LEN;
                    else if ((cmd_addr % BYTES_PER_BEAT)!=0) error_code<=ERR_UNALIGNED;
                    else error_code<=ERR_TOO_LONG;
                end else begin
                    active<=1; busy<=1; aw_done<=0;
                    m_axi_awaddr<=cmd_addr;
                    burst_size<=initial_burst_size;
                    burst_remaining<=initial_burst_size;
                    m_axi_awlen<=initial_burst_size-1'b1;
                    total_remaining<=cmd_beats;
                    data_q_valid<=0; last_q<=0;
                end
            end

            if (aw_handshake) aw_done<=1;

            if (stream_handshake) begin
                if (stream_last!=expected_stream_last) begin
                    error<=1; error_code<=ERR_STREAM_LAST;
                    active<=0; busy<=0; data_q_valid<=0;
                end else begin
                    data_q<=stream_data;
                    last_q<=(burst_remaining==1);
                    data_q_valid<=1;
                end
            end

            if (w_handshake) begin
                data_q_valid<=0;
                total_remaining<=total_remaining-1'b1;
                burst_remaining<=burst_remaining-1'b1;
            end

            if (b_handshake) begin
                if (m_axi_bresp!=RESP_OKAY) begin
                    active<=0; busy<=0; error<=1; error_code<=ERR_BRESP;
                end else if (total_remaining==0) begin
                    active<=0; busy<=0; done<=1;
                end else begin
                    m_axi_awaddr<=m_axi_awaddr+(burst_size*BYTES_PER_BEAT);
                    burst_size<=calc_burst(m_axi_awaddr+(burst_size*BYTES_PER_BEAT),total_remaining);
                    burst_remaining<=calc_burst(m_axi_awaddr+(burst_size*BYTES_PER_BEAT),total_remaining);
                    m_axi_awlen<=calc_burst(m_axi_awaddr+(burst_size*BYTES_PER_BEAT),total_remaining)-1'b1;
                    aw_done<=0;
                end
            end
        end
    end

    initial begin
        if ((DATA_W % 8)!=0 || BYTES_PER_BEAT<1 ||
            (BYTES_PER_BEAT & (BYTES_PER_BEAT-1))!=0)
            $error("DATA_W must contain a power-of-two number of bytes");
    end
endmodule

`default_nettype wire
