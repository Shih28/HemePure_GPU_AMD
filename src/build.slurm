#!/usr/bin/env bash
#SBATCH --job-name=hemepure_build
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=01:30:00
#SBATCH --output=build_%j.out 
#
# Builds the AMD/ROCm (gfx1201, Radeon R9700) HemeLB executables for BOTH
# boundary-condition variants required by the test cases:
#   * PP  (pressure-pressure)  -> for cases/Aneurysm   (input_PP.xml)
#   * VP  (velocity-pressure)  -> for cases/coW-6.4um   (input_test.xml)
#
# Compiling does NOT need a GPU, so no --gres is requested here -- that leaves
# the single R9700 free for the run jobs. We still use -p amd because that node
# (GPU4) carries the ROCm toolchain. We never touch the RTX 5090.
#
# Submit with:   sbatch build.slurm      (run from this src/ directory)
# Outputs:       build/hemepure_gpu_PP  and  build/hemepure_gpu_VP

# ---- paths -----------------------------------------------------------------
ROOT="/home/hpc-i/student10/HemePure_GPU_AMD"   # adjust if the repo moves
SRC="$ROOT/src"
GPU_ARCH="gfx1201"                               # AMD R9700 (RDNA4)
JOBS="${SLURM_CPUS_PER_TASK:-16}"

# ---- environment -----------------------------------------------------------
source /etc/profile.d/modules.sh
module load nvhpc-hpcx/26.3     # MPI (the only MPI on this machine)
module load rocm/7.2.0          # hipcc / clang for AMD
export HIP_PATH=/opt/rocm HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr

# ---- sanity: gcc-built dependencies must be present -------------------------
# (libmetis.a / libparmetis.a were rebuilt with gcc; the shipped nvc-built ones
#  do not link with clang. See explanation.md / script_build_R9700.sh deps.)
if [ ! -f "$ROOT/dep/install/lib/libparmetis.a" ]; then
  echo "ERROR: $ROOT/dep/install/lib/libparmetis.a not found."
  echo "       Build the dependencies first (see script_build_R9700.sh deps)."
  exit 1
fi

# ---- build helper ----------------------------------------------------------
# build_variant <name> <extra cmake flags...>
build_variant() {
  local name="$1"; shift
  local bdir="$SRC/build/$name"
  echo "============================================================"
  echo "==> Building $name variant in $bdir"
  echo "============================================================"
  rm -rf "$bdir"
  cmake -S "$SRC" -B "$bdir" \
        -DHEMELB_GPU_BACKEND=HIP_ROCM \
        -DCMAKE_CXX_COMPILER=hipcc \
        -DAMDGPU_TARGETS="$GPU_ARCH" \
        -DHEMELB_KERNEL=LBGK \
        -DHEMELB_LATTICE=D3Q19 \
        -DHEMELB_WALL_BOUNDARY=SIMPLEBOUNCEBACK \
        -DHEMELB_USE_MPI_PARALLEL_IO=ON \
        "$@" || { echo "ERROR: cmake configure failed for $name"; exit 1; }

  cmake --build "$bdir" -j"$JOBS" || { echo "ERROR: build failed for $name"; exit 1; }

  cp "$bdir/hemepure_gpu" "$SRC/build/hemepure_gpu_$name" \
      || { echo "ERROR: $name executable not produced"; exit 1; }
  echo "==> $name done: $SRC/build/hemepure_gpu_$name"
}

# ---- PP: pressure inlets + pressure outlets (Aneurysm) ---------------------
build_variant PP \
  -DHEMELB_USE_VELOCITY_WEIGHTS_FILE=OFF \
  -DHEMELB_INLET_BOUNDARY=NASHZEROTHORDERPRESSUREIOLET \
  -DHEMELB_OUTLET_BOUNDARY=NASHZEROTHORDERPRESSUREIOLET \
  -DHEMELB_WALL_INLET_BOUNDARY=NASHZEROTHORDERPRESSURESBB \
  -DHEMELB_WALL_OUTLET_BOUNDARY=NASHZEROTHORDERPRESSURESBB

# ---- VP: velocity-from-file inlets + pressure outlets (coW-6.4um) -----------
build_variant VP \
  -DHEMELB_USE_VELOCITY_WEIGHTS_FILE=ON \
  -DHEMELB_INLET_BOUNDARY=LADDIOLET \
  -DHEMELB_OUTLET_BOUNDARY=NASHZEROTHORDERPRESSUREIOLET \
  -DHEMELB_WALL_INLET_BOUNDARY=LADDIOLETSBB \
  -DHEMELB_WALL_OUTLET_BOUNDARY=NASHZEROTHORDERPRESSURESBB

# ---- summary ---------------------------------------------------------------
# Report whichever variants were actually built (PP and/or VP).
echo "============================================================"
echo "==> Build complete. Executables:"
for exe in "$SRC"/build/hemepure_gpu_*; do
  [ -e "$exe" ] || continue
  ls -la "$exe"
  echo "    arch: $(roc-obj-ls "$exe" 2>/dev/null | grep -o 'gfx[0-9a-z]*' | sort -u | paste -sd, -)"
done
