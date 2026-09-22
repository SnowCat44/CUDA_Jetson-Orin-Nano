/*
 * bench_throughput.cu — 배치 throughput 측정 (골격)
 * 참고 (Claude 생성): 스텁. GPU 커널 구현 후 서명/초를 측정하고
 * CPU 참조 (clean)와 비교. 현재는 틀만 존재.
 */
#include <cstdio>
#include "mldsa87_gpu.h"

int main(void) {
    // TODO(Phase 4): 각 배치 크기 (1K, 4K, 16K...)에서 cudaEvent 측정
    // TODO(Phase 4): sign/sec, verify/sec를 CPU baseline과 대비
    printf("[INFO] benchmark scaffold — 커널 구현 후 활성화\n");
    return 0;
}
