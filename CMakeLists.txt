cmake_minimum_required(VERSION 3.16)
project(rate_limiter)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)

# Find hiredis
pkg_check_modules(HIREDIS REQUIRED hiredis)

# Add executable
add_executable(rate_limiter main.cpp)

# Include directories for header-only libraries
target_include_directories(rate_limiter PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/httplib
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/json/include
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/redis-plus-plus/src
)

# Link libraries
target_link_libraries(rate_limiter 
    PRIVATE 
    ${HIREDIS_LIBRARIES}
    redis++
    Threads::Threads
)

# Compiler flags
target_compile_options(rate_limiter PRIVATE 
    -Wall 
    -Wextra 
    -O3 
    -DNDEBUG
    ${HIREDIS_CFLAGS_OTHER}
)

# Link directories
target_link_directories(rate_limiter PRIVATE ${HIREDIS_LIBRARY_DIRS})

# For Apple Silicon optimization
if(APPLE AND CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
    target_compile_options(rate_limiter PRIVATE -mcpu=apple-m1)
endif()