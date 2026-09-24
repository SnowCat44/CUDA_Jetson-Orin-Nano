/*
 * keygen.cu  ---  ML-DSA-87 KeyGen 디바이스 진입점 (베이스라인, 단일 스레드)
 *
 * 원본 sign.c 의 PQCLEAN_MLDSA87_CLEAN_crypto_sign_keypair 본문을 그대로 옮기되,
 * 단 하나 randombytes() 호출만 "시드를 인자로 받는" 형태로 바꿨습니다(R1).
 * 나머지 로직/호출 순서는 원본과 동일합니다.
 */
#include "fips202.h"
#include "packing.h"
#include "params.h"
#include "poly.h"
#include "polyvec.h"
#include "symmetric.h"
#include <stdint.h>

/* 디바이스 KeyGen 코어: 32바이트 시드를 입력으로 받음 */
__device__ void mldsa87_keygen_core(const uint8_t seed_in[SEEDBYTES],
                                    uint8_t *pk, uint8_t *sk) {
    uint8_t seedbuf[2 * SEEDBYTES + CRHBYTES];
    uint8_t tr[TRBYTES];
    const uint8_t *rho, *rhoprime, *key;
    polyvecl mat[K];
    polyvecl s1, s1hat;
    polyveck s2, t1, t0;

    /* --- R1: randombytes(seedbuf, SEEDBYTES) 대체 (디바이스에서 OS 난수 불가) --- */
    for (int i = 0; i < SEEDBYTES; ++i) {
        seedbuf[i] = seed_in[i];
    }
    /* --- 이하 원본 crypto_sign_keypair 와 동일 --- */
    seedbuf[SEEDBYTES + 0] = K;
    seedbuf[SEEDBYTES + 1] = L;
    shake256(seedbuf, 2 * SEEDBYTES + CRHBYTES, seedbuf, SEEDBYTES + 2);
    rho = seedbuf;
    rhoprime = rho + SEEDBYTES;
    key = rhoprime + CRHBYTES;

    /* Expand matrix */
    PQCLEAN_MLDSA87_CLEAN_polyvec_matrix_expand(mat, rho);

    /* Sample short vectors s1 and s2 */
    PQCLEAN_MLDSA87_CLEAN_polyvecl_uniform_eta(&s1, rhoprime, 0);
    PQCLEAN_MLDSA87_CLEAN_polyveck_uniform_eta(&s2, rhoprime, L);

    /* Matrix-vector multiplication */
    s1hat = s1;
    PQCLEAN_MLDSA87_CLEAN_polyvecl_ntt(&s1hat);
    PQCLEAN_MLDSA87_CLEAN_polyvec_matrix_pointwise_montgomery(&t1, mat, &s1hat);
    PQCLEAN_MLDSA87_CLEAN_polyveck_reduce(&t1);
    PQCLEAN_MLDSA87_CLEAN_polyveck_invntt_tomont(&t1);

    /* Add error vector s2 */
    PQCLEAN_MLDSA87_CLEAN_polyveck_add(&t1, &t1, &s2);

    /* Extract t1 and write public key */
    PQCLEAN_MLDSA87_CLEAN_polyveck_caddq(&t1);
    PQCLEAN_MLDSA87_CLEAN_polyveck_power2round(&t1, &t0, &t1);
    PQCLEAN_MLDSA87_CLEAN_pack_pk(pk, rho, &t1);

    /* Compute H(rho, t1) and write secret key */
    shake256(tr, TRBYTES, pk, PQCLEAN_MLDSA87_CLEAN_CRYPTO_PUBLICKEYBYTES);
    PQCLEAN_MLDSA87_CLEAN_pack_sk(sk, rho, tr, key, &t0, &s1, &s2);
}

/* __global__ 진입 커널: <<<1,1>>> 단일 스레드로 실행 */
__global__ void keygen_kernel(const uint8_t *seed, uint8_t *pk, uint8_t *sk) {
    mldsa87_keygen_core(seed, pk, sk);
}
