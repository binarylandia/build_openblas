# Prebuilt static OpenBLAS libraries for multiple platforms

## [Releases](https://github.com/binarylandia/build_openblas/releases)

Cross-compiles [OpenBLAS](https://github.com/OpenMathLib/OpenBLAS) as static libraries with LAPACK support for Linux, macOS, Windows, and WebAssembly targets. Includes variants with threading and ReLAPACK optimizations.

Every target builds the same OpenBLAS source: develop commit `de5d4914`, the 432nd commit after `v0.3.34`, which the archive version names as `git describe` does (`0.3.34-432-gde5d4914`). It has the fixes for the dgemm stack overflow on AMD Zen 4 and Zen 5 servers that `v0.3.34` lacks, and C LAPACK functions and an `xerbla` that take no hidden string lengths and return `void`, which WebAssembly needs.

## Variants

- **plain**: Single-threaded, standard LAPACK
- **threads**: Multi-threaded (up to 64 threads)
- **relapack**: ReLAPACK recursive algorithms in place of the LAPACK ones they cover; GEMMT stays the one of OpenBLAS
- **threads-relapack**: Multi-threaded with ReLAPACK

## Native targets

Every native target builds with clang and flang of LLVM 22.1.8 ([binarylandia/build_llvm](https://github.com/binarylandia/build_llvm), release `llvm-22.1.8-2026-10-18_10-26-24`) on the C library and system files of a target toolchain:

| Target | Target toolchain | Oldest system |
| --- | --- | --- |
| `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu` | crosstool-NG GCC 16.2.0 ([binarylandia/build_crosstool-ng](https://github.com/binarylandia/build_crosstool-ng)): sysroot, crt files, libgcc | glibc 2.17 |
| `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl` | crosstool-NG GCC 16.2.0: musl 1.2.6, crt files, libgcc | none (static) |
| `x86_64-apple-darwin`, `aarch64-apple-darwin` | osxcross with the macOS 11.1 SDK and compiler-rt ([binarylandia/build_osxcross](https://github.com/binarylandia/build_osxcross)) | macOS 10.12 (x86_64), 11.0 (arm64) |
| `x86_64-pc-windows-gnullvm`, `aarch64-pc-windows-gnullvm` | llvm-mingw of the LLVM release: mingw-w64 with the UCRT, compiler-rt | Windows 10; Windows 7 and 8 with the Universal C Runtime update (untested) |
| `x86_64-win7-windows-gnu` | crosstool-NG MinGW GCC 16.2.0: mingw-w64 v14.0.0 with msvcrt, crt files, libgcc, winpthreads | Windows 7 |

The C and Fortran code and flang-rt compile for the CPU baseline of the programs that link the archives (`TARGET_CPU_FLAGS` of the build image):

| Target | CPU flags |
| --- | --- |
| x86_64 targets | `-march=x86-64-v2` |
| `aarch64-unknown-linux-gnu`, `aarch64-unknown-linux-musl` | `-march=armv8-a -moutline-atomics` |
| `aarch64-pc-windows-gnullvm` | `-march=armv8-a+lse` |
| `aarch64-apple-darwin` | `-mcpu=apple-m1` |

OpenBLAS adds the flags of a CPU after them for the kernels of that CPU, which it selects at run time (`DYNAMIC_ARCH`). On aarch64, it also adds the `-march` of its target CPU for the rest of the code (`Makefile.arm64`): `-march=armv8-a` for `ARMV8` (Linux and Windows) and `-march=armv8.3-a` for `VORTEX` (macOS), so that code compiles for Armv8.0 without LSE on Windows and for Armv8.3 on macOS, both within the baseline.

The build image builds the Fortran runtime flang-rt for its target from the LLVM source of the same release (`docker/files/build-llvm-runtimes`), with the patches of `patches/llvm-<version>/flang-rt/`, which apply only to that LLVM version. The patches of LLVM 22.1.8 make flang-rt compile with the libstdc++ headers and the msvcrt headers of mingw-w64:

- `0001-mingw-getpid.patch`: uses the `getpid` of `process.h`, which the libstdc++ headers include through `pthread.h` of winpthreads, in place of the `getpid` that flang-rt defines for Windows with another return type
- `0002-msvcrt-system-clock.patch`: `SYSTEM_CLOCK` reads the UTC time with `GetSystemTimeAsFileTime` where the C runtime has no `timespec_get` with `TIME_UTC`, as msvcrt

Each change applies only where the unpatched source does not compile (`_CRT_GETPID_DEFINED`, Windows without `TIME_UTC`), and `#line` keeps the line numbers of the unpatched source, which the runtime names in its error messages. Every target builds the patched source: built from the same directory, flang-rt for `x86_64-pc-windows-gnullvm`, `x86_64-unknown-linux-gnu`, and `x86_64-apple-darwin` is byte for byte the same archive with and without the patches.

An archive holds:

- `lib/libopenblas.a`: BLAS, CBLAS, LAPACK, and LAPACKE, with the kernels of every CPU of the architecture (`DYNAMIC_ARCH`)
- `lib/libflang_rt.runtime.a`: the Fortran runtime of the flang that compiled LAPACK, static and position-independent, with its license in `share/doc/flang-rt/LICENSE.TXT` and the patches of its source in `share/doc/flang-rt/patches/`
- headers, and pkg-config and CMake files that name both libraries. The pkg-config file `lib/pkgconfig/openblas.pc` names its folders relative to itself (`libdir=${pcfiledir}/..`, `includedir=${pcfiledir}/../../include`), so `PKG_CONFIG_LIBDIR=<folder>/lib/pkgconfig pkg-config --libs --cflags openblas` works wherever the archive is unpacked

A program links both archives and then needs only the C library of the target:

- Linux: `cc main.c libopenblas.a libflang_rt.runtime.a -lm -lpthread` needs glibc 2.17 on gnu targets, and nothing on musl targets when it links statically
- macOS: `cc main.c libopenblas.a libflang_rt.runtime.a` loads only `/usr/lib/libSystem.B.dylib`
- Windows (`*-pc-windows-gnullvm`): `x86_64-w64-mingw32-clang main.c libopenblas.a libflang_rt.runtime.a` imports only `KERNEL32.dll` and the UCRT (`api-ms-win-crt-*.dll`). The archives use the UCRT, so they do not link with toolchains for msvcrt
- Windows 7 (`x86_64-win7-windows-gnu`): `x86_64-w64-mingw32-gcc -static main.c libopenblas.a libflang_rt.runtime.a` imports only `KERNEL32.dll` and `msvcrt.dll`, and no function of Windows 8 or later. The archives use msvcrt and link with the MinGW GCC toolchains for msvcrt, such as the one of the Rust target `x86_64-win7-windows-gnu`. `-static` links libgcc and winpthreads, whose `clock_gettime` the `RANDOM_INIT` of flang-rt calls, into the program

The archives need no C++ runtime and no unwinder. They call the compiler support routines of libgcc or compiler-rt (128-bit integer and floating-point arithmetic, complex multiplication and division, aarch64 atomics), which C compilers link by default.

Every build checks each archive:

- the kernels of every core of `DYNAMIC_ARCH` are present
- `libopenblas.a` calls no gfortran runtime, `libflang_rt.runtime.a` defines every Fortran runtime function that it calls, and neither archive needs a C++ runtime
- pkg-config, with the pkg-config file of the archive as its only search folder, names the library and header folders of the archive, `-lopenblas`, and `-lflang_rt.runtime`
- on macOS, no object needs a newer macOS than the deployment target, and both archives have the BSD symbol table that the linker of Xcode needs
- a C program (`scripts/consumer-check.c`) that calls `dgemm_`, `sgemm_`, `dsyev_`, `dgttrf_`, and `dgttrs_` links both archives, once as a consumer does and once with every object of `libopenblas.a`, and needs no shared library beyond the system ones above; on macOS, its minimum macOS version is the deployment target
- on `x86_64-win7-windows-gnu`, the program links with the MinGW GCC driver, imports only system DLLs of Windows 7 (`KERNEL32.dll`, `msvcrt.dll`, `ADVAPI32.dll`, `SHELL32.dll`, `USER32.dll`), no `ucrtbase.dll` or `api-ms-win-*.dll`, and none of the functions of Windows 8 or later. The build lists these functions from the mingw-w64 headers of the toolchain: the functions that a header declares with `_WIN32_WINNT=0x0A00` and the newest `NTDDI_VERSION` and not with `_WIN32_WINNT=0x0601` (the headers guard them with `_WIN32_WINNT >= 0x0602` or the `NTDDI` macros), each header compiled on its own after `windows.h`, plus the exports that `msvcrt.dll` gained in Windows 8 and 8.1 (`msvcrt.def.in` of mingw-w64), which the headers do not guard. The list lacks the functions of Windows 8 or later that the headers declare without a guard, such as `GetSystemTimePreciseAsFileTime` and `WaitOnAddress`
- the program computes the known results: natively on x86_64 Linux, under Wine on x86_64 Windows, and under `qemu-aarch64` on aarch64 Linux, there once with the detected core and once with each core forced through `OPENBLAS_CORETYPE`
- the OpenBLAS tests pass (`make tests`: the BLAS, CBLAS, and unit tests), started directly on x86_64 Linux, under Wine on x86_64 Windows, and under `qemu-aarch64` on aarch64 Linux

macOS programs and aarch64 Windows programs do not run on the Linux build machine: their builds link the check program and the OpenBLAS tests without running them.

The aarch64 archives leave out two cores, whose kernels compute wrong results on some CPUs that OpenBLAS selects them for:

- `ARMV9SME` (`NO_SME=1`): the SME GEMM kernels are correct only with a streaming vector length of 512 bits, while OpenBLAS selects them on any CPU with SME. These CPUs use the kernels of their SVE or Neoverse N1 core. On macOS, `NO_SME=1` also leaves out `VORTEXM4`, so Apple M4 uses the Neoverse N1 kernels as the other Apple CPUs do
- `ARMV8SVE`, the generic SVE core for SVE CPUs that OpenBLAS does not recognize: its SSYRK and SSYR2K kernels are wrong at SVE vector lengths above 128 bits, and its DSYRK and DSYR2K kernels at 512 bits. These CPUs use the `ARMV8` kernels

The aarch64 Linux builds also run the level-3 BLAS tests of the remaining SVE cores under `qemu-aarch64` at SVE vector lengths of 128, 256, and 512 bits, `NEOVERSEV1` without 512 bits (its DSYRK and DSYR2K kernels are wrong there, and OpenBLAS selects it only for Neoverse V1, whose SVE vector length is 256 bits), and of `CORTEXA72` once.

The aarch64 Windows archive has the kernels of the aarch64 Linux archives, but OpenBLAS detects no CPU on Windows and uses the `ARMV8` kernels, unless `OPENBLAS_CORETYPE` names a core, for example `NEOVERSEN1`.

## WebAssembly

The `wasm32-unknown-emscripten` target builds OpenBLAS with `emcc` for `TARGET=WASM128_GENERIC` (SIMD128 kernels), with LAPACK from the C translation that ships with OpenBLAS, plus the patches in `patches/wasm32-unknown-emscripten/` when that directory has any. WebAssembly traps on a call whose signature differs from the callee, so the LAPACK functions and `xerbla` must take no hidden string lengths and return `void`.

- **plain**: Single-threaded
- **mt**: For modules with threads (`-pthread`). Every object is compiled with atomics, which `wasm-ld` requires for shared memory, and `USE_LOCKING=1` locks the work buffers, so threads can call BLAS at the same time. OpenBLAS's own thread pool stays off

Emscripten has no ABI guarantee between versions, so an archive links only with the Emscripten version that built it. The version is part of the file name (`wasm32-unknown-emscripten.6.0.10`) and is stored in `share/openblas/emscripten-version.txt`.

The WebAssembly archives have the same relocatable pkg-config file, without the Fortran runtime.

```bash
CROSS_TARGET=wasm32-unknown-emscripten ./build
```

## Building and releasing

```bash
# Native targets into .out/<build time>/, with one metadata file per archive
BUILD_TIME="$(date -u '+%Y-%m-%d_%H-%M-%S')" ./build-all
# One target, or some variants of it
CROSS_TARGET=aarch64-unknown-linux-gnu ./build
CROSS_TARGET=aarch64-unknown-linux-gnu ./build 'VARIANTS="plain threads" ./scripts/main'
# WebAssembly, with its own build time
CROSS_TARGET=wasm32-unknown-emscripten ./build

# Check, then publish one build time as a release
./scripts/release --dry-run <build time>
./scripts/release <build time>
```

- Native archives become release `openblas-<version>-<build time>`, WebAssembly archives `openblas-<version>-emscripten-<Emscripten version>-<build time>`
- The base images are pinned by digest, and the OpenBLAS source and every download of the build images by sha256. The distribution packages of the images (yum, apt) come from their mirrors and are not pinned
- Archives list their files in sorted order with one owner and the commit time, so the same files give the same archive
- `scripts/release` publishes only a build of a clean, pushed commit, and never changes a published release
- Each release has `SHA256SUMS` and `manifest.json`, which records for every archive its target, variant, OpenBLAS version and commit, source and sha256, compilers, LLVM release, target toolchain archive and sha256, flang-rt file, sha256, and patches, the files in the archive, build image file and sha256, and build commit

## Features

- Static library with position-independent code (-fPIC)
- LAPACK and LAPACKE included
- Fortran interfaces
- Dynamic architecture dispatch (DYNAMIC_ARCH)
- Optimized for Haswell (x86_64) and ARMv8 (aarch64)

## Use Cases

- Statically linking BLAS/LAPACK into applications
- Building portable scientific computing binaries
- Rust, Python, or Julia projects requiring OpenBLAS
- Cross-platform numerical computing
- WebAssembly applications built with Emscripten

## Keywords

openblas static, prebuilt openblas, openblas download, blas static library, lapack static, cross compile openblas, openblas linux, openblas macos, openblas windows, openblas arm, openblas aarch64, relapack, openblas wasm, openblas webassembly, openblas emscripten
