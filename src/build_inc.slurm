#!/usr/bin/env bash
#SBATCH --job-name=hemepure_binc
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=00:30:00
#SBATCH --output=binc_%j.out
#
# INCREMENTAL rebuild of one already-configured variant (build/PP or build/VP).
# Recompiles only changed TUs and relinks -- much faster than build.slurm's full
# clean build, for perf-optimization iteration. Compiling needs no GPU.
#   sbatch build_inc.slurm                       # VARIANT=VP (default)
#   sbatch --export=ALL,VARIANT=PP build_inc.slurm
VARIANT="${VARIANT:-VP}"
SRC="/home/hpc-i/student10/HemePure_GPU_AMD/src"
BDIR="$SRC/build/$VARIANT"
JOBS="${SLURM_CPUS_PER_TASK:-16}"

source /etc/profile.d/modules.sh
module load nvhpc-hpcx/26.3
module load rocm/7.2.0
export HIP_PATH=/opt/rocm HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr

[ -d "$BDIR" ] || { echo "ERROR: $BDIR not configured; run build.slurm first"; exit 1; }
echo "==> incremental build of $VARIANT in $BDIR"
cmake --build "$BDIR" -j"$JOBS" || { echo "ERROR: build failed"; exit 1; }
cp "$BDIR/hemepure_gpu" "$SRC/build/hemepure_gpu_$VARIANT" || exit 1
echo "==> updated $SRC/build/hemepure_gpu_$VARIANT"
ls -la "$SRC/build/hemepure_gpu_$VARIANT"
