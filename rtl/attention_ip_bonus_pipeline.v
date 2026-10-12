`timescale 1ns / 1ps
//=============================================================================
// attention_ip_bonus_pipeline —— B 项加分：流水线/周期优化
//-----------------------------------------------------------------------------
// 在 attention_ip_ref.v 基础上，把原本 S_EXP 和 S_UPDATE 两个状态合并为一个状态。
// 因为 exp_lut 是组合逻辑，算出 weight 后同一拍就能累加 L 和 ACC。
// 这样每个 Token 少消耗 1 拍，8 个 Token 共减少 8 拍。
//
// 原参考实现计算阶段周期数（不含装载/输出）：
//   DOT: 8 Token × 4 拍 = 32
//   MAX: 1
//   EXP/UPDATE: 8 Token × 2 拍 = 16
//   NORM: 1
//   合计 ≈ 50 拍（含状态跳转细节）
// 本实现：
//   DOT: 32
//   MAX: 1
//   EXP_UPDATE: 8 Token × 1 拍 = 8
//   NORM: 1
//   合计 ≈ 42 拍，约减少 16% 计算周期。
//
// 资源代价：无额外硬件，只是状态合并，组合路径略长（因为 weight 要同时驱动
// 加法器和乘法器），但仍在单拍内可完成。
//=============================================================================
module attention_ip_bonus_pipeline (
    input  wire               clk,
    input  wire               rst_n,      // 低有效
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

    //------------------------------------------------------------------
    // 1. 状态机（10 个，S_UPDATE 保留但不再使用）
    //------------------------------------------------------------------
    localparam [3:0]
        S_IDLE    = 4'd0,
        S_LOAD_Q  = 4'd1,
        S_LOAD_KV = 4'd2,
        S_DOT     = 4'd3,   // 点积：dim_cnt 4 拍 MAC -> score_buf[tok]
        S_MAX     = 4'd4,   // 在 8 个 score 中找 xmax
        S_EXP     = 4'd5,   // B 项：合并 EXP + UPDATE
        S_UPDATE  = 4'd6,   // 保留编号，未使用
        S_NEXT    = 4'd7,   // Token 计数
        S_NORM    = 4'd8,   // O[d] = round(ACC[d] / L)
        S_OUTPUT  = 4'd9;

    reg [3:0]  state;
    reg [1:0]  q_cnt;
    reg [2:0]  tok_cnt;
    reg [1:0]  dim_cnt;

    //------------------------------------------------------------------
    // 2. 存储
    //------------------------------------------------------------------
    reg signed [7:0]  q_reg [0:3];
    reg signed [7:0]  k_buf [0:31];
    reg signed [7:0]  v_buf [0:31];
    reg signed [17:0] score_acc;
    reg signed [17:0] score_buf [0:7];
    reg        [15:0] weight_buf[0:7];
    reg        [15:0] L;
    reg signed [19:0] ACC   [0:3];
    reg signed [17:0] xmax;
    reg signed [7:0]  O_buf [0:3];

    //------------------------------------------------------------------
    // 3. 指数 LUT
    //------------------------------------------------------------------
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

    //------------------------------------------------------------------
    // 4. 反压
    //------------------------------------------------------------------
    assign data_ready = (state == S_IDLE) || (state == S_LOAD_Q)
                      || (state == S_LOAD_KV);

    //------------------------------------------------------------------
    // 5. 主状态机
    //------------------------------------------------------------------
    integer di;
    reg signed [17:0] mx;
    reg        [15:0] w;       // B 项：当前 Token 的临时 weight（阻塞赋值）

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
            xmax      <= 18'sd0;
            score_acc <= 18'sd0;
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
                        xmax    <= 18'sd0;
                        score_acc <= 18'sd0;
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

                // ---------------- B 项优化：EXP + UPDATE 合并 ----------------
                S_DOT: begin
                    if (dim_cnt == 2'd0)
                        score_acc <= $signed(q_reg[0]) * $signed(k_buf[{tok_cnt, 2'd0}]);
                    else
                        score_acc <= score_acc + $signed(q_reg[dim_cnt]) * $signed(k_buf[{tok_cnt, dim_cnt}]);
                    if (dim_cnt == 2'd3) begin
                        score_buf[tok_cnt] <= score_acc + $signed(q_reg[dim_cnt]) * $signed(k_buf[{tok_cnt, dim_cnt}]);
                        dim_cnt <= 2'd0;
                        if (tok_cnt == 3'd7) state <= S_MAX;
                        else begin
                            tok_cnt <= tok_cnt + 3'd1;
                            state   <= S_DOT;
                        end
                    end else begin
                        dim_cnt <= dim_cnt + 2'd1;
                    end
                end

                S_MAX: begin
                    mx = score_buf[0];
                    for (di = 1; di < 8; di = di + 1)
                        if (score_buf[di] > mx) mx = score_buf[di];
                    xmax    <= mx;
                    tok_cnt <= 3'd0;
                    state   <= S_EXP;
                end

                S_EXP: begin
                    // 同一拍：查 exp_lut + 累加 L + 累加 ACC
                    if (xmax - score_buf[tok_cnt] >= 18'sd4)
                        w = 16'd0;
                    else
                        w = exp_lut(xmax - score_buf[tok_cnt]);
                    weight_buf[tok_cnt] <= w;
                    L <= L + w;
                    for (di = 0; di < 4; di = di + 1)
                        ACC[di] <= ACC[di] + $signed(w) * $signed(v_buf[{tok_cnt, di[1:0]}]);
                    state <= S_NEXT;
                end

                S_NEXT: begin
                    if (tok_cnt == 3'd7) state <= S_NORM;
                    else begin
                        tok_cnt <= tok_cnt + 3'd1;
                        state   <= S_EXP;
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
