`timescale 1ns/1ps

module pim_simd_mac #(
    parameter DATA_W = 8,
    parameter LANES  = 8,
    parameter ACC_W  = 32
) (
    input  wire                     clk_i,
    input  wire                     rst_ni,
    input  wire                     valid_i,
    input  wire                     first_i,
    input  wire                     last_i,
    input  wire [DATA_W*LANES-1:0]  w_i,
    input  wire [DATA_W*LANES-1:0]  x_i,
    output reg                      done_o,
    output reg  signed [ACC_W-1:0]  acc_o
);
    reg signed [2*DATA_W-1:0] prod_q [0:LANES-1];
    wire [LANES*ACC_W-1:0] prod_ext;
    reg va_q, fa_q, la_q;

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : g_lane
            wire signed [DATA_W-1:0] w_lane = $signed(w_i[i*DATA_W +: DATA_W]);
            wire signed [DATA_W-1:0] x_lane = $signed(x_i[i*DATA_W +: DATA_W]);

            always @(posedge clk_i) begin
                if (valid_i) prod_q[i] <= w_lane * x_lane;
            end

            assign prod_ext[i*ACC_W +: ACC_W] = {{(ACC_W-2*DATA_W){prod_q[i][2*DATA_W-1]}}, prod_q[i]};
        end
    endgenerate

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            va_q <= 1'b0;
            fa_q <= 1'b0;
            la_q <= 1'b0;
        end else begin
            va_q <= valid_i;
            fa_q <= first_i;
            la_q <= last_i;
        end
    end

    reg signed [ACC_W-1:0] sum_c, sum_q;
    reg vb_q, fb_q, lb_q;

    integer k;
    always @(*) begin
        sum_c = {ACC_W{1'b0}};
        for (k = 0; k < LANES; k = k + 1)
            sum_c = sum_c + $signed(prod_ext[k*ACC_W +: ACC_W]);
    end

    always @(posedge clk_i) begin
        if (va_q) sum_q <= sum_c;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            vb_q <= 1'b0;
            fb_q <= 1'b0;
            lb_q <= 1'b0;
        end else begin
            vb_q <= va_q;
            fb_q <= fa_q;
            lb_q <= la_q;
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            acc_o  <= {ACC_W{1'b0}};
            done_o <= 1'b0;
        end else begin
            done_o <= vb_q & lb_q;
            if (vb_q) acc_o <= fb_q ? sum_q : acc_o + sum_q;
        end
    end
endmodule
