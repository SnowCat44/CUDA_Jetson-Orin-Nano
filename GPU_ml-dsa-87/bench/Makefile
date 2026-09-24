# ML-DSA-87 KeyGen 단계별 벤치마크 빌드
#
#   make cpu                 # CPU 계측판 (clock_gettime, µs)   → ../ref 원본 사용
#   make gpu ARCH=-arch=sm_86  # GPU 계측판 (clock64, cycles+µs) → ../cuda 포트 사용
#
# 실행:
#   ./keypair_bench                 # CPU: 단계별 µs (mean/median/min)
#   ./keygen_bench <gpu_clock_MHz>  # GPU: 단계별 cycles + µs  (예: ./keygen_bench 1410)

CC   ?= gcc
NVCC ?= nvcc
ARCH ?= -arch=sm_70

CFLAGS    = -O2 -std=c99 -I../ref
NVCCFLAGS = -O2 -rdc=true $(ARCH) -I../cuda

# --- CPU: 원본 clean(무수정) + 계측판 (randombytes/sign.c 불필요: 시드 내장) ---
CPU_SRC = ../ref/ntt.c ../ref/reduce.c ../ref/rounding.c ../ref/poly.c \
          ../ref/polyvec.c ../ref/packing.c ../ref/symmetric-shake.c \
          ../ref/fips202.c keypair_bench.c

# --- GPU: .cu 포트 + 계측 커널 (keygen.cu/main.cu 는 제외; 자체 커널/메인 보유) ---
GPU_SRC = ../cuda/fips202.cu ../cuda/reduce.cu ../cuda/ntt.cu ../cuda/rounding.cu \
          ../cuda/poly.cu ../cuda/polyvec.cu ../cuda/packing.cu \
          ../cuda/symmetric-shake.cu keygen_bench.cu

.PHONY: all cpu gpu clean
all: cpu gpu

cpu: keypair_bench
keypair_bench: $(CPU_SRC)
	$(CC) $(CFLAGS) $(CPU_SRC) -o $@

gpu: keygen_bench
keygen_bench: $(GPU_SRC)
	$(NVCC) $(NVCCFLAGS) $(GPU_SRC) -o $@

clean:
	rm -f keypair_bench keygen_bench
