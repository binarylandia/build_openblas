# Prebuilt static OpenBLAS libraries for multiple platforms

## [Releases](https://github.com/binarylandia/build_openblas/releases)

Cross-compiles [OpenBLAS](https://github.com/OpenMathLib/OpenBLAS) as static libraries with LAPACK support for Linux, macOS, and Windows targets. Includes variants with threading and ReLAPACK optimizations.

## Variants

- **plain**: Single-threaded, standard LAPACK
- **threads**: Multi-threaded (up to 64 threads)
- **relapack**: ReLAPACK recursive algorithms
- **threads-relapack**: Multi-threaded with ReLAPACK

## WebAssembly

The `wasm32-unknown-emscripten` target builds OpenBLAS with `emcc` for `TARGET=WASM128_GENERIC` (SIMD128 kernels), with LAPACK from the C translation that ships with OpenBLAS. It uses a develop commit of OpenBLAS whose LAPACK functions and `xerbla` take no hidden string lengths and return `void`, plus the patches in `patches/wasm32-unknown-emscripten/` when that directory has any, because WebAssembly traps on a call whose signature differs from the callee. The archive version names the commit as `git describe` does: `0.3.34-432-gde5d4914` is the 432nd commit after `v0.3.34`.

- **plain**: Single-threaded
- **mt**: For modules with threads (`-pthread`). Every object is compiled with atomics, which `wasm-ld` requires for shared memory, and `USE_LOCKING=1` locks the work buffers, so threads can call BLAS at the same time. OpenBLAS's own thread pool stays off

Emscripten has no ABI guarantee between versions, so an archive links only with the Emscripten version that built it. The version is part of the file name (`wasm32-unknown-emscripten.6.0.10`) and is stored in `share/openblas/emscripten-version.txt`.

```bash
CROSS_TARGET=wasm32-unknown-emscripten ./build
```

## Building and releasing

```bash
# Native targets into .out/<build time>/, with one metadata file per archive
BUILD_TIME="$(date -u '+%Y-%m-%d_%H-%M-%S')" ./build-all
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
- Each release has `SHA256SUMS` and `manifest.json`, which records for every archive its target, variant, OpenBLAS version, source and sha256, compiler, build image file and sha256, and build commit

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
