#!/usr/bin/env bash
JOB="$1"
ROOT=/home/hpc-i/student10/HemePure_GPU_AMD
export LD_LIBRARY_PATH=/home/hpc-i/student10/.local/lib:$LD_LIBRARY_PATH
HX="$ROOT/hemeXtract/hemeXtract"
while squeue -h -j "$JOB" 2>/dev/null | grep -q .; do sleep 30; done
echo "=== PP job $JOB finished $(date) ==="
NEW="$ROOT/cases/Aneurysm/results_Aneurysm_${JOB}/Extracted"
BASE="$ROOT/cases/Aneurysm/results_Aneurysm_BASELINE/Extracted"
RPT="$ROOT/cases/Aneurysm/results_Aneurysm_${JOB}/report.txt"
echo "=== timing (PP, float) ==="
grep -E "Ran for|Simulation total|LB calc only|^Total |Lattice Data init|MPI Wait|Extraction writing" "$RPT" 2>/dev/null
echo
echo "=== STRICT accuracy vs Aneurysm BASELINE (cols: t t VelCorrel MaxVelA MaxVelB ShCorr ShL2 PresCorrel PresL2) ==="
for f in ANUplane1 ANUplane2 ANUplane3 ANUplane4 ANUplane5 inlet outlet; do
  if [ -f "$NEW/$f.dat" ] && [ -f "$BASE/$f.dat" ]; then
    echo "--- $f.dat ---"
    "$HX" -C -s -r "$BASE/$f.dat" "$NEW/$f.dat" 2>/dev/null \
      | grep -E "^[0-9]" | head -6
  else
    echo "--- $f.dat MISSING (new exists: $([ -f "$NEW/$f.dat" ] && echo yes || echo no)) ---"
  fi
done
echo "=== files in NEW ==="; ls -la "$NEW" 2>/dev/null
