cmake_minimum_required(VERSION 3.16)
project(oep_core C CXX)

# OEP core: portable part of the player (XP3 reader, engine detection, scan,
# logging).  No Apple/Windows specific API beyond <filesystem>, so it builds and
# is tested on the Windows development machine and is compiled unchanged into
# the iOS app.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

if(MSVC)
    # Sources are UTF-8; /utf-8 also silences C4819 on the Japanese Windows locale.
    add_compile_options(/utf-8)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

option(OEP_BUILD_TESTS "build the core test binary" ON)
option(OEP_BUILD_CLI "build the oep-cli tool" ON)

add_library(oep_core STATIC
    src/xp3.cpp
    src/detect.cpp
    src/scan.cpp
    src/pack.cpp
    src/log.cpp
    src/platform.cpp
    third_party/miniz/miniz.c
    third_party/miniz/miniz_tdef.c
    third_party/miniz/miniz_tinfl.c
)

target_include_directories(oep_core
    PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src
            ${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz
)

set_target_properties(oep_core PROPERTIES
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)

if(MSVC)
    target_compile_options(oep_core PRIVATE /W4 /permissive- /wd4244 /wd4267)
else()
    target_compile_options(oep_core PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

# The engine links this library into the iOS app; keep a plain static archive.
if(WIN32)
    # CommandLineToArgvW (UTF-16 command line -> UTF-8 arguments)
    target_link_libraries(oep_core PUBLIC shell32)
endif()

if(OEP_BUILD_CLI)
    add_executable(oep_cli tools/oep_cli.cpp)
    target_link_libraries(oep_cli PRIVATE oep_core)
    set_target_properties(oep_cli PROPERTIES OUTPUT_NAME oep-cli)
endif()

if(OEP_BUILD_TESTS)
    enable_testing()
    add_executable(oep_tests tests/test_main.cpp)
    target_link_libraries(oep_tests PRIVATE oep_core)
    target_include_directories(oep_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz)
    add_test(NAME oep_core_tests COMMAND oep_tests)
endif()
