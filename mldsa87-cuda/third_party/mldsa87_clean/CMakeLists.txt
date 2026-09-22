# third_party/mldsa87_clean/CMakeLists.txt
# 참고 (Claude 생성): PQClean ML-DSA-87 clean 구현을 검증용 라이브러리로 만드는 뼈대.
# 내부의 .c/.h는 PQClean 유래 (수정 금지). randombytes는 환경 의존.

add_library(mldsa87_clean_ref STATIC
  sign.c
  packing.c
  polyvec.c
  poly.c
  ntt.c
  reduce.c
  rounding.c
  symmetric-shake.c
  fips202.c
  randombytes.c
)
target_include_directories(mldsa87_clean_ref PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
