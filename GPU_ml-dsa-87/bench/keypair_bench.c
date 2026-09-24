/*
 * keypair_bench.c  ---  CPU 계측판 (원본 clean, 무수정 로직)
 *
 * 원본 PQCLEAN_MLDSA87_CLEAN_crypto_sign_keypair 의 본문을 그대로 복제하되,
 * 각 연산 함수 호출을 clock_gettime(CLOCK_MONOTONIC) 으로 감싸 단계별 µs 를 측정합니다.
 * 로직/호출 순서는 원본과 100% 동일합니다(측정 코드만 추가).
 *
 * 반복 측정: 워밍업 후 NRUNS 회 반복 → 단계별 평균/중앙값/최소(µs).
 * randombytes 는 결정론적 고정 시드(비교 기준 재현용).
 *
 * 빌드:
 *   gcc -O2 -std=c99 -I. ntt.c reduce.c rounding.c poly.c polyvec.c \
 *       packing.c symmetric-shake.c fips202.c keypair_bench.c -o keypair_bench
 *   (원본 clean + fips202 필요. randombytes 는 이 파일 안에 고정 시드로 내장.)
 */
/* clock_gettime / CLOCK_MONOTONIC 는 POSIX 심볼이라 -std=c99 에서 노출 필요 */
#define _POSIX_C_SOURCE 199309L

#include "params.h"
#include "poly.h"
#include "polyvec.h"
#include "packing.h"
#include "symmetric.h"
#include "fips202.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ------- 설정 ------- */
#ifndef NRUNS
#define NRUNS 1000        /* 측정 반복 횟수 */
#endif
#ifndef NWARMUP
#define NWARMUP 50        /* 워밍업(통계 제외) */
#endif

/* 측정 단계 정의 (§1 호출 그래프 순서) */
enum {
    S_SEED_EXPAND = 0,  /* shake256: seed -> rho|rhoprime|key */
    S_EXPAND_A,         /* polyvec_matrix_expand (ExpandA) */
    S_EXPAND_S1,        /* polyvecl_uniform_eta (ExpandS s1) */
    S_EXPAND_S2,        /* polyveck_uniform_eta (ExpandS s2) */
    S_NTT_S1,           /* polyvecl_ntt */
    S_MATVEC,           /* polyvec_matrix_pointwise_montgomery */
    S_REDUCE,           /* polyveck_reduce */
    S_INVNTT,           /* polyveck_invntt_tomont */
    S_ADD_S2,           /* polyveck_add */
    S_CADDQ,            /* polyveck_caddq */
    S_POWER2ROUND,      /* polyveck_power2round */
    S_PACK_PK,          /* pack_pk */
    S_TR,               /* shake256: H(pk) */
    S_PACK_SK,          /* pack_sk */
    NSTAGES
};

static const char *STAGE_NAME[NSTAGES] = {
    "seed_expand(shake256)",
    "ExpandA(matrix_expand)",
    "ExpandS_s1(uniform_eta)",
    "ExpandS_s2(uniform_eta)",
    "NTT(s1)",
    "matvec_pointwise",
    "reduce",
    "invNTT_tomont",
    "add_s2",
    "caddq",
    "power2round",
    "pack_pk",
    "H(pk)=tr(shake256)",
    "pack_sk",
};

/* 결정론적 고정 시드 (GPU main.cu 의 seed[i]=i 와 동일하게 맞출 수 있음) */
static void fixed_seed(uint8_t *out, size_t n) {
    for (size_t i = 0; i < n; i++) {
        out[i] = (uint8_t)(i & 0xff);
    }
}

static inline double ns_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

/* 계측판 keypair: 단계별 소요시간(µs)을 stage_us[] 에 기록 */
static void keypair_instrumented(uint8_t *pk, uint8_t *sk, double stage_us[NSTAGES]) {
    uint8_t seedbuf[2 * SEEDBYTES + CRHBYTES];
    uint8_t tr[TRBYTES];
    const uint8_t *rho, *rhoprime, *key;
    polyvecl mat[K];
    polyvecl s1, s1hat;
    polyveck s2, t1, t0;
    double a, b;

    /* 시드 주입(측정 대상 아님) */
    fixed_seed(seedbuf, SEEDBYTES);
    seedbuf[SEEDBYTES + 0] = K;
    seedbuf[SEEDBYTES + 1] = L;

    a = ns_now();
    shake256(seedbuf, 2 * SEEDBYTES + CRHBYTES, seedbuf, SEEDBYTES + 2);
    b = ns_now(); stage_us[S_SEED_EXPAND] = (b - a) / 1e3;

    rho = seedbuf;
    rhoprime = rho + SEEDBYTES;
    key = rhoprime + CRHBYTES;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyvec_matrix_expand(mat, rho);
    b = ns_now(); stage_us[S_EXPAND_A] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyvecl_uniform_eta(&s1, rhoprime, 0);
    b = ns_now(); stage_us[S_EXPAND_S1] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyveck_uniform_eta(&s2, rhoprime, L);
    b = ns_now(); stage_us[S_EXPAND_S2] = (b - a) / 1e3;

    s1hat = s1;
    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyvecl_ntt(&s1hat);
    b = ns_now(); stage_us[S_NTT_S1] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyvec_matrix_pointwise_montgomery(&t1, mat, &s1hat);
    b = ns_now(); stage_us[S_MATVEC] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyveck_reduce(&t1);
    b = ns_now(); stage_us[S_REDUCE] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyveck_invntt_tomont(&t1);
    b = ns_now(); stage_us[S_INVNTT] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyveck_add(&t1, &t1, &s2);
    b = ns_now(); stage_us[S_ADD_S2] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyveck_caddq(&t1);
    b = ns_now(); stage_us[S_CADDQ] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_polyveck_power2round(&t1, &t0, &t1);
    b = ns_now(); stage_us[S_POWER2ROUND] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_pack_pk(pk, rho, &t1);
    b = ns_now(); stage_us[S_PACK_PK] = (b - a) / 1e3;

    a = ns_now();
    shake256(tr, TRBYTES, pk, PQCLEAN_MLDSA87_CLEAN_CRYPTO_PUBLICKEYBYTES);
    b = ns_now(); stage_us[S_TR] = (b - a) / 1e3;

    a = ns_now();
    PQCLEAN_MLDSA87_CLEAN_pack_sk(sk, rho, tr, key, &t0, &s1, &s2);
    b = ns_now(); stage_us[S_PACK_SK] = (b - a) / 1e3;
}

/* --- 통계 --- */
static int cmp_double(const void *x, const void *y) {
    double a = *(const double *)x, b = *(const double *)y;
    return (a > b) - (a < b);
}

int main(void) {
    static double samples[NSTAGES][NRUNS];
    uint8_t *pk = (uint8_t *)malloc(PQCLEAN_MLDSA87_CLEAN_CRYPTO_PUBLICKEYBYTES);
    uint8_t *sk = (uint8_t *)malloc(PQCLEAN_MLDSA87_CLEAN_CRYPTO_SECRETKEYBYTES);
    double stage_us[NSTAGES];

    for (int w = 0; w < NWARMUP; w++) {
        keypair_instrumented(pk, sk, stage_us);
    }
    for (int r = 0; r < NRUNS; r++) {
        keypair_instrumented(pk, sk, stage_us);
        for (int s = 0; s < NSTAGES; s++) {
            samples[s][r] = stage_us[s];
        }
    }

    printf("# ML-DSA-87 KeyGen CPU per-stage timing (clock_gettime, µs)\n");
    printf("# NRUNS=%d, NWARMUP=%d\n", NRUNS, NWARMUP);
    printf("%-26s %10s %10s %10s\n", "stage", "mean_us", "median_us", "min_us");

    double total_mean = 0, total_med = 0, total_min = 0;
    for (int s = 0; s < NSTAGES; s++) {
        double sum = 0, mn = samples[s][0];
        for (int r = 0; r < NRUNS; r++) {
            sum += samples[s][r];
            if (samples[s][r] < mn) {
                mn = samples[s][r];
            }
        }
        qsort(samples[s], NRUNS, sizeof(double), cmp_double);
        double med = samples[s][NRUNS / 2];
        double mean = sum / NRUNS;
        printf("%-26s %10.3f %10.3f %10.3f\n", STAGE_NAME[s], mean, med, mn);
        total_mean += mean; total_med += med; total_min += mn;
    }
    printf("%-26s %10.3f %10.3f %10.3f\n", "TOTAL(sum of stages)",
           total_mean, total_med, total_min);

    free(pk);
    free(sk);
    return 0;
}
