#!/usr/bin/env bash
#SBATCH --job-name=hemepure_run_PP
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=2                 # rank 0 = CPU master, rank 1 = GPU worker (NGPUS+1)
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:r9700:1         # the AMD R9700 (RDNA4, gfx1201). NEVER plain gpu:1 (may grab a 5090)
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=run_%j.out
#
# Runs a pre-built HemeLB-GPU (AMD/ROCm) executable on a test case.
#
# Pick the test case with the CASE variable below (or on the command line).
# Build the executables first with build.slurm, then submit from this src/ dir:
#   sbatch run.slurm                                 # uses CASE set below
#   sbatch --export=ALL,CASE=coW-6.4um run.slurm     # override the test case
#
# For 2 GPU ranks set --ntasks=3 and --gres=gpu:r9700:2 (only one R9700 exists
# on the node, so 1 GPU is the practical max here).

# ---- choose the test case --------------------------------------------------
CASE="${CASE:-coW-6.4um}"          # <-- testcase name; override via --export=ALL,CASE=...

# ---- paths -----------------------------------------------------------------
ROOT="/home/hpc-i/student10/HemePure_GPU_AMD"   # adjust if the repo moves
SRC="$ROOT/src"

# Map each test case to its input xml and the matching executable variant.
#   PP = pressure inlets + pressure outlets   (build/hemepure_gpu_PP)
#   VP = velocity-from-file inlets + pressure (build/hemepure_gpu_VP)
case "$CASE" in
  Aneurysm)          INPUT="$ROOT/cases/Aneurysm/input_PP.xml";        VARIANT=PP ;;
  coW-6.4um)         INPUT="$ROOT/cases/coW-6.4um/input_test.xml";     VARIANT=VP ;;
  bifurcation_hires) INPUT="$ROOT/cases/bifurcation_hires/input.xml";  VARIANT=PP ;;
  SixBranch_3inlet)  INPUT="$ROOT/cases/SixBranch_3inlet/input.xml";   VARIANT=VP ;;
  *) echo "ERROR: unknown CASE '$CASE' (known: Aneurysm, coW-6.4um, bifurcation_hires, SixBranch_3inlet)"; exit 1 ;;
esac

EXE="${EXE:-$SRC/build/hemepure_gpu_$VARIANT}"  # override with EXE=... if needed
INPUT="${INPUT_OVERRIDE:-$INPUT}"               # override the xml with INPUT_OVERRIDE=...
# Fresh output dir per job (HemeLB refuses to overwrite an existing one).
OUT="${OUT:-$(dirname "$INPUT")/results_${CASE}_${SLURM_JOB_ID:-manual}}"

# ---- environment (runtime needs the ROCm libs + the MPI used to build) -----
source /etc/profile.d/modules.sh
module load nvhpc-hpcx/26.3     # OpenMPI runtime (only MPI on this machine)
module load rocm/7.2.0          # libamdhip64 / device runtime
export HIP_PATH=/opt/rocm HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-8}
export OMP_PROC_BIND=spread OMP_PLACES=cores

# ---- sanity ----------------------------------------------------------------
if [ ! -x "$EXE" ];   then echo "ERROR: executable not found: $EXE (build the $VARIANT variant first)"; exit 1; fi
if [ ! -f "$INPUT" ]; then echo "ERROR: input xml not found: $INPUT";                                  exit 1; fi
rm -rf "$OUT"                                   # HemeLB errors if -out already exists

echo "============================================================"
echo "  case  : $CASE  (variant $VARIANT)"
echo "  exe   : $EXE"
echo "  input : $INPUT"
echo "  output: $OUT"
echo "  ntasks: ${SLURM_NTASKS:-?}   gpus: ${SLURM_GPUS_ON_NODE:-?}"
echo "  node  : $(hostname)"
echo "============================================================"

# ---- run -------------------------------------------------------------------
# Launch with mpirun, NOT srun. srun is a dead end on this box: its only PMIx
# plugin (mpi/pmix_v5) needs PMIx >=4.0 (symbols PMIx_Info_create/_free/_load,
# PMIx_Value_load), but the HPC-X OpenMPI 4.1.9 here ships PMIx 3.2 and there is
# no PMIx 4/5 lib anywhere -> "can not load PMIx library". This OpenMPI also has
# no PMI2 client (only the pmix3x component), so --mpi=pmi2 can't wire it up.
#
# The earlier mpirun crash was NOT an env-sync issue -- it was OpenMPI's process
# binding clashing with SLURM's cgroup ("hwloc_set_cpubind ... bitmap 0,192").
# --bind-to none disables OMPI binding so the ranks stay in the cpuset SLURM
# gave us. On a single node mpirun also forwards this script's environment
# (the loaded modules) to every rank, so env is already in sync.
#
# `-x VAR` only *forwards* an existing var, it does not define one -- forwarding
# an unset var (e.g. HIP_VISIBLE_DEVICES, which SLURM does NOT set; it exposes
# the AMD GPU via ROCR_VISIBLE_DEVICES) just prints a harmless "could not find
# environment variable" warning. So we forward only the vars that are actually
# set, which keeps the log clean.
FWD=()
for v in PATH LD_LIBRARY_PATH HIP_PATH HIP_PLATFORM ROCR_VISIBLE_DEVICES GPU_DEVICE_ORDINAL HIP_VISIBLE_DEVICES; do
  [ -n "${!v+x}" ] && FWD+=(-x "$v")
done

# HemeLB resolves the geometry datafile path relative to the input xml's
# directory, so an absolute -in keeps the .gmy lookup correct.
mpirun -np "${SLURM_NTASKS:-2}" --bind-to none "${FWD[@]}" \
       "$EXE" -in "$INPUT" -out "$OUT"
status=$?

echo "============================================================"
echo "==> hemepure_gpu exited with status $status"
[ -f "$OUT/report.txt" ] && { echo "---- report.txt ----"; cat "$OUT/report.txt"; }
exit $status
