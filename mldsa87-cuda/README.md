# mldsa87-cuda

ML-DSA-87 (FIPS 204) 을 CUDA GPU에서 **대량 배치 서명**으로 처리하는 구현.

> **참고 (Claude 생성):** 코드 상당수는 Claude가 PQClean을 GPU용으로 개조/작성한 것.
> **이 개발 환경엔 nvcc/GPU가 없어 실제 디바이스 컴파일·실행은 미검증**이며,
> 각 단계의 정확성은 순수 C 컴파일 + CPU 참조 대조로 확인했다.
> 실제 GPU 빌드·실행 및 성능 확인은 사용자 GPU 환경에서 필요.

## 설계 요약

- **알고리즘:** ML-DSA-87 (NIST level 5). 로직은 PQClean과 동일(결과 일치 검증됨).
- **병렬화 모델:** **1 스레드 = 1 서명.** 병렬성은 배치 차원(스레드 = 서명)에서만.
  세부 함수(NTT 등)는 PQClean 순차형 그대로 → 각 스레드가 독립적으로 서명 1개 처리.
- **난수:** OS 시스템콜인 randombytes는 GPU 불가 → **호스트에서 시드 생성 후 주입**.
- **향후(2단계):** 병목(NTT/SHAKE)을 "1블록=1서명" 협력형으로 승격하는 최적화 여지.

## 디렉토리 구성

```
mldsa87-cuda/
├── include/mldsa87_gpu.h      공개 배치 API (keypair/sign/verify batch)
├── src/batch_host.cu          호스트 오케스트레이션 (시드생성·전송·커널실행·회수)
├── kernels/batch_kernels.cu   __global__ 배치 커널 3개 (1스레드=1서명)
├── device_port/               PQClean을 GPU용으로 개조한 소스 (핵심)
│   ├── *.c *.h                MLD_HD(__host__ __device__) 부착, 시드주입
│   ├── fips202_dev.{c,h}      SHAKE: malloc→고정배열 개조
│   └── CHANGES.md             ★ 원본 대비 변경 내역 전체 기록
├── third_party/mldsa87_clean/ PQClean 원본 (검증 기준, 수정 안 함)
├── tests/test_batch.cu        GPU 배치 정확성 테스트
├── docs/                      설계·로드맵
└── CMakeLists.txt
```

## 개조 내역 (원본 → GPU)

전체는 `device_port/CHANGES.md` 참조. 요약:
1. **fips202(SHAKE):** 컨텍스트를 힙 malloc → 고정 배열. (GPU에서 malloc은 느림)
2. **디바이스화:** 모든 함수에 `MLD_HD`(`__host__ __device__`) 부착.
3. **난수:** `keypair`/`signature`에 시드 인자 추가, 내부 randombytes → memcpy(주입시드).

각 개조는 **동일 시드 하에서 원본과 공개키·서명 바이트 단위 일치**로 검증 완료.

## 빌드 (사용자 GPU 환경)

```bash
mkdir build && cd build
cmake .. -DMLDSA_BUILD_TESTS=ON
cmake --build . -j
./test_batch      # GPU 배치 keygen→sign→verify 정확성 확인
```

## 알려진 조정 필요 지점 (GPU 실빌드 시)

- `mat[K]` ≈ 56KB 스레드 로컬 스택 (1스레드=1서명의 부담) → global 작업버퍼 이전 검토.
- device에서 `memcpy`/`<string.h>` 대체 필요 가능성.
- `.c` 파일을 CUDA 언어로 컴파일할 때의 링크/한정자 이슈.
- 배치 sign/verify의 메시지 stride는 단순화된 가정 → 실사용 규약에 맞게 조정.

## 로드맵

`docs/ROADMAP.md` 참조.
