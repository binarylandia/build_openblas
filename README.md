# Prebuilt static OpenBLAS libraries for multiple platforms

## [Releases](https://github.com/binarylandia/build_openblas/releases)

Cross-compiles [OpenBLAS](https://github.com/OpenMathLib/OpenBLAS) as static libraries with LAPACK support for Linux, macOS, Windows, and WebAssembly targets. Includes variants with threading and ReLAPACK optimizations.

Every target builds the same OpenBLAS source: develop commit `de5d4914`, the 432nd commit after `v0.3.34`, which the archive version names as `git describe` does (`0.3.34-432-gde5d4914`). It has the fixes for the dgemm stack overflow on AMD Zen 4 and Zen 5 servers that `v0.3.34` lacks, and C LAPACK functions and an `xerbla` that take no hidden string lengths and return `void`, which WebAssembly needs.

## Variants

- **plain**: Single-threaded, standard LAPACK
- **threads**: Multi-threaded (up to 64 threads)
- **relapack**: ReLAPACK recursive algorithms
- **threads-relapack**: Multi-threaded with ReLAPACK

## Linux targets

`x86_64-unknown-linux-gnu`, `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-gnu`, and `aarch64-unknown-linux-musl` build with clang and flang of LLVM 22.1.8 ([binarylandia/build_llvm](https://github.com/binarylandia/build_llvm)), on the sysroots and GCC runtimes of the crosstool-NG GCC 14.4.0 toolchains ([binarylandia/build_crosstool-ng](https://github.com/binarylandia/build_crosstool-ng)), with glibc 2.17 on the gnu targets. The build image builds the Fortran runtime flang-rt for its target from the LLVM source of the same release (`docker/files/build-llvm-runtimes`).

An archive holds:

- `lib/libopenblas.a`: BLAS, CBLAS, LAPACK, and LAPACKE, with the kernels of every CPU of the architecture (`DYNAMIC_ARCH`)
- `lib/libflang_rt.runtime.a`: the Fortran runtime of the flang that compiled LAPACK, static and position-independent, with its license in `share/doc/flang-rt/LICENSE.TXT`
- headers, and pkg-config and CMake files that name both libraries

A program links both archives, for example `cc main.c libopenblas.a libflang_rt.runtime.a -lm -lpthread`, and then needs only the C library of the target: glibc 2.17 on gnu targets, nothing on musl targets when it links statically. The archives need no C++ runtime and no unwinder. They call the compiler support routines of libgcc or compiler-rt (128-bit integer and floating-point arithmetic, complex multiplication and division, aarch64 atomics), which C compilers link by default.

Every build checks each archive:

- the kernels of every core of `DYNAMIC_ARCH` are present
- `libopenblas.a` calls no gfortran runtime, `libflang_rt.runtime.a` defines every Fortran runtime function that it calls, and neither archive needs a C++ runtime
- a C program (`scripts/consumer-check.c`) that calls `dgemm_`, `sgemm_`, `dsyev_`, `dgttrf_`, and `dgttrs_` links both archives, needs no shared library beyond glibc 2.17 (gnu) or none (musl), and computes the known results: natively on x86_64, and under `qemu-aarch64` on aarch64, there once with the detected core and once with each core forced through `OPENBLAS_CORETYPE`
- the OpenBLAS tests pass (`make tests`: the BLAS, CBLAS, and unit tests). Their makefiles start the test programs directly, so on aarch64 the build machine needs a binfmt_misc handler for `qemu-aarch64`

The aarch64 archives leave out two cores, whose kernels compute wrong results on some CPUs that OpenBLAS selects them for:

- `ARMV9SME` (`NO_SME=1`): the SME GEMM kernels are correct only with a streaming vector length of 512 bits, while OpenBLAS selects them on any CPU with SME. These CPUs use the kernels of their SVE or Neoverse N1 core
- `ARMV8SVE`, the generic SVE core for SVE CPUs that OpenBLAS does not recognize: its SSYRK and SSYR2K kernels are wrong at SVE vector lengths above 128 bits, and its DSYRK and DSYR2K kernels at 512 bits. These CPUs use the `ARMV8` kernels

The aarch64 builds also run the level-3 BLAS tests of the remaining SVE cores (`NEOVERSEV1`, `NEOVERSEN2`, `A64FX`) and of `CORTEXA72` under `qemu-aarch64` at SVE vector lengths of 128, 256, and 512 bits.

The macOS and Windows images still carry GCC toolchains, and `scripts/main` builds only targets whose image provides clang, flang, and flang-rt.

## WebAssembly

The `wasm32-unknown-emscripten` target builds OpenBLAS with `emcc` for `TARGET=WASM128_GENERIC` (SIMD128 kernels), with LAPACK from the C translation that ships with OpenBLAS, plus the patches in `patches/wasm32-unknown-emscripten/` when that directory has any. WebAssembly traps on a call whose signature differs from the callee, so the LAPACK functions and `xerbla` must take no hidden string lengths and return `void`.

- **plain**: Single-threaded
- **mt**: For modules with threads (`-pthread`). Every object is compiled with atomics, which `wasm-ld` requires for shared memory, and `USE_LOCKING=1` locks the work buffers, so threads can call BLAS at the same time. OpenBLAS's own thread pool stays off

Emscripten has no ABI guarantee between versions, so an archive links only with the Emscripten version that built it. The version is part of the file name (`wasm32-unknown-emscripten.6.0.10`) and is stored in `share/openblas/emscripten-version.txt`.

```bash
CROSS_TARGET=wasm32-unknown-emscripten ./build
```

## Building and releasing

```bash
# Linux targets into .out/<build time>/, with one metadata file per archive
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
- Each release has `SHA256SUMS` and `manifest.json`, which records for every archive its target, variant, OpenBLAS version and commit, source and sha256, compilers, LLVM and GCC toolchain releases, flang-rt file and sha256, the files in the archive, build image file and sha256, and build commit

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
