`timescale 1ns / 1ps
//=============================================================================
// exp_pwl_comb —— F 项加分：组合逻辑版 PWL exp(-u)*16
//-----------------------------------------------------------------------------
// 与 exp_pwl.v 功能相同，但无 clk 延迟，可直接替换 attention_ip 中的
// exp_lut 函数调用。
//=============================================================================
module exp_pwl_comb (
    input  wire [7:0]  u,
    output wire [15:0] y
);

    wire [3:0] seg  = u[5:2];   // 16 段，每段 raw 宽 4
    wire [1:0] frac = u[1:0];   // 段内 4 等分

    reg [9:0] f_start [0:15];
    reg [9:0] f_end   [0:15];

    initial begin
        f_start[0]  = 10'd256;  f_end[0]  = 10'd199;
        f_start[1]  = 10'd199;  f_end[1]  = 10'd155;
        f_start[2]  = 10'd155;  f_end[2]  = 10'd121;
        f_start[3]  = 10'd121;  f_end[3]  = 10'd94;
        f_start[4]  = 10'd94;   f_end[4]  = 10'd73;
        f_start[5]  = 10'd73;   f_end[5]  = 10'd57;
        f_start[6]  = 10'd57;   f_end[6]  = 10'd44;
        f_start[7]  = 10'd44;   f_end[7]  = 10'd35;
        f_start[8]  = 10'd35;   f_end[8]  = 10'd27;
        f_start[9]  = 10'd27;   f_end[9]  = 10'd21;
        f_start[10] = 10'd21;   f_end[10] = 10'd16;
        f_start[11] = 10'd16;   f_end[11] = 10'd13;
        f_start[12] = 10'd13;   f_end[12] = 10'd10;
        f_start[13] = 10'd10;   f_end[13] = 10'd8;
        f_start[14] = 10'd8;    f_end[14] = 10'd6;
        f_start[15] = 10'd6;    f_end[15] = 10'd5;
    end

    wire signed [10:0] delta = $signed({1'b0, f_end[seg]}) - $signed({1'b0, f_start[seg]});
    wire signed [12:0] mult  = delta * $signed({10'b0, frac});
    wire signed [15:0] y_signed = $signed({6'b0, f_start[seg]}) + (mult >>> 2);

    assign y = (u >= 8'd64) ? 16'd0 :
               (y_signed < 0) ? 16'd0 : y_signed[15:0];

endmodule
