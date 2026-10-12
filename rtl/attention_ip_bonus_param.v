`timescale 1ns / 1ps
//=============================================================================
// attention_ip_bonus_param —— C 项加分：参数化骨架
//-----------------------------------------------------------------------------
// 将硬编码的 S=8 改为 parameter，D 固定为 4（也可继续扩展）。
// 关键改动：
//   - parameter S = 8
//   - 计数器位宽用 $clog2 自动推导
//   - score / weight / L / ACC 位宽随 S 增长
//   - 存储数组维度用 S 表示
//
// 验证思路：
//   1) S=8 时结果与基础版一致。
//   2) S=4 时，只装载前 4 个 Token，结果与 golden_model 的 S=4 版本一致。
//   3) S=16 时，测试状态机能正常走完 16 个 Token（可用简化向量）。
//=============================================================================
module attention_ip_bonus_param #(
    parameter S = 8                       // 可配置 Token 数：8 / 16 / 32 等
)(
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

    localparam D = 4;                                    // 维度固定为 4，可继续扩展
    localparam SCORE_W = 18;                             // 8+8+clog2(4)=18，带符号
    localparam TOK_W   = $clog2(S);                      // Token 计数器位宽
    localparam DIM_W   = $clog2(D);                      // 维度计数器位宽
    localparam WEIGHT_W = 16;                            // 4.4 定点，无符号
    localparam ACC_W    = SCORE_W + 8 + $clog2(S);       // weight(16) * v(8) 累加 S 次

    localparam [DIM_W-1:0]  DIM_MAX = D - 1;
    localparam [TOK_W-1:0]  TOK_MAX = S - 1;
    localparam signed [SCORE_W-1:0] SCORE_CLIP = 4;

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

    reg [3:0]          state;
    reg [DIM_W-1:0]    q_cnt;
    reg [TOK_W-1:0]    tok_cnt;
    reg [DIM_W-1:0]    dim_cnt;

    reg signed [7:0]   q_reg [0:D-1];
    reg signed [7:0]   k_buf [0:S*D-1];
    reg signed [7:0]   v_buf [0:S*D-1];
    reg signed [SCORE_W-1:0] score_acc;
    reg signed [SCORE_W-1:0] score_buf [0:S-1];
    reg        [WEIGHT_W-1:0] weight_buf[0:S-1];
    reg        [WEIGHT_W-1:0] L;
    reg signed [ACC_W-1:0]    ACC [0:D-1];
    reg signed [SCORE_W-1:0]  xmax;
    reg signed [7:0]          O_buf [0:D-1];

    function [WEIGHT_W-1:0] exp_lut;
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
    reg signed [SCORE_W-1:0] mx;

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            q_cnt     <= {DIM_W{1'b0}};
            tok_cnt   <= {TOK_W{1'b0}};
            dim_cnt   <= {DIM_W{1'b0}};
            out_valid <= 1'b0;
            done      <= 1'b0;
            out_data  <= 8'sd0;
            L         <= {WEIGHT_W{1'b0}};
            xmax      <= {SCORE_W{1'b0}};
            score_acc <= {SCORE_W{1'b0}};
            for (di = 0; di < D; di = di + 1) ACC[di] <= {ACC_W{1'b0}};
        end else begin
            done      <= 1'b0;
            out_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state   <= S_LOAD_Q;
                        q_cnt   <= {DIM_W{1'b0}};
                        tok_cnt <= {TOK_W{1'b0}};
                        dim_cnt <= {DIM_W{1'b0}};
                        L       <= {WEIGHT_W{1'b0}};
                        xmax    <= {SCORE_W{1'b0}};
                        score_acc <= {SCORE_W{1'b0}};
                        for (di = 0; di < D; di = di + 1) ACC[di] <= {ACC_W{1'b0}};
                    end
                end

                S_LOAD_Q: begin
                    if (q_valid) begin
                        q_reg[q_cnt] <= q_in;
                        if (q_cnt == DIM_MAX) begin
                            q_cnt <= {DIM_W{1'b0}};
                            state <= S_LOAD_KV;
                        end else begin
                            q_cnt <= q_cnt + 1'b1;
                        end
                    end
                end

                S_LOAD_KV: begin
                    if (kv_valid) begin
                        k_buf[{tok_cnt, dim_cnt}] <= k_in;
                        v_buf[{tok_cnt, dim_cnt}] <= v_in;
                        if (dim_cnt == DIM_MAX) begin
                            dim_cnt <= {DIM_W{1'b0}};
                            if (tok_cnt == TOK_MAX) begin
                                tok_cnt   <= {TOK_W{1'b0}};
                                score_acc <= {SCORE_W{1'b0}};
                                state     <= S_DOT;
                            end else begin
                                tok_cnt <= tok_cnt + 1'b1;
                            end
                        end else begin
                            dim_cnt <= dim_cnt + 1'b1;
                        end
                    end
                end

                S_DOT: begin
                    if (dim_cnt == {DIM_W{1'b0}})
                        score_acc <= $signed(q_reg[0]) * $signed(k_buf[{tok_cnt, {DIM_W{1'b0}}}]);
                    else
                        score_acc <= score_acc + $signed(q_reg[dim_cnt]) * $signed(k_buf[{tok_cnt, dim_cnt}]);
                    if (dim_cnt == DIM_MAX) begin
                        score_buf[tok_cnt] <= score_acc + $signed(q_reg[dim_cnt]) * $signed(k_buf[{tok_cnt, dim_cnt}]);
                        dim_cnt <= {DIM_W{1'b0}};
                        if (tok_cnt == TOK_MAX) state <= S_MAX;
                        else begin
                            tok_cnt <= tok_cnt + 1'b1;
                            state   <= S_DOT;
                        end
                    end else begin
                        dim_cnt <= dim_cnt + 1'b1;
                    end
                end

                S_MAX: begin
                    mx = score_buf[0];
                    for (di = 1; di < S; di = di + 1)
                        if (score_buf[di] > mx) mx = score_buf[di];
                    xmax    <= mx;
                    tok_cnt <= {TOK_W{1'b0}};
                    state   <= S_EXP;
                end

                S_EXP: begin
                    if (xmax - score_buf[tok_cnt] >= SCORE_CLIP)
                        weight_buf[tok_cnt] <= {WEIGHT_W{1'b0}};
                    else
                        weight_buf[tok_cnt] <= exp_lut(xmax - score_buf[tok_cnt]);
                    state <= S_UPDATE;
                end

                S_UPDATE: begin
                    L <= L + weight_buf[tok_cnt];
                    for (di = 0; di < D; di = di + 1)
                        ACC[di] <= ACC[di] + $signed(weight_buf[tok_cnt]) * $signed(v_buf[{tok_cnt, di[DIM_W-1:0]}]);
                    state <= S_NEXT;
                end

                S_NEXT: begin
                    if (tok_cnt == TOK_MAX) state <= S_NORM;
                    else begin
                        tok_cnt <= tok_cnt + 1'b1;
                        state   <= S_EXP;
                    end
                end

                S_NORM: begin
                    for (di = 0; di < D; di = di + 1) begin
                        if (ACC[di] >= 0)
                            O_buf[di] <= (ACC[di] + $signed(L >> 1)) / $signed(L);
                        else
                            O_buf[di] <= (ACC[di] - $signed(L >> 1)) / $signed(L);
                    end
                    q_cnt <= {DIM_W{1'b0}};
                    state <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    out_valid <= 1'b1;
                    out_data  <= O_buf[q_cnt];
                    if (q_cnt == DIM_MAX) begin
                        q_cnt <= {DIM_W{1'b0}};
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        q_cnt <= q_cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
