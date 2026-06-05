#!/usr/bin/env bash
# Per-rank rocprofv3 wrapper for HemeLB-GPU under mpirun.
# Only rank 1 runs GPU kernels (rank 0 is the CPU master with 0 fluid sites),
# but we wrap every rank and write to a per-rank directory so the outputs never
# clash. Look at rank1/ for the kernel stats.
#
# Driven by env vars exported from profile.slurm:
#   PROF_OUTDIR  - directory to collect per-rank profiling output
#   PROF_MODE    - "kernel" (kernel-dispatch trace+stats) or "sys" (full trace)
rank="${OMPI_COMM_WORLD_RANK:-${PMIX_RANK:-0}}"
outdir="${PROF_OUTDIR:-prof_out}/rank${rank}"
mkdir -p "$outdir"

case "${PROF_MODE:-kernel}" in
  counters) flags=(-i "${PROF_PMC:?set PROF_PMC to a pmc input file}") ;;
  sys)      flags=(--sys-trace --stats -S) ;;
  *)        flags=(--kernel-trace --stats -S) ;;
esac

exec rocprofv3 "${flags[@]}" -d "$outdir" -o prof -f csv -- "$@"
