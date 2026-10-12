`timescale 1ns / 1ps
//=============================================================================
// tb_show_output —— 只跑规范算例，把中间结果和最终 O 打印到终端
// 不用 GTKWave，直接看 $display 输出
//=============================================================================
module tb_show_output;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg q_valid = 1'b0, kv_valid = 1'b0;
    reg signed [7:0] q_in = 8'sd0, k_in = 8'sd0, v_in = 8'sd0;
    wire data_ready, out_valid, done;
    wire signed [7:0] out_data;

    attention_ip_ref dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .q_in(q_in), .k_in(k_in), .v_in(v_in),
        .q_valid(q_valid), .kv_valid(kv_valid),
        .data_ready(data_ready), .out_data(out_data),
        .out_valid(out_valid), .done(done)
    );

    always #5 clk = ~clk;

    task send_q;
        begin
            q_valid <= 1'b1;
            q_in <= 8'sd1;  @(posedge clk);
            q_in <= 8'sd2;  @(posedge clk);
            q_in <= -8'sd1; @(posedge clk);
            q_in <= 8'sd0;  @(posedge clk);
            q_valid <= 1'b0;
        end
    endtask

    task send_kv;
        begin
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
        end
    endtask

    integer i;
    reg signed [7:0] got [0:3];
    integer ocnt;

    initial begin
        $display("============================================");
        $display(" tb_show_output: canonical case O = ? ");
        $display("============================================");

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        while (!data_ready) @(posedge clk);
        start <= 1'b1; @(posedge clk); start <= 1'b0;

        send_q;
        send_kv;

        // 等待 S_OUTPUT 完成，期间捕获 out_data
        ocnt = 0;
        while (ocnt < 4) begin
            @(posedge clk);
            // 在 out_valid 有效时捕获输出
            if (out_valid) begin
                got[ocnt] = out_data;
                ocnt = ocnt + 1;
            end
        end

        // 此时已回到 IDLE，O_buf 和内部信号保持最后一次计算结果
        $display("score  = [%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
            dut.score_buf[0], dut.score_buf[1], dut.score_buf[2], dut.score_buf[3],
            dut.score_buf[4], dut.score_buf[5], dut.score_buf[6], dut.score_buf[7]);
        $display("xmax   = %0d", dut.xmax);
        $display("weight = [%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
            dut.weight_buf[0], dut.weight_buf[1], dut.weight_buf[2], dut.weight_buf[3],
            dut.weight_buf[4], dut.weight_buf[5], dut.weight_buf[6], dut.weight_buf[7]);
        $display("L      = %0d", dut.L);
        $display("ACC    = [%0d,%0d,%0d,%0d]",
            dut.ACC[0], dut.ACC[1], dut.ACC[2], dut.ACC[3]);
        $display("O_buf  = [%0d,%0d,%0d,%0d]",
            dut.O_buf[0], dut.O_buf[1], dut.O_buf[2], dut.O_buf[3]);
        $display("out_data sequence = [%0d,%0d,%0d,%0d]", got[0], got[1], got[2], got[3]);

        $finish;
    end

    initial begin #20000000; $display("[FAIL] global timeout"); $finish; end

endmodule
