`timescale 1ns/1ps

module pim_global_buffer #(
    parameter AW     = 5,
    parameter WORD_W = 64
) (
    input  wire              clk_i,
    input  wire              we_i,
    input  wire [AW-1:0]     waddr_i,
    input  wire [WORD_W-1:0] wdata_i,
    input  wire              re_i,
    input  wire [AW-1:0]     raddr_i,
    output reg  [WORD_W-1:0] rdata_o
);
    localparam DEPTH = 1 << AW;
    reg [WORD_W-1:0] mem_q [0:DEPTH-1];

    always @(posedge clk_i) begin
        if (we_i) mem_q[waddr_i] <= wdata_i;
        if (re_i) rdata_o        <= mem_q[raddr_i];
    end
endmodule
