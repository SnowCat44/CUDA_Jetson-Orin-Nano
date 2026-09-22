/* batch_host.cu — 배치 커널 호스트 오케스트레이션
 *
 * 참고 (Claude 생성): 시드 생성(CPU) → cudaMalloc/전송 → 커널 실행 →
 * 결과 회수 흐름. 공개 API(include/mldsa87_gpu.h)를 구현.
 * 이 환경엔 nvcc가 없어 미검증. 사용자 GPU에서 빌드·실행 필요.
 */
#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include "mldsa87_gpu.h"

extern "C" {
#include "sign.h"
#include "params.h"
#include "randombytes.h"   /* 호스트 측 시드 생성용 */
}

#define PK_BYTES  MLDSA87_PUBLICKEYBYTES
#define SK_BYTES  MLDSA87_SECRETKEYBYTES
#define SIG_BYTES MLDSA87_SIGNATUREBYTES

/* 커널 선언 (kernels/batch_kernels.cu) */
extern "C" __global__ void keygen_batch_kernel(uint8_t*, uint8_t*, const uint8_t*, size_t);
extern "C" __global__ void sign_batch_kernel(uint8_t*, size_t*, const uint8_t*, const size_t*,
                                             size_t, const uint8_t*, const uint8_t*, size_t);
extern "C" __global__ void verify_batch_kernel(int*, const uint8_t*, const size_t*,
                                               const uint8_t*, const size_t*, size_t,
                                               const uint8_t*, size_t);

#define CUDA_CHECK(x) do { cudaError_t e=(x); if(e!=cudaSuccess){ \
    fprintf(stderr,"CUDA error %s at %s:%d\n",cudaGetErrorString(e),__FILE__,__LINE__); \
    return MLDSA_ERR_CUDA; } } while(0)

static int threads_per_block = 128;

extern "C" mldsa_status mldsa87_gpu_keypair_batch(uint8_t *pk, uint8_t *sk, size_t batch) {
    if (!pk || !sk || batch == 0) return MLDSA_ERR_INVALID_ARG;

    /* 1) 호스트에서 시드 생성 (OS 엔트로피는 CPU에서만) */
    uint8_t *h_seed = (uint8_t*)malloc(batch * SEEDBYTES);
    if (!h_seed) return MLDSA_ERR_CUDA;
    randombytes(h_seed, batch * SEEDBYTES);   /* 주의: 대량이면 청크 고려 */

    /* 2) device 버퍼 */
    uint8_t *d_pk, *d_sk, *d_seed;
    CUDA_CHECK(cudaMalloc(&d_pk,   batch * PK_BYTES));
    CUDA_CHECK(cudaMalloc(&d_sk,   batch * SK_BYTES));
    CUDA_CHECK(cudaMalloc(&d_seed, batch * SEEDBYTES));
    CUDA_CHECK(cudaMemcpy(d_seed, h_seed, batch * SEEDBYTES, cudaMemcpyHostToDevice));

    /* 3) 커널 실행 */
    size_t blocks = (batch + threads_per_block - 1) / threads_per_block;
    keygen_batch_kernel<<<blocks, threads_per_block>>>(d_pk, d_sk, d_seed, batch);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    /* 4) 결과 회수 */
    CUDA_CHECK(cudaMemcpy(pk, d_pk, batch * PK_BYTES, cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(sk, d_sk, batch * SK_BYTES, cudaMemcpyDeviceToHost));

    cudaFree(d_pk); cudaFree(d_sk); cudaFree(d_seed); free(h_seed);
    return MLDSA_OK;
}

extern "C" mldsa_status mldsa87_gpu_sign_batch(uint8_t *sigs,
                                               const uint8_t *msgs, const size_t *msg_lens,
                                               const uint8_t *sk, size_t batch) {
    if (!sigs || !msgs || !msg_lens || !sk || batch == 0) return MLDSA_ERR_INVALID_ARG;

    /* 메시지는 고정 stride 가정 — 최대 길이를 stride로 (간단화). 실제론 호출측 규약에 맞춤. */
    size_t msg_stride = 0;
    for (size_t i = 0; i < batch; ++i) if (msg_lens[i] > msg_stride) msg_stride = msg_lens[i];
    if (msg_stride == 0) msg_stride = 1;

    /* 서명용 rnd 시드 생성 (호스트) */
    uint8_t *h_rnd = (uint8_t*)malloc(batch * RNDBYTES);
    if (!h_rnd) return MLDSA_ERR_CUDA;
    randombytes(h_rnd, batch * RNDBYTES);

    uint8_t *d_sig, *d_msg, *d_sk, *d_rnd;
    size_t  *d_siglen, *d_msglen;
    CUDA_CHECK(cudaMalloc(&d_sig,    batch * SIG_BYTES));
    CUDA_CHECK(cudaMalloc(&d_siglen, batch * sizeof(size_t)));
    CUDA_CHECK(cudaMalloc(&d_msg,    batch * msg_stride));
    CUDA_CHECK(cudaMalloc(&d_msglen, batch * sizeof(size_t)));
    CUDA_CHECK(cudaMalloc(&d_sk,     batch * SK_BYTES));
    CUDA_CHECK(cudaMalloc(&d_rnd,    batch * RNDBYTES));

    /* 메시지를 stride 배열로 정렬 복사 */
    uint8_t *h_msg = (uint8_t*)calloc(batch, msg_stride);
    for (size_t i = 0; i < batch; ++i)
        memcpy(h_msg + i * msg_stride, msgs /* 호출측이 이미 stride로 넘긴다고 가정 */ + i * msg_stride, msg_lens[i]);

    CUDA_CHECK(cudaMemcpy(d_msg,    h_msg,    batch * msg_stride,     cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_msglen, msg_lens, batch * sizeof(size_t), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_sk,     sk,       batch * SK_BYTES,       cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_rnd,    h_rnd,    batch * RNDBYTES,       cudaMemcpyHostToDevice));

    size_t blocks = (batch + threads_per_block - 1) / threads_per_block;
    sign_batch_kernel<<<blocks, threads_per_block>>>(d_sig, d_siglen, d_msg, d_msglen,
                                                     msg_stride, d_sk, d_rnd, batch);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    CUDA_CHECK(cudaMemcpy(sigs, d_sig, batch * SIG_BYTES, cudaMemcpyDeviceToHost));

    cudaFree(d_sig); cudaFree(d_siglen); cudaFree(d_msg); cudaFree(d_msglen);
    cudaFree(d_sk); cudaFree(d_rnd); free(h_rnd); free(h_msg);
    return MLDSA_OK;
}

extern "C" mldsa_status mldsa87_gpu_verify_batch(int *results,
                                                 const uint8_t *sigs,
                                                 const uint8_t *msgs, const size_t *msg_lens,
                                                 const uint8_t *pk, size_t batch) {
    if (!results || !sigs || !msgs || !msg_lens || !pk || batch == 0) return MLDSA_ERR_INVALID_ARG;

    size_t msg_stride = 0;
    for (size_t i = 0; i < batch; ++i) if (msg_lens[i] > msg_stride) msg_stride = msg_lens[i];
    if (msg_stride == 0) msg_stride = 1;

    /* siglen은 전부 SIG_BYTES로 가정(detached full signature) */
    size_t *h_siglen = (size_t*)malloc(batch * sizeof(size_t));
    for (size_t i = 0; i < batch; ++i) h_siglen[i] = SIG_BYTES;

    int *d_res; uint8_t *d_sig, *d_msg, *d_pk; size_t *d_siglen, *d_msglen;
    CUDA_CHECK(cudaMalloc(&d_res,    batch * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_sig,    batch * SIG_BYTES));
    CUDA_CHECK(cudaMalloc(&d_siglen, batch * sizeof(size_t)));
    CUDA_CHECK(cudaMalloc(&d_msg,    batch * msg_stride));
    CUDA_CHECK(cudaMalloc(&d_msglen, batch * sizeof(size_t)));
    CUDA_CHECK(cudaMalloc(&d_pk,     batch * PK_BYTES));

    CUDA_CHECK(cudaMemcpy(d_sig,    sigs,     batch * SIG_BYTES,      cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_siglen, h_siglen, batch * sizeof(size_t), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_msg,    msgs,     batch * msg_stride,     cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_msglen, msg_lens, batch * sizeof(size_t), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_pk,     pk,       batch * PK_BYTES,       cudaMemcpyHostToDevice));

    size_t blocks = (batch + threads_per_block - 1) / threads_per_block;
    verify_batch_kernel<<<blocks, threads_per_block>>>(d_res, d_sig, d_siglen,
                                                       d_msg, d_msglen, msg_stride, d_pk, batch);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    CUDA_CHECK(cudaMemcpy(results, d_res, batch * sizeof(int), cudaMemcpyDeviceToHost));

    cudaFree(d_res); cudaFree(d_sig); cudaFree(d_siglen);
    cudaFree(d_msg); cudaFree(d_msglen); cudaFree(d_pk); free(h_siglen);
    return MLDSA_OK;
}
