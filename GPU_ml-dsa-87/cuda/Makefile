# ML-DSA-87 KeyGen CUDA 베이스라인 빌드
# 주의: 여러 .cu 에 흩어진 __device__ 함수를 서로 호출하므로 -rdc=true 필수.
#       GPU 아키텍처(ARCH)는 본인 카드에 맞게 조정하세요 (예: sm_80, sm_86, sm_89, sm_90).

NVCC  ?= nvcc
ARCH  ?= -arch=sm_70
NVCCFLAGS = -O2 -rdc=true $(ARCH)

SRC = fips202.cu reduce.cu ntt.cu rounding.cu poly.cu polyvec.cu \
      packing.cu symmetric-shake.cu keygen.cu main.cu

TARGET = mldsa87_keygen_cuda

$(TARGET): $(SRC)
	$(NVCC) $(NVCCFLAGS) $(SRC) -o $@

.PHONY: run clean
run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)
