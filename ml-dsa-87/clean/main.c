/*
 * main.c
 * ML-DSA-87 (PQClean, clean 구현) 분리형(detached) API 검증 테스트
 *
 * 실행 흐름: keygen -> sign -> verify (성공 케이스 확인)
 * 사용 함수:
 *   - PQCLEAN_MLDSA87_CLEAN_crypto_sign_keypair   (키 생성)
 *   - PQCLEAN_MLDSA87_CLEAN_crypto_sign_signature (분리형 서명)
 *   - PQCLEAN_MLDSA87_CLEAN_crypto_sign_verify    (분리형 검증)
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>

#include "api.h"

/* api.h에 정의된 크기 상수 */
#define PK_BYTES  PQCLEAN_MLDSA87_CLEAN_CRYPTO_PUBLICKEYBYTES  /* 2592 */
#define SK_BYTES  PQCLEAN_MLDSA87_CLEAN_CRYPTO_SECRETKEYBYTES  /* 4896 */
#define SIG_BYTES PQCLEAN_MLDSA87_CLEAN_CRYPTO_BYTES           /* 4627 (최대 서명 길이) */

int main(void) {
    /* 키/서명 버퍼 */
    uint8_t pk[PK_BYTES];
    uint8_t sk[SK_BYTES];
    uint8_t sig[SIG_BYTES];
    size_t  siglen = 0;

    /* 서명할 메시지 */
    const uint8_t message[] = "Hello, ML-DSA-87! This is a signature test message.";
    const size_t  mlen = sizeof(message) - 1;  /* 마지막 널 문자 제외 */

    int ret;

    printf("=== ML-DSA-87 detached sign/verify test ===\n");
    printf("PK: %d bytes, SK: %d bytes, SIG(max): %d bytes\n\n",
           PK_BYTES, SK_BYTES, SIG_BYTES);

    /* ---------- 1) keygen: 키 쌍 생성 ---------- */
    ret = PQCLEAN_MLDSA87_CLEAN_crypto_sign_keypair(pk, sk);
    if (ret != 0) {
        printf("[FAIL] keygen 실패 (ret = %d)\n", ret);
        return 1;
    }
    printf("[OK] keygen 성공\n");

    /* ---------- 2) sign: 분리형 서명 생성 ---------- */
    ret = PQCLEAN_MLDSA87_CLEAN_crypto_sign_signature(sig, &siglen, message, mlen, sk);
    if (ret != 0) {
        printf("[FAIL] sign 실패 (ret = %d)\n", ret);
        return 1;
    }
    printf("[OK] sign 성공 (siglen = %zu bytes)\n", siglen);

    /* ---------- 3) verify: 분리형 검증 ---------- */
    ret = PQCLEAN_MLDSA87_CLEAN_crypto_sign_verify(sig, siglen, message, mlen, pk);
    if (ret != 0) {
        printf("[FAIL] verify 실패 (ret = %d)\n", ret);
        return 1;
    }
    printf("[OK] verify 성공 (ret = 0)\n");

    printf("\n=== 모든 단계 통과: 서명 검증 정상 동작 ===\n");
    return 0;
}
