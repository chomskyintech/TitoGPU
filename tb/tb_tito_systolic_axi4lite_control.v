`timescale 1ns/1ps
`default_nettype none
module tb_tito_systolic_axi4lite_control;
    reg clk, resetb;
    reg [31:0] awaddr, wdata, araddr;
    reg awvalid, wvalid, bready, arvalid, rready;
    reg [3:0] wstrb;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    reg op_busy, op_done, op_error;
    reg writeback_start_ready, writeback_busy, writeback_done, writeback_error;
    reg [3:0] writeback_error_code;
    wire op_start, writeback_start;
    wire [31:0] a_base_addr, b_base_addr, writeback_base_addr;
    wire [7:0] op_tile_count;
    integer op_start_count, wb_start_count, cycles, i;
    reg [31:0] read_value;
    reg [1:0] read_resp;

    tito_systolic_axi4lite_control dut (
        .clk(clk), .resetb(resetb),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .op_start(op_start), .a_base_addr(a_base_addr), .b_base_addr(b_base_addr),
        .op_tile_count(op_tile_count), .op_busy(op_busy), .op_done(op_done), .op_error(op_error),
        .writeback_start(writeback_start), .writeback_base_addr(writeback_base_addr),
        .writeback_start_ready(writeback_start_ready), .writeback_busy(writeback_busy),
        .writeback_done(writeback_done), .writeback_error(writeback_error),
        .writeback_error_code(writeback_error_code)
    );
    always #5 clk=~clk;
    always @(posedge clk) begin
        if (!resetb) begin op_start_count<=0; wb_start_count<=0; end
        else begin
            if (op_start) op_start_count<=op_start_count+1;
            if (writeback_start) wb_start_count<=wb_start_count+1;
        end
    end

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0] strb;
        input integer w_first;
        input [1:0] expected_resp;
        begin
            if (w_first) begin
                @(negedge clk); wdata=data; wstrb=strb; wvalid=1;
                do @(posedge clk); while (!wready);
                @(negedge clk); wvalid=0;
                repeat(2) @(negedge clk);
                awaddr=addr; awvalid=1;
                do @(posedge clk); while (!awready);
                @(negedge clk); awvalid=0;
            end else begin
                @(negedge clk); awaddr=addr; awvalid=1;
                do @(posedge clk); while (!awready);
                @(negedge clk); awvalid=0;
                repeat(2) @(negedge clk);
                wdata=data; wstrb=strb; wvalid=1;
                do @(posedge clk); while (!wready);
                @(negedge clk); wvalid=0;
            end
            cycles=0;
            while (!bvalid && cycles<20) begin @(posedge clk); cycles=cycles+1; end
            if (!bvalid) $fatal(1,"FAIL: BVALID timeout for write addr %h",addr);
            if (bresp!==expected_resp)
                $fatal(1,"FAIL: BRESP for %h got %b expected %b",addr,bresp,expected_resp);
            @(negedge clk); bready=1;
            @(posedge clk);
            @(negedge clk); bready=0;
        end
    endtask

    task axi_read;
        input [31:0] addr;
        input [1:0] expected_resp;
        output [31:0] data;
        begin
            @(negedge clk); araddr=addr; arvalid=1;
            do @(posedge clk); while (!arready);
            @(negedge clk); arvalid=0;
            cycles=0;
            while (!rvalid && cycles<20) begin @(posedge clk); cycles=cycles+1; end
            if (!rvalid) $fatal(1,"FAIL: RVALID timeout for read addr %h",addr);
            read_value=rdata; read_resp=rresp;
            if (rresp!==expected_resp)
                $fatal(1,"FAIL: RRESP for %h got %b expected %b",addr,rresp,expected_resp);
            repeat(2) begin
                @(posedge clk);
                if (!rvalid || rdata!==read_value || rresp!==read_resp)
                    $fatal(1,"FAIL: R channel payload not held stable under backpressure");
            end
            @(negedge clk); rready=1;
            @(posedge clk);
            @(negedge clk); rready=0;
            data=read_value;
        end
    endtask

    initial begin
        clk=0; resetb=0;
        awaddr=0; awvalid=0; wdata=0; wstrb=0; wvalid=0; bready=0;
        araddr=0; arvalid=0; rready=0;
        op_busy=0; op_done=0; op_error=0;
        writeback_start_ready=1; writeback_busy=0; writeback_done=0;
        writeback_error=0; writeback_error_code=0;
        op_start_count=0; wb_start_count=0; cycles=0; read_value=0; read_resp=0;
        repeat(3) @(negedge clk); resetb=1;

        // AW and W arrive independently in both orders; byte strobes are honoured.
        axi_write(32'h08,32'h12345678,4'hF,0,2'b00);
        axi_write(32'h0C,32'hAABBCCDD,4'hF,1,2'b00);
        axi_write(32'h08,32'h000000EE,4'h1,1,2'b00);
        axi_write(32'h10,32'h00000003,4'h1,0,2'b00);
        axi_write(32'h14,32'h00002000,4'hF,0,2'b00);
        axi_read(32'h08,2'b00,read_value);
        if (read_value!==32'h123456EE) $fatal(1,"FAIL: A base/strobe readback %h",read_value);
        axi_read(32'h0C,2'b00,read_value);
        if (read_value!==32'hAABBCCDD) $fatal(1,"FAIL: B base readback %h",read_value);
        axi_read(32'h10,2'b00,read_value);
        if (read_value!==3) $fatal(1,"FAIL: tile-count readback %h",read_value);
        axi_read(32'h14,2'b00,read_value);
        if (read_value!==32'h2000) $fatal(1,"FAIL: writeback base readback %h",read_value);
        axi_read(32'h1C,2'b00,read_value);
        if (read_value!==32'h00010000) $fatal(1,"FAIL: version readback %h",read_value);

        // Starts are write-one pulses and are rejected when the datapath is busy.
        axi_write(32'h00,32'h1,4'h1,0,2'b00);
        repeat(2) @(negedge clk);
        if (op_start_count!=1) $fatal(1,"FAIL: compute start pulse count %0d",op_start_count);
        axi_write(32'h00,32'h2,4'h1,1,2'b00);
        repeat(2) @(negedge clk);
        if (wb_start_count!=1) $fatal(1,"FAIL: writeback start pulse count %0d",wb_start_count);
        axi_write(32'h00,32'h3,4'h1,0,2'b00);
        repeat(2) @(negedge clk);
        if (op_start_count!=1 || wb_start_count!=1)
            $fatal(1,"FAIL: combined start bits should reject both commands");
        axi_read(32'h04,2'b00,read_value);
        if (!read_value[31]) $fatal(1,"FAIL: combined start rejection not recorded");
        axi_write(32'h04,32'h80000000,4'h1,0,2'b00);
        axi_read(32'h04,2'b00,read_value);
        if (!read_value[31]) $fatal(1,"FAIL: WSTRB lane 0 incorrectly cleared STATUS bit 31");
        axi_write(32'h04,32'h80000000,4'h8,1,2'b00);
        axi_read(32'h04,2'b00,read_value);
        if (read_value[31]) $fatal(1,"FAIL: byte lane 3 did not clear command_rejected");

        op_busy=1;
        axi_write(32'h00,32'h1,4'h1,0,2'b00);
        op_busy=0;
        axi_read(32'h04,2'b00,read_value);
        if (!read_value[31]) $fatal(1,"FAIL: busy command rejection not recorded");
        axi_write(32'h04,32'h80000000,4'hF,0,2'b00);
        axi_read(32'h04,2'b00,read_value);
        if (read_value[31]) $fatal(1,"FAIL: W1C did not clear command_rejected");

        // Hardware completion/error events become sticky software-readable status.
        @(negedge clk); op_done=1; writeback_done=1;
        @(negedge clk); op_done=0; writeback_done=0;
        writeback_error=1; writeback_error_code=4'd6;
        @(negedge clk); writeback_error=0;
        axi_read(32'h04,2'b00,read_value);
        if (!read_value[1] || !read_value[9] || !read_value[10])
            $fatal(1,"FAIL: event/status latches missing (%h)",read_value);
        axi_read(32'h18,2'b00,read_value);
        if (read_value!==6) $fatal(1,"FAIL: error code readback %h",read_value);
        axi_write(32'h04,32'h00000606,4'hF,0,2'b00);
        axi_read(32'h04,2'b00,read_value);
        if (read_value[1] || read_value[9] || read_value[10])
            $fatal(1,"FAIL: W1C did not clear completion/error latches");
        axi_read(32'h18,2'b00,read_value);
        if (read_value!==0) $fatal(1,"FAIL: W1C did not clear error code");

        // Invalid and read-only addresses return DECERR.
        axi_write(32'h18,32'h1,4'hF,0,2'b11);
        axi_read(32'h24,2'b11,read_value);
        axi_read(32'h03,2'b11,read_value);
        $display("PASS: AXI-Lite AW/W independence, byte strobes, and register readback");
        $display("PASS: start pulses, busy rejection, sticky status, W1C, and error-code latch");
        $display("PASS: AXI-Lite response backpressure and DECERR handling");
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $fatal(1);
    end
endmodule
`default_nettype wire
