cmake_minimum_required(VERSION 3.18.1)

project(fishengine)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(PIKAFISH_SRC_DIR ${CMAKE_SOURCE_DIR}/pikafish/src)

file(GLOB PIKAFISH_SOURCES
    ${PIKAFISH_SRC_DIR}/*.cpp
    ${PIKAFISH_SRC_DIR}/nnue/*.cpp
    ${PIKAFISH_SRC_DIR}/nnue/features/*.cpp
    ${PIKAFISH_SRC_DIR}/nnue/layers/*.cpp
    ${PIKAFISH_SRC_DIR}/external/common/*.cpp
    ${PIKAFISH_SRC_DIR}/external/decompress/*.cpp
)

list(REMOVE_ITEM PIKAFISH_SOURCES ${PIKAFISH_SRC_DIR}/main.cpp)
list(REMOVE_ITEM PIKAFISH_SOURCES ${PIKAFISH_SRC_DIR}/benchmark.cpp)
# Remove universal entry points - they define main() which conflicts with the library build
list(FILTER PIKAFISH_SOURCES EXCLUDE REGEX "universal/")

add_library(
    fishengine
    SHARED
    engine_wrapper.cpp
    ${PIKAFISH_SOURCES}
)

include_directories(
    ${PIKAFISH_SRC_DIR}
    ${PIKAFISH_SRC_DIR}/nnue
    ${PIKAFISH_SRC_DIR}/nnue/features
    ${PIKAFISH_SRC_DIR}/nnue/layers
    ${PIKAFISH_SRC_DIR}/external
    ${PIKAFISH_SRC_DIR}/external/common
    ${PIKAFISH_SRC_DIR}/external/decompress
)

target_compile_definitions(fishengine PRIVATE
    NNUE_EMBEDDING_OFF
)

target_compile_options(fishengine PRIVATE
    -Wno-unused-parameter
    -Wno-sign-compare
    -Wno-reorder
    -Wno-missing-field-initializers
)

target_link_libraries(
    fishengine
    android
    log
)
