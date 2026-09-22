// ============================================================================
//  deviceQuery 현재 GPU의 하드웨어 정보 출력
//  컴파일:  nvcc device_info.cu -o device_info
//  실행:    ./device_info
// ============================================================================

#include <cstdio>
#include <cuda_runtime.h>

int main()
{
    int deviceCount = 0;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        printf("CUDA 지원 GPU를 찾지 못했습니다.\n");
        return 0;
    }

    for (int dev = 0; dev < deviceCount; dev++) {
        cudaDeviceProp p;
        cudaGetDeviceProperties(&p, dev);

        printf("==================================================\n");
        printf(" Device %d: \"%s\"\n", dev, p.name);
        printf("==================================================\n");

        // --- Compute Capability ---
        printf(" Compute Capability            : %d.%d  (sm_%d%d)\n",
               p.major, p.minor, p.major, p.minor);

        // --- SM 개수 / 코어 ---
        printf(" SM(멀티프로세서) 개수         : %d\n", p.multiProcessorCount);

        // --- 병렬 구조 한계 조건 (occupancy 계산에 쓰는 값) ---
        printf("\n [병렬 구조 한계 조건]\n");
        printf(" warp size                     : %d\n", p.warpSize);
        printf(" SM당 최대 스레드              : %d\n", p.maxThreadsPerMultiProcessor);
        printf(" SM당 최대 워프                : %d\n", p.maxThreadsPerMultiProcessor / p.warpSize);
        printf(" 블록당 최대 스레드            : %d\n", p.maxThreadsPerBlock);
#if CUDART_VERSION >= 11000
        printf(" SM당 최대 블록                : %d\n", p.maxBlocksPerMultiProcessor);
#endif

        // --- SM 보유 자원 ---
        printf("\n [SM 보유 자원]\n");
        printf(" SM당 레지스터                 : %d\n", p.regsPerMultiprocessor);
        printf(" 블록당 최대 레지스터          : %d\n", p.regsPerBlock);
        printf(" SM당 shared memory (byte)     : %zu\n", p.sharedMemPerMultiprocessor);
        printf(" 블록당 shared memory (byte)   : %zu\n", p.sharedMemPerBlock);
        printf(" 상수 메모리 (byte)            : %zu\n", p.totalConstMem);

        // --- 메모리 ---
        printf("\n [메모리]\n");
        printf(" 전역 메모리 (MB)              : %.0f\n", p.totalGlobalMem / (1024.0 * 1024.0));
        printf(" L2 캐시 (byte)                : %d\n", p.l2CacheSize);
        printf(" CPU-GPU 메모리 공유(통합)     : %s\n", p.integrated ? "예 (integrated)" : "아니오 (discrete)");
        printf(" cudaMallocManaged 지원        : %s\n", p.managedMemory ? "예" : "아니오");
    }
    return 0;
}
