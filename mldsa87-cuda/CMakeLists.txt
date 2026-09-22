# CMakeLists.txt — mldsa87-cuda (1스레드=1서명 배치 구현)
# 참고 (Claude 생성): CUDA Toolkit과 nvcc 필요. 커널 미실행 환경에서 작성됨.

cmake_minimum_required(VERSION 3.18)
project(mldsa87_cuda LANGUAGES C CXX CUDA)

set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CXX_STANDARD 17)

if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
  set(CMAKE_CUDA_ARCHITECTURES 80 86 89 90)
endif()

option(MLDSA_BUILD_TESTS "Build correctness tests" ON)

# --- CPU 참조 라이브러리 (PQClean clean, 원본 보존) ---
add_subdirectory(third_party/mldsa87_clean)

# --- 디바이스화된 ML-DSA 소스 (device_port) ---
#     .c 파일이지만 nvcc가 디바이스 코드로 컴파일하도록 CUDA 언어로 취급
set(DEVPORT_SRC
  device_port/fips202_dev.c
  device_port/sign.c
  device_port/poly.c
  device_port/polyvec.c
  device_port/ntt.c
  device_port/reduce.c
  device_port/rounding.c
  device_port/packing.c
  device_port/symmetric-shake.c
)
set_source_files_properties(${DEVPORT_SRC} PROPERTIES LANGUAGE CUDA)

# --- GPU 라이브러리 (배치 커널 + 호스트 오케스트레이션 + 디바이스 함수) ---
add_library(mldsa87_gpu
  src/batch_host.cu
  kernels/batch_kernels.cu
  ${DEVPORT_SRC}
)
target_include_directories(mldsa87_gpu PUBLIC include device_port)
set_target_properties(mldsa87_gpu PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
# device_port는 랜덤시드를 인자로 받으므로 randombytes.c는 호스트 전용으로 별도 링크
target_sources(mldsa87_gpu PRIVATE third_party/mldsa87_clean/randombytes.c)

# --- 테스트 ---
if(MLDSA_BUILD_TESTS)
  add_executable(test_batch tests/test_batch.cu)
  target_link_libraries(test_batch PRIVATE mldsa87_gpu mldsa87_clean_ref)
  target_include_directories(test_batch PRIVATE include device_port third_party/mldsa87_clean)
endif()
