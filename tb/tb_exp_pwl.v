`timescale 1ns / 1ps
//=============================================================================
// tb_exp_pwl —— F 项加分：对 exp_pwl 模块的独立测试
//-----------------------------------------------------------------------------
// 测试方法：
//   输入 u 从 0 到 64（步进 1，即 0 到 4.0，步进 1/16），
//   与理论值 round(exp(-u_real) * 16) 对比，统计最大误差。
//=============================================================================
module tb_exp_pwl;

    reg        clk = 0;
    reg        rst_n;
    reg        en;
    reg  [7:0] u;
    wire [15:0] y;
    wire        valid;

    exp_pwl uut (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .u     (u),
        .y     (y),
        .valid (valid)
    );

    always #5 clk = ~clk;

    // 理论值表：u = 0/16, 1/16, ..., 64/16 时 round(exp(-u)*16)
    reg [15:0] expected [0:64];
    initial begin
        expected[0]  = 16; expected[1]  = 15; expected[2]  = 14; expected[3]  = 13;
        expected[4]  = 12; expected[5]  = 12; expected[6]  = 11; expected[7]  = 10;
        expected[8]  = 10; expected[9]  = 9;  expected[10] = 9;  expected[11] = 8;
        expected[12] = 8;  expected[13] = 7;  expected[14] = 7;  expected[15] = 6;
        expected[16] = 6;  expected[17] = 6;  expected[18] = 5;  expected[19] = 5;
        expected[20] = 5;  expected[21] = 4;  expected[22] = 4;  expected[23] = 4;
        expected[24] = 4;  expected[25] = 3;  expected[26] = 3;  expected[27] = 3;
        expected[28] = 3;  expected[29] = 3;  expected[30] = 2;  expected[31] = 2;
        expected[32] = 2;  expected[33] = 2;  expected[34] = 2;  expected[35] = 2;
        expected[36] = 2;  expected[37] = 2;  expected[38] = 1;  expected[39] = 1;
        expected[40] = 1;  expected[41] = 1;  expected[42] = 1;  expected[43] = 1;
        expected[44] = 1;  expected[45] = 1;  expected[46] = 1;  expected[47] = 1;
        expected[48] = 1;  expected[49] = 1;  expected[50] = 1;  expected[51] = 0;
        expected[52] = 0;  expected[53] = 0;  expected[54] = 0;  expected[55] = 0;
        expected[56] = 0;  expected[57] = 0;  expected[58] = 0;  expected[59] = 0;
        expected[60] = 0;  expected[61] = 0;  expected[62] = 0;  expected[63] = 0;
        expected[64] = 0;
    end

    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer max_err  = 0;
    integer err;
    integer check_idx;

    // 1 拍延迟对齐：valid 拉高时，u_delay 保存了 1 拍前的输入
    reg [7:0] u_delay;
    always @(posedge clk) begin
        if (!rst_n)
            u_delay <= 8'd0;
        else if (en)
            u_delay <= u;
    end

    initial begin
        $display("============================================");
        $display(" tb_exp_pwl: PWL exp approximation test ");
        $display("============================================");

        rst_n = 0;
        en    = 0;
        u     = 8'd0;
        #20;
        rst_n = 1;
        #10;

        // 依次输入 u = 0..64
        for (check_idx = 0; check_idx <= 64; check_idx = check_idx + 1) begin
            @(posedge clk);
            en <= 1'b1;
            u  <= check_idx[7:0];
        end

        // 再输入 2 个 dummy 以排空流水线
        @(posedge clk); en <= 1'b0; u <= 8'd0;
        @(posedge clk);

        #50;

        if (fail_cnt == 0)
            $display("PWL EXP TEST PASS : %0d/%0d points", pass_cnt, pass_cnt + fail_cnt);
        else
            $display("PWL EXP TEST FAIL : %0d pass, %0d fail, max_err = %0d", pass_cnt, fail_cnt, max_err);

        $finish;
    end

    // 输出检查：exp_pwl 输出是 4.4 定点原始值，与 expected 比较前需 >>4
    reg [15:0] y_actual;
    always @(posedge clk) begin
        if (valid) begin
            y_actual = (y + 8) >> 4;  // 含四舍五入转回实际值
            err = $signed(y_actual) - $signed(expected[u_delay]);
            if (err < 0) err = -err;
            if (err > max_err) max_err = err;

            if (err <= 1) begin  // 允许最大误差 1（可调）
                pass_cnt = pass_cnt + 1;
                $display("PASS: u=%0d (raw), expected=%0d, got=%0d, err=%0d", u_delay, expected[u_delay], y_actual, err);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL: u=%0d (raw), expected=%0d, got=%0d, err=%0d", u_delay, expected[u_delay], y_actual, err);
            end
        end
    end

endmodule
