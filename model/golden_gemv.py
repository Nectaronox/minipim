#!/usr/bin/env python3
"""miniPIM GEMV 골든 모델: 랜덤 W(MxK), x(K) 생성 -> 뱅크별 hex, GB hex, 기대값 hex"""
import argparse
import numpy as np


def pack_word(vals, data_w=8):
    """lane 0이 LSB 쪽에 오도록 부호 있는 정수들을 한 워드로 묶는다."""
    mask = (1 << data_w) - 1
    word = 0
    for i, v in enumerate(vals):
        word |= (int(v) & mask) << (i * data_w)   # 음수는 & mask로 2의 보수 비트패턴이 된다
    return word


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--M", type=int, default=64)
    p.add_argument("--K", type=int, default=256)
    p.add_argument("--banks", type=int, default=4)
    p.add_argument("--lanes", type=int, default=8)
    p.add_argument("--rows", type=int, default=64)   # 뱅크당 DRAM row 수
    p.add_argument("--cols", type=int, default=32)   # row당 column 수
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--mode", default="random", choices=["random", "maxpos", "maxneg", "zero"])
    p.add_argument("--out", default=".")
    a = p.parse_args()

    assert a.K % a.lanes == 0 and a.K <= a.cols * a.lanes, "K 조건 위반"
    assert a.M % a.banks == 0 and a.M // a.banks <= a.rows, "M 조건 위반"

    rng = np.random.default_rng(a.seed)
    if a.mode == "random":
        W = rng.integers(-128, 128, size=(a.M, a.K), dtype=np.int64)
        x = rng.integers(-128, 128, size=a.K, dtype=np.int64)
    elif a.mode == "maxpos":      # (-128)*(-128) 누적: 가장 큰 양수
        W = np.full((a.M, a.K), -128, dtype=np.int64); x = np.full(a.K, -128, dtype=np.int64)
    elif a.mode == "maxneg":      # (-128)*127 누적: 가장 작은 음수
        W = np.full((a.M, a.K), -128, dtype=np.int64); x = np.full(a.K, 127, dtype=np.int64)
    else:
        W = np.zeros((a.M, a.K), dtype=np.int64); x = np.zeros(a.K, dtype=np.int64)

    y = W @ x
    assert np.all(np.abs(y) < 2**31), "INT32 누산기 범위 초과"

    ncols = a.K // a.lanes
    hexw = a.lanes * 2                    # 64bit -> 16자리
    zero = [0] * a.lanes
    for b in range(a.banks):
        with open(f"{a.out}/w_bank{b}.hex", "w") as f:
            for r in range(a.rows):
                for c in range(a.cols):
                    i = r * a.banks + b   # 이 (bank, row)에 저장되는 W의 행 번호
                    vals = W[i, c*a.lanes:(c+1)*a.lanes] if (i < a.M and c < ncols) else zero
                    f.write(f"{pack_word(vals):0{hexw}x}\n")
    with open(f"{a.out}/x_gb.hex", "w") as f:
        for c in range(a.cols):
            vals = x[c*a.lanes:(c+1)*a.lanes] if c < ncols else zero
            f.write(f"{pack_word(vals):0{hexw}x}\n")
    with open(f"{a.out}/y_expected.hex", "w") as f:
        for v in y:
            f.write(f"{int(v) & 0xFFFFFFFF:08x}\n")
    print(f"[golden] M={a.M} K={a.K} ncols={ncols} banks={a.banks} seed={a.seed} mode={a.mode}")


if __name__ == "__main__":
    main()
