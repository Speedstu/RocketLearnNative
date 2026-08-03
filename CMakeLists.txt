cmake_minimum_required(VERSION 3.24)
project(RocketLearnNative LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

set(ROCKETSIM_DIR "${CMAKE_CURRENT_LIST_DIR}/third_party/RocketSim" CACHE PATH "RocketSim source directory")
set(TORCH_ROOT "${CMAKE_CURRENT_LIST_DIR}/third_party/libtorch" CACHE PATH "LibTorch root")

if(NOT EXISTS "${ROCKETSIM_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "RocketSim not found at ${ROCKETSIM_DIR}")
endif()
if(NOT EXISTS "${TORCH_ROOT}/lib/torch.lib")
  message(FATAL_ERROR "LibTorch not found at ${TORCH_ROOT}")
endif()

add_subdirectory("${ROCKETSIM_DIR}" "${CMAKE_BINARY_DIR}/rocketsim")

add_executable(rocket_learn_native
  cpp/main.cpp
  cpp/heatseeker_env.cpp
  cpp/ppo.cpp
)

add_executable(rocket_learn_visualizer
  cpp/visualize_main.cpp
  cpp/heatseeker_env.cpp
)

add_executable(rocket_learn_evaluator
  cpp/evaluate_main.cpp
  cpp/heatseeker_env.cpp
)

add_executable(rocket_kuxir_native
  cpp/kuxir_main.cpp
  cpp/kuxir_env.cpp
  cpp/kuxir_ppo.cpp
)

add_executable(rocket_kuxir_visualizer
  cpp/kuxir_visualize_main.cpp
  cpp/kuxir_env.cpp
)

target_include_directories(rocket_learn_native PRIVATE
  cpp
  "${ROCKETSIM_DIR}/src"
  "${TORCH_ROOT}/include"
  "${TORCH_ROOT}/include/torch/csrc/api/include"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/cuda118-sdk/nvidia/cuda_runtime/include"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/cuda118-sdk/nvidia/cuda_nvcc/include"
)
target_include_directories(rocket_learn_visualizer PRIVATE
  cpp
  "${ROCKETSIM_DIR}/src"
  "${TORCH_ROOT}/include"
  "${TORCH_ROOT}/include/torch/csrc/api/include"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/cuda118-sdk/nvidia/cuda_runtime/include"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/cuda118-sdk/nvidia/cuda_nvcc/include"
)
target_include_directories(rocket_learn_evaluator PRIVATE
  cpp
  "${ROCKETSIM_DIR}/src"
  "${TORCH_ROOT}/include"
  "${TORCH_ROOT}/include/torch/csrc/api/include"
)
target_include_directories(rocket_kuxir_native PRIVATE
  cpp
  "${ROCKETSIM_DIR}/src"
  "${TORCH_ROOT}/include"
  "${TORCH_ROOT}/include/torch/csrc/api/include"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/cuda118-sdk/nvidia/cuda_runtime/include"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/cuda118-sdk/nvidia/cuda_nvcc/include"
)
target_include_directories(rocket_kuxir_visualizer PRIVATE
  cpp
  "${ROCKETSIM_DIR}/src"
  "${TORCH_ROOT}/include"
  "${TORCH_ROOT}/include/torch/csrc/api/include"
)

target_compile_definitions(rocket_learn_native PRIVATE RS_MAX_SPEED RS_DONT_LOG NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(rocket_learn_native PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/O2 /Ob3 /GL /fp:fast /arch:AVX2 /EHsc /bigobj>)
target_link_options(rocket_learn_native PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/LTCG>)
target_compile_definitions(rocket_learn_visualizer PRIVATE RS_MAX_SPEED RS_DONT_LOG NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(rocket_learn_visualizer PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/O2 /Ob3 /GL /fp:fast /arch:AVX2 /EHsc /bigobj>)
target_link_options(rocket_learn_visualizer PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/LTCG>)
target_compile_definitions(rocket_learn_evaluator PRIVATE RS_MAX_SPEED RS_DONT_LOG NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(rocket_learn_evaluator PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/O2 /Ob3 /GL /fp:fast /arch:AVX2 /EHsc /bigobj>)
target_link_options(rocket_learn_evaluator PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/LTCG>)
target_compile_definitions(rocket_kuxir_native PRIVATE RS_MAX_SPEED RS_DONT_LOG NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(rocket_kuxir_native PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/O2 /Ob3 /GL /fp:fast /arch:AVX2 /EHsc /bigobj>)
target_link_options(rocket_kuxir_native PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/LTCG>)
target_compile_definitions(rocket_kuxir_visualizer PRIVATE RS_MAX_SPEED RS_DONT_LOG NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(rocket_kuxir_visualizer PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/O2 /Ob3 /GL /fp:fast /arch:AVX2 /EHsc /bigobj>)
target_link_options(rocket_kuxir_visualizer PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/LTCG>)

target_link_libraries(rocket_learn_native PRIVATE
  RocketSim
  "${TORCH_ROOT}/lib/torch.lib"
  "${TORCH_ROOT}/lib/torch_cpu.lib"
  "${TORCH_ROOT}/lib/torch_cuda.lib"
  "${TORCH_ROOT}/lib/c10.lib"
  "${TORCH_ROOT}/lib/c10_cuda.lib"
  "${TORCH_ROOT}/lib/kineto.lib"
)
target_link_libraries(rocket_learn_visualizer PRIVATE
  RocketSim ws2_32
  "${TORCH_ROOT}/lib/torch.lib"
  "${TORCH_ROOT}/lib/torch_cpu.lib"
  "${TORCH_ROOT}/lib/c10.lib"
)
target_link_libraries(rocket_learn_evaluator PRIVATE
  RocketSim
  "${TORCH_ROOT}/lib/torch.lib"
  "${TORCH_ROOT}/lib/torch_cpu.lib"
  "${TORCH_ROOT}/lib/c10.lib"
)
target_link_libraries(rocket_kuxir_native PRIVATE
  RocketSim
  "${TORCH_ROOT}/lib/torch.lib"
  "${TORCH_ROOT}/lib/torch_cpu.lib"
  "${TORCH_ROOT}/lib/torch_cuda.lib"
  "${TORCH_ROOT}/lib/c10.lib"
  "${TORCH_ROOT}/lib/c10_cuda.lib"
  "${TORCH_ROOT}/lib/kineto.lib"
)
target_link_libraries(rocket_kuxir_visualizer PRIVATE
  RocketSim ws2_32
  "${TORCH_ROOT}/lib/torch.lib"
  "${TORCH_ROOT}/lib/torch_cpu.lib"
  "${TORCH_ROOT}/lib/c10.lib"
)

set_target_properties(rocket_learn_native PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
set_target_properties(rocket_learn_visualizer PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
set_target_properties(rocket_learn_evaluator PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
set_target_properties(rocket_kuxir_native PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
set_target_properties(rocket_kuxir_visualizer PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
