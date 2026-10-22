`timescale 1ns/1ps
module tb_pim_bank_array;
  localparam ROW_AW    = 6, COL_AW = 5, WORD_W = 64;
  localparam NUM_ROWS  = 1 << ROW_AW;
  localparam NUM_COLS  = 1 << COL_AW;
  localparam DEPTH     = NUM_ROWS * NUM_COLS;
  localparam TIMEOUT   = 100000;
  localparam INIT_FILE = "w_bank0.hex";

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg                en = 1'b0, we = 1'b0;
  reg  [ROW_AW-1:0]  row = 0;
  reg  [COL_AW-1:0]  col = 0;
  reg  [WORD_W-1:0]  wdata = 0;
  wire [WORD_W-1:0]  rdata;

  pim_bank_array #(.ROW_AW(ROW_AW), .COL_AW(COL_AW), .WORD_W(WORD_W)) dut (
    .clk_i(clk), .en_i(en), .we_i(we), .row_i(row), .col_i(col),
    .wdata_i(wdata), .rdata_o(rdata)
  );

  reg                en_init = 1'b0;
  wire [WORD_W-1:0]  rdata_init;

  pim_bank_array #(.ROW_AW(ROW_AW), .COL_AW(COL_AW), .WORD_W(WORD_W),
                   .INIT_FILE(INIT_FILE)) dut_init (
    .clk_i(clk), .en_i(en_init), .we_i(1'b0), .row_i(row), .col_i(col),
    .wdata_i({WORD_W{1'b0}}), .rdata_o(rdata_init)
  );

  reg  [WORD_W-1:0] model   [0:DEPTH-1];
  reg  [WORD_W-1:0] ref_mem [0:DEPTH-1];
  wire [31:0]       idx = row * NUM_COLS + col;

  integer errors = 0;

  reg              seen_q = 1'b0, seen_init_q = 1'b0;
  reg [WORD_W-1:0] exp_q, exp_init_q;

  always @(posedge clk) begin
    if (seen_q && rdata !== exp_q) begin
      errors = errors + 1;
      if (errors <= 10) $display("[%0t] DUT1 rdata got %h exp %h", $time, rdata, exp_q);
    end
    if (seen_init_q && rdata_init !== exp_init_q) begin
      errors = errors + 1;
      if (errors <= 10) $display("[%0t] DUT2 rdata got %h exp %h", $time, rdata_init, exp_init_q);
    end
    if (en) begin
      if (we) model[idx] <= wdata;
      else begin
        exp_q  <= model[idx];
        seen_q <= 1'b1;
      end
    end
    if (en_init) begin
      exp_init_q  <= ref_mem[idx];
      seen_init_q <= 1'b1;
    end
  end

  task write_word(input [ROW_AW-1:0] r, input [COL_AW-1:0] c, input [WORD_W-1:0] d);
    begin
      en <= 1'b1; we <= 1'b1; row <= r; col <= c; wdata <= d;
      @(posedge clk);
    end
  endtask

  task read_word(input [ROW_AW-1:0] r, input [COL_AW-1:0] c);
    begin
      en <= 1'b1; we <= 1'b0; row <= r; col <= c;
      @(posedge clk);
    end
  endtask

  task read_init(input [ROW_AW-1:0] r, input [COL_AW-1:0] c);
    begin
      en_init <= 1'b1; row <= r; col <= c;
      @(posedge clk);
    end
  endtask

  task idle(input integer n);
    begin
      en <= 1'b0; we <= 1'b0; en_init <= 1'b0;
      repeat (n) @(posedge clk);
    end
  endtask

  function [WORD_W-1:0] pattern(input [ROW_AW-1:0] r, input [COL_AW-1:0] c, input inv);
    reg [WORD_W-1:0] p;
    begin
      p = {r, c, {(WORD_W - 2*(ROW_AW+COL_AW)){1'b0}}, ~r, ~c};
      pattern = inv ? ~p : p;
    end
  endfunction

  integer r, c, pass, i, missing;
  initial begin
    $dumpfile("tb_pim_bank_array.vcd");
    $dumpvars(0, tb_pim_bank_array);

    $readmemh(INIT_FILE, ref_mem);
    missing = 0;
    for (i = 0; i < DEPTH; i = i + 1)
      if (^ref_mem[i] === 1'bx) missing = missing + 1;
    if (missing != 0) begin
      errors = errors + 1;
      $display("%s: %0d words missing (run model/golden_gemv.py first)", INIT_FILE, missing);
    end

    repeat (2) @(posedge clk);

    write_word(2, 3, 64'h0123_4567_89ab_cdef);
    write_word(2, 4, 64'hfedc_ba98_7654_3210);
    read_word(2, 3);
    read_word(2, 4);
    idle(3);
    write_word(2, 4, 64'h0);
    idle(2);
    read_word(2, 4);
    idle(2);

    for (pass = 0; pass < 2; pass = pass + 1) begin
      for (r = 0; r < NUM_ROWS; r = r + 1)
        for (c = 0; c < NUM_COLS; c = c + 1)
          write_word(r, c, pattern(r, c, pass));
      for (r = 0; r < NUM_ROWS; r = r + 1)
        for (c = 0; c < NUM_COLS; c = c + 1)
          read_word(r, c);
    end
    idle(2);

    for (r = 0; r < NUM_ROWS; r = r + 1)
      for (c = 0; c < NUM_COLS; c = c + 1)
        read_init(r, c);
    idle(2);

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
