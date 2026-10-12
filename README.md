# Attention 加速器 IP 设计与验证

本项目是我在数字 IC / Verilog 学习过程中的练习作品：用 Verilog 实现一个单头 Attention 加速器 IP，并通过 Icarus Verilog 仿真验证。

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
  attention_ip.v        # 主实现（骨架版已填完）
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

## 学习收获

通过这个项目，我对以下内容有了更深的理解：

- 如何用 Verilog 描述状态机和数据通路
- 8-bit 有符号定点数与 4.4 定点的缩放关系
- Softmax 的数值稳定性：先求 `xmax` 再做 `exp`
- 阻塞赋值 `=` 与非阻塞赋值 `<=` 的适用场景
- 如何用 Python 黄金模型生成测试向量并比对 RTL 输出

## 后续可扩展方向

- 合并 EXP/UPDATE 状态，进一步缩短单任务周期
- 用 PWL（分段线性近似）替代 LUT，提高 exp 精度
- 加入因果 Mask（Causal Mask）支持自回归 Attention
- 把序列长度 `S` 参数化，支持更大规模
