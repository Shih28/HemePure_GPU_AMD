#!/usr/bin/env bash
#
# Build HemePure_GPU_AMD for the AMD Radeon R9700 (RDNA4, gfx1201) using the
# ROCm/HIP backend.
#
# Usage (run from anywhere):
#   ./script_build_R9700.sh             # configure if needed, then build
#   ./script_build_R9700.sh clean       # wipe src/build, reconfigure, build
#   ./script_build_R9700.sh deps        # rebuild metis/parmetis with gcc first
#   ./script_build_R9700.sh clean deps  # do both
#
# Override parallelism with e.g.  JOBS=16 ./script_build_R9700.sh

# ---- locations -------------------------------------------------------------
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../HemePure_GPU_AMD/src
ROOT_DIR="$(dirname "$SRC_DIR")"                          # .../HemePure_GPU_AMD
BUILD_DIR="$SRC_DIR/build"
INSTALL_DIR="$ROOT_DIR/dep/install"
GPU_ARCH="gfx1201"          # AMD R9700 (RDNA4); change for other AMD cards
JOBS="${JOBS:-8}"

# ---- environment -----------------------------------------------------------
# nvhpc-hpcx supplies the only MPI on this box (NVHPC's bundled OpenMPI);
# rocm supplies hipcc / clang for the AMD GPU. Both are needed for cmake AND make.
source /etc/profile.d/modules.sh
module load nvhpc-hpcx/26.3
module load rocm/7.2.0
export HIP_PATH=/opt/rocm HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr

# ---- parse args ------------------------------------------------------------
want_clean=0; want_deps=0
for a in "$@"; do
  case "$a" in
    clean) want_clean=1 ;;
    deps)  want_deps=1 ;;
    *) echo "unknown arg: '$a' (expected: clean, deps)"; exit 1 ;;
  esac
done

# ---- (optional) rebuild metis/parmetis with gcc ----------------------------
# The shipped libmetis.a / libparmetis.a were built with nvc and emit NVHPC
# intrinsics (__c_mset1, __fd_pow_*, ...) that clang's linker cannot resolve.
# Rebuild them with gcc; OpenMPI's OMPI_CC/OMPI_CXX override makes the mpicc
# wrapper use gcc as its backend while keeping the MPI include/link flags.
if [ "$want_deps" = 1 ]; then
  echo "==> Rebuilding metis/parmetis with gcc"
  PM="$ROOT_DIR/dep/build/ParMETIS-prefix/src/ParMETIS"
  ( cd "$PM" || exit 1
    export OMPI_CC=gcc OMPI_CXX=g++
    make distclean >/dev/null 2>&1
    ( cd metis && make distclean >/dev/null 2>&1 )
    make config cc=mpicc cxx=mpicxx prefix="$INSTALL_DIR"            || exit 1
    ( cd metis && make config cc=mpicc cxx=mpicxx prefix="$INSTALL_DIR" ) || exit 1
    make -j"$JOBS" MAKEFLAGS=                                        || exit 1
    make install MAKEFLAGS=                                          || exit 1
    ( cd metis && make -j"$JOBS" MAKEFLAGS= && make install MAKEFLAGS= ) || exit 1
  ) || { echo "dependency rebuild failed"; exit 1; }
fi

# ---- configure -------------------------------------------------------------
if [ "$want_clean" = 1 ]; then
  echo "==> Wiping $BUILD_DIR"
  rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

if [ ! -f CMakeCache.txt ] || [ "$want_clean" = 1 ]; then
  echo "==> Configuring (HIP_ROCM, $GPU_ARCH)"
  cmake -DHEMELB_GPU_BACKEND=HIP_ROCM \
        -DCMAKE_CXX_COMPILER=hipcc \
        -DAMDGPU_TARGETS="$GPU_ARCH" \
        -DHEMELB_USE_VELOCITY_WEIGHTS_FILE=ON \
        -DHEMELB_INLET_BOUNDARY=NASHZEROTHORDERPRESSUREIOLET \
        -DHEMELB_OUTLET_BOUNDARY=NASHZEROTHORDERPRESSUREIOLET \
        -DHEMELB_WALL_INLET_BOUNDARY=NASHZEROTHORDERPRESSURESBB \
        -DHEMELB_WALL_OUTLET_BOUNDARY=NASHZEROTHORDERPRESSURESBB \
        -DHEMELB_WALL_BOUNDARY=SIMPLEBOUNCEBACK \
        -DHEMELB_KERNEL=LBGK \
        -DHEMELB_LATTICE=D3Q19 \
        .. || { echo "cmake configure failed"; exit 1; }
fi

# ---- build -----------------------------------------------------------------
echo "==> Building (-j$JOBS)"
make -j"$JOBS" || { echo "build failed"; exit 1; }
echo "==> Done: $BUILD_DIR/hemepure_gpu"