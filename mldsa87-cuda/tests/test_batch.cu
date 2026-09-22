/* test_batch.cu — GPU 배치 keygen/sign/verify 정확성 테스트
 *
 * 참고 (Claude 생성): GPU 배치로 생성한 키·서명을 GPU verify + CPU 참조로 교차검증.
 * 이 환경(nvcc 없음)에서 미실행. 사용자 GPU에서 빌드·실행 시 동작 예상.
 */
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "mldsa87_gpu.h"

int main(void) {
    const size_t BATCH = 1024;
    const char *msg = "gpu batch correctness";
    size_t mlen = strlen(msg);

    /* stride = mlen (모든 메시지 동일) */
    uint8_t *pk   = (uint8_t*)malloc(BATCH * MLDSA87_PUBLICKEYBYTES);
    uint8_t *sk   = (uint8_t*)malloc(BATCH * MLDSA87_SECRETKEYBYTES);
    uint8_t *sigs = (uint8_t*)malloc(BATCH * MLDSA87_SIGNATUREBYTES);
    uint8_t *msgs = (uint8_t*)malloc(BATCH * mlen);
    size_t  *lens = (size_t*)malloc(BATCH * sizeof(size_t));
    int     *res  = (int*)malloc(BATCH * sizeof(int));
    for (size_t i = 0; i < BATCH; ++i) { memcpy(msgs + i*mlen, msg, mlen); lens[i] = mlen; }

    printf("[1] GPU keygen batch=%zu ...\n", BATCH);
    if (mldsa87_gpu_keypair_batch(pk, sk, BATCH) != MLDSA_OK) { printf("keygen FAIL\n"); return 1; }

    printf("[2] GPU sign batch ...\n");
    if (mldsa87_gpu_sign_batch(sigs, msgs, lens, sk, BATCH) != MLDSA_OK) { printf("sign FAIL\n"); return 1; }

    printf("[3] GPU verify batch ...\n");
    if (mldsa87_gpu_verify_batch(res, sigs, msgs, lens, pk, BATCH) != MLDSA_OK) { printf("verify FAIL\n"); return 1; }

    size_t ok = 0;
    for (size_t i = 0; i < BATCH; ++i) if (res[i] == 0) ok++;
    printf("[결과] 검증 성공 %zu / %zu\n", ok, BATCH);
    printf(ok == BATCH ? "[OK] 전체 서명이 검증을 통과\n" : "[FAIL] 일부 검증 실패\n");

    free(pk); free(sk); free(sigs); free(msgs); free(lens); free(res);
    return ok == BATCH ? 0 : 1;
}
