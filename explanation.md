# Porting HemePure_GPU_AMD from CUDA to AMD (ROCm/HIP)

Target machine: **AMD Radeon R9700** (RDNA4, GPU arch `gfx1201`), ROCm 7.2.0 at `/opt/rocm`.
Date: 2026-05-25.

This file tracks how the build was switched from the CUDA/NVIDIA backend to the
AMD/ROCm backend, and why each change was needed.

---

## TL;DR

The repo came configured to build with **CUDA (nvcc)**, which can never produce
code for an AMD GPU. The fix was to reconfigure for the **HIP_ROCM** backend and
clear up two follow-on issues (a dependency built with the wrong compiler, and a
C++ linkage detail that clang is stricter about than nvc++).

Build now with:

```sh
cd ~/HemePure_GPU_AMD/src
./script_build_R9700.sh          # normal build
./script_build_R9700.sh clean    # wipe + reconfigure + build
./script_build_R9700.sh deps     # also rebuild metis/parmetis with gcc
```

Result: `~/HemePure_GPU_AMD/src/build/hemepure_gpu`, containing device code for
`hipv4-amdgcn-amd-amdhsa--gfx1201`.

---

## The original errors

Running `make` in `src/build/` failed. The first error was:

```
net/MpiDataType.h:10:10: fatal error: mpi.h: No such file or directory
```

and after the MPI path was worked around, the next was a wall of:

```
cuda_params.cu: error: identifier "hipGetErrorString" is undefined
```

Both lines were preceded by `Building CUDA object ...` — the giveaway that the
build was using **nvcc**, i.e. the CUDA backend, on a machine with an AMD GPU.

---

## Root cause

`src/build` was configured with `HEMELB_GPU_BACKEND=CUDA` and
`CMAKE_CXX_COMPILER=nvc++` / `CMAKE_CUDA_COMPILER=nvcc` (NVIDIA HPC SDK). That is
the NVIDIA path. The AMD R9700 needs the **HIP_ROCM** path (hipcc/clang).

This also explains the second error: the function `initGPUSymbolConstants` in
`src/cuda_kernels_def_decl/cuda_params.cu` is written with the **HIP** API
(`hipGetErrorString`, `hipMemcpy`, `HIP_SYMBOL`, ...) and even carries a comment
about "ROCm/HIP on gfx1201 (RDNA4)" — it was written *for this GPU*. nvcc cannot
compile HIP calls, so it errored. Once we use hipcc, that code is correct as-is.

---

## Changes made

### 1. Switch the build to the ROCm/HIP backend  *(main fix)*

Wiped the CUDA-configured `src/build` and reconfigured with:

```sh
module load nvhpc-hpcx/26.3      # MPI (see note below)
module load rocm/7.2.0           # hipcc / clang for AMD
export HIP_PATH=/opt/rocm HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr

cmake -DHEMELB_GPU_BACKEND=HIP_ROCM \
      -DCMAKE_CXX_COMPILER=hipcc \
      -DAMDGPU_TARGETS=gfx1201 \
      ...(same HEMELB boundary-condition options as before)... ..
```

All HEMELB options were kept identical to the previous CUDA config
(Pressure–Pressure BCs: `NASHZEROTHORDERPRESSUREIOLET` in/out,
`NASHZEROTHORDERPRESSURESBB` walls; `LBGK`; `D3Q19`) so only the *backend*
changed.

This single change fixed **both** original errors:
- `mpi.h not found`: under nvcc, CMake had decided `.../ompi/include` was an
  "implicit" compiler include and stripped the `-I` for it, so nvcc never
  searched it. Under hipcc (clang), CMake's `FindMPI` passes that include
  directory explicitly, so `mpi.h` is found.
- `hipGetErrorString undefined`: now compiled by hipcc, which knows the HIP API.

### 2. Rebuild metis/parmetis with gcc

After switching backends the compile succeeded but **linking** failed:

```
ld.lld: error: undefined symbol: __fd_pow_1_avx2   (and __c_mset1, __c_mcopy4,
__builtin_va_gparg1, ...)  referenced from libmetis.a / libparmetis.a
```

These symbols are **NVIDIA HPC compiler runtime intrinsics**. The dependency
libraries had been built with `nvc` (the dependency build used the NVHPC MPI
wrapper as its compiler), so they expected NVHPC's runtime. clang's linker
(`lld`) can't resolve them.

Fix: rebuild only `libmetis.a` and `libparmetis.a` with **gcc**. Because the only
MPI on the machine is NVHPC's OpenMPI, the trick was OpenMPI's `OMPI_CC`/`OMPI_CXX`
override — it makes the existing `mpicc`/`mpicxx` wrappers use gcc/g++ as the
backend compiler while still providing the MPI include/link flags:

```sh
cd ~/HemePure_GPU_AMD/dep/build/ParMETIS-prefix/src/ParMETIS
export OMPI_CC=gcc OMPI_CXX=g++
make distclean ; ( cd metis && make distclean )
make config cc=mpicc cxx=mpicxx prefix=.../dep/install
( cd metis && make config cc=mpicc cxx=mpicxx prefix=.../dep/install )
make ; make install ; ( cd metis && make && make install )
```

Boost (already installed as 1.83 in `dep/install`) and the other dependencies
were left untouched. (This step is automated by `script_build_R9700.sh deps`.)

### 3. `D3Q19::NUMVECTORS` link fix

The final link error was:

```
ld.lld: error: undefined symbol: hemelb::lb::lattices::D3Q19::NUMVECTORS
```

In `src/lb/lattices/D3Q19.h` the constant was declared
`static const Direction NUMVECTORS = 19;`. When it is "ODR-used" (here, streamed
into the logger in `extraction/LocalDistributionInput.cc`), a non-`constexpr`
`static const` member needs a separate out-of-line definition. nvc++ tolerated
its absence; clang does not.

Fix (one line, D3Q19 only): change it to

```cpp
static constexpr Direction NUMVECTORS = 19;
```

`constexpr` static members are implicitly `inline` in C++17, so no out-of-line
definition is needed. (The other lattices D3Q15/D3Q27/D3Q15i still use the old
form; they aren't used by this build. If you ever build with a different
`HEMELB_LATTICE`, apply the same one-line change there.)

---

## Status

- [x] `make` completes; `hemepure_gpu` is produced.
- [x] Binary targets `gfx1201` (verified with `roc-obj-ls`).

## Open items / things to watch at run time (not build problems)

- **GPU-aware MPI:** the build has `HEMELB_CUDA_AWARE_MPI=ON`, but NVHPC's
  OpenMPI is not ROCm-aware. If a multi-rank run passes device pointers to MPI it
  may crash. If so, reconfigure with `-DHEMELB_CUDA_AWARE_MPI=OFF`.
- **GPU access:** `rocminfo` does not run for this user (no sudo). That may mean
  limited access to the GPU device, which would block *running* the executable
  even though it builds. Worth confirming device access before a real run.