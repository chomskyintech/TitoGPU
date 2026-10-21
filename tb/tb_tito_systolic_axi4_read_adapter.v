`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_axi4_read_adapter;
    localparam integer ADDR_W=32, DATA_W=32, LEN_W=8, ID_W=2;
    reg clk, resetb;
    reg rd_req_valid;
    wire rd_req_ready;
    reg [ADDR_W-1:0] rd_req_addr;
    reg [LEN_W-1:0] rd_req_len;
    wire rd_data_valid;
    reg rd_data_ready;
    wire [DATA_W-1:0] rd_data;
    wire rd_data_last, rd_error;

    wire [ID_W-1:0] m_axi_arid;
    wire [ADDR_W-1:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid;
    reg m_axi_arready;

    reg [ID_W-1:0] m_axi_rid;
    reg [DATA_W-1:0] m_axi_rdata;
    reg [1:0] m_axi_rresp;
    reg m_axi_rlast, m_axi_rvalid;
    wire m_axi_rready;

    integer beats_seen;

    tito_systolic_axi4_read_adapter #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W), .ID_W(ID_W)
    ) dut (
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

    always #5 clk = ~clk;

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task start_request;
        input [ADDR_W-1:0] addr;
        input [LEN_W-1:0] len;
        begin
            @(negedge clk);
            m_axi_arready=1;
            rd_req_addr=addr; rd_req_len=len; rd_req_valid=1;
            @(posedge clk); #1;
            @(negedge clk); rd_req_valid=0; m_axi_arready=0;
        end
    endtask

    task send_beat;
        input [DATA_W-1:0] data_value;
        input last_value;
        input [1:0] resp_value;
        input [ID_W-1:0] id_value;
        begin
            @(negedge clk);
            m_axi_rdata=data_value; m_axi_rlast=last_value;
            m_axi_rresp=resp_value; m_axi_rid=id_value; m_axi_rvalid=1;
            #1;
            if (resp_value == 2'b00 && id_value == 0) begin
                if (!rd_data_valid || rd_data !== data_value || rd_data_last !== last_value) begin
                    $display("FAIL: valid R beat was not forwarded correctly");
                    $fatal(1);
                end
            end else begin
                if (!rd_error) begin
                    $display("FAIL: bad RRESP/RID did not raise rd_error");
                    $fatal(1);
                end
            end
            if (!m_axi_rready) begin
                $display("FAIL: expected R channel ready for this beat");
                $fatal(1);
            end
            tick();
            @(negedge clk); m_axi_rvalid=0; m_axi_rlast=0;
        end
    endtask

    initial begin
        clk=0; resetb=0;
        rd_req_valid=0; rd_req_addr=0; rd_req_len=0; rd_data_ready=1;
        m_axi_arready=0; m_axi_rid=0; m_axi_rdata=0;
        m_axi_rresp=0; m_axi_rlast=0; m_axi_rvalid=0; beats_seen=0;
        repeat(3) tick();
        @(negedge clk); resetb=1;

        // Address channel must hold its request under AR backpressure.
        @(negedge clk); rd_req_addr=32'h10; rd_req_len=4; rd_req_valid=1;
        #1;
        if (!m_axi_arvalid || m_axi_araddr !== 32'h40 ||
            m_axi_arlen !== 8'd3 || m_axi_arsize !== 3'd2 ||
            m_axi_arburst !== 2'b01 || m_axi_arid !== 0) begin
            $display("FAIL: AXI AR fields incorrect");
            $fatal(1);
        end
        repeat(2) begin
            tick();
            if (!m_axi_arvalid || m_axi_araddr !== 32'h40 || m_axi_arlen !== 8'd3) begin
                $display("FAIL: AR payload changed while stalled");
                $fatal(1);
            end
        end
        @(negedge clk); m_axi_arready=1;
        tick();
        @(negedge clk); rd_req_valid=0; m_axi_arready=0;

        // Exercise R-channel backpressure: beat remains visible until accepted.
        @(negedge clk); m_axi_rid=0; m_axi_rresp=0; m_axi_rdata=32'h12345678;
        m_axi_rlast=0; m_axi_rvalid=1; rd_data_ready=0;
        #1;
        if (!rd_data_valid || m_axi_rready) begin
            $display("FAIL: R-channel backpressure not propagated");
            $fatal(1);
        end
        repeat(2) begin
            tick();
            if (!m_axi_rvalid || !rd_data_valid || rd_data !== 32'h12345678) begin
                $display("FAIL: R data not held stable during downstream stall");
                $fatal(1);
            end
        end
        @(negedge clk); rd_data_ready=1;
        tick();
        @(negedge clk); m_axi_rvalid=0;

        send_beat(32'h00000002,0,0,0);
        send_beat(32'h00000003,0,0,0);
        send_beat(32'h00000004,1,0,0);
        if (dut.read_active) begin
            $display("FAIL: final RLAST did not release outstanding transaction");
            $fatal(1);
        end
        $display("PASS: AR backpressure, byte-address conversion, INCR burst fields, R backpressure, and RLAST");

        // Error response must be surfaced and consumed even if the consumer stalls.
        start_request(32'h20,1);
        @(negedge clk); rd_data_ready=0;
        send_beat(32'hDEADBEEF,1,2'b10,0);
        if (dut.read_active || !rd_error) begin
            // rd_error is expected to drop after the bad beat is no longer valid;
            // read_active must nevertheless have been cleared by RLAST.
            if (dut.read_active) begin
                $display("FAIL: error RLAST did not clear outstanding transaction");
                $fatal(1);
            end
        end
        $display("PASS: SLVERR is surfaced and consumed despite downstream backpressure");

        // RID mismatch is also a fatal response, not valid payload data.
        start_request(32'h30,1);
        @(negedge clk); rd_data_ready=1;
        send_beat(32'hCAFEBABE,1,0,1);
        if (dut.read_active) begin
            $display("FAIL: bad RID RLAST did not clear outstanding transaction");
            $fatal(1);
        end
        $display("PASS: unexpected RID rejected");
        $display("PASS: AXI4 read adapter regression complete");
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT");
        $fatal(1);
    end
endmodule

`default_nettype wire
