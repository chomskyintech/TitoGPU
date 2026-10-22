`timescale 1ns/1ps
`default_nettype none

module tb_tito_systolic_axi4_width_converter;
    localparam integer ADDR_W=16, DATA_W=8, AXI_DATA_W=32, LEN_W=5, ID_W=2;
    reg clk, resetb;
    reg rd_req_valid, rd_data_ready, m_axi_arready;
    reg [ADDR_W-1:0] rd_req_addr;
    reg [LEN_W-1:0] rd_req_len;
    wire rd_req_ready, rd_data_valid, rd_data_last, rd_error;
    wire [DATA_W-1:0] rd_data;
    wire [ID_W-1:0] m_axi_arid;
    wire [ADDR_W-1:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid;
    reg [ID_W-1:0] m_axi_rid;
    reg [AXI_DATA_W-1:0] m_axi_rdata;
    reg [1:0] m_axi_rresp;
    reg m_axi_rlast, m_axi_rvalid;
    wire m_axi_rready;
    integer byte_checks;

    tito_systolic_axi4_read_adapter #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .AXI_DATA_W(AXI_DATA_W),
        .LEN_W(LEN_W), .ID_W(ID_W)
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

    always #5 clk=~clk;

    task reset_dut;
        begin
            @(negedge clk); resetb=0;
            rd_req_valid=0; rd_data_ready=0; m_axi_arready=0;
            m_axi_rvalid=0; m_axi_rlast=0; m_axi_rresp=0; m_axi_rid=0;
            repeat(3) @(negedge clk);
            resetb=1;
            @(negedge clk);
        end
    endtask

    task start_request;
        input [ADDR_W-1:0] addr;
        input [LEN_W-1:0] len;
        input [7:0] expected_arlen;
        begin
            rd_req_addr=addr; rd_req_len=len; rd_req_valid=1; m_axi_arready=1;
            #1;
            if (!m_axi_arvalid || m_axi_araddr!==addr ||
                m_axi_arlen!==expected_arlen || m_axi_arsize!==3'd2 ||
                m_axi_arburst!==2'b01 || m_axi_arid!==0) begin
                $display("FAIL: wide AXI AR fields addr=%h len=%0d size=%0d",
                    m_axi_araddr,m_axi_arlen,m_axi_arsize);
                $fatal(1);
            end
            @(posedge clk); #1;
            @(negedge clk); rd_req_valid=0; m_axi_arready=0;
        end
    endtask

    task send_beat;
        input [31:0] data_value;
        input last_value;
        input [1:0] resp_value;
        input [ID_W-1:0] id_value;
        begin
            m_axi_rdata=data_value; m_axi_rlast=last_value;
            m_axi_rresp=resp_value; m_axi_rid=id_value; m_axi_rvalid=1;
            while (!m_axi_rready) @(negedge clk);
            @(posedge clk); #1;
            @(negedge clk); m_axi_rvalid=0; m_axi_rlast=0;
        end
    endtask

    task consume_byte;
        input [7:0] expected_byte;
        input expected_last;
        input integer stall_cycles;
        integer s;
        begin
            #1;
            if (!rd_data_valid || rd_data!==expected_byte || rd_data_last!==expected_last) begin
                $display("FAIL: byte lane mismatch got=%h last=%b expected=%h last=%b",
                    rd_data,rd_data_last,expected_byte,expected_last);
                $fatal(1);
            end
            rd_data_ready=0;
            for (s=0;s<stall_cycles;s=s+1) begin
                @(posedge clk); #1;
                if (!rd_data_valid || rd_data!==expected_byte ||
                    rd_data_last!==expected_last || m_axi_rready) begin
                    $display("FAIL: byte/data or lane changed during downstream stall");
                    $fatal(1);
                end
            end
            @(negedge clk); rd_data_ready=1;
            @(posedge clk); #1;
            byte_checks=byte_checks+1;
            @(negedge clk); rd_data_ready=0;
        end
    endtask

    initial begin
        clk=0; resetb=0; rd_req_valid=0; rd_req_addr=0; rd_req_len=0;
        rd_data_ready=0; m_axi_arready=0; m_axi_rid=0; m_axi_rdata=0;
        m_axi_rresp=0; m_axi_rlast=0; m_axi_rvalid=0; byte_checks=0;
        reset_dut();

        // Two 32-bit beats deliver eight distinct INT8 operands, low lane first.
        start_request(16'h0100,8,8'd1);
        send_beat(32'h80FE7F01,0,2'b00,0);
        consume_byte(8'h01,0,2);
        consume_byte(8'h7F,0,1);
        consume_byte(8'hFE,0,2);
        consume_byte(8'h80,0,1);
        send_beat(32'h44332211,1,2'b00,0);
        consume_byte(8'h11,0,1);
        consume_byte(8'h22,0,2);
        consume_byte(8'h33,0,1);
        consume_byte(8'h44,1,2);
        if (rd_error || dut.read_active || byte_checks!=8)
            $fatal(1,"FAIL: normal width-conversion transaction status");
        $display("PASS: 32-to-8 lane order, stable backpressure, logical RLAST (%0d bytes)",byte_checks);

        // Early RLAST must be rejected before any data can look like completion.
        reset_dut();
        start_request(16'h0100,8,8'd1);
        send_beat(32'h04030201,1,2'b00,0);
        if (!rd_error || dut.read_active) $fatal(1,"FAIL: early RLAST not rejected");
        $display("PASS: early AXI RLAST rejected");

        // The final AXI beat must carry RLAST; a missing marker is fatal too.
        reset_dut();
        start_request(16'h0100,8,8'd1);
        send_beat(32'h04030201,0,2'b00,0);
        consume_byte(8'h01,0,0); consume_byte(8'h02,0,0);
        consume_byte(8'h03,0,0); consume_byte(8'h04,0,0);
        send_beat(32'h08070605,0,2'b00,0);
        if (!rd_error || dut.read_active) $fatal(1,"FAIL: missing final RLAST not rejected");
        $display("PASS: missing final AXI RLAST rejected");

        reset_dut();
        start_request(16'h0100,4,8'd0);
        send_beat(32'h04030201,1,2'b10,0);
        if (!rd_error) $fatal(1,"FAIL: non-OKAY RRESP not rejected");
        $display("PASS: non-OKAY RRESP rejected on 32-bit bus");

        reset_dut();
        start_request(16'h0100,4,8'd0);
        send_beat(32'h04030201,1,2'b00,1);
        if (!rd_error) $fatal(1,"FAIL: unexpected RID not rejected");
        $display("PASS: unexpected RID rejected on 32-bit bus");
        $display("PASS: AXI width-converter regression complete");
        $finish;
    end

    initial begin
        #20000;
        $display("TIMEOUT");
        $fatal(1);
    end
endmodule

`default_nettype wire
