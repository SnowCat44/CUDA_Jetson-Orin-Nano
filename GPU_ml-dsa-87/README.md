# ML-DSA-87 KeyGen — CUDA 베이스라인

PQClean `ml-dsa-87/clean` 의 **KeyGen** 을 GPU에서 도는 **단일 스레드 CUDA 베이스라인**으로 옮긴 것입니다.
목적은 성능이 아니라 **"GPU에서 CPU와 바이트 단위로 동일한 pk/sk가 나온다"** 를 확인하는 발판입니다.

> ⚠️ **이 코드는 GPU가 없는 환경에서 생성되었으며, 컴파일·실행 검증이 되지 않았습니다.**
> `cuda/` 쪽은 nvcc/실제 GPU에서 처음 빌드할 때 C→C++ 관련 수정이 몇 군데 필요할 수 있습니다.
> 반면 `ref/`(CPU 참조)는 생성 환경에서 빌드·실행을 확인했습니다.

---

## 구성

```
mldsa87-keygen-cuda/
├── cuda/      GPU 포트 (nvcc 로 빌드)         ← 검증 대상
├── ref/       CPU 참조 (원본 clean, 무수정)   ← 비교 기준(오라클)
├── EXPECTED.txt  ref 실행 결과(기대 pk/sk)     ← 빠른 눈대중 확인용
└── README.md
```

## 변환 원칙: "본문 보존, 필요한 것만 변경"

`cuda/` 의 알고리즘 본문(암호 계산 로직)은 **원본과 한 글자도 다르지 않습니다.** GPU에 꼭 필요한 것만 기계적으로 바꿨습니다:

1. **함수 한정자**: 모든 알고리즘 함수에 `__device__` 부여 (총 122개).
2. **상수 테이블 → `__constant__`**: `zetas[256]`(ntt.cu), `KeccakF_RoundConstants[24]`(fips202.cu). 값·순서 불변.
3. **fips202 `malloc` 제거**: ctx 구조체를 포인터(`uint64_t *ctx`)에서 **고정 배열**(`uint64_t ctx[26]`)로 바꿔 21곳의 `malloc/free/exit` 제거. 디바이스 힙 불필요.
4. **시드 분리(R1)**: `crypto_sign_keypair` 의 `randombytes()` 호출만 떼어내고, **32바이트 시드를 커널 인자로** 받도록 `keygen.cu` 로 재구성. 나머지 로직은 원본과 동일.

`randombytes.c` 는 OS 난수(디바이스 불가)라 GPU 포트에 포함하지 않았습니다(시드는 호스트가 공급).

---

## 빌드 & 실행

### 1) GPU 포트 (cuda/)
```bash
cd cuda
make ARCH=-arch=sm_86      # 본인 GPU 아키텍처로 조정 (sm_80/86/89/90 등)
./mldsa87_keygen_cuda      # pk/sk 16진수를 stdout 으로 출력
```
- **`-rdc=true` 필수** (Makefile에 포함): 여러 `.cu` 에 흩어진 `__device__` 함수를 서로 호출하므로 relocatable device code가 필요합니다.

### 2) CPU 참조 (ref/)
```bash
cd ref
make
./mldsa87_keygen_ref       # 동일 형식으로 pk/sk 출력
```

### 3) 검증 (바이트 일치)
두 실행의 **stdout(pk/sk 16진수)** 을 비교합니다. 진단 메시지는 stderr 로 빠지므로 diff 에 섞이지 않습니다.
```bash
diff <(./ref/mldsa87_keygen_ref 2>/dev/null) <(./cuda/mldsa87_keygen_cuda 2>/dev/null) \
  && echo "일치: GPU KeyGen 정확성 OK"
```
빠른 눈대중 확인: 고정 시드 `00 01 02 … 1f` 에서 **pk 첫 줄(rho, 32B)** 은
```
9792bcec2f2430686a82fccf3c2f5ff665e771d7ab41b90258cfa7e90ec97124
```
(전체 기대값은 `EXPECTED.txt`)

---

## 단계별 벤치마크 (bench/)

`crypto_sign_keypair` 안의 각 연산 함수 호출을 타이머로 감싸 **단계별 소요시간**을 잽니다.
비교 단위는 **µs 로 통일**하되, 도달 방법이 장치별로 다릅니다.

- **CPU** (`bench/keypair_bench.c`): `clock_gettime(CLOCK_MONOTONIC)` 로 µs **직접** 측정. 원본 로직 그대로 복제하고 타이머만 추가. 워밍업 후 1000회 반복 → 단계별 **mean/median/min(µs)**.
- **GPU** (`bench/keygen_bench.cu`): 커널 내부 `clock64()` 로 단계별 **사이클** 측정. 100회 반복 → 단계별 사이클 **중앙값**을, 사용자가 준 GPU 클럭(MHz)으로 나눠 **µs 환산**. 출력에 **사이클과 µs 를 함께** 표기.

측정 단계(원본 호출 순서): seed_expand · ExpandA · ExpandS(s1) · ExpandS(s2) · NTT(s1) · matvec · reduce · invNTT · add · caddq · power2round · pack_pk · H(pk) · pack_sk.

```bash
cd bench
make cpu                       # CPU 계측판
./keypair_bench                # 단계별 µs (mean/median/min)

make gpu ARCH=-arch=sm_86      # GPU 계측판 (본인 아키텍처로)
./keygen_bench 1410            # 인자 = GPU SM 클럭(MHz). nvidia-smi 로 실제값 확인해 입력
```

> 참고: GPU µs 는 `clock64()` 사이클 ÷ 지정 클럭입니다. 부스트/스로틀로 실제 클럭이 변하면 오차가 생기므로, 사이클 원본도 함께 출력합니다(필요 시 정확한 클럭으로 재환산). CPU 는 벽시계를 직접 재므로 환산이 필요 없습니다.

## 한계 · 주의

- **성능**: `<<<1,1>>>` 단일 스레드라 **의도적으로 느립니다**(병렬성 0). 이 단계는 정확성 발판이며, 병렬화(HASH·NTT)는 다음 단계입니다.
- **sign/verify 미포함**: 이번 범위는 KeyGen. `sign()`/`verify()` 는 동일한 시드/난수 분리 리팩터가 필요해 이 베이스라인에는 넣지 않았습니다.
- **로컬 메모리**: 커널이 `polyvecl mat[K]` 등 큰 지역 배열(합 ~90KB/스레드)을 써서 로컬 메모리를 많이 씁니다. 실행 실패 시 스택 한도 상향(`cudaDeviceSetLimit(cudaLimitStackSize, ...)`)이 필요할 수 있습니다.
- **보안**: `ref/randombytes.c` 와 `cuda/main.cu` 의 시드는 **검증용 고정값**입니다. 실제 키 생성에 절대 쓰지 마세요.
- **첫 컴파일 수정 가능성**: `.cu` 는 C++(nvcc)로 컴파일되어, C에선 통과하던 일부 패턴(`void*` 암묵 변환 등)이 걸릴 수 있습니다. 처음 빌드 시 나오는 오류를 따라 수정하세요.
