/*
 * randombytes.c (참조 빌드 전용, 결정론적)
 *   실제 난수 대신 고정 시드 0x00,0x01,... 를 채웁니다.
 *   CUDA main.cu 의 seed[i]=i 와 반드시 동일해야 pk/sk 가 일치합니다.
 *   randombytes.h 의 매크로에 의해 이 정의는 PQCLEAN_randombytes 가 됩니다.
 *   ⚠ 검증 전용입니다. 실제 키 생성에 사용하면 안 됩니다.
 */
#include "randombytes.h"
#include <stdint.h>

int randombytes(uint8_t *output, size_t n) {
    for (size_t i = 0; i < n; i++) {
        output[i] = (uint8_t)(i & 0xff);
    }
    return 0;
}
