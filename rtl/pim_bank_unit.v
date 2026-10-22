`timescale 1ns/1ps

module pim_bank_unit #(
    parameter DATA_W    = 8,
    parameter LANES     = 8,
    parameter ACC_W     = 32,
    parameter ROW_AW    = 6,
    parameter COL_AW    = 5,
    parameter INIT_FILE = ""
) (
    input  wire                     clk_i,
    input  wire                     rst_ni,
    input  wire                     arr_en_i,
    input  wire                     arr_we_i,
    input  wire [ROW_AW-1:0]        row_i,
    input  wire [COL_AW-1:0]        col_i,
    input  wire [DATA_W*LANES-1:0]  wdata_i,
    input  wire                     mac_issue_i,
    input  wire                     mac_first_i,
    input  wire                     mac_last_i,
    input  wire [DATA_W*LANES-1:0]  gb_rdata_i,
    output wire [DATA_W*LANES-1:0]  rdata_o,
    output wire                     acc_valid_o,
    input  wire                     out_re_i,
    input  wire [ROW_AW-1:0]        out_raddr_i,
    output reg  [ACC_W-1:0]         out_rdata_o
);
    localparam WORD_W   = DATA_W * LANES;
    localparam NUM_ROWS = 1 << ROW_AW;

    wire [WORD_W-1:0] arr_rdata;

    reg issue_q, first_q, last_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            issue_q <= 1'b0;
            first_q <= 1'b0;
            last_q  <= 1'b0;
        end else begin
            issue_q <= mac_issue_i;
            first_q <= mac_first_i;
            last_q  <= mac_last_i;
        end
    end

    pim_bank_array #(
        .ROW_AW    (ROW_AW),
        .COL_AW    (COL_AW),
        .WORD_W    (WORD_W),
        .INIT_FILE (INIT_FILE)
    ) u_array (
        .clk_i   (clk_i),
        .en_i    (arr_en_i),
        .we_i    (arr_we_i),
        .row_i   (row_i),
        .col_i   (col_i),
        .wdata_i (wdata_i),
        .rdata_o (arr_rdata)
    );

    wire signed [ACC_W-1:0] acc;

    pim_simd_mac #(
        .DATA_W (DATA_W),
        .LANES  (LANES),
        .ACC_W  (ACC_W)
    ) u_mac (
        .clk_i   (clk_i),
        .rst_ni  (rst_ni),
        .valid_i (issue_q),
        .first_i (first_q),
        .last_i  (last_q),
        .w_i     (arr_rdata),
        .x_i     (gb_rdata_i),
        .done_o  (acc_valid_o),
        .acc_o   (acc)
    );

    assign rdata_o = arr_rdata;

    reg [ACC_W-1:0] out_mem [0:NUM_ROWS-1];

    always @(posedge clk_i) begin
        if (acc_valid_o) out_mem[row_i] <= acc;
        if (out_re_i)    out_rdata_o    <= out_mem[out_raddr_i];
    end
endmodule
