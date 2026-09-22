/* batch_kernels.cu — 1 스레드 = 1 서명 배치 커널 (keygen / sign / verify)
 *
 * 참고 (Claude 생성): device_port/ 의 디바이스화된 PQClean 함수를 호출하는
 * __global__ 커널. 각 스레드가 전역 ID(gid)로 자기 몫의 서명 1개를 처리한다.
 * 병렬성은 오직 배치 차원(스레드 = 서명)에서 나온다.
 *
 * 검증: 이 환경엔 nvcc가 없어 실제 컴파일·실행 미검증. 사용자 GPU에서 확인 필요.
 * 내부 함수의 정확성은 device_port 단계에서 CPU 대조로 검증 완료.
 */
#include <stdint.h>
#include <stddef.h>

extern "C" {
#include "sign.h"
#include "params.h"
}

/* 크기 상수 (api.h와 동일) */
#define PK_BYTES  PQCLEAN_MLDSA87_CLEAN_CRYPTO_PUBLICKEYBYTES  /* 2592 */
#define SK_BYTES  PQCLEAN_MLDSA87_CLEAN_CRYPTO_SECRETKEYBYTES  /* 4896 */
#define SIG_BYTES PQCLEAN_MLDSA87_CLEAN_CRYPTO_BYTES           /* 4627 */

/*
 * keygen 배치 커널.
 *  d_pk   : [batch * PK_BYTES]
 *  d_sk   : [batch * SK_BYTES]
 *  d_seed : [batch * SEEDBYTES]  (호스트에서 randombytes로 생성해 전송)
 */
extern "C" __global__ void keygen_batch_kernel(uint8_t *d_pk, uint8_t *d_sk,
                                               const uint8_t *d_seed, size_t batch) {
    size_t gid = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (gid >= batch) return;

    PQCLEAN_MLDSA87_CLEAN_crypto_sign_keypair(
        d_pk  + gid * PK_BYTES,
        d_sk  + gid * SK_BYTES,
        d_seed + gid * SEEDBYTES);
}

/*
 * sign 배치 커널 (detached signature).
 *  d_sig    : [batch * SIG_BYTES]      출력
 *  d_siglen : [batch]                  각 서명 길이 출력
 *  d_msg    : [batch * msg_stride]     메시지들 (고정 stride 가정)
 *  d_msglen : [batch]                  각 메시지 길이
 *  d_sk     : [batch * SK_BYTES]
 *  d_rnd    : [batch * RNDBYTES]       서명용 시드 (호스트 생성; 결정론이면 0)
 */
extern "C" __global__ void sign_batch_kernel(uint8_t *d_sig, size_t *d_siglen,
                                             const uint8_t *d_msg, const size_t *d_msglen,
                                             size_t msg_stride,
                                             const uint8_t *d_sk,
                                             const uint8_t *d_rnd, size_t batch) {
    size_t gid = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (gid >= batch) return;

    PQCLEAN_MLDSA87_CLEAN_crypto_sign_signature(
        d_sig + gid * SIG_BYTES,
        &d_siglen[gid],
        d_msg + gid * msg_stride,
        d_msglen[gid],
        d_sk  + gid * SK_BYTES,
        d_rnd + gid * RNDBYTES);
}

/*
 * verify 배치 커널.
 *  d_res : [batch]  결과 0(성공)/-1(실패)
 */
extern "C" __global__ void verify_batch_kernel(int *d_res,
                                               const uint8_t *d_sig, const size_t *d_siglen,
                                               const uint8_t *d_msg, const size_t *d_msglen,
                                               size_t msg_stride,
                                               const uint8_t *d_pk, size_t batch) {
    size_t gid = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (gid >= batch) return;

    d_res[gid] = PQCLEAN_MLDSA87_CLEAN_crypto_sign_verify(
        d_sig + gid * SIG_BYTES,
        d_siglen[gid],
        d_msg + gid * msg_stride,
        d_msglen[gid],
        d_pk  + gid * PK_BYTES);
}
