#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
golden_model.py —— Attention 定点参考实现（黄金模型）

用途：
  1. python3 golden_model.py           跑通手册里的 S=8 算例并打印
  2. python3 golden_model.py --random 5 --out vec
     生成 5 组随机测试向量（含期望输出），供 RTL 随机验证比对

注意：EXP_LUT 必须换成出题方给的表；定点格式（frac=8 即 Q7.8）如出题方
有约定，务必同步修改并在报告里说明。
"""
import os
import random
import sys

S, D = 8, 4

# v2 指数表（与 RTL exp_lut 一致）：u = xmax - score，u>=4 限幅 0
# 权重 = round(exp(-u) * 16)，4.4 定点：16 / 6 / 2 / 1 / 0
EXP_LUT = {0: 16, 1: 6, 2: 2, 3: 1, 4: 0}


def clamp_lut(u, lut):
    """u = xmax - score >= 0；超出 LUT 量程（u>4）时输出 0，与 RTL 限幅一致"""
    keys = sorted(lut.keys())
    if u < keys[0]:
        return lut[keys[0]]
    if u > keys[-1]:
        return lut[keys[-1]]
    return lut[u]


def div_round(acc, L):
    """与 RTL 一致的带符号四舍五入：(ACC ± L>>1) / L，向零截断（不是 round() 银行家舍入）"""
    if acc >= 0:
        return (acc + (L >> 1)) // L
    return -((- (acc - (L >> 1))) // L)


def attention(q, k, v, lut=EXP_LUT):
    """q: [D], k: [S][D], v: [S][D] -> dict(score, weight, L, ACC, O)"""
    score = [sum(q[d] * k[t][d] for d in range(D)) for t in range(S)]
    xmax = max(score)
    weight = [clamp_lut(xmax - s, lut) for s in score]
    L = sum(weight)
    ACC = [sum(weight[t] * v[t][d] for t in range(S)) for d in range(D)]
    O = [div_round(ACC[d], L) for d in range(D)]   # 8-bit 有符号，与 out_data 同口径
    return {"score": score, "weight": weight, "L": L,
            "ACC": ACC, "O": O}


def check_range(r, v):
    """O 是 V 的凸组合，必然落在 V 的最小/最大值之间，越界必有 bug"""
    for d in range(D):
        col = [v[t][d] for t in range(S)]
        assert min(col) <= r["O"][d] <= max(col), \
            "O[%d]=%.3f 超出 V 的范围 [%d, %d]" % (
                d, r["O"][d], min(col), max(col))


def write_vec(path, q, k, v, lut=EXP_LUT):
    """把一组向量和期望结果写进文本文件，方便 testbench 用 $fscanf 读取"""
    r = attention(q, k, v, lut)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# q\n" + " ".join(map(str, q)) + "\n")
        f.write("# k\n")
        for t in range(S):
            f.write(" ".join(map(str, k[t])) + "\n")
        f.write("# v\n")
        for t in range(S):
            f.write(" ".join(map(str, v[t])) + "\n")
        f.write("# exp_lut  u weight\n")
        for s in sorted(lut):
            f.write("%d %d\n" % (s, lut[s]))
        f.write("# expect_L\n%d\n" % r["L"])
        f.write("# expect_O\n" + " ".join(map(str, r["O"])) + "\n")


def demo():
    """手册 4.2 节的 S=8 算例"""
    q = [1, 2, -1, 0]
    k = [[1, 0, 0, 0], [0, 1, 0, 0], [1, 1, 0, 0], [0, 0, 1, 0],
         [0, 0, 0, 1], [2, 0, 1, 0], [1, 0, 1, 0], [2, 0, 0, 0]]
    v = [[4, 2, 0, 1], [1, 6, 2, 0], [3, 1, 1, 2], [0, 0, 5, 3],
         [2, 2, 2, 2], [5, 0, 1, 1], [1, 1, 1, 1], [2, 3, 0, 4]]
    r = attention(q, k, v)
    check_range(r, v)
    print("score  =", r["score"])
    print("xmax   =", max(r["score"]))
    print("weight =", r["weight"], " L =", r["L"])
    print("ACC    =", r["ACC"])
    print("O      =", r["O"])


def gen_random(n, outdir):
    os.makedirs(outdir, exist_ok=True)
    rnd = random.Random(2026)  # 固定种子，结果可复现
    for c in range(n):
        q = [rnd.randint(-128, 127) for _ in range(D)]
        k = [[rnd.randint(-128, 127) for _ in range(D)] for _ in range(S)]
        v = [[rnd.randint(-128, 127) for _ in range(D)] for _ in range(S)]
        path = os.path.join(outdir, "case_%02d.txt" % c)
        write_vec(path, q, k, v)
        r = attention(q, k, v)
        print("生成 %s  L=%d  O_fix=%s" % (path, r["L"], r["O_fix"]))


if __name__ == "__main__":
    args = sys.argv
    if "--random" in args:
        i = args.index("--random")
        n = int(args[i + 1]) if len(args) > i + 1 else 5
        outdir = args[args.index("--out") + 1] if "--out" in args else "vec"
        gen_random(n, outdir)
    else:
        demo()
