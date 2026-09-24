/*
 * main_ref.c  ---  CPU 참조 (원본 clean, 무수정)
 *   고정 시드(randombytes.c)로 원본 KeyGen 을 실행하고 pk/sk 16진수를 출력.
 *   출력 형식은 CUDA main.cu 와 동일 → `diff` 로 바이트 일치 검증.
 */
#include "api.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void print_hex(const char *label, const uint8_t *b, size_t n) {
    printf("%s:\n", label);
    for (size_t i = 0; i < n; i++) {
        printf("%02x", b[i]);
        if ((i + 1) % 32 == 0) {
            printf("\n");
        }
    }
    if (n % 32) {
        printf("\n");
    }
}

int main(void) {
    const size_t PKB = PQCLEAN_MLDSA87_CLEAN_CRYPTO_PUBLICKEYBYTES;
    const size_t SKB = PQCLEAN_MLDSA87_CLEAN_CRYPTO_SECRETKEYBYTES;

    uint8_t *pk = (uint8_t *)malloc(PKB);
    uint8_t *sk = (uint8_t *)malloc(SKB);

    /* 원본 함수 그대로 (내부에서 결정론적 randombytes 사용) */
    PQCLEAN_MLDSA87_CLEAN_crypto_sign_keypair(pk, sk);

    fprintf(stderr, "=== ML-DSA-87 KeyGen (CPU reference, 원본 clean) ===\n");
    print_hex("pk", pk, PKB);
    print_hex("sk", sk, SKB);

    free(pk);
    free(sk);
    return 0;
}
