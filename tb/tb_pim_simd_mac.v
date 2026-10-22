`timescale 1ns/1ps
module tb_pim_simd_mac;
  localparam DATA_W = 8, LANES = 8, ACC_W = 32;
  localparam WORD_W  = DATA_W * LANES;
  localparam TIMEOUT = 100000;
  localparam MODE_RAND = 0, MODE_M128 = 1, MODE_M1 = 2;

  reg clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  reg                      valid = 1'b0, first = 1'b0, last = 1'b0;
  reg  [WORD_W-1:0]        w = 0, x = 0;
  wire                     done;
  wire signed [ACC_W-1:0]  acc;

  pim_simd_mac #(.DATA_W(DATA_W), .LANES(LANES), .ACC_W(ACC_W)) dut (
    .clk_i(clk), .rst_ni(rst_n), .valid_i(valid), .first_i(first), .last_i(last),
    .w_i(w), .x_i(x), .done_o(done), .acc_o(acc)
  );

  integer exp_fifo [0:1023];
  integer wr_ptr = 0, rd_ptr = 0;
  integer errors = 0;

  always @(posedge clk) begin
    if (done) begin
      if (acc !== exp_fifo[rd_ptr]) begin
        errors = errors + 1;
        $display("ERROR: dot %0d, acc = %0d, exp = %0d", rd_ptr, acc, exp_fifo[rd_ptr]);
      end
      rd_ptr = rd_ptr + 1;
    end
  end

  task send_dot(input integer ncols, input integer mode);
    integer c, j, exp_sum;
    reg signed [DATA_W-1:0] tw, tx;
    reg [WORD_W-1:0] wv, xv;
    begin
      exp_sum = 0;
      for (c = 0; c < ncols; c = c + 1) begin
        for (j = 0; j < LANES; j = j + 1) begin
          if (mode == MODE_RAND) begin
            tw = $random; tx = $random;
          end
          else if (mode == MODE_M128) begin
            tw = -128; tx = -128;
          end
          else if (mode == MODE_M1) begin
            tw = -1; tx = -1;
          end

          wv[j*DATA_W +: DATA_W] = tw;
          xv[j*DATA_W +: DATA_W] = tx;
          exp_sum = exp_sum + tw * tx;
        end
        valid <= 1'b1; first <= (c == 0); last <= (c == ncols - 1);
        w <= wv; x <= xv;
        @(posedge clk);
      end
      exp_fifo[wr_ptr] = exp_sum;
      wr_ptr = wr_ptr + 1;
    end
  endtask

  task idle(input integer n);
    begin
      valid <= 1'b0; first <= 1'b0; last <= 1'b0;
      repeat (n) @(posedge clk);
    end
  endtask

  integer n;
  initial begin
    $dumpfile("tb_pim_simd_mac.vcd");
    $dumpvars(0, tb_pim_simd_mac);
    repeat (2) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);

    send_dot(1, MODE_RAND); idle(5);

    send_dot(32, MODE_M128); idle(5);
    send_dot(32, MODE_M1);   idle(5);

    for (n = 0; n < 50; n = n + 1) begin
      send_dot(1 + {$random} % 32, MODE_RAND);
      idle(1 + {$random} % 3);
    end

    for (n = 0; n < 50; n = n + 1)
      send_dot(1 + {$random} % 32, MODE_RAND);
    idle(10);

    if (rd_ptr != wr_ptr) begin
      errors = errors + 1;
      $display("COUNT MISMATCH sent=%0d done=%0d", wr_ptr, rd_ptr);
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
