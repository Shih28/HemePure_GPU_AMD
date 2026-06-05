#!/usr/bin/env bash
JOB="$1"; CASE="${2:-coW-6.4um}"
ROOT=/home/hpc-i/student10/HemePure_GPU_AMD
export LD_LIBRARY_PATH=/home/hpc-i/student10/.local/lib:$LD_LIBRARY_PATH
HX="$ROOT/hemeXtract/hemeXtract"
while squeue -h -j "$JOB" 2>/dev/null | grep -q .; do sleep 30; done
echo "=== job $JOB finished $(date) ==="
NEW="$ROOT/cases/$CASE/results_${CASE}_${JOB}/Extracted"
BASE="$ROOT/cases/$CASE/results_${CASE}_BASELINE/Extracted"
RPT="$ROOT/cases/$CASE/results_${CASE}_${JOB}/report.txt"
echo "=== timing (optimized) ==="
grep -E "Simulation total|LB calc only|Total |Lattice Data init|MPI Wait|Extraction writing" "$RPT" 2>/dev/null
echo
echo "=== accuracy vs BASELINE (cols: VelCorrel MaxVelA MaxVelB ShearCorr ShearL2 PresCorrel PresL2) ==="
for f in inlet outlet; do
  echo "--- $f.dat ---"
  [ -f "$NEW/$f.dat" ] && [ -f "$BASE/$f.dat" ] && \
  "$HX" -C -s -r "$BASE/$f.dat" "$NEW/$f.dat" 2>/dev/null \
    | grep -vE "^#|^$|Reading|Building|done|Finished|Reached|No more|outputf|HEADER|FIELD|version|voxel|origin|num_|^field" | tail -12 \
    || echo "MISSING $f.dat (new=$NEW)"
done
echo "=== files present in NEW ==="; ls -la "$NEW" 2>/dev/null
