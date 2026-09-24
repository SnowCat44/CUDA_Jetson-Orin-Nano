# ML-DSA-87 KeyGen CPU 참조 빌드 (원본 clean, 무수정)
# CUDA 결과와 바이트 비교하기 위한 기준 실행 파일을 만듭니다.

CC ?= gcc
CFLAGS = -O2 -std=c99 -I.

REF = ntt.c reduce.c rounding.c poly.c polyvec.c packing.c \
      symmetric-shake.c sign.c fips202.c randombytes.c main_ref.c

TARGET = mldsa87_keygen_ref

$(TARGET): $(REF)
	$(CC) $(CFLAGS) $(REF) -o $@

.PHONY: run clean
run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)
