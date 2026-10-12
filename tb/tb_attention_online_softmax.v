`timescale 1ns / 1ps

//=============================================================================
// tb_attention_online_softmax —— 验证 Online Softmax 版 Attention
// 期望输出与原 golden_model 一致：O = [3, 2, 1, 2]
//=============================================================================
module tb_attention_online_softmax;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg q_valid = 1'b0, kv_valid = 1'b0;
    reg signed [7:0] q_in = 8'sd0, k_in = 8'sd0, v_in = 8'sd0;
    wire data_ready;
    wire out_valid;
    wire done;
    wire signed [7:0] out_data;

    attention_ip_online_softmax dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .data_ready(data_ready),
        .out_data(out_data), .out_valid(out_valid), .done(done)
    );

    always #5 clk = ~clk;
    integer i, wait_cnt, errors;
    reg signed [7:0] q_vec [0:3];
    reg signed [7:0] KF [0:31];
    reg signed [7:0] VF [0:31];
    reg signed [7:0] expected [0:3];
    reg signed [7:0] got [0:3];

    initial begin
        q_vec[0]=8'sd1; q_vec[1]=8'sd2; q_vec[2]=-8'sd1; q_vec[3]=8'sd0;
        KF[0]=8'sd1; KF[1]=8'sd0; KF[2]=8'sd0; KF[3]=8'sd0;
        KF[4]=8'sd0; KF[5]=8'sd1; KF[6]=8'sd0; KF[7]=8'sd0;
        KF[8]=8'sd1; KF[9]=8'sd1; KF[10]=8'sd0; KF[11]=8'sd0;
        KF[12]=8'sd0; KF[13]=8'sd0; KF[14]=8'sd1; KF[15]=8'sd0;
        KF[16]=8'sd0; KF[17]=8'sd0; KF[18]=8'sd0; KF[19]=8'sd1;
        KF[20]=8'sd2; KF[21]=8'sd0; KF[22]=8'sd1; KF[23]=8'sd0;
        KF[24]=8'sd1; KF[25]=8'sd0; KF[26]=8'sd1; KF[27]=8'sd0;
        KF[28]=8'sd2; KF[29]=8'sd0; KF[30]=8'sd0; KF[31]=8'sd0;
        VF[0]=8'sd4; VF[1]=8'sd2; VF[2]=8'sd0; VF[3]=8'sd1;
        VF[4]=8'sd1; VF[5]=8'sd6; VF[6]=8'sd2; VF[7]=8'sd0;
        VF[8]=8'sd3; VF[9]=8'sd1; VF[10]=8'sd1; VF[11]=8'sd2;
        VF[12]=8'sd0; VF[13]=8'sd0; VF[14]=8'sd5; VF[15]=8'sd3;
        VF[16]=8'sd2; VF[17]=8'sd2; VF[18]=8'sd2; VF[19]=8'sd2;
        VF[20]=8'sd5; VF[21]=8'sd0; VF[22]=8'sd1; VF[23]=8'sd1;
        VF[24]=8'sd1; VF[25]=8'sd1; VF[26]=8'sd1; VF[27]=8'sd1;
        VF[28]=8'sd2; VF[29]=8'sd3; VF[30]=8'sd0; VF[31]=8'sd4;
        expected[0]=8'sd3; expected[1]=8'sd2; expected[2]=8'sd1; expected[3]=8'sd2;
    end

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

    task run_once(input integer id);
        begin
            $display("---- online task %0d ----", id);
            @(posedge clk);
            while (!data_ready) @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            send_q;
            send_kv;
            wait_cnt = 0;
            while (!done && wait_cnt < 2000) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end
            if (done) $display("[PASS] done at cycle %0d", wait_cnt);
            else begin
                $display("[FAIL] no done");
                errors = errors + 1;
            end
            $display("  L=%0d, ACC=[%0d,%0d,%0d,%0d]", dut.L, dut.ACC[0], dut.ACC[1], dut.ACC[2], dut.ACC[3]);
            $display("  O_buf=[%0d,%0d,%0d,%0d]", dut.O_buf[0], dut.O_buf[1], dut.O_buf[2], dut.O_buf[3]);
            for (i = 0; i < 4; i = i + 1)
                if (dut.O_buf[i] !== expected[i]) begin
                    $display("[FAIL] O_buf[%0d]=%0d, expected=%0d", i, dut.O_buf[i], expected[i]);
                    errors = errors + 1;
                end
        end
    endtask

    initial begin
        $dumpfile("build/online.vcd");
        $dumpvars(0, tb_attention_online_softmax);
        errors = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        run_once(1);
        run_once(2);
        if (errors == 0) $display("==== ONLINE SOFTMAX TEST PASS ====");
        else             $display("==== ONLINE SOFTMAX TEST FAIL (%0d) ====", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("==== ONLINE SOFTMAX TEST FAIL (timeout) ====");
        $finish;
    end
endmodule
