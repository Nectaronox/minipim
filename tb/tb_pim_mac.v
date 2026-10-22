`timescale 1ns/1ps
module tb_pim_mac;
  localparam DATA_W = 8, ACC_W = 32;
  localparam TIMEOUT = 100000;

  reg clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  reg                      en = 1'b0, first = 1'b0;
  reg  signed [DATA_W-1:0] a = 0, b = 0;
  wire signed [ACC_W-1:0]  acc;

  pim_mac #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
    .clk_i(clk), .rst_ni(rst_n), .en_i(en), .first_i(first),
    .a_i(a), .b_i(b), .acc_o(acc)
  );

  reg signed [DATA_W-1:0] ta, tb;
  integer i, n, exp_acc, errors;

  initial begin
    $dumpfile("tb_pim_mac.vcd");
    $dumpvars(0, tb_pim_mac);
    errors = 0;
    repeat (2) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);

    for (n = 0; n < 20; n = n + 1) begin
      for (i = 0; i < 32; i = i + 1) begin
        ta = $random; tb = $random;
        if (n == 0) begin ta = -128; tb = -128; end
        a <= ta; b <= tb; en <= 1'b1; first <= (i == 0);
        exp_acc = (i == 0) ? ta * tb : exp_acc + ta * tb;
        @(posedge clk);
      end
      en <= 1'b0; first <= 1'b0;
      @(posedge clk);
      if (acc !== exp_acc) begin
        errors = errors + 1;
        $display("[%0t] MISMATCH n=%0d acc=%0d exp=%0d", $time, n, acc, exp_acc);
      end
    end

    for (n = 0; n < 20; n = n + 2) begin
      for (i = 0; i < 32; i = i + 3) begin
        ta = $random; tb = $random;
        if (n == 0) begin ta = -128; tb = -128; end
        a <= ta; b <= tb; en <= 1'b1; first <= (i == 0);
        exp_acc = (i == 0) ? ta * tb : exp_acc + ta * tb;
        @(posedge clk);
      end
      en <= 1'b0; first <= 1'b0;
      @(posedge clk);
      if (acc !== exp_acc) begin
        errors = errors + 1;
        $display("[%0t] MISMATCH n=%0d acc=%0d exp=%0d", $time, n, acc, exp_acc);
      end
    end
    if (errors == 0) $display("PASS"); else $display("FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    repeat (TIMEOUT) @(posedge clk);
    $display("TIMEOUT");
    $display("FAIL (%0d errors)", errors + 1);
    $finish;
  end
endmodule
