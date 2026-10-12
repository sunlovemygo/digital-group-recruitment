`timescale 1ns / 1ps
//=============================================================================
// attention_ip_bonus_filter —— D 项加分：简单筛选 / 稀疏 Attention 扩展
//-----------------------------------------------------------------------------
// 在基础 Attention 输出 O 之后，按 score 动态阈值输出 Key 索引。
// 新增端口：
//   score_threshold : 有符号阈值，score > threshold 的 Token 被输出
//   filter_idx      : 当前输出的 Key 索引（3-bit，范围 0~7）
//   filter_valid    : filter_idx 有效
//   filter_done     : 所有索引输出完成，拉高 1 拍
//
// 输出顺序：先输出 4 拍 O（out_valid），再连续输出满足条件的 Key 索引，
// 最后 filter_done 拉高。done 也在 filter_done 同一拍拉高，表示整个任务结束。
//=============================================================================
module attention_ip_bonus_filter (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire signed [7:0]  q_in,
    input  wire signed [7:0]  k_in,
    input  wire signed [7:0]  v_in,
    input  wire               q_valid,
    input  wire               kv_valid,
    input  wire signed [17:0] score_threshold,   // D 项新增：动态阈值
    output wire               data_ready,
    output reg  signed [7:0]  out_data,
    output reg                out_valid,
    output reg                done,
    output reg  [2:0]         filter_idx,
    output reg                filter_valid,
    output reg                filter_done
);

    localparam [3:0]
        S_IDLE         = 4'd0,
        S_LOAD_Q       = 4'd1,
        S_LOAD_KV      = 4'd2,
        S_DOT          = 4'd3,
        S_MAX          = 4'd4,
        S_EXP          = 4'd5,
        S_UPDATE       = 4'd6,
        S_NEXT         = 4'd7,
        S_NORM         = 4'd8,
        S_OUTPUT       = 4'd9,
        S_FILTER_SCAN  = 4'd10,
        S_FILTER_DONE  = 4'd11;

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
            state       <= S_IDLE;
            q_cnt       <= 2'd0;
            tok_cnt     <= 3'd0;
            dim_cnt     <= 2'd0;
            out_valid   <= 1'b0;
            done        <= 1'b0;
            out_data    <= 8'sd0;
            L           <= 16'd0;
            xmax        <= 18'sd0;
            score_acc   <= 18'sd0;
            ACC[0]      <= 20'sd0; ACC[1] <= 20'sd0; ACC[2] <= 20'sd0; ACC[3] <= 20'sd0;
            filter_idx  <= 3'd0;
            filter_valid <= 1'b0;
            filter_done <= 1'b0;
        end else begin
            done        <= 1'b0;
            out_valid   <= 1'b0;
            filter_valid <= 1'b0;
            filter_done <= 1'b0;
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
                    if (xmax - score_buf[tok_cnt] >= 18'sd4)
                        weight_buf[tok_cnt] <= 16'd0;
                    else
                        weight_buf[tok_cnt] <= exp_lut(xmax - score_buf[tok_cnt]);
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
                        q_cnt   <= 2'd0;
                        tok_cnt <= 3'd0;
                        state   <= S_FILTER_SCAN;
                    end else begin
                        q_cnt <= q_cnt + 2'd1;
                    end
                end

                // ---------------- D 项：扫描并输出满足条件的 Key 索引 ----------------
                S_FILTER_SCAN: begin
                    if (score_buf[tok_cnt] > score_threshold) begin
                        filter_idx   <= tok_cnt;
                        filter_valid <= 1'b1;
                    end
                    if (tok_cnt == 3'd7) begin
                        state <= S_FILTER_DONE;
                    end else begin
                        tok_cnt <= tok_cnt + 3'd1;
                    end
                end

                S_FILTER_DONE: begin
                    filter_done <= 1'b1;
                    done        <= 1'b1;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
