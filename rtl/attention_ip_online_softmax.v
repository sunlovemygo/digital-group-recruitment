`timescale 1ns / 1ps
//=============================================================================
// attention_ip_online_softmax —— 基于 Online Softmax 的 Attention 实现
//-----------------------------------------------------------------------------
// 参考文献：
//   [1] Milakov & Gimelshein, "Online normalizer calculation for softmax",
//       NVIDIA, 2018.
//   [2] Youming Zhao, "From online safe softmax to FlashAttention", 2023.
//
// 核心思想：把“先求 xmax 再求 weight”的两遍扫描合并成一遍。
//   维护运行最大值 xmax、运行分母 L、运行分子 ACC[d]。
//   每读入一个 score：
//     - 若 score > xmax：说明最大值更新，需把旧 L/ACC 按 exp(old_max - new_max)
//       缩放，再加入当前 token（其相对新 max 的 weight = 1.0，即 16）。
//     - 否则：直接按 exp(xmax - score) 查表得到 weight，累加到 L/ACC。
//    rescale 因子同样是 4.4 定点：factor = round(exp(-delta) * 16) = exp_lut(delta)。
//
// 相比原 10 状态 FSM，省掉 S_MAX 和 S_EXP/S_UPDATE 的分隔，
// 数据流更符合 FlashAttention 中“online normalizer”思想。
//=============================================================================
module attention_ip_online_softmax (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire signed [7:0]  q_in,
    input  wire signed [7:0]  k_in,
    input  wire signed [7:0]  v_in,
    input  wire               q_valid,
    input  wire               kv_valid,
    output wire               data_ready,
    output reg  signed [7:0]  out_data,
    output reg                out_valid,
    output reg                done
);

    localparam [3:0]
        S_IDLE      = 4'd0,
        S_LOAD_Q    = 4'd1,
        S_LOAD_KV   = 4'd2,
        S_DOT       = 4'd3,
        S_ONLINE    = 4'd4,   // 合并 MAX + EXP + UPDATE
        S_NEXT      = 4'd5,
        S_NORM      = 4'd6,
        S_OUTPUT    = 4'd7;

    reg [3:0]  state;
    reg [1:0]  q_cnt;
    reg [2:0]  tok_cnt;
    reg [1:0]  dim_cnt;

    reg signed [7:0]  q_reg [0:3];
    reg signed [7:0]  k_buf [0:31];
    reg signed [7:0]  v_buf [0:31];
    reg signed [17:0] score_acc;
    reg signed [17:0] score_buf [0:7];
    reg        [15:0] L;
    reg signed [19:0] ACC [0:3];
    reg signed [17:0] xmax;
    reg signed [7:0]  O_buf [0:3];

    // 4.4 定点 exp(-u)*16 的 LUT，u 为整数差
    function [15:0] exp_lut;
        input [3:0] u;
        begin
            case (u)
                4'd0:    exp_lut = 16'd16;
                4'd1:    exp_lut = 16'd6;
                4'd2:    exp_lut = 16'd2;
                4'd3:    exp_lut = 16'd1;
                default: exp_lut = 16'd0;
            endcase
        end
    endfunction

    assign data_ready = (state == S_IDLE) || (state == S_LOAD_Q)
                      || (state == S_LOAD_KV);

    integer di;
    reg signed [17:0] new_score;
    reg signed [17:0] delta;
    reg        [15:0] factor;
    reg        [15:0] w;
    reg signed [19:0] scaled_acc [0:3];   // rescale 后的旧 ACC，用于新 max 更新

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            q_cnt     <= 2'd0;
            tok_cnt   <= 3'd0;
            dim_cnt   <= 2'd0;
            out_valid <= 1'b0;
            done      <= 1'b0;
            out_data  <= 8'sd0;
            L         <= 16'd0;
            score_acc <= 18'sd0;
            xmax      <= -18'sd131072;  // 最小值，保证第一个 score 能成为 max
            ACC[0]    <= 20'sd0; ACC[1] <= 20'sd0; ACC[2] <= 20'sd0; ACC[3] <= 20'sd0;
        end else begin
            done      <= 1'b0;
            out_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state   <= S_LOAD_Q;
                        q_cnt   <= 2'd0;
                        tok_cnt <= 3'd0;
                        dim_cnt <= 2'd0;
                        L       <= 16'd0;
                        score_acc <= 18'sd0;
                        xmax    <= -18'sd131072;
                        ACC[0]  <= 20'sd0; ACC[1] <= 20'sd0; ACC[2] <= 20'sd0; ACC[3] <= 20'sd0;
                    end
                end

                S_LOAD_Q: begin
                    if (q_valid) begin
                        q_reg[q_cnt] <= q_in;
                        if (q_cnt == 2'd3) begin
                            q_cnt <= 2'd0;
                            state <= S_LOAD_KV;
                        end else begin
                            q_cnt <= q_cnt + 2'd1;
                        end
                    end
                end

                S_LOAD_KV: begin
                    if (kv_valid) begin
                        k_buf[{tok_cnt, dim_cnt}] <= k_in;
                        v_buf[{tok_cnt, dim_cnt}] <= v_in;
                        if (dim_cnt == 2'd3) begin
                            dim_cnt <= 2'd0;
                            if (tok_cnt == 3'd7) begin
                                tok_cnt   <= 3'd0;
                                score_acc <= 18'sd0;
                                state     <= S_DOT;
                            end else begin
                                tok_cnt <= tok_cnt + 3'd1;
                            end
                        end else begin
                            dim_cnt <= dim_cnt + 2'd1;
                        end
                    end
                end

                S_DOT: begin
                    if (dim_cnt == 2'd0)
                        score_acc <= $signed(q_reg[0]) * $signed(k_buf[{tok_cnt, 2'd0}]);
                    else
                        score_acc <= score_acc + $signed(q_reg[dim_cnt]) * $signed(k_buf[{tok_cnt, dim_cnt}]);
                    if (dim_cnt == 2'd3) begin
                        score_buf[tok_cnt] <= score_acc + $signed(q_reg[dim_cnt]) * $signed(k_buf[{tok_cnt, dim_cnt}]);
                        dim_cnt <= 2'd0;
                        if (tok_cnt == 3'd7) begin
                            tok_cnt <= 3'd0;
                            state   <= S_ONLINE;
                        end else begin
                            tok_cnt <= tok_cnt + 3'd1;
                            state   <= S_DOT;
                        end
                    end else begin
                        dim_cnt <= dim_cnt + 2'd1;
                    end
                end

                // -------------- Online Softmax：一遍完成 max + exp + sum --------------
                S_ONLINE: begin
                    new_score = score_buf[tok_cnt];
                    if (new_score > xmax) begin
                        delta  = new_score - xmax;           // delta >= 0
                        if (delta >= 18'sd4) factor = 16'd0;
                        else factor = exp_lut(delta[3:0]); // exp(-delta) in 4.4
                        // 先阻塞算出 rescale 后的旧 ACC，避免用上一拍的 factor
                        for (di = 0; di < 4; di = di + 1)
                            scaled_acc[di] = ($signed(ACC[di]) * $signed({1'b0, factor})) >>> 4;
                        // 旧统计量 rescale 到新 max 下，再加入当前 token（weight=1.0 -> 16）
                        L <= ((L * factor) >> 4) + 16'd16;
                        for (di = 0; di < 4; di = di + 1)
                            ACC[di] <= scaled_acc[di] + ($signed(16'sd16) * $signed(v_buf[{tok_cnt, di[1:0]}]));
                        xmax <= new_score;
                    end else begin
                        delta = xmax - new_score;
                        if (delta >= 18'sd4) w = 16'd0;
                        else w = exp_lut(delta[3:0]);
                        L <= L + w;
                        for (di = 0; di < 4; di = di + 1)
                            ACC[di] <= ACC[di] + $signed(w) * $signed(v_buf[{tok_cnt, di[1:0]}]);
                    end
                    state <= S_NEXT;
                end

                S_NEXT: begin
                    if (tok_cnt == 3'd7) state <= S_NORM;
                    else begin
                        tok_cnt <= tok_cnt + 3'd1;
                        state   <= S_ONLINE;
                    end
                end

                S_NORM: begin
                    for (di = 0; di < 4; di = di + 1) begin
                        if (ACC[di] >= 0)
                            O_buf[di] <= (ACC[di] + $signed(L >> 1)) / $signed(L);
                        else
                            O_buf[di] <= (ACC[di] - $signed(L >> 1)) / $signed(L);
                    end
                    q_cnt <= 2'd0;
                    state <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    out_valid <= 1'b1;
                    out_data  <= O_buf[q_cnt];
                    if (q_cnt == 2'd3) begin
                        q_cnt <= 2'd0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        q_cnt <= q_cnt + 2'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
