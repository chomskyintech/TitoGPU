`timescale 1ns/1ps
`default_nettype none
module tb_tito_packed_scratchpad;
  localparam N=4, K=4, DATA_W=8, AW=4, KW=2;
  reg clk=0, resetb=0;
  reg wr_en=0, wr_buffer=0, wr_bank=0;
  reg [AW-1:0] wr_addr=0;
  reg [7:0] wr_data=0;
  reg pack_wr_en=0, pack_wr_buffer=0, pack_wr_bank=0;
  reg [AW-1:0] pack_wr_base=0;
  reg [31:0] pack_wr_data=0;
  reg [3:0] pack_wr_mask=0;
  reg rd_en=0, rd_buffer=0;
  reg [N*KW-1:0] a_rd_addr=0, b_rd_addr=0;
  wire [N*DATA_W-1:0] a_rd_data, b_rd_data;
  integer i;
  always #5 clk=~clk;

  tito_systolic_double_buffered_banked_scratchpad #(.N(N),.K(K),.DATA_W(DATA_W)) dut(
    .clk(clk),.resetb(resetb),.wr_en(wr_en),.wr_buffer(wr_buffer),.wr_bank(wr_bank),
    .wr_addr(wr_addr),.wr_data(wr_data),.pack_wr_en(pack_wr_en),
    .pack_wr_buffer(pack_wr_buffer),.pack_wr_bank(pack_wr_bank),
    .pack_wr_base(pack_wr_base),.pack_wr_data(pack_wr_data),.pack_wr_mask(pack_wr_mask),
    .rd_en(rd_en),.rd_buffer(rd_buffer),.a_rd_addr(a_rd_addr),.b_rd_addr(b_rd_addr),
    .a_rd_data(a_rd_data),.b_rd_data(b_rd_data)
  );

  initial begin
    repeat(2) @(negedge clk); resetb=1;
    // Four byte lanes map to consecutive A logical addresses in buffer 1.
    pack_wr_en=1; pack_wr_buffer=1; pack_wr_bank=0; pack_wr_base=0;
    pack_wr_data=32'h44332211; pack_wr_mask=4'b1111;
    @(negedge clk);
    pack_wr_en=0;
    if (dut.a1_mem[0][0] !== 8'h11 || dut.a1_mem[0][1] !== 8'h22 ||
        dut.a1_mem[0][2] !== 8'h33 || dut.a1_mem[0][3] !== 8'h44)
      $fatal(1,"packed A lane ordering or mapping failed");

    // Seed masked-off B locations with known sentinels before the partial write.
    wr_en=1; wr_buffer=0; wr_bank=1; wr_addr=5; wr_data=8'h55;
    @(negedge clk);
    wr_addr=7; wr_data=8'h77;
    @(negedge clk);
    wr_en=0;

    // Partial final word: only lanes 0 and 2 commit; masked lanes must not write.
    pack_wr_en=1; pack_wr_buffer=0; pack_wr_bank=1; pack_wr_base=4;
    pack_wr_data=32'hD4C3B2A1; pack_wr_mask=4'b0101;
    @(negedge clk);
    pack_wr_en=0;
    if (dut.b0_mem[0][1] !== 8'hA1 || dut.b0_mem[2][1] !== 8'hC3)
      $fatal(1,"packed B active lanes failed");
    if (dut.b0_mem[1][1] !== 8'h55 || dut.b0_mem[3][1] !== 8'h77)
      $fatal(1,"masked packed lanes overwrote sentinel data");

    // Packed and byte writes are both supported; byte port remains the reference path.
    wr_en=1; wr_buffer=1; wr_bank=0; wr_addr=5; wr_data=8'h5A;
    @(negedge clk); wr_en=0;
    if (dut.a1_mem[1][1] !== 8'h5A) $fatal(1,"legacy byte write regressed");

    $display("PASS: packed scratchpad writes, lane order, mask and legacy port");
    $finish;
  end
endmodule
`default_nettype wire
