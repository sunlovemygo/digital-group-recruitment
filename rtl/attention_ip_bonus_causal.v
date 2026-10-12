`timescale 1ns / 1ps
//=============================================================================
// attention_ip_bonus_causal —— A 项加分：因果 Mask 骨架
//-----------------------------------------------------------------------------
// 在基础版 attention_ip.v 上增加：
//   - input [2:0] mask_pos    // 当前查询位置 i，只有 tok_cnt <= i 的 Key 才参与
//   - 在 S_EXP 阶段，若 tok_cnt > mask_pos，强制 weight = 0（等价于 exp(-∞)=0）
// 其余状态机与 v2 基础版保持一致。
//
// 验证思路：
//   1) mask_pos = 7 时，所有 Key 都参与，结果与无 Mask 基础版一致。
//   2) mask_pos = 0 时，只有 tok_cnt=0 参与，O ≈ V[0]。
//   3) mask_pos = 3 时，只有前 4 个 Token 参与，L 变小但归一化仍正确。
//=============================================================================
module attention_ip_bonus_causal (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire signed [7:0]  q_in,
    input  wire signed [7:0]  k_in,
    input  wire signed [7:0]  v_in,
    input  wire               q_valid,
    input  wire               kv_valid,
    input  wire        [2:0]  mask_pos,     // <-- A 项新增：因果位置 i
    output wire               data_ready,
    output reg  signed [7:0]  out_data,
    output reg                out_valid,
    output reg                done
);

    localparam [3:0]
        S_IDLE    = 4'd0,
        S_LOAD_Q  = 4'd1,
        S_LOAD_KV = 4'd2,
        S_DOT     = 4'd3,
        S_MAX     = 4'd4,
        S_EXP     = 4'd5,
        S_UPDATE  = 4'd6,
        S_NEXT    = 4'd7,
        S_NORM    = 4'd8,
        S_OUTPUT  = 4'd9;

    reg [3:0]  state;
    reg [1:0]  q_cnt;
    reg [2:0]  tok_cnt;
    reg [1:0]  dim_cnt;

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
    reg signed [17:0] mx;

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
            ACC[0] <= 20'sd0; ACC[1] <= 20'sd0; ACC[2] <= 20'sd0; ACC[3] <= 20'sd0;
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
                        ACC[0] <= 20'sd0; ACC[1] <= 20'sd0; ACC[2] <= 20'sd0; ACC[3] <= 20'sd0;
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

                // ------------------------------------------------------------------
                // A 项核心：因果 Mask
                // 当当前 Token 索引 tok_cnt > mask_pos 时，该 Key 被屏蔽
                // 实现方式：令 weight = 0（等价于 exp(-∞)）
                // ------------------------------------------------------------------
                S_EXP: begin
                    if (tok_cnt > mask_pos) begin
                        weight_buf[tok_cnt] <= 16'd0;        // 被屏蔽，权重为 0
                    end else if (xmax - score_buf[tok_cnt] >= 18'sd4) begin
                        weight_buf[tok_cnt] <= 16'd0;
                    end else begin
                        weight_buf[tok_cnt] <= exp_lut(xmax - score_buf[tok_cnt]);
                    end
                    state <= S_UPDATE;
                end

                S_UPDATE: begin
                    L <= L + weight_buf[tok_cnt];
                    for (di = 0; di < 4; di = di + 1)
                        ACC[di] <= ACC[di] + $signed(weight_buf[tok_cnt]) * $signed(v_buf[{tok_cnt, di[1:0]}]);
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
