`timescale 1ns / 1ps
//=============================================================================
// tb_attention_bonus_pwl —— F 项加分：验证 PWL 版 Attention 输出
//-----------------------------------------------------------------------------
// 测试规范算例：
//   Q=[1,2,-1,0]
//   K/V 与 golden_model.py 一致
//   PWL 版期望 O=[2,2,1,2]（与基础 LUT 版 [3,2,1,2] 仅有微小差异）
//=============================================================================
module tb_attention_bonus_pwl;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg q_valid = 1'b0, kv_valid = 1'b0;
    reg signed [7:0] q_in = 8'sd0, k_in = 8'sd0, v_in = 8'sd0;
    wire data_ready, out_valid, done;
    wire signed [7:0] out_data;

    attention_ip_bonus_pwl dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .data_ready(data_ready), .out_data(out_data),
        .out_valid(out_valid), .done(done)
    );

    always #5 clk = ~clk;

    reg signed [7:0] got [0:3];
    reg signed [7:0] exp [0:3];
    integer ocnt, cc, j;

    initial begin
        exp[0] = 8'sd2; exp[1] = 8'sd2; exp[2] = 8'sd1; exp[3] = 8'sd2;

        $display("============================================");
        $display(" tb_attention_bonus_pwl: PWL attention test ");
        $display("============================================");

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        while (!data_ready) @(posedge clk);
        start <= 1'b1; @(posedge clk); start <= 1'b0;

        // 送 Q：1,2,-1,0
        q_valid <= 1'b1;
        q_in <= 8'sd1;  @(posedge clk);
        q_in <= 8'sd2;  @(posedge clk);
        q_in <= -8'sd1; @(posedge clk);
        q_in <= 8'sd0;  @(posedge clk);
        q_valid <= 1'b0;

        // 送 K/V
        kv_valid <= 1'b1;
        // t0
        k_in <= 8'sd1; v_in <= 8'sd4; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
        // t1
        k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
        k_in <= 8'sd1; v_in <= 8'sd6; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
        // t2
        k_in <= 8'sd1; v_in <= 8'sd3; @(posedge clk);
        k_in <= 8'sd1; v_in <= 8'sd1; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
        // t3
        k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
        k_in <= 8'sd1; v_in <= 8'sd5; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd3; @(posedge clk);
        // t4
        k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
        k_in <= 8'sd1; v_in <= 8'sd2; @(posedge clk);
        // t5
        k_in <= 8'sd2; v_in <= 8'sd5; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
        k_in <= 8'sd1; v_in <= 8'sd1; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
        // t6
        k_in <= 8'sd1; v_in <= 8'sd1; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
        k_in <= 8'sd1; v_in <= 8'sd1; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
        // t7
        k_in <= 8'sd2; v_in <= 8'sd2; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd3; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
        k_in <= 8'sd0; v_in <= 8'sd4; @(posedge clk);
        kv_valid <= 1'b0;

        // 收集输出
        ocnt = 0; cc = 0;
        while (ocnt < 4 && cc < 5000) begin
            @(posedge clk); cc = cc + 1;
            if (out_valid) begin got[ocnt] = out_data; ocnt = ocnt + 1; end
        end

        if (ocnt < 4) begin
            $display("[FAIL] no 4 out_valid within 5000 cycles");
        end else if (got[0]==exp[0] && got[1]==exp[1] && got[2]==exp[2] && got[3]==exp[3]) begin
            $display("PWL ATTENTION TEST PASS : O=[%0d,%0d,%0d,%0d]", got[0], got[1], got[2], got[3]);
        end else begin
            $display("[FAIL] got=[%0d,%0d,%0d,%0d] exp=[%0d,%0d,%0d,%0d]",
                got[0], got[1], got[2], got[3], exp[0], exp[1], exp[2], exp[3]);
        end

        $finish;
    end

    initial begin #20000000; $display("[FAIL] global timeout"); $finish; end

endmodule
