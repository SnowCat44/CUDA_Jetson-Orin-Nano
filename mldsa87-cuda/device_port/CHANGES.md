# PQClean → GPU 개조 변경 내역

> 이 문서는 "1 스레드 = 1 서명" 모델로 ML-DSA-87을 GPU에 올리기 위해
> PQClean 원본 소스에서 **정확히 무엇을, 왜 바꿨는지**를 기록한다.
> 원칙: 알고리즘 로직·계산 결과는 원본과 **동일하게 유지**하고,
> GPU(디바이스)에서 컴파일·실행 가능하게 만드는 최소한의 변경만 가한다.
>
> 원본은 `third_party/mldsa87_clean/` 에 그대로 보존(검증 기준).
> 개조판은 `device_port/` 에 별도 파일(`*_dev.*`)로 둔다.

---

## 1. fips202 (SHAKE/Keccak) — `device_port/fips202_dev.{c,h}`

원본: `third_party/mldsa87_clean/fips202.{c,h}`

### 변경 1-A. SHAKE 컨텍스트: 힙 포인터 → 고정 배열
**이유:** 원본은 `state->ctx = malloc(...)` 로 컨텍스트를 힙에 할당한다.
GPU 커널 안에서 device `malloc`은 (1) 모든 스레드가 공유하는 힙에서 직렬화되어
매우 느리고, (2) 1스레드=1서명 모델에서 서명마다 SHAKE를 여러 번 쓰므로
호출 횟수가 배치 크기에 비례해 폭증한다. → malloc 자체를 제거.

**변경 내용 (`fips202_dev.h`):** 구조체 멤버를 포인터에서 고정 배열로.
```
// 원본
typedef struct { uint64_t *ctx; } shake256incctx;
// 개조
typedef struct { uint64_t ctx[26]; } shake256incctx;   // 25 상태 + 1 카운터
```
- inc 계열(shake128inc, shake256inc, sha3_*inc): `ctx[26]`
- non-inc(shake128ctx, shake256ctx): `ctx[25]`
- 크기 근거: 원본 `PQC_SHAKEINCCTX_BYTES = sizeof(uint64_t)*26`,
  `PQC_SHAKECTX_BYTES = sizeof(uint64_t)*25`.

### 변경 1-B. malloc/free/exit 제거
**이유:** 위 개조로 할당이 불필요. device에서 `exit()`도 사용 불가.

- `*_inc_init` / `*_absorb`(non-inc) 함수의
  `state->ctx = malloc(...); if(NULL) exit(111);` 블록 **삭제**
  (구조체 배열이 이미 저장공간이므로 `keccak_*_init` 직접 호출만 남김).
- `*_ctx_release`: `free(state->ctx);` → **no-op** (`(void)state;`).
  고정 배열이라 해제할 것이 없음. 함수는 API 호환 위해 남겨둠.
- `*_ctx_clone`: `dest->ctx = malloc(...); memcpy(...)` →
  **`memcpy(dest->ctx, src->ctx, ...)` 만** (배열 복사).

### 변경 1-C. `__host__ __device__` 한정자 부착
**이유:** 같은 소스를 CPU(검증용)와 GPU(커널) 양쪽에서 컴파일하기 위함.

- 헤더 상단에 매크로 추가:
  ```
  #ifdef __CUDACC__
  #define FIPS202_HD __host__ __device__
  #else
  #define FIPS202_HD
  #endif
  ```
  → nvcc가 아니면 빈 매크로가 되어 일반 C로도 그대로 컴파일됨.
- 모든 함수 정의·선언 앞에 `FIPS202_HD` 부착(총 50개 함수).

### 검증 (이 환경, GPU 없이)
개조판을 일반 C로 컴파일하여 **원본과 출력 대조**:
- shake128 / shake256 (입력 길이 0~200) + 증분 API
- 결과: **모든 출력이 원본과 바이트 단위 완전 일치**.
- 의미: malloc→배열 개조가 계산 결과를 바꾸지 않음을 확인.
- 한계: 이 환경엔 nvcc가 없어 **디바이스 실제 실행 검증은 미실시**.
  `__CUDACC__` 경로(디바이스 컴파일)는 사용자 GPU 환경에서 확인 필요.

---

## 2. 난수(randombytes) — (예정, 아직 미적용)

**계획:** `sign.c`의 `randombytes(seedbuf, SEEDBYTES)`(keypair, 32B)와
`randombytes(rnd, RNDBYTES)`(signature, 32B)는 GPU 커널에서 호출 불가.
→ 호스트에서 서명 B개분 시드를 미리 생성해 배열로 전송하고,
각 스레드가 자기 시드를 사용하도록 커널 인자로 주입할 예정.
결정론(KAT) 모드도 이 경로로 고정 시드를 넣어 검증에 사용.

---

## 3. 아직 손대지 않은 것

- `sign.c`, `poly.c`, `polyvec.c`, `ntt.c`, `reduce.c`, `rounding.c`,
  `packing.c`, `symmetric-shake.c` 의 디바이스화(`__device__` 부착)는 다음 단계.
- 이들은 가변 전역 상태가 없고 순수 계산 함수임을 확인함(개조 난이도 낮음).
- 앞서 만든 협력형 `kernels/ntt.cu`(버터플라이를 여러 스레드로 분할)는
  "1블록=1서명" 모델용이므로, 현재 "1스레드=1서명" 모델에서는 **미사용**.
  향후 내부 병렬화(2단계 최적화) 때 재활용 예정.

---

## 4. 전체 소스 디바이스화 — `device_port/*.{c,h}` (이번 단계)

원본: `third_party/mldsa87_clean/` → 개조판: `device_port/` (원본 이름 유지)

### 변경 4-A. `MLD_HD` 한정자 부착
- `params.h`에 매크로 정의 추가:
  ```
  #ifdef __CUDACC__
  #define MLD_HD __host__ __device__
  #else
  #define MLD_HD
  #endif
  ```
- 대상 파일의 모든 함수 정의·선언 앞에 `MLD_HD` 부착:
  sign.c(9), poly.c(28), polyvec.c(26), ntt.c(2), reduce.c(4),
  rounding.c(4), packing.c(6), symmetric-shake.c(2) + 대응 헤더들.
- 효과: nvcc에서 host/device 양쪽 컴파일, 일반 C에서는 빈 매크로.

### 변경 4-B. fips202 include 연결
- sign.c / symmetric-shake.c / symmetric.h 의 `#include "fips202.h"`
  → `#include "fips202_dev.h"` (2절의 고정배열 개조판).

### 변경 4-C. 난수 시드 주입 (randombytes 제거)
**이유:** randombytes는 OS 시스템콜(getrandom, /dev/urandom)이라 GPU 커널에서
호출 불가. 엔트로피 출처는 CPU에 두고, 시드를 인자로 주입.

- `crypto_sign_keypair(pk, sk)` → `(pk, sk, const uint8_t *seed)`.
  내부 `randombytes(seedbuf, SEEDBYTES)` → `memcpy(seedbuf, seed, SEEDBYTES)`.
- `crypto_sign_signature_ctx(...)` 끝에 `const uint8_t *rnd_in` 추가.
  내부 `randombytes(rnd, RNDBYTES)` → `memcpy(rnd, rnd_in, RNDBYTES)`.
- 이를 호출하는 래퍼 4개(crypto_sign_ctx / crypto_sign /
  crypto_sign_signature)도 `rnd_in`을 받아 통과하도록 시그니처 확장.
- sign.h 선언 5개 동기화.
- sign.c에 `#include <string.h>`(memcpy) 추가.
- 결정론(KAT) 모드: seed/rnd에 고정값을 넣으면 재현 가능.

### 검증 (이 환경, GPU 없이)
- 개조판 전체를 순수 C로 컴파일(경고 0) → keygen→sign→verify 동작 확인.
- **동일 고정 시드** 하에서 원본 PQClean(내부 randombytes를 같은 상수로 스텁)과
  대조: **공개키·서명 모두 바이트 단위 완전 일치**.
- 결론: 디바이스화·시드주입이 계산 결과를 바꾸지 않음(원본과 수학적 동일).
- 한계: nvcc 없어 **디바이스 실제 컴파일·실행은 미검증**. 특히 GPU에서는
  `memcpy`/`<string.h>` 대체, `mat[K]`≈56KB 스택(스레드 로컬 부담) 등
  추가 조정이 필요할 수 있음(다음 단계 최적화 대상).
