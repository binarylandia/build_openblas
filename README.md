# Prebuilt static OpenBLAS libraries for multiple platforms

## [Releases](https://github.com/binarylandia/build_openblas/releases)

Cross-compiles [OpenBLAS](https://github.com/OpenMathLib/OpenBLAS) as static libraries with LAPACK support for Linux, macOS, and Windows targets. Includes variants with threading and ReLAPACK optimizations.

## Variants

- **plain**: Single-threaded, standard LAPACK
- **threads**: Multi-threaded (up to 64 threads)
- **relapack**: ReLAPACK recursive algorithms
- **threads-relapack**: Multi-threaded with ReLAPACK

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

## Keywords

openblas static, prebuilt openblas, openblas download, blas static library, lapack static, cross compile openblas, openblas linux, openblas macos, openblas windows, openblas arm, openblas aarch64, relapack
