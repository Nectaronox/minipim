`timescale 1ns/1ps

module pim_bank_array #(
    parameter ROW_AW    = 6,
    parameter COL_AW    = 5,
    parameter WORD_W    = 64,
    parameter INIT_FILE = ""
) (
    input  wire              clk_i,
    input  wire              en_i,
    input  wire              we_i,
    input  wire [ROW_AW-1:0] row_i,
    input  wire [COL_AW-1:0] col_i,
    input  wire [WORD_W-1:0] wdata_i,
    output reg  [WORD_W-1:0] rdata_o
);
    localparam DEPTH = 1 << (ROW_AW + COL_AW);
    reg [WORD_W-1:0] mem [0:DEPTH-1];
    wire [ROW_AW+COL_AW-1:0] addr = {row_i, col_i};

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk_i) begin
        if (en_i) begin
            if (we_i) mem[addr] <= wdata_i;
            else      rdata_o   <= mem[addr];
        end
    end
endmodule
