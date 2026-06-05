#!/usr/bin/env bash
#SBATCH --job-name=hemepure_prof
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=2                 # rank 0 = CPU master, rank 1 = GPU worker (NGPUS+1)
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:r9700:1         # the AMD R9700 (RDNA4, gfx1201). NEVER plain gpu:1
#SBATCH --time=00:25:00
#SBATCH --output=prof_%j.out
#
# Profiles the HemeLB-GPU LB kernels with rocprofv3 on a TRUNCATED run so we can
# see which GPU kernel dominates and how it behaves -- without paying for a full
# 100k/50k-step simulation. Submit from src/:
#   sbatch profile.slurm                              # VP, 2000 steps (default)
#   sbatch --export=ALL,CASE=Aneurysm profile.slurm   # PP instead
#
# Mirrors run.slurm's launch setup (mpirun --bind-to none, env forwarding) which
# is the only thing that works on this box (see run.slurm for the srun/PMIx saga).

# ---- choose the case (truncated inputs) ------------------------------------
CASE="${CASE:-coW-6.4um}"
ROOT="/home/hpc-i/student10/HemePure_GPU_AMD"
SRC="$ROOT/src"

case "$CASE" in
  coW-6.4um) INPUT="$ROOT/cases/coW-6.4um/input_test_prof.xml"; VARIANT=VP ;;
  Aneurysm)  INPUT="$ROOT/cases/Aneurysm/input_PP_prof.xml";    VARIANT=PP ;;
  *) echo "ERROR: unknown CASE '$CASE' (known: coW-6.4um, Aneurysm)"; exit 1 ;;
esac

EXE="${EXE:-$SRC/build/hemepure_gpu_$VARIANT}"
OUT="$(dirname "$INPUT")/results_prof_${CASE}_${SLURM_JOB_ID:-manual}"
export PROF_OUTDIR="$SRC/prof_${CASE}_${SLURM_JOB_ID:-manual}"
export PROF_MODE="${PROF_MODE:-kernel}"

# ---- environment -----------------------------------------------------------
source /etc/profile.d/modules.sh
module load nvhpc-hpcx/26.3
module load rocm/7.2.0
export HIP_PATH=/opt/rocm HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-8}

# ---- sanity ----------------------------------------------------------------
[ -x "$EXE" ]   || { echo "ERROR: exe not found: $EXE (build $VARIANT first)"; exit 1; }
[ -f "$INPUT" ] || { echo "ERROR: input not found: $INPUT"; exit 1; }
rm -rf "$OUT" "$PROF_OUTDIR"
chmod +x "$SRC/prof_wrap.sh"

echo "============================================================"
echo "  PROFILE  case=$CASE variant=$VARIANT mode=$PROF_MODE"
echo "  exe   : $EXE"
echo "  input : $INPUT"
echo "  prof  : $PROF_OUTDIR"
echo "  node  : $(hostname)"
echo "============================================================"

# ---- forward only the env vars that are actually set (clean log) -----------
FWD=()
for v in PATH LD_LIBRARY_PATH HIP_PATH HIP_PLATFORM ROCR_VISIBLE_DEVICES \
         GPU_DEVICE_ORDINAL HIP_VISIBLE_DEVICES PROF_OUTDIR PROF_MODE; do
  [ -n "${!v+x}" ] && FWD+=(-x "$v")
done

mpirun -np "${SLURM_NTASKS:-2}" --bind-to none "${FWD[@]}" \
       "$SRC/prof_wrap.sh" "$EXE" -in "$INPUT" -out "$OUT"
status=$?

echo "============================================================"
echo "==> exited with status $status"
echo "==> profiling CSVs under: $PROF_OUTDIR/rank1/"
ls -R "$PROF_OUTDIR" 2>/dev/null | head -40
exit $status
