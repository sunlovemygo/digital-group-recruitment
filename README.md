# 集协数字组招新 · Attention IP 入门项目

这是一个面向招新的轻量级数字 IC 入门项目：用 Verilog 实现一个单头 Attention 加速器 IP，并通过仿真验证。

## 项目规模

- 序列长度 `S = 8`
- 每个 token 维度 `d = 4`
- 输入/输出：8-bit 有符号定点
- 权重：4.4 定点（16 代表 1.0）

## 核心内容

本项目完整实现了 Attention 机制的三个步骤：

1. **Score = Q · K^T**：每个 token 做 4 维点积。
2. **Softmax**：先求 `xmax`，再查 LUT 得到 `exp(score − xmax)`，归一化为权重。
3. **Output = Σ weight × V**：加权求和后做带符号四舍五入归一化。

控制核心是一个 **10 状态 FSM**，带 `data_ready` 反压信号。

## 目录结构

```
rtl/          # 设计代码
  attention_ip.v        # 你的主实现（骨架版已填完）
  attention_ip_ref.v    # 参考实现
  attention_ip_online_softmax.v  # Online Softmax 改进版
  ...

tb/           # 测试平台
  tb_attention_smoke.v   # 冒烟测试（固定算例）
  tb_attention_random.v  # 随机测试（100 组向量）
  ...

model/        # Python 黄金模型与随机激励生成
  golden_model.py
  gen_random_tb.py

sim.bat       # 一键跑冒烟测试
sim_random.bat# 一键跑随机测试
wave_smoke.bat# 打开冒烟测试波形
wave_random.bat
Makefile
```

## 运行方式

需要安装 [Icarus Verilog](https://steveicarus.github.io/iverilog/)（iverilog）和 GTKWave。

```bash
# 冒烟测试
sim.bat

# 随机测试
sim_random.bat

# 看波形（先跑 sim.bat 生成 out.vcd）
wave_smoke.bat
```

冒烟测试期望输出：

```text
score_buf = [1,2,3,-1,0,1,0,2]
xmax = 3
weight_buf(4.4) = [2,6,16,0,1,2,1,6]
L = 34
ACC = [87,77,33,63]
==== SMOKE TEST PASS ====
```

最终输出 `O = [3, 2, 1, 2]`。

## 招新说明

如果你能看到这里，说明你已经具备了：

- 基础的数字电路知识
- 一定的 Verilog 语法基础
- 对状态机、定点数、存储器组织有概念

加入数字组后，你会进一步学习：

- 更复杂的流水线设计
- FPGA 上板验证
- 综合、时序分析、面积优化
- SystemVerilog / UVM 验证方法学

欢迎提交 Issue 或 PR！
