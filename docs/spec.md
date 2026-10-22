# miniPIM 마이크로아키텍처 명세

현재 구현된 범위는 DRAM 뱅크 하나에 해당하는 데이터패스입니다. 뱅크 컨트롤러, 명령 인터페이스, 멀티 뱅크 최상위 모듈은 아직 구현되지 않았습니다.

## 1. 파라미터

| 파라미터 | 기본값 | 의미 |
|---|---|---|
| `DATA_W` | 8 | 원소 폭 (INT8) |
| `LANES` | 8 | 64bit 워드 하나에 들어 있는 원소 수 |
| `WORD_W` | 64 | `DATA_W × LANES` |
| `ACC_W` | 32 | 누산기 폭 |
| `ROW_AW` | 6 | 뱅크당 DRAM row 64개 |
| `COL_AW` | 5 | row당 column 32개 |

## 2. 데이터 매핑 (y = W·x, W: M×K, INT8)

- W의 i번째 행은 뱅크 `i mod NUM_BANKS`의 DRAM row `i div NUM_BANKS`에 저장합니다.
- DRAM row 하나는 32 column × 64bit = INT8 256개이므로, K ≤ 256인 W의 행 하나가 DRAM row 하나에 들어갑니다.
- column 워드 하나에서 lane j는 비트 `[8j+7:8j]`를 차지하고, lane 0이 LSB 쪽입니다: `word[8j+7:8j] = W[i][8c + j]`.
- x는 Global Buffer에 같은 방식으로 32워드 × 64bit로 저장합니다.
- 뱅크 메모리의 주소는 `{row, col}`, 즉 `row × 32 + col`이고, hex 파일의 줄 번호와 같습니다.

## 3. 블록도

`pim_bank_unit`은 `pim_bank_array`, 제어 신호 지연 레지스터, `pim_simd_mac`, 결과 버퍼 `out_mem`으로 구성됩니다. `pim_global_buffer`는 바깥에 있고, 여러 뱅크가 공유하도록 설계했습니다.

```
 pim_global_buffer (32 x 64b) ------------- x ---------+
                                                       |
                                                       v
 pim_bank_array (2048 x 64b) ------------- w ---> pim_simd_mac ---- acc ----> out_mem (64 x 32b)
     ^                                           8 lanes, 3 stages           written at acc_valid
     |                                                 ^
     | arr_en, arr_we, row, col, wdata                 | valid, first, last
     |                                                 |
 controller (testbench for now) -- mac_issue --> 1-cycle delay
                                   first, last   (issue_q, first_q, last_q)
```

## 4. 모듈별 인터페이스

### 4.1 `pim_simd_mac`: 8-lane INT8 SIMD MAC

| 포트 | 방향 | 폭 | 설명 |
|---|---|---|---|
| `clk_i`, `rst_ni` | in | 1 | 클럭, active-low 비동기 리셋 |
| `valid_i` | in | 1 | 이번 사이클의 `w_i`, `x_i`가 유효함 |
| `first_i` | in | 1 | 내적의 첫 column (누산기를 새로 시작) |
| `last_i` | in | 1 | 내적의 마지막 column |
| `w_i`, `x_i` | in | 64 | INT8 8개씩 (lane 0이 LSB) |
| `done_o` | out | 1 | 내적 완료 펄스 (1사이클) |
| `acc_o` | out | 32 | 누산 결과 (signed) |

3단 파이프라인입니다: (A) lane별 곱셈 → (B) 8개 곱의 합 → (C) 누산. 매 사이클 column 하나를 받을 수 있고, 내적 사이에 쉬는 사이클 없이 다음 내적을 이어서 넣을 수 있습니다.

### 4.2 `pim_bank_array`: 뱅크 셀 배열

| 포트 | 방향 | 폭 | 설명 |
|---|---|---|---|
| `en_i` | in | 1 | 접근 enable |
| `we_i` | in | 1 | 1: 쓰기, 0: 읽기 |
| `row_i`, `col_i` | in | 6, 5 | 주소 |
| `wdata_i` | in | 64 | 쓰기 데이터 |
| `rdata_o` | out | 64 | 읽기 데이터 (`en_i` 다음 사이클에 유효) |

파라미터 `INIT_FILE`이 비어 있지 않으면 시뮬레이션 시작 시 `$readmemh`로 hex 파일을 로드합니다. 메모리 배열은 데이터 저장소라서 리셋하지 않습니다. ACT/PRE 순서와 DRAM 타이밍은 이 모듈이 아니라 컨트롤러가 지키도록 역할을 나눴습니다.

### 4.3 `pim_global_buffer`: x 벡터 버퍼

쓰기 포트 1개(`we_i`, `waddr_i`, `wdata_i`)와 읽기 포트 1개(`re_i`, `raddr_i`, `rdata_o`)를 가진 32 × 64bit 메모리입니다. 읽기 레이턴시를 뱅크 메모리와 같은 1사이클로 맞춰서, 같은 사이클에 읽기를 걸면 w와 x가 같은 사이클에 도착합니다.

### 4.4 `pim_bank_unit`: 뱅크 데이터패스

| 포트 | 방향 | 폭 | 설명 |
|---|---|---|---|
| `arr_en_i`, `arr_we_i`, `row_i`, `col_i`, `wdata_i` | in | | 뱅크 메모리 접근 |
| `mac_issue_i` | in | 1 | 이번 사이클의 뱅크 읽기를 MAC에 투입 |
| `mac_first_i`, `mac_last_i` | in | 1 | 내적의 첫 column / 마지막 column |
| `gb_rdata_i` | in | 64 | Global Buffer에서 읽은 x |
| `rdata_o` | out | 64 | 뱅크 메모리 일반 읽기 결과 |
| `acc_valid_o` | out | 1 | 내적 완료 펄스. 이 사이클에 `out_mem[row_i]`에 결과를 저장 |
| `out_re_i`, `out_raddr_i` | in | 1, 6 | 결과 버퍼 읽기 |
| `out_rdata_o` | out | 32 | 결과 버퍼 읽기 데이터 (`out_re_i` 다음 사이클에 유효) |

메모리 읽기에 1사이클이 걸리므로, `mac_issue_i`, `mac_first_i`, `mac_last_i`를 레지스터로 1사이클 늦춰서 `pim_simd_mac`에 넣습니다. 그래야 `valid`가 1인 사이클에 w와 x가 실제 데이터입니다.

## 5. 레이턴시

| 경로 | 사이클 |
|---|---|
| `pim_bank_array` 읽기 → `rdata_o` | 1 |
| `pim_global_buffer` 읽기 → `rdata_o` | 1 |
| `pim_simd_mac` `valid_i`(`last_i`) → `done_o` | 3 |
| `pim_bank_unit` 마지막 `mac_issue_i` → `acc_valid_o` | 4 (메모리 1 + MAC 3) |
| `acc_valid_o` → `out_mem[row_i]` 저장 | 같은 사이클의 끝 edge |
| `out_re_i` → `out_rdata_o` | 1 |

## 6. 타이밍 다이어그램: column 3개짜리 내적

```
cycle          0      1      2      3      4      5      6
mac_issue      1      1      1      0
mac_first      1      0      0
mac_last       0      0      1
col            0      1      2
w, x (read)           c0     c1     c2
issue_q               1      1      1      0
stage A (mul)                c0     c1     c2
stage B (sum)                       c0     c1     c2
acc_o                                      c0    c0+c1  c0+c1+c2
acc_valid_o                                              1
row_i          <---------------- held ------------------->
```

## 7. 인터페이스 약속

1. `pim_bank_array`의 `rdata_o`는 다음 읽기 전까지 값을 유지합니다. 쓰기 사이클에도 바뀌지 않습니다.
2. `mac_issue_i = 1`인 사이클에는 뱅크 읽기(`arr_en_i = 1`, `arr_we_i = 0`)와 Global Buffer 읽기(같은 column)를 함께 겁니다.
3. 내적을 시작한 뒤 `acc_valid_o`가 뜬 사이클이 끝날 때까지 `row_i`를 바꾸지 않습니다. 바꾸면 결과가 다른 row 칸에 저장됩니다.
4. column이 1개인 내적은 `mac_first_i`와 `mac_last_i`를 같은 사이클에 1로 줍니다.
5. column 사이에 `mac_issue_i = 0`인 쉬는 사이클이 있어도 됩니다. 누산에는 `valid`가 1인 사이클만 반영됩니다.

## 8. 검증

| 테스트벤치 | 검사 내용 |
|---|---|
| `tb_pim_mac` | 스칼라 MAC: 32개·11개짜리 내적, (-128)×(-128) 포함 |
| `tb_pim_mac_simple` | 스칼라 MAC 스모크 테스트 (3·4 + 5·6 + 7·9 = 105) |
| `tb_pim_simd_mac` | column 1개짜리 내적, 음수 전용(-128, -1) 최대 길이, 랜덤 길이와 쉬는 사이클, 쉬지 않는 연속 입력. 정답 FIFO로 출력 순서대로 비교하고 `done` 펄스 개수 확인 |
| `tb_pim_bank_array` | 매 사이클 "rdata = 마지막으로 읽은 주소의 값"을 검사해 읽기 레이턴시 1과 값 유지 확인. 2048개 주소 전체에 패턴과 반전 패턴 쓰기·읽기. Python이 만든 hex 파일 로드와 `row × 32 + col` 배치 확인 |
| `tb_pim_bank_unit` | Python(numpy) 정답과 비교: K = 256 두 row 연속, K = 8, column 사이 쉬는 사이클, 같은 row 재계산(덮어쓰기). `acc_valid_o` 레이턴시(4)와 펄스 개수 확인. 데이터 모드 4종(random, maxpos, maxneg, zero) |

모든 테스트벤치는 `!==`로 비교하고, TIMEOUT 감시를 두고, 마지막 줄에 `PASS` 또는 `FAIL (N errors)`를 출력합니다. 모든 모듈은 Verilator `-Wall` lint 경고 0개입니다.
