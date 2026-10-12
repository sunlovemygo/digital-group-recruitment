`timescale 1ns / 1ps
//=============================================================================
// exp_pwl —— F 项加分：分段线性近似实现 exp(-u) * 16
//-----------------------------------------------------------------------------
// 输入 u：4.4 定点无符号（高 4 位整数，低 4 位小数），范围 [0, 4]。
// 输出 y：4.4 定点无符号，约等于 exp(-u) * 16。
//
// 分段策略：把 [0,4] 分成 16 段，每段实际宽 0.25（raw 宽 4）。
// 段索引 seg = u[7:2]（0~15）
// 段内偏移 frac = u[1:0]（0~3，代表 0/4 ~ 3/4）
// 每段预存：f_start[seg]、f_end[seg]，均为 4.4 定点原始值
// 计算：y_raw = f_start + ((f_end - f_start) * frac) >> 2
//
// 注意：u >= 4.0（即 u_raw >= 64）时输出 0。
//=============================================================================
module exp_pwl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [7:0]  u,
    output reg  [15:0] y,
    output reg         valid
);

    wire [3:0] seg  = u[5:2];   // 16 段，每段 raw 宽 4
    wire [1:0] frac = u[1:0];   // 段内 4 等分

    // f_start/f_end：4.4 定点原始值（实际值 * 16）
    // 由 exp(-seg*0.25)*256 和 exp(-(seg+1)*0.25)*256 四舍五入得到
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

    // 组合逻辑：端点线性插值
    wire signed [10:0] delta = $signed({1'b0, f_end[seg]}) - $signed({1'b0, f_start[seg]});
    wire signed [12:0] mult  = delta * $signed({10'b0, frac});
    wire signed [15:0] y_comb_signed = $signed({6'b0, f_start[seg]}) + (mult >>> 2);
    wire        [15:0] y_comb = (y_comb_signed < 0) ? 16'd0 : y_comb_signed[15:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            y     <= 16'd0;
            valid <= 1'b0;
        end else begin
            valid <= en;
            if (u >= 8'd64)
                y <= 16'd0;
            else
                y <= y_comb;
        end
    end

endmodule
