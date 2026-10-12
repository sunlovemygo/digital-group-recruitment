`timescale 1ns / 1ps
//=============================================================================
// tb_attention_bonus_causal —— A 项加分：因果 Mask 验证
//-----------------------------------------------------------------------------
// 测试规范算例，分别验证 mask_pos=7（不屏蔽）和 mask_pos=0（只保留 t=0）。
// mask_pos=7 时期望 O=[3,2,1,2]（与基础版一致）。
// mask_pos=0 时只有 t=0 参与，weight=16, L=16, O≈V[0]=[4,2,0,1]。
//=============================================================================
module tb_attention_bonus_causal;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg q_valid = 1'b0, kv_valid = 1'b0;
    reg signed [7:0] q_in = 8'sd0, k_in = 8'sd0, v_in = 8'sd0;
    reg [2:0] mask_pos = 3'd7;
    wire data_ready, out_valid, done;
    wire signed [7:0] out_data;

    attention_ip_bonus_causal dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .mask_pos(mask_pos),
        .data_ready(data_ready), .out_data(out_data),
        .out_valid(out_valid), .done(done)
    );

    always #5 clk = ~clk;

    reg signed [7:0] got [0:3];
    reg signed [7:0] exp [0:3];
    integer ocnt, cc, j, test_id;

    task send_q_kv;
        begin
            q_valid <= 1'b1;
            q_in <= 8'sd1;  @(posedge clk);
            q_in <= 8'sd2;  @(posedge clk);
            q_in <= -8'sd1; @(posedge clk);
            q_in <= 8'sd0;  @(posedge clk);
            q_valid <= 1'b0;

            kv_valid <= 1'b1;
            // t0..t7 K/V 顺序送
            k_in <= 8'sd1; v_in <= 8'sd4; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd1; v_in <= 8'sd6; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
            k_in <= 8'sd1; v_in <= 8'sd3; @(posedge clk);
            k_in <= 8'sd1; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
            k_in <= 8'sd1; v_in <= 8'sd5; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd3; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd2; @(posedge clk);
            k_in <= 8'sd1; v_in <= 8'sd2; @(posedge clk);
            k_in <= 8'sd2; v_in <= 8'sd5; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
            k_in <= 8'sd1; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd1; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd1; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd1; @(posedge clk);
            k_in <= 8'sd2; v_in <= 8'sd2; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd3; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd0; @(posedge clk);
            k_in <= 8'sd0; v_in <= 8'sd4; @(posedge clk);
            kv_valid <= 1'b0;
        end
    endtask

    initial begin
        $display("============================================");
        $display(" tb_attention_bonus_causal: causal mask test ");
        $display("============================================");

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // ---------- test 1: mask_pos = 7，等价无 Mask ----------
        test_id = 0;
        mask_pos = 3'd7;
        exp[0] = 8'sd3; exp[1] = 8'sd2; exp[2] = 8'sd1; exp[3] = 8'sd2;

        while (!data_ready) @(posedge clk);
        start <= 1'b1; @(posedge clk); start <= 1'b0;
        send_q_kv;

        ocnt = 0; cc = 0;
        while (ocnt < 4 && cc < 5000) begin
            @(posedge clk); cc = cc + 1;
            if (out_valid) begin got[ocnt] = out_data; ocnt = ocnt + 1; end
        end

        if (got[0]==exp[0] && got[1]==exp[1] && got[2]==exp[2] && got[3]==exp[3])
            $display("TEST 1 PASS (mask_pos=7): O=[%0d,%0d,%0d,%0d]", got[0], got[1], got[2], got[3]);
        else
            $display("TEST 1 FAIL (mask_pos=7): got=[%0d,%0d,%0d,%0d] exp=[%0d,%0d,%0d,%0d]",
                got[0], got[1], got[2], got[3], exp[0], exp[1], exp[2], exp[3]);

        // ---------- test 2: mask_pos = 0，只有 t=0 ----------
        test_id = 1;
        mask_pos = 3'd0;
        exp[0] = 8'sd4; exp[1] = 8'sd2; exp[2] = 8'sd0; exp[3] = 8'sd1;

        while (!data_ready) @(posedge clk);
        start <= 1'b1; @(posedge clk); start <= 1'b0;
        send_q_kv;

        ocnt = 0; cc = 0;
        while (ocnt < 4 && cc < 5000) begin
            @(posedge clk); cc = cc + 1;
            if (out_valid) begin got[ocnt] = out_data; ocnt = ocnt + 1; end
        end

        if (got[0]==exp[0] && got[1]==exp[1] && got[2]==exp[2] && got[3]==exp[3])
            $display("TEST 2 PASS (mask_pos=0): O=[%0d,%0d,%0d,%0d]", got[0], got[1], got[2], got[3]);
        else
            $display("TEST 2 FAIL (mask_pos=0): got=[%0d,%0d,%0d,%0d] exp=[%0d,%0d,%0d,%0d]",
                got[0], got[1], got[2], got[3], exp[0], exp[1], exp[2], exp[3]);

        $finish;
    end

    initial begin #20000000; $display("[FAIL] global timeout"); $finish; end

endmodule
