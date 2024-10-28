set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")

set(triple "x86_64-unknown-linux-musl")

get_filename_component(TOOLCHAIN_DIR "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)

set(CMAKE_C_COMPILER "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-gcc")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-g++")
set(CMAKE_Fortran_COMPILER "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-gfortran")
set(CMAKE_AR "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-ar")
set(CMAKE_AS "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-as")
set(CMAKE_LD "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-ld")
set(CMAKE_LINKER "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-ld" CACHE FILEPATH "ld")
set(CMAKE_RANLIB "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-ranlib" CACHE FILEPATH "ranlib")
set(CMAKE_OBJCOPY "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-objcopy" CACHE FILEPATH "objcopy")
set(CMAKE_OBJDUMP "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-objdump" CACHE FILEPATH "objdump")
set(CMAKE_STRIP "${TOOLCHAIN_DIR}/bin/x86_64-unknown-linux-musl-strip" CACHE FILEPATH "strip")

set(CMAKE_C_COMPILER_TARGET ${triple})
set(CMAKE_CXX_COMPILER_TARGET ${triple})
set(CMAKE_Fortran_COMPILER_TARGET ${triple})

set(CMAKE_SYSROOT "${TOOLCHAIN_DIR}")
set(CMAKE_FIND_ROOT_PATH "${TOOLCHAIN_DIR}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_EXE_LINKER_FLAGS "-static -static-libgcc -static-libstdc++")
set(CMAKE_MODULE_LINKER_FLAGS "-static -static-libgcc -static-libstdc++ -static-libgfortran")
set(CMAKE_SHARED_LINKER_FLAGS "-static -static-libgcc -static-libstdc++ -static-libgfortran")
