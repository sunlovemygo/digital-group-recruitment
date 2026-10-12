`timescale 1ns / 1ps
//=============================================================================
// tb_attention_bonus_filter —— D 项加分测试
//-----------------------------------------------------------------------------
// 使用规范算例，score_buf = [1,2,3,-1,0,1,0,2]。
// 设置 score_threshold=1，期望输出 score>1 的 Key 索引：1, 2。
// 同时验证 Attention 输出 O 保持 [3,2,1,2] 不变。
//=============================================================================
module tb_attention_bonus_filter;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg q_valid = 1'b0, kv_valid = 1'b0;
    reg signed [7:0] q_in = 8'sd0, k_in = 8'sd0, v_in = 8'sd0;
    reg signed [17:0] score_threshold = 18'sd1;
    wire data_ready, out_valid, done;
    wire filter_valid, filter_done;
    wire [2:0] filter_idx;
    wire signed [7:0] out_data;

    attention_ip_bonus_filter dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .score_threshold(score_threshold),
        .data_ready(data_ready),
        .out_data(out_data), .out_valid(out_valid), .done(done),
        .filter_idx(filter_idx), .filter_valid(filter_valid), .filter_done(filter_done)
    );

    always #5 clk = ~clk;

    reg signed [7:0] q_vec [0:3];
    reg signed [7:0] KF [0:31];
    reg signed [7:0] VF [0:31];
    initial begin
        q_vec[0]=8'sd1; q_vec[1]=8'sd2; q_vec[2]=-8'sd1; q_vec[3]=8'sd0;
        KF[0]=8'sd1;  KF[1]=8'sd0;  KF[2]=8'sd0;  KF[3]=8'sd0;
        KF[4]=8'sd0;  KF[5]=8'sd1;  KF[6]=8'sd0;  KF[7]=8'sd0;
        KF[8]=8'sd1;  KF[9]=8'sd1;  KF[10]=8'sd0; KF[11]=8'sd0;
        KF[12]=8'sd0; KF[13]=8'sd0; KF[14]=8'sd1; KF[15]=8'sd0;
        KF[16]=8'sd0; KF[17]=8'sd0; KF[18]=8'sd0; KF[19]=8'sd1;
        KF[20]=8'sd2; KF[21]=8'sd0; KF[22]=8'sd1; KF[23]=8'sd0;
        KF[24]=8'sd1; KF[25]=8'sd0; KF[26]=8'sd1; KF[27]=8'sd0;
        KF[28]=8'sd2; KF[29]=8'sd0; KF[30]=8'sd0; KF[31]=8'sd0;
        VF[0]=8'sd4;  VF[1]=8'sd2;  VF[2]=8'sd0;  VF[3]=8'sd1;
        VF[4]=8'sd1;  VF[5]=8'sd6;  VF[6]=8'sd2;  VF[7]=8'sd0;
        VF[8]=8'sd3;  VF[9]=8'sd1;  VF[10]=8'sd1; VF[11]=8'sd2;
        VF[12]=8'sd0; VF[13]=8'sd0; VF[14]=8'sd5; VF[15]=8'sd3;
        VF[16]=8'sd2; VF[17]=8'sd2; VF[18]=8'sd2; VF[19]=8'sd2;
        VF[20]=8'sd5; VF[21]=8'sd0; VF[22]=8'sd1; VF[23]=8'sd1;
        VF[24]=8'sd1; VF[25]=8'sd1; VF[26]=8'sd1; VF[27]=8'sd1;
        VF[28]=8'sd2; VF[29]=8'sd3; VF[30]=8'sd0; VF[31]=8'sd4;
    end

    integer j;
    integer ocnt, fcnt, cc;
    reg signed [7:0] got_O [0:3];
    reg [2:0] got_idx [0:7];
    integer exp_O [0:3];
    integer exp_idx_1 [0:2];

    initial begin
        exp_O[0] = 3; exp_O[1] = 2; exp_O[2] = 1; exp_O[3] = 2;
        exp_idx_1[0] = 1; exp_idx_1[1] = 2; exp_idx_1[2] = 7;
    end

    task send_q;
        begin
            for (j = 0; j < 4; j = j + 1) begin
                while (!data_ready) @(posedge clk);
                q_in   <= q_vec[j];
                q_valid <= 1'b1;
                @(posedge clk);
            end
            q_valid <= 1'b0;
        end
    endtask

    task send_kv;
        begin
            for (j = 0; j < 32; j = j + 1) begin
                while (!data_ready) @(posedge clk);
                k_in    <= KF[j];
                v_in    <= VF[j];
                kv_valid <= 1'b1;
                @(posedge clk);
            end
            kv_valid <= 1'b0;
        end
    endtask

    initial begin
        $display("============================================");
        $display(" tb_attention_bonus_filter: sparse filter test ");
        $display("============================================");

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        @(posedge clk);
        while (!data_ready) @(posedge clk);
        start <= 1'b1; @(posedge clk); start <= 1'b0;

        send_q;
        send_kv;

        ocnt = 0; fcnt = 0; cc = 0;
        while (!done && cc < 5000) begin
            @(posedge clk); cc = cc + 1;
            if (out_valid) begin
                got_O[ocnt] = out_data;
                ocnt = ocnt + 1;
            end
            if (filter_valid) begin
                got_idx[fcnt] = filter_idx;
                fcnt = fcnt + 1;
            end
        end

        // 检查 O
        if (ocnt != 4) begin
            $display("[FAIL] O 输出拍数=%0d，期望 4", ocnt);
        end else if (got_O[0]!=exp_O[0] || got_O[1]!=exp_O[1] || got_O[2]!=exp_O[2] || got_O[3]!=exp_O[3]) begin
            $display("[FAIL] O 不匹配 got=[%0d,%0d,%0d,%0d]", got_O[0], got_O[1], got_O[2], got_O[3]);
        end else begin
            $display("[PASS] O = [%0d,%0d,%0d,%0d]", got_O[0], got_O[1], got_O[2], got_O[3]);
        end

        // 检查 filter 索引
        $display("threshold = %0d", score_threshold);
        $display("filter indices count = %0d", fcnt);
        for (j = 0; j < fcnt; j = j + 1)
            $display("  idx[%0d] = %0d", j, got_idx[j]);

        if (score_threshold == 1 && fcnt == 3 &&
            got_idx[0] == exp_idx_1[0] && got_idx[1] == exp_idx_1[1] && got_idx[2] == exp_idx_1[2]) begin
            $display("[PASS] D 项筛选输出正确");
        end else if (score_threshold != 1) begin
            $display("[INFO] threshold 非 1，请人工核对 indices");
        end else begin
            $display("[FAIL] D 项筛选输出不匹配，期望 [1,2,7]");
        end

        $finish;
    end

    initial begin #20000000; $display("[FAIL] global timeout"); $finish; end

endmodule
