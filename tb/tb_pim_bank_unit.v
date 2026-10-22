`timescale 1ns/1ps
module tb_pim_bank_unit;
  localparam DATA_W = 8, LANES = 8, ACC_W = 32;
  localparam ROW_AW = 6, COL_AW = 5;
  localparam WORD_W   = DATA_W * LANES;
  localparam NUM_ROWS = 1 << ROW_AW;
  localparam NUM_COLS = 1 << COL_AW;
  localparam DEPTH    = NUM_ROWS * NUM_COLS;
  localparam MAC_LAT  = 4;
  localparam TIMEOUT  = 100000;
  localparam M_ROWS   = 4;
  localparam W_FILE   = "w_bank0.hex";
  localparam X_FILE   = "x_gb.hex";
  localparam Y_FILE   = "y_expected.hex";

  reg clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  reg               arr_en = 1'b0, arr_we = 1'b0;
  reg  [ROW_AW-1:0] row = 0;
  reg  [COL_AW-1:0] col = 0;
  reg  [WORD_W-1:0] wdata = 0;
  reg               mac_issue = 1'b0, mac_first = 1'b0, mac_last = 1'b0;
  reg               gb_we = 1'b0, gb_re = 1'b0;
  reg  [COL_AW-1:0] gb_waddr = 0, gb_raddr = 0;
  reg  [WORD_W-1:0] gb_wdata = 0;
  reg               out_re = 1'b0;
  reg  [ROW_AW-1:0] out_raddr = 0;

  wire [WORD_W-1:0] gb_rdata, rdata;
  wire              acc_valid;
  wire [ACC_W-1:0]  out_rdata;

  pim_global_buffer #(.AW(COL_AW), .WORD_W(WORD_W)) gb (
    .clk_i(clk), .we_i(gb_we), .waddr_i(gb_waddr), .wdata_i(gb_wdata),
    .re_i(gb_re), .raddr_i(gb_raddr), .rdata_o(gb_rdata)
  );

  pim_bank_unit #(.DATA_W(DATA_W), .LANES(LANES), .ACC_W(ACC_W),
                  .ROW_AW(ROW_AW), .COL_AW(COL_AW), .INIT_FILE(W_FILE)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .arr_en_i(arr_en), .arr_we_i(arr_we), .row_i(row), .col_i(col), .wdata_i(wdata),
    .mac_issue_i(mac_issue), .mac_first_i(mac_first), .mac_last_i(mac_last),
    .gb_rdata_i(gb_rdata),
    .rdata_o(rdata), .acc_valid_o(acc_valid),
    .out_re_i(out_re), .out_raddr_i(out_raddr), .out_rdata_o(out_rdata)
  );

  reg [WORD_W-1:0] wmem    [0:DEPTH-1];
  reg [WORD_W-1:0] xmem    [0:NUM_COLS-1];
  reg [ACC_W-1:0]  yexp    [0:M_ROWS-1];
  reg [ACC_W-1:0]  exp_out [0:NUM_ROWS-1];
  reg              exp_vld [0:NUM_ROWS-1];

  integer errors = 0;

  function integer dot(input integer r, input integer ncols);
    integer c, j;
    reg [WORD_W-1:0]        ww, xw;
    reg signed [DATA_W-1:0] w8, x8;
    begin
      dot = 0;
      for (c = 0; c < ncols; c = c + 1) begin
        ww = wmem[r * NUM_COLS + c];
        xw = xmem[c];
        for (j = 0; j < LANES; j = j + 1) begin
          w8 = ww[j*DATA_W +: DATA_W];
          x8 = xw[j*DATA_W +: DATA_W];
          dot = dot + w8 * x8;
        end
      end
    end
  endfunction

  integer since_last = 0;
  integer n_acc      = 0;
  always @(posedge clk) begin
    if (acc_valid) begin
      n_acc = n_acc + 1;
      if (since_last != MAC_LAT) begin
        errors = errors + 1;
        $display("[%0t] acc_valid latency %0d (exp %0d)", $time, since_last, MAC_LAT);
      end
    end
    if (mac_issue && mac_last) since_last = 1;
    else                       since_last = since_last + 1;
  end

  task gb_load;
    integer c;
    begin
      for (c = 0; c < NUM_COLS; c = c + 1) begin
        gb_we <= 1'b1; gb_waddr <= c; gb_wdata <= xmem[c];
        @(posedge clk);
      end
      gb_we <= 1'b0;
    end
  endtask

  task write_word(input integer r, input integer c, input [WORD_W-1:0] d);
    begin
      arr_en <= 1'b1; arr_we <= 1'b1; row <= r; col <= c; wdata <= d;
      @(posedge clk);
      arr_en <= 1'b0; arr_we <= 1'b0;
    end
  endtask

  task read_check(input integer r, input integer c, input [WORD_W-1:0] exp);
    begin
      arr_en <= 1'b1; arr_we <= 1'b0; row <= r; col <= c;
      @(posedge clk);
      arr_en <= 1'b0;
      @(posedge clk);
      if (rdata !== exp) begin
        errors = errors + 1;
        $display("[%0t] rdata row %0d col %0d got %h exp %h", $time, r, c, rdata, exp);
      end
    end
  endtask

  task mac_row(input integer r, input integer ncols, input integer gap, input [ACC_W-1:0] expected);
    integer c;
    begin
      for (c = 0; c < ncols; c = c + 1) begin
        arr_en    <= 1'b1; arr_we <= 1'b0; row <= r; col <= c;
        gb_re     <= 1'b1; gb_raddr <= c;
        mac_issue <= 1'b1; mac_first <= (c == 0); mac_last <= (c == ncols - 1);
        @(posedge clk);
        if (gap > 0 && c != ncols - 1) begin
          arr_en <= 1'b0; gb_re <= 1'b0;
          mac_issue <= 1'b0; mac_first <= 1'b0; mac_last <= 1'b0;
          repeat (gap) @(posedge clk);
        end
      end
      arr_en <= 1'b0; gb_re <= 1'b0;
      mac_issue <= 1'b0; mac_first <= 1'b0; mac_last <= 1'b0;
      @(posedge clk);
      while (acc_valid !== 1'b1) @(posedge clk);
      @(posedge clk);
      exp_out[r] = expected;
      exp_vld[r] = 1'b1;
    end
  endtask

  task out_check(input integer r);
    begin
      out_re <= 1'b1; out_raddr <= r;
      @(posedge clk);
      out_re <= 1'b0;
      @(posedge clk);
      if (out_rdata !== exp_out[r]) begin
        errors = errors + 1;
        $display("out_mem[%0d] got %0d exp %0d", r, $signed(out_rdata), $signed(exp_out[r]));
      end
    end
  endtask

  integer r, i, n_mac, missing;
  initial begin
    $dumpfile("tb_pim_bank_unit.vcd");
    $dumpvars(0, tb_pim_bank_unit);

    $readmemh(W_FILE, wmem);
    $readmemh(X_FILE, xmem);
    $readmemh(Y_FILE, yexp);
    missing = 0;
    for (i = 0; i < DEPTH; i = i + 1)    if (^wmem[i] === 1'bx) missing = missing + 1;
    for (i = 0; i < NUM_COLS; i = i + 1) if (^xmem[i] === 1'bx) missing = missing + 1;
    for (i = 0; i < M_ROWS; i = i + 1)   if (^yexp[i] === 1'bx) missing = missing + 1;
    if (missing != 0) begin
      errors = errors + 1;
      $display("hex files: %0d words missing (run model/golden_gemv.py first)", missing);
    end

    for (r = 0; r < M_ROWS; r = r + 1)
      if (dot(r, NUM_COLS) != $signed(yexp[r])) begin
        errors = errors + 1;
        $display("model mismatch row %0d: tb %0d python %0d", r, dot(r, NUM_COLS), $signed(yexp[r]));
      end

    for (r = 0; r < NUM_ROWS; r = r + 1) exp_vld[r] = 1'b0;
    n_mac = 0;

    repeat (2) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);

    gb_load;

    read_check(0, 0, wmem[0]);
    read_check(3, NUM_COLS - 1, wmem[3*NUM_COLS + NUM_COLS - 1]);
    write_word(10, 5, 64'h0123_4567_89ab_cdef);
    read_check(10, 5, 64'h0123_4567_89ab_cdef);

    mac_row(0, NUM_COLS, 0, yexp[0]);          n_mac = n_mac + 1;
    mac_row(1, NUM_COLS, 0, yexp[1]);          n_mac = n_mac + 1;
    mac_row(2, 1, 0, dot(2, 1));               n_mac = n_mac + 1;
    mac_row(3, NUM_COLS, 2, yexp[3]);          n_mac = n_mac + 1;
    mac_row(2, NUM_COLS, 0, yexp[2]);          n_mac = n_mac + 1;

    for (r = 0; r < NUM_ROWS; r = r + 1)
      if (exp_vld[r]) out_check(r);

    if (n_acc != n_mac) begin
      errors = errors + 1;
      $display("COUNT MISMATCH sent=%0d acc_valid=%0d", n_mac, n_acc);
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
