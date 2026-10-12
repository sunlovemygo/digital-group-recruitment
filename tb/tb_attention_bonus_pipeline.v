`timescale 1ns / 1ps
//=============================================================================
// tb_attention_bonus_pipeline —— B 项加分测试
//-----------------------------------------------------------------------------
// 验证 attention_ip_bonus_pipeline 与参考实现输出一致，并统计从 start 到 done
// 的周期数，展示状态合并后的周期收益。
//=============================================================================
module tb_attention_bonus_pipeline;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg q_valid = 1'b0, kv_valid = 1'b0;
    reg signed [7:0] q_in = 8'sd0, k_in = 8'sd0, v_in = 8'sd0;
    wire data_ready, out_valid, done;
    wire signed [7:0] out_data;

    attention_ip_bonus_pipeline dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .data_ready(data_ready),
        .out_data(out_data), .out_valid(out_valid), .done(done)
    );

    always #5 clk = ~clk;

    // 规范算例数据
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

    integer i, j;
    reg signed [7:0] exp_O [0:3];
    reg signed [7:0] got [0:3];
    integer ocnt, cc, start_cycle, end_cycle;

    initial begin
        exp_O[0] = 8'sd3; exp_O[1] = 8'sd2; exp_O[2] = 8'sd1; exp_O[3] = 8'sd2;
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
        $dumpfile("build/pipeline.vcd");
        $dumpvars(0, tb_attention_bonus_pipeline);
        $display("============================================");
        $display(" tb_attention_bonus_pipeline: cycle opt test ");
        $display("============================================");

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        @(posedge clk);
        while (!data_ready) @(posedge clk);
        start <= 1'b1;
        start_cycle = $time / 10;   // 周期数 = time / (clock period 10ns)
        @(posedge clk);
        start <= 1'b0;

        send_q;
        send_kv;

        ocnt = 0; cc = 0;
        while (ocnt < 4 && cc < 5000) begin
            @(posedge clk); cc = cc + 1;
            if (out_valid) begin
                got[ocnt] = out_data;
                ocnt = ocnt + 1;
            end
            if (done) end_cycle = $time / 10;
        end

        if (ocnt < 4) begin
            $display("[FAIL] 未收到 4 拍 out_valid");
        end else begin
            $display("got O = [%0d,%0d,%0d,%0d]", got[0], got[1], got[2], got[3]);
            $display("exp O = [%0d,%0d,%0d,%0d]", exp_O[0], exp_O[1], exp_O[2], exp_O[3]);
            if (got[0]==exp_O[0] && got[1]==exp_O[1] && got[2]==exp_O[2] && got[3]==exp_O[3]) begin
                $display("[PASS] B 项流水线版输出正确");
            end else begin
                $display("[FAIL] 输出不匹配");
            end
            $display("start cycle = %0d, done cycle = %0d, total cycles = %0d", start_cycle, end_cycle, end_cycle - start_cycle);
        end

        $finish;
    end

    initial begin #20000000; $display("[FAIL] global timeout"); $finish; end

endmodule
