/*
 * keygen_bench.cu  ---  GPU 계측판 (단일 스레드 커널)
 *
 * keygen.cu 의 KeyGen 코어와 동일한 호출 순서로 실행하되, 각 연산 함수 호출을
 * clock64()(SM 사이클 카운터) 로 감싸 단계별 소요 "사이클"을 측정합니다.
 * 호스트가 커널을 NRUNS 회 반복 실행 → 단계별 사이클 중앙값 → 사용자가 지정한
 * GPU 클럭(MHz)으로 µs 환산. 출력은 단계별 [cycles, µs] 를 함께 표기합니다.
 *
 * 로직/호출 순서는 원본 keypair 와 동일(측정 코드만 추가).
 * randombytes 없음: 시드는 호스트가 인자로 공급(고정 시드).
 *
 * 빌드 (다른 .cu 의 __device__ 함수를 호출하므로 -rdc=true 필수):
 *   nvcc -O2 -rdc=true -arch=sm_86 \
 *       fips202.cu reduce.cu ntt.cu rounding.cu poly.cu polyvec.cu \
 *       packing.cu symmetric-shake.cu keygen_bench.cu -o keygen_bench
 *
 * 실행 (GPU 클럭 MHz 를 인자로; 예: 1410):
 *   ./keygen_bench 1410
 *   → clock64() 사이클을 1410MHz 로 나눠 µs 환산.
 *   ⚠ 정확한 환산을 위해 nvidia-smi 등으로 실제 SM 클럭을 확인해 넣으세요.
 */
#include "params.h"
#include "poly.h"
#include "polyvec.h"
#include "packing.h"
#include "symmetric.h"
#include "fips202.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

#ifndef NRUNS
#define NRUNS 100         /* 커널 반복 횟수 (중앙값용) */
#endif

enum {
    S_SEED_EXPAND = 0, S_EXPAND_A, S_EXPAND_S1, S_EXPAND_S2,
    S_NTT_S1, S_MATVEC, S_REDUCE, S_INVNTT, S_ADD_S2, S_CADDQ,
    S_POWER2ROUND, S_PACK_PK, S_TR, S_PACK_SK, NSTAGES
};

static const char *STAGE_NAME[NSTAGES] = {
    "seed_expand(shake256)", "ExpandA(matrix_expand)",
    "ExpandS_s1(uniform_eta)", "ExpandS_s2(uniform_eta)",
    "NTT(s1)", "matvec_pointwise", "reduce", "invNTT_tomont",
    "add_s2", "caddq", "power2round", "pack_pk",
    "H(pk)=tr(shake256)", "pack_sk",
};

#define CK(call) do { cudaError_t e = (call); if (e != cudaSuccess) { \
    fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__, \
            cudaGetErrorString(e)); return 1; } } while (0)

/* 계측 커널: 단계별 사이클을 cyc[NSTAGES] 에 기록 */
__global__ void keygen_bench_kernel(const uint8_t *seed_in, uint8_t *pk,
                                    uint8_t *sk, long long *cyc) {
    uint8_t seedbuf[2 * SEEDBYTES + CRHBYTES];
    uint8_t tr[TRBYTES];
    const uint8_t *rho, *rhoprime, *key;
    polyvecl mat[K];
    polyvecl s1, s1hat;
    polyveck s2, t1, t0;
    long long c0, c1;

    for (int i = 0; i < SEEDBYTES; ++i) {
        seedbuf[i] = seed_in[i];
    }
    seedbuf[SEEDBYTES + 0] = K;
    seedbuf[SEEDBYTES + 1] = L;

    c0 = clock64();
    shake256(seedbuf, 2 * SEEDBYTES + CRHBYTES, seedbuf, SEEDBYTES + 2);
    c1 = clock64(); cyc[S_SEED_EXPAND] = c1 - c0;

    rho = seedbuf;
    rhoprime = rho + SEEDBYTES;
    key = rhoprime + CRHBYTES;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyvec_matrix_expand(mat, rho);
    c1 = clock64(); cyc[S_EXPAND_A] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyvecl_uniform_eta(&s1, rhoprime, 0);
    c1 = clock64(); cyc[S_EXPAND_S1] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyveck_uniform_eta(&s2, rhoprime, L);
    c1 = clock64(); cyc[S_EXPAND_S2] = c1 - c0;

    s1hat = s1;
    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyvecl_ntt(&s1hat);
    c1 = clock64(); cyc[S_NTT_S1] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyvec_matrix_pointwise_montgomery(&t1, mat, &s1hat);
    c1 = clock64(); cyc[S_MATVEC] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyveck_reduce(&t1);
    c1 = clock64(); cyc[S_REDUCE] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyveck_invntt_tomont(&t1);
    c1 = clock64(); cyc[S_INVNTT] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyveck_add(&t1, &t1, &s2);
    c1 = clock64(); cyc[S_ADD_S2] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyveck_caddq(&t1);
    c1 = clock64(); cyc[S_CADDQ] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_polyveck_power2round(&t1, &t0, &t1);
    c1 = clock64(); cyc[S_POWER2ROUND] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_pack_pk(pk, rho, &t1);
    c1 = clock64(); cyc[S_PACK_PK] = c1 - c0;

    c0 = clock64();
    shake256(tr, TRBYTES, pk, PQCLEAN_MLDSA87_CLEAN_CRYPTO_PUBLICKEYBYTES);
    c1 = clock64(); cyc[S_TR] = c1 - c0;

    c0 = clock64();
    PQCLEAN_MLDSA87_CLEAN_pack_sk(sk, rho, tr, key, &t0, &s1, &s2);
    c1 = clock64(); cyc[S_PACK_SK] = c1 - c0;
}

static int cmp_ll(const void *x, const void *y) {
    long long a = *(const long long *)x, b = *(const long long *)y;
    return (a > b) - (a < b);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <gpu_clock_MHz>\n", argv[0]);
        fprintf(stderr, "  예: %s 1410   (실제 SM 클럭을 nvidia-smi 로 확인해 입력)\n", argv[0]);
        return 2;
    }
    double clk_mhz = atof(argv[1]);
    if (clk_mhz <= 0) {
        fprintf(stderr, "잘못된 클럭: %s\n", argv[1]);
        return 2;
    }

    const size_t PKB = PQCLEAN_MLDSA87_CLEAN_CRYPTO_PUBLICKEYBYTES;
    const size_t SKB = PQCLEAN_MLDSA87_CLEAN_CRYPTO_SECRETKEYBYTES;

    uint8_t seed[SEEDBYTES];
    for (int i = 0; i < SEEDBYTES; i++) {
        seed[i] = (uint8_t)i;
    }

    uint8_t *d_seed, *d_pk, *d_sk;
    long long *d_cyc;
    CK(cudaMalloc(&d_seed, SEEDBYTES));
    CK(cudaMalloc(&d_pk, PKB));
    CK(cudaMalloc(&d_sk, SKB));
    CK(cudaMalloc(&d_cyc, NSTAGES * sizeof(long long)));
    CK(cudaMemcpy(d_seed, seed, SEEDBYTES, cudaMemcpyHostToDevice));

    static long long samples[NSTAGES][NRUNS];
    long long h_cyc[NSTAGES];

    /* 워밍업 1회 */
    keygen_bench_kernel<<<1, 1>>>(d_seed, d_pk, d_sk, d_cyc);
    CK(cudaGetLastError());
    CK(cudaDeviceSynchronize());

    for (int r = 0; r < NRUNS; r++) {
        keygen_bench_kernel<<<1, 1>>>(d_seed, d_pk, d_sk, d_cyc);
        CK(cudaGetLastError());
        CK(cudaDeviceSynchronize());
        CK(cudaMemcpy(h_cyc, d_cyc, NSTAGES * sizeof(long long), cudaMemcpyDeviceToHost));
        for (int s = 0; s < NSTAGES; s++) {
            samples[s][r] = h_cyc[s];
        }
    }

    printf("# ML-DSA-87 KeyGen GPU per-stage timing (clock64, single thread)\n");
    printf("# NRUNS=%d, gpu_clock=%.1f MHz\n", NRUNS, clk_mhz);
    printf("%-26s %14s %12s\n", "stage", "cycles(median)", "us(median)");

    long long tot_cyc = 0;
    for (int s = 0; s < NSTAGES; s++) {
        qsort(samples[s], NRUNS, sizeof(long long), cmp_ll);
        long long med = samples[s][NRUNS / 2];
        double us = (double)med / clk_mhz;   /* cycles / (cycles/µs) = µs */
        printf("%-26s %14lld %12.3f\n", STAGE_NAME[s], med, us);
        tot_cyc += med;
    }
    printf("%-26s %14lld %12.3f\n", "TOTAL(sum of stages)",
           tot_cyc, (double)tot_cyc / clk_mhz);

    cudaFree(d_seed); cudaFree(d_pk); cudaFree(d_sk); cudaFree(d_cyc);
    return 0;
}
