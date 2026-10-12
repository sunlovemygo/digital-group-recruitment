`timescale 1ns / 1ps
//=============================================================================
// tb_attention_bonus_param —— C 项加分：参数化验证
//-----------------------------------------------------------------------------
// 分别例化 S=8 和 S=4，验证状态机能正常结束，且 S=8 结果与基础版一致。
//=============================================================================
module tb_attention_bonus_param;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg q_valid = 1'b0, kv_valid = 1'b0;
    reg signed [7:0] q_in = 8'sd0, k_in = 8'sd0, v_in = 8'sd0;
    wire data_ready8, out_valid8, done8;
    wire data_ready4, out_valid4, done4;
    wire signed [7:0] out_data8, out_data4;

    attention_ip_bonus_param #(.S(8)) dut8 (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .data_ready(data_ready8), .out_data(out_data8),
        .out_valid(out_valid8), .done(done8)
    );

    attention_ip_bonus_param #(.S(4)) dut4 (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .data_ready(data_ready4), .out_data(out_data4),
        .out_valid(out_valid4), .done(done4)
    );

    always #5 clk = ~clk;

    reg signed [7:0] got [0:3];
    reg signed [7:0] exp [0:3];
    integer ocnt, cc, j;

    task send_q_kv8;
        begin
            q_valid <= 1'b1;
            q_in <= 8'sd1;  @(posedge clk);
            q_in <= 8'sd2;  @(posedge clk);
            q_in <= -8'sd1; @(posedge clk);
            q_in <= 8'sd0;  @(posedge clk);
            q_valid <= 1'b0;

            kv_valid <= 1'b1;
            // 8 tokens
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

    task send_q_kv4;
        begin
            q_valid <= 1'b1;
            q_in <= 8'sd1;  @(posedge clk);
            q_in <= 8'sd2;  @(posedge clk);
            q_in <= -8'sd1; @(posedge clk);
            q_in <= 8'sd0;  @(posedge clk);
            q_valid <= 1'b0;

            kv_valid <= 1'b1;
            // 4 tokens (only first 4 of canonical)
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
            kv_valid <= 1'b0;
        end
    endtask

    initial begin
        $display("============================================");
        $display(" tb_attention_bonus_param: parameterization test ");
        $display("============================================");

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // ---------- test S=8 ----------
        exp[0] = 8'sd3; exp[1] = 8'sd2; exp[2] = 8'sd1; exp[3] = 8'sd2;

        while (!data_ready8) @(posedge clk);
        start <= 1'b1; @(posedge clk); start <= 1'b0;
        send_q_kv8;

        ocnt = 0; cc = 0;
        while (ocnt < 4 && cc < 5000) begin
            @(posedge clk); cc = cc + 1;
            if (out_valid8) begin got[ocnt] = out_data8; ocnt = ocnt + 1; end
        end

        if (got[0]==exp[0] && got[1]==exp[1] && got[2]==exp[2] && got[3]==exp[3])
            $display("TEST S=8 PASS: O=[%0d,%0d,%0d,%0d]", got[0], got[1], got[2], got[3]);
        else
            $display("TEST S=8 FAIL: got=[%0d,%0d,%0d,%0d] exp=[%0d,%0d,%0d,%0d]",
                got[0], got[1], got[2], got[3], exp[0], exp[1], exp[2], exp[3]);

        // ---------- test S=4 ----------
        // Q 与 K0..K3 点积：1,2,3,-1；xmax=3；weights = exp(-[2,1,0,4])*16 = [2,6,16,0]
        // L=24；ACC = 2*[4,2,0,1] + 6*[1,6,2,0] + 16*[3,1,1,2] = [8+6+48, 4+36+16, 0+12+16, 2+0+32] = [62,56,28,34]
        // O = round_away([62,56,28,34]/24) = [3,2,1,1]
        exp[0] = 8'sd3; exp[1] = 8'sd2; exp[2] = 8'sd1; exp[3] = 8'sd1;

        while (!data_ready4) @(posedge clk);
        start <= 1'b1; @(posedge clk); start <= 1'b0;
        send_q_kv4;

        ocnt = 0; cc = 0;
        while (ocnt < 4 && cc < 5000) begin
            @(posedge clk); cc = cc + 1;
            if (out_valid4) begin got[ocnt] = out_data4; ocnt = ocnt + 1; end
        end

        if (got[0]==exp[0] && got[1]==exp[1] && got[2]==exp[2] && got[3]==exp[3])
            $display("TEST S=4 PASS: O=[%0d,%0d,%0d,%0d]", got[0], got[1], got[2], got[3]);
        else
            $display("TEST S=4 FAIL: got=[%0d,%0d,%0d,%0d] exp=[%0d,%0d,%0d,%0d]",
                got[0], got[1], got[2], got[3], exp[0], exp[1], exp[2], exp[3]);

        $finish;
    end

    initial begin #20000000; $display("[FAIL] global timeout"); $finish; end

endmodule
