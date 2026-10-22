# miniPIM

LLM decode용 bank-level PIM(Processing-in-Memory) GEMV 가속기를 Verilog로 설계하는 프로젝트입니다.
현재는 DRAM 뱅크 하나에 해당하는 데이터패스(뱅크 메모리, 8-lane INT8 SIMD MAC, 결과 버퍼)까지 구현하고 검증했습니다.

## 배경

LLM 추론의 decode 단계는 토큰마다 큰 가중치 행렬에 벡터 하나를 곱하는 GEMV입니다. INT8 가중치 1바이트가 곱셈과 덧셈에 한 번만 쓰이므로 연산 강도가 약 2 ops/byte에 그치고, 성능은 연산기보다 메모리 대역폭에 의해 결정됩니다(memory-bound).

DRAM 내부에서는 여러 뱅크가 동시에 데이터를 읽을 수 있어서 내부 대역폭이 칩 외부 I/O 대역폭보다 훨씬 큽니다. PIM은 연산기를 뱅크 옆에 두어 이 내부 대역폭을 연산에 직접 활용합니다. Samsung HBM-PIM과 SK hynix AiM이 이런 구조의 실제 사례이고, miniPIM은 이를 "뱅크별 INT8 SIMD MAC + Global Buffer" 구조로 단순화했습니다.

## 구현 현황

| 모듈 | 역할 | 상태 |
|---|---|---|
| `pim_mac` | 스칼라 INT8 MAC | 완료 |
| `pim_simd_mac` | 8-lane INT8 SIMD MAC, 3단 파이프라인 | 완료 |
| `pim_bank_array` | DRAM 뱅크 셀 배열 (64 row × 32 column × 64bit), 동기 읽기 | 완료 |
| `pim_global_buffer` | x 벡터 버퍼 (32 × 64bit) | 완료 |
| `pim_bank_unit` | 뱅크 메모리 + SIMD MAC + 결과 버퍼 | 완료 |
| 뱅크 컨트롤러 | ACT/RD/PRE 순서와 DRAM 타이밍(tRCD, tRP)을 지키는 FSM | 예정 |
| 명령 인터페이스 | 명령 FIFO와 디코더 | 예정 |
| 멀티 뱅크 최상위 | 뱅크 여러 개를 동시에 구동 (bank-level parallelism) | 예정 |
| 후처리 | 재양자화, LUT 기반 활성함수 | 예정 |
| 성능 분석·합성 | 성능 카운터, FPGA 합성 결과 | 예정 |

인터페이스, 레이턴시, 타이밍 다이어그램은 [docs/spec.md](docs/spec.md)에 정리했습니다.

## 데이터 매핑

y = W·x (W: M×K, 모두 INT8)를 다음과 같이 배치합니다.

- W의 i번째 행은 뱅크 `i mod NUM_BANKS`의 DRAM row `i div NUM_BANKS`에 저장합니다.
- DRAM row 하나는 32 column × 64bit = INT8 256개이므로, K ≤ 256이면 W의 행 하나가 DRAM row 하나에 들어갑니다.
- column 워드 하나에는 INT8 8개가 들어가고, lane 0이 LSB 쪽입니다.
- 이렇게 배치하면 모든 뱅크가 같은 row 번호를 동시에 읽어서 y의 원소 NUM_BANKS개를 한 번에 계산할 수 있습니다. 이 동작은 멀티 뱅크 최상위 모듈에서 구현할 예정이고, 현재 테스트는 뱅크 1개(NUM_BANKS = 1) 기준입니다.

## 디렉토리 구조

```
rtl/    Verilog RTL (Verilog-2001, 모듈 하나당 파일 하나)
tb/     self-checking 테스트벤치
model/  Python 골든 모델 (테스트 데이터 hex 파일과 기대값 생성)
sim/    Makefile
docs/   마이크로아키텍처 명세
```

## 실행 방법

필요한 도구: Icarus Verilog 12, Verilator 5 (lint), Python 3 + numpy

```bash
cd sim
make test                                  # 모든 테스트벤치 실행
make lint-all                              # 모든 모듈 Verilator lint
make sim TOP=tb_pim_bank_unit MODE=maxneg  # 테스트벤치 하나 실행 (MODE: random, maxpos, maxneg, zero)
make wave TOP=tb_pim_bank_unit             # 파형 보기 (GTKWave)
```

`make test` 실행 결과:

```
tb_pim_mac           PASS
tb_pim_mac_simple    PASS
tb_pim_simd_mac      PASS
tb_pim_bank_array    PASS
tb_pim_bank_unit     PASS
```

hex 파일이 필요한 테스트벤치는 `make sim`이 실행 직전에 `model/golden_gemv.py`로 hex 파일을 생성합니다.

## 검증

| 테스트벤치 | 검사 내용 |
|---|---|
| `tb_pim_mac` | 스칼라 MAC의 32개·11개짜리 내적, (-128)×(-128) 포함 |
| `tb_pim_simd_mac` | column 1개짜리 내적, 음수 전용 최대 길이 내적, 랜덤 길이와 쉬는 사이클, 쉬지 않는 연속 입력 |
| `tb_pim_bank_array` | 읽기 레이턴시 1과 값 유지, 2048개 주소 전체 쓰기·읽기, hex 파일 로드와 주소 배치 |
| `tb_pim_bank_unit` | Python(numpy) 기대값과 비교, 서로 다른 row 연속 계산, K = 8, column 사이 쉬는 사이클, acc_valid 레이턴시와 개수 |

- 기대값은 테스트벤치가 직접 계산하거나 Python 골든 모델이 만든 파일에서 읽어 옵니다.
- 비교는 X/Z를 놓치지 않도록 `!==`로 하고, 모든 테스트벤치에 TIMEOUT 감시가 있습니다.
- 모든 모듈은 Verilator `-Wall` lint 경고 0개입니다.

## 현재 한계

- 뱅크 하나의 데이터패스만 구현했고, 제어 신호는 아직 테스트벤치가 직접 넣습니다.
- DRAM 타이밍(tRCD, tRP 등)은 아직 반영하지 않았습니다. 뱅크 메모리는 저장만 하고, 타이밍은 뱅크 컨트롤러에서 처리할 예정입니다.
- 합성 결과(면적, 동작 주파수)는 아직 없습니다.

## 코딩 규칙

[lowRISC Verilog Coding Style Guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md)를 바탕으로 합니다. 입력 `_i`, 출력 `_o`, 레지스터 `_q`, active-low 비동기 리셋 `rst_ni`, 이름 기반 포트 연결, 파라미터화된 폭을 사용합니다.

## 참고 자료

- S. Lee et al., "Hardware Architecture and Software Stack for PIM Based on Commercial DRAM Technology: Industrial Product," ISCA 2021.
- M. He et al., "Newton: A DRAM-maker's Accelerator-in-Memory (AiM) Architecture for Machine Learning," MICRO 2020.

## AI 도구 사용

설계 학습과 일부 RTL·테스트벤치 작성에 AI 코딩 도구(Claude 등)를 보조로 사용했습니다.
