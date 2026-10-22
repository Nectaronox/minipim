`timescale 1ns/1ps

module tb_pim_mac_simple;
    localparam TIMEOUT = 1000;

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg en = 1'b0, first = 1'b0;

    reg signed [7:0] a = 0, b = 0;
    wire signed [31:0] acc;

    pim_mac #(.DATA_W(8), .ACC_W(32)) dut (
        .clk_i(clk), .rst_ni(rst_n), .en_i(en), .first_i(first),
        .a_i(a), .b_i(b), .acc_o(acc)
    );

    initial begin
        $dumpfile("tb_pim_mac_simple.vcd");
        $dumpvars(0, tb_pim_mac_simple);

        repeat (2) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        a <= 3; b <= 4; first <= 1'b1; en <= 1'b1; @(posedge clk);
        a <= 5; b <= 6; first <= 1'b0; @(posedge clk);
        a <= 7; b <= 9; @(posedge clk);
        en <= 1'b0; @(posedge clk);

        if (acc !== 105) begin
            $display("acc = %0d (exp 105)", acc);
            $display("FAIL (1 errors)");
        end else $display("PASS");
        $finish;
    end

    initial begin
        repeat (TIMEOUT) @(posedge clk);
        $display("TIMEOUT");
        $display("FAIL (1 errors)");
        $finish;
    end
endmodule
