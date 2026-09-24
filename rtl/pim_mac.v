`timescale 1ns/1ps

module pim_mac #(
    parameter DATA_W = 8,
    parameter ACC_W = 32
) (

    input wire clk_i,
    input wire rst_ni,
    input wire en_i,
    input wire first_i,

    input wire signed [DATA_W-1:0] a_i,
    input wire signed [DATA_W-1:0] b_i,
    output reg signed [ACC_W-1:0] acc_o
);
    wire signed [2*DATA_W-1:0] prod = a_i * b_i;

    wire signed [ACC_W-1:0] prod_ext = {{(ACC_W-2*DATA_W){prod[2*DATA_W-1]}}, prod};

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) acc_o <= {ACC_W{1'b0}};
        else if (en_i && first_i) acc_o <= prod_ext;
        else if (en_i) acc_o <= acc_o + prod_ext;
    end
endmodule
