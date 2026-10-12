`timescale 1ns / 1ps
//=============================================================================
// attention_ip —— 骨架版 v2（可编译、可仿真，计算通路留 TODO）
//
// 规模：S = 8, d = 4，输入 8-bit 有符号
// v2 相对 v1 的硬变化：
//   1) Softmax 必须先求 xmax，再算 exp(score − xmax)
//   2) weight 是 4 位小数定点（无符号）：weight = round(exp(score−xmax) × 16)
//      L、ACC 同为 4.4 定点，除完缩放抵消，O = round(ACC / L)，8-bit 有符号
//   3) 状态机 10 个（新增独立的 S_MAX）
//
// 接口约定：
//   start      仅 IDLE 有效，拉高 1 拍启动一次任务
//   q_valid    q_in 有效，共 4 拍（Q 的 4 个分量）
//   kv_valid   k_in / v_in 同拍有效，按 K0,V0 → K7,V7 顺序，
//              每个 Token 4 拍（d=4），共 8x4 = 32 拍
//   data_ready 为 1 时才允许发送输入（反压）
//   out_valid  out_data 有效，共 4 拍
//   done       拉高 1 拍表示任务结束，之后回 IDLE
//=============================================================================
module attention_ip (
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
    // 1. 状态机状态定义（10 个）
    //------------------------------------------------------------------
    localparam [3:0]
        S_IDLE    = 4'd0,
        S_LOAD_Q  = 4'd1,
        S_LOAD_KV = 4'd2,
        S_DOT     = 4'd3,   // TODO: 点积累加，每个 Token 4 拍 → score_buf[tok]
        S_MAX     = 4'd4,   // TODO: 在 8 个 score 中找 xmax
        S_EXP     = 4'd5,   // TODO: u = xmax − score；查 exp_lut → weight_buf[tok]
        S_UPDATE  = 4'd6,   // TODO: 累加 L 和 4 路 ACC
        S_NEXT    = 4'd7,   // Token 计数
        S_NORM    = 4'd8,   // TODO: O[d] = round(ACC[d] / L)
        S_OUTPUT  = 4'd9;

    reg [3:0]  state;
    reg [1:0]  q_cnt;      // Q 分量计数 0..3 / 也复用为输出计数
    reg [2:0]  tok_cnt;    // Token 计数 0..7
    reg [1:0]  dim_cnt;    // 维度计数 0..3

    //------------------------------------------------------------------
    // 2. 存储（位宽按 v2 推导表）
    //------------------------------------------------------------------
    reg signed [7:0]  q_reg [0:3];    // Q 的 4 个分量
    reg signed [7:0]  k_buf [0:31];   // K，索引 tok_cnt*4 + dim_cnt
    reg signed [7:0]  v_buf [0:31];   // V，同上
    reg signed [17:0] score_acc;           // 点积累加器（DOT 每 Token 4 拍 MAC）
    reg signed [17:0] score_buf [0:7];   // 8 个 Score，18-bit 有符号
    reg        [15:0] weight_buf[0:7];   // 8 个 weight，4.4 定点（低 5 位：1 整数 + 4 小数）
    reg        [15:0] L;                  // 分母，4.4 定点
    reg signed [19:0] ACC   [0:3];        // 4 路 ACC，4.4 定点，20-bit 有符号
    reg signed [17:0] xmax;               // 8 个 score 的最大值
    reg signed [7:0]  O_buf [0:3];         // 最终输出，8-bit 有符号

    //------------------------------------------------------------------
    // 3. 指数 LUT 助手（v2 自行实现）：u = xmax − score ≥ 0
    //    weight = round(exp(−u) × 16)，u≥4 限幅为 0
    //------------------------------------------------------------------
    function [15:0] exp_lut;
        input [3:0] u;
        begin
            case (u)
                4'd0:    exp_lut = 16'd16;
                4'd1:    exp_lut = 16'd6;
                4'd2:    exp_lut = 16'd2;
                4'd3:    exp_lut = 16'd1;
                default: exp_lut = 16'd0;   // u ≥ 4
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // 4. 反压：处于可接收输入的状态时允许发送
    //------------------------------------------------------------------
    assign data_ready = (state == S_IDLE) || (state == S_LOAD_Q)
                      || (state == S_LOAD_KV);

    //------------------------------------------------------------------
    // 5. 主状态机
    //    骨架实现：复位 / 装载 / 路由；计算算术（DOT/MAX/EXP/UPDATE/NORM）
    //    留 TODO，你按《学习页》和 golden_model.py 对照填。
    //------------------------------------------------------------------
    integer di;       
    reg signed [17:0] mx;   // S_MAX 临时最大值 

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
            done      <= 1'b0;          // done / out_valid 只拉高一拍
            out_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state   <= S_LOAD_Q;
                        q_cnt   <= 2'd0;
                        tok_cnt <= 3'd0;
                        dim_cnt <= 2'd0;
                        // 每次启动新任务清零累加器，避免二次任务残值漂移
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
                                tok_cnt <= 3'd0;
                                state   <= S_DOT;   // 32 拍装载完 → 进入计算
                            end else begin
                                tok_cnt <= tok_cnt + 3'd1;
                            end
                        end else begin
                            dim_cnt <= dim_cnt + 2'd1;
                        end
                    end
                end

                // ---------------- 以下计算路径：路由已通，算术留 TODO ----------------
                S_DOT: begin
                    // 【骨架占位·路由】真实 S_DOT 由你按《分步指南 v2》增量1 实现
                    // （dim_cnt 4 拍 MAC -> score_buf[tok_cnt]）。这里只推进 tok_cnt，
                    // 让 8 个 Token 走完后进入 S_MAX，保证状态机能正常到达 done。
                   score_buf[tok_cnt] <= $signed(q_reg[0]) * $signed(k_buf[{tok_cnt, 2'd0}]) + 
                                 $signed(q_reg[1]) * $signed(k_buf[{tok_cnt, 2'd1}]) + 
                                 $signed(q_reg[2]) * $signed(k_buf[{tok_cnt, 2'd2}]) + 
                                 $signed(q_reg[3]) * $signed(k_buf[{tok_cnt, 2'd3}]);
                    if (tok_cnt == 3'd7) state <= S_MAX;
                     
                    else begin
                        tok_cnt <= tok_cnt + 3'd1;
                        state   <= S_DOT;
                    end
                end

                S_MAX: begin
                    // TODO: 在 score_buf[0..7] 中找最大值 → xmax
                    // 骨架占位：直接进 EXP（xmax 由你填）
                    mx = score_buf[0];
                    for (di = 1; di < 8; di = di + 1) begin
                        if (score_buf[di] > mx) begin
                            mx = score_buf[di];
                        end
                    end
                    xmax    <= mx;
                    tok_cnt <= 3'd0;
                    state   <= S_EXP;
                end

                S_EXP: begin
                    // TODO: u = xmax − score_buf[tok_cnt]; weight_buf[tok_cnt] <= exp_lut(u);
                    if (xmax - score_buf[tok_cnt] >= 18'sd4) begin
                        weight_buf[tok_cnt] <= 16'd0;
                    end else begin
                        weight_buf[tok_cnt] <= exp_lut(xmax - score_buf[tok_cnt]);
                    end
                    state <= S_UPDATE;
                end

                S_UPDATE: begin
                    // TODO: L <= L + weight_buf[tok_cnt];
                    //       ACC[d] <= ACC[d] + weight_buf[tok_cnt] * v_buf[{tok_cnt, d}];
                    L <= L + weight_buf[tok_cnt];
                    for (di = 0; di < 4; di = di + 1    ) begin
                        ACC[di] <= ACC[di] + $signed(weight_buf[tok_cnt]) * $signed(v_buf[{tok_cnt, di[1:0]}]);
                    end  
                    state <= S_NEXT;
                end

                S_NEXT: begin
                    if (tok_cnt == 3'd7) state <= S_NORM;   // 8 个 Token 处理完
                    else begin
                        tok_cnt <= tok_cnt + 3'd1;
                        state   <= S_EXP;                    // 回 EXP 处理下一个
                    end
                end

                S_NORM: begin
                    // TODO: O_buf[d] = round(ACC[d] / L)，d = 0..3
                    for (di = 0; di < 4; di = di + 1) begin
                        if (ACC[di] >= 0) begin
                            O_buf[di] <= (ACC[di] + $signed(L >> 1)) / $signed(L);
                        end else begin
                            O_buf[di] <= (ACC[di] - $signed(L >> 1)) / $signed(L);
                        end
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
