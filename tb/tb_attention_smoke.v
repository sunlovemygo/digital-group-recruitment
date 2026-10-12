`timescale 1ns / 1ps

//=============================================================================
// tb_attention_smoke —— v2 冒烟 + 数值核对
// 激励：规范算例 q=[1,2,-1,0]，K/V 见 golden_model.py 的 canonical 向量。
// 期望（来自 golden_model.py，v2 算法）：
//   score_buf = [1,2,3,-1,0,1,0,2]
//   xmax = 3，weight_buf(4.4定点) = [2,6,16,0,1,2,1,6]
//   L = 34，ACC = [87,77,33,63]
//   out_data = [3,2,1,2]
// 注：骨架未填计算时内部为 0；填完对应增量后，打印值应逐项对上。
//=============================================================================
module tb_attention_smoke;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg q_valid = 1'b0, kv_valid = 1'b0;
    reg signed [7:0] q_in = 8'sd0, k_in = 8'sd0, v_in = 8'sd0;
    wire                 data_ready;
    wire                 out_valid;
    wire                 done;
    wire signed [7:0]  out_data;

    attention_ip dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .data_ready(data_ready),
        .out_data(out_data), .out_valid(out_valid), .done(done)
    );
    always #5 clk = ~clk;   // 100 MHz
    integer i, j, wait_cnt, errors;

    // 规范算例数据
    reg signed [7:0] q_vec [0:3];
    reg signed [7:0] KF [0:31];   // 展平 K[t][d]，索引 t*4 + d
    reg signed [7:0] VF [0:31];   // 展平 V[t][d]
    initial begin
        q_vec[0]=8'sd1; q_vec[1]=8'sd2; q_vec[2]=-8'sd1; q_vec[3]=8'sd0;
        // K (8x4)，逐元素初始化（iverilog 不支持数组部分赋值）
        KF[0]=8'sd1; KF[1]=8'sd0; KF[2]=8'sd0; KF[3]=8'sd0;
        KF[4]=8'sd0; KF[5]=8'sd1; KF[6]=8'sd0; KF[7]=8'sd0;
        KF[8]=8'sd1; KF[9]=8'sd1; KF[10]=8'sd0; KF[11]=8'sd0;
        KF[12]=8'sd0; KF[13]=8'sd0; KF[14]=8'sd1; KF[15]=8'sd0;
        KF[16]=8'sd0; KF[17]=8'sd0; KF[18]=8'sd0; KF[19]=8'sd1;
        KF[20]=8'sd2; KF[21]=8'sd0; KF[22]=8'sd1; KF[23]=8'sd0;
        KF[24]=8'sd1; KF[25]=8'sd0; KF[26]=8'sd1; KF[27]=8'sd0;
        KF[28]=8'sd2; KF[29]=8'sd0; KF[30]=8'sd0; KF[31]=8'sd0;
        // V (8x4)
        VF[0]=8'sd4; VF[1]=8'sd2; VF[2]=8'sd0; VF[3]=8'sd1;
        VF[4]=8'sd1; VF[5]=8'sd6; VF[6]=8'sd2; VF[7]=8'sd0;
        VF[8]=8'sd3; VF[9]=8'sd1; VF[10]=8'sd1; VF[11]=8'sd2;
        VF[12]=8'sd0; VF[13]=8'sd0; VF[14]=8'sd5; VF[15]=8'sd3;
        VF[16]=8'sd2; VF[17]=8'sd2; VF[18]=8'sd2; VF[19]=8'sd2;
        VF[20]=8'sd5; VF[21]=8'sd0; VF[22]=8'sd1; VF[23]=8'sd1;
        VF[24]=8'sd1; VF[25]=8'sd1; VF[26]=8'sd1; VF[27]=8'sd1;
        VF[28]=8'sd2; VF[29]=8'sd3; VF[30]=8'sd0; VF[31]=8'sd4;
    end

    //-----------------------------------------------------------------
    // 发送 Q：4 拍，规范 q=[1,2,-1,0]
    //-----------------------------------------------------------------
    task send_q;
        begin
            for (i = 0; i < 4; i = i + 1) begin
                while (!data_ready) @(posedge clk);
                q_in   <= q_vec[i];
                q_valid <= 1'b1;
                @(posedge clk);
            end
            q_valid <= 1'b0;
        end
    endtask
    //-----------------------------------------------------------------
    // 发送 K/V：32 拍，顺序 K0V0..K7V7（每个 Token 4 拍）
    //-----------------------------------------------------------------
    task send_kv;
        begin
            for (i = 0; i < 32; i = i + 1) begin
                while (!data_ready) @(posedge clk);
                k_in    <= KF[i];
                v_in    <= VF[i];
                kv_valid <= 1'b1;
                @(posedge clk);
            end
            kv_valid <= 1'b0;
        end
    endtask
    //-----------------------------------------------------------------
    // 等 done，带超时
    //-----------------------------------------------------------------
    task wait_done(input integer timeout);
        begin
            wait_cnt = 0;
            while (!done && wait_cnt < timeout) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end
            if (done) $display("[PASS] done asserted at cycle %0d", wait_cnt);
            else begin
                $display("[FAIL] no done within %0d cycles", timeout);
                errors = errors + 1;
            end
        end
    endtask
    //-----------------------------------------------------------------
    // 打印内部中间结果（填完对应增量后逐项核对）
    //-----------------------------------------------------------------
    task report;
        begin
            $display("  score_buf = [%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
                dut.score_buf[0],dut.score_buf[1],dut.score_buf[2],dut.score_buf[3],
                dut.score_buf[4],dut.score_buf[5],dut.score_buf[6],dut.score_buf[7]);
            $display("  xmax = %0d", dut.xmax);
            $display("  weight_buf(4.4) = [%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
                dut.weight_buf[0],dut.weight_buf[1],dut.weight_buf[2],dut.weight_buf[3],
                dut.weight_buf[4],dut.weight_buf[5],dut.weight_buf[6],dut.weight_buf[7]);
            $display("  L = %0d", dut.L);
            $display("  ACC = [%0d,%0d,%0d,%0d]",
                dut.ACC[0],dut.ACC[1],dut.ACC[2],dut.ACC[3]);
        end
    endtask

    task run_once(input integer id);
        begin
            $display("---- task %0d ----", id);
            @(posedge clk);
            while (!data_ready) @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            send_q;
            send_kv;
            wait_done(2000);
            report;
        end
    endtask

    initial begin
        $dumpfile("build/out.vcd");
        $dumpvars(0, tb_attention_smoke);
        errors = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        run_once(1);
        run_once(2);   // 验证 done 后能回 IDLE 并再次启动
        if (errors == 0) $display("==== SMOKE TEST PASS ====");
        else             $display("==== SMOKE TEST FAIL (%0d) ====", errors);
        $finish;
    end
    // 全局看门狗
    initial begin
        #200000;
        $display("[FAIL] global timeout");
        $display("==== SMOKE TEST FAIL ====");
        $finish;
    end
endmodule
