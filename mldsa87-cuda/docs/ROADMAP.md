# 로드맵

> Claude가 생성한 계획 뼈대. 각 단계는 제안이며 우선순위는 조정 가능.

## Phase 0 — 골격 (현재 위치)
- [x] 디렉토리 구성
- [x] CPU 참조 구현 (PQClean clean) 편입
- [x] 빌드 설정 (CMake) 뼈대
- [x] API 헤더·커널 스텁
- [ ] 참조 구현이 본 프로젝트 내에서 빌드·실행되는지 확인

## Phase 1 — 검증 기반
- [ ] CPU 참조로 keygen/sign/verify를 돌리는 하네스
- [ ] KAT 대조 유틸 (고정 시드 RNG)
- [ ] GPU 출력과 CPU 출력을 비교하는 틀 (아직 GPU는 비어 있음)

## Phase 2 — 단위 커널 (보텀업)
- [~] `ntt.cu` : dev_ntt / dev_invntt_tomont 포팅 완료. 포팅 인덱싱 로직을
      순수 C 시뮬레이션으로 참조와 계수 일치 검증(1000회 통과). **GPU 실빌드·실행 검증은 미실시**(이 환경에 nvcc 없음).
- [ ] `reduce` / `rounding` 의 디바이스 함수화
- [ ] `shake.cu` : Keccak-f[1600]. 알려진 테스트벡터로 검증

## Phase 3 — 단계 커널
- [ ] `keygen.cu` : 배치 키생성 → CPU 참조와 일치 확인
- [ ] `verify.cu` : 배치 검증 (반복 없어 비교적 수월)
- [ ] `sign.cu` : rejection sampling 포함 서명. CPU verify 통과 확인

## Phase 4 — 통합·최적화
- [ ] H2D/D2H 집약, 스트림 다중화
- [ ] shared memory / constant memory 활용
- [ ] throughput 벤치(서명/초)를 clean CPU와 비교

## Phase 5 — 발전 (선택)
- [ ] reject 서명의 compaction 재투입
- [ ] 다중 SHAKE 동시 처리
- [ ] ml-dsa-44 / 65 로 파라미터 일반화
