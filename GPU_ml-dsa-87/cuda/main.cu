/*
 * main.cu  ---  호스트 하니스 (CUDA)
 *   고정 시드로 GPU KeyGen 커널을 실행하고 pk/sk 를 16진수로 출력합니다.
 *   stdout 에는 pk/sk 16진수만, 진단 메시지는 stderr 로 보냅니다.
 *   → ref 빌드 출력과 `diff` 로 바이트 일치 검증 가능.
 */
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cuda_runtime.h>
#include "params.h"

__global__ void keygen_kernel(const uint8_t *seed, uint8_t *pk, uint8_t *sk);

#define CK(call) do { cudaError_t e = (call); if (e != cudaSuccess) { \
    fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__, \
            cudaGetErrorString(e)); return 1; } } while (0)

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

    /* 고정 시드: 0x00,0x01,...,0x1f  (ref 빌드의 randombytes 와 반드시 동일) */
    uint8_t seed[SEEDBYTES];
    for (int i = 0; i < SEEDBYTES; i++) {
        seed[i] = (uint8_t)i;
    }

    uint8_t *pk = (uint8_t *)malloc(PKB);
    uint8_t *sk = (uint8_t *)malloc(SKB);
    uint8_t *d_seed = nullptr, *d_pk = nullptr, *d_sk = nullptr;

    CK(cudaMalloc(&d_seed, SEEDBYTES));
    CK(cudaMalloc(&d_pk, PKB));
    CK(cudaMalloc(&d_sk, SKB));
    CK(cudaMemcpy(d_seed, seed, SEEDBYTES, cudaMemcpyHostToDevice));

    keygen_kernel<<<1, 1>>>(d_seed, d_pk, d_sk);
    CK(cudaGetLastError());
    CK(cudaDeviceSynchronize());

    CK(cudaMemcpy(pk, d_pk, PKB, cudaMemcpyDeviceToHost));
    CK(cudaMemcpy(sk, d_sk, SKB, cudaMemcpyDeviceToHost));

    fprintf(stderr, "=== ML-DSA-87 KeyGen (CUDA baseline, <<<1,1>>>) ===\n");
    fprintf(stderr, "seed: ");
    for (int i = 0; i < SEEDBYTES; i++) {
        fprintf(stderr, "%02x", seed[i]);
    }
    fprintf(stderr, "\n");

    print_hex("pk", pk, PKB);
    print_hex("sk", sk, SKB);

    cudaFree(d_seed);
    cudaFree(d_pk);
    cudaFree(d_sk);
    free(pk);
    free(sk);
    return 0;
}
