/*
 * mldsa87_gpu.h — ML-DSA-87 배치 GPU API (공개 헤더)
 *
 * 참고 (Claude 생성): 이것은 골격 인터페이스 정의이며,
 * 구현 (src/, kernels/) 은 아직 미완성 스텁. 함수는 현재 -1 (미구현) 반환.
 */
#ifndef MLDSA87_GPU_H
#define MLDSA87_GPU_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 크기 상수 (ml-dsa-87). 참조 구현 api.h와 일치시킬 것. */
#define MLDSA87_PUBLICKEYBYTES 2592
#define MLDSA87_SECRETKEYBYTES 4896
#define MLDSA87_SIGNATUREBYTES 4627

/* 반환값 */
typedef enum {
    MLDSA_OK = 0,
    MLDSA_ERR_NOT_IMPLEMENTED = -1,
    MLDSA_ERR_CUDA = -2,
    MLDSA_ERR_INVALID_ARG = -3,
} mldsa_status;

/*
 * 배치 키생성: batch개의 (pk, sk) 생성.
 * pk: batch * MLDSA87_PUBLICKEYBYTES
 * sk: batch * MLDSA87_SECRETKEYBYTES
 */
mldsa_status mldsa87_gpu_keypair_batch(uint8_t *pk, uint8_t *sk, size_t batch);

/*
 * 배치 서명: 각 (msg[i], sk[i]) 로부터 sig[i] 생성.
 * msgs   : 연결된 메시지, msg_lens[i]가 각 길이
 * sigs   : batch * MLDSA87_SIGNATUREBYTES
 */
mldsa_status mldsa87_gpu_sign_batch(uint8_t *sigs,
                                    const uint8_t *msgs, const size_t *msg_lens,
                                    const uint8_t *sk, size_t batch);

/*
 * 배치 검증: 각 (sig[i], msg[i], pk[i]) 검증. results[i]에 0/1.
 */
mldsa_status mldsa87_gpu_verify_batch(int *results,
                                      const uint8_t *sigs,
                                      const uint8_t *msgs, const size_t *msg_lens,
                                      const uint8_t *pk, size_t batch);

#ifdef __cplusplus
}
#endif
#endif /* MLDSA87_GPU_H */
