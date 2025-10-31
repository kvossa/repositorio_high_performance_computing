#!/usr/bin/env bash
set -euo pipefail

# ==========================
# CONFIG
# ==========================
HOST=$(hostname 2>/dev/null || echo "unknown_host")
DATE=$(date +%Y%m%d_%H%M%S)
OUTDIR="profiles_pi/${HOST}_${DATE}"
mkdir -p "$OUTDIR"

# tamaño de prueba (ajusta según tu máquina)
# 2e8 es razonable, 1e9 ya es pesado
DART_N=${DART_N:-200000000}
NEEDLE_N=${NEEDLE_N:-200000000}
NEEDLE_L=${NEEDLE_L:-0.5}
NEEDLE_ELL=${NEEDLE_ELL:-1.0}
SEED=${SEED:-42}

# hilos que quieres perfilar (para threads/omp)
THREADS_TO_TEST=(1 2 4 8)

# ==========================
# helpers
# ==========================
check_bin() {
  if [[ ! -x "./$1" ]]; then
    echo "[WARN] no existe ./$1, lo salto" | tee -a "$OUTDIR/WARNINGS.log"
    return 1
  fi
  return 0
}

run_perf() {
  local outfile="$1"; shift
  # -d: más stats, -r: repeticiones (aquí 1)
  perf stat -d "$@" 1>>"$outfile".out 2>>"$outfile".perf || true
}

run_timev() {
  local outfile="$1"; shift
  /usr/bin/time -v "$@" 1>>"$outfile".out 2>>"$outfile".time || true
}

summary_line() {
  local tag="$1"
  local timefile="$2"
  local perffile="$3"
  local wall="NA"
  local instr="NA"
  local cycles="NA"
  local ipc="NA"

  if [[ -f "$timefile" ]]; then
    wall=$(grep -F "Elapsed (wall clock) time" "$timefile" | awk '{print $8}')
  fi
  if [[ -f "$perffile" ]]; then
    instr=$(grep -F "instructions" "$perffile" | tail -n1 | awk '{print $1}')
    cycles=$(grep -F "cycles" "$perffile" | tail -n1 | awk '{print $1}')
    ipc=$(grep -F "insn per cycle" "$perffile" | tail -n1 | awk '{print $1}')
  fi
  echo "$tag | wall=$wall | instr=$instr | cycles=$cycles | ipc=$ipc"
}

echo "[INFO] Guardando perfiles en $OUTDIR"

# ==========================
# 1. DART
# ==========================
if check_bin dart_serial_o2; then
  TAG="dart_serial"
  OUT="$OUTDIR/${TAG}"
  echo "[RUN] $TAG..."
  run_perf  "$OUT" ./dart_serial_o2 "$DART_N" "$SEED"
  run_timev "$OUT" ./dart_serial_o2 "$DART_N" "$SEED"
fi

if check_bin dart_threads_o2; then
  for th in "${THREADS_TO_TEST[@]}"; do
    TAG="dart_threads_t${th}"
    OUT="$OUTDIR/${TAG}"
    echo "[RUN] $TAG..."
    run_perf  "$OUT" ./dart_threads_o2 "$DART_N" "$th" "$SEED"
    run_timev "$OUT" ./dart_threads_o2 "$DART_N" "$th" "$SEED"
  done
fi

if check_bin dart_fork_o2; then
  for th in "${THREADS_TO_TEST[@]}"; do
    TAG="dart_fork_p${th}"
    OUT="$OUTDIR/${TAG}"
    echo "[RUN] $TAG..."
    run_perf  "$OUT" ./dart_fork_o2 "$DART_N" "$th" "$SEED"
    run_timev "$OUT" ./dart_fork_o2 "$DART_N" "$th" "$SEED"
  done
fi

if check_bin dart_omp_o2; then
  for th in "${THREADS_TO_TEST[@]}"; do
    TAG="dart_omp_t${th}"
    OUT="$OUTDIR/${TAG}"
    echo "[RUN] $TAG..."
    OMP_NUM_THREADS=$th run_perf  "$OUT" ./dart_omp_o2 "$DART_N" "$th" "$SEED"
    OMP_NUM_THREADS=$th run_timev "$OUT" ./dart_omp_o2 "$DART_N" "$th" "$SEED"
  done
fi

# ==========================
# 2. NEEDLE
# ==========================
if check_bin needle_serial_o2; then
  TAG="needle_serial"
  OUT="$OUTDIR/${TAG}"
  echo "[RUN] $TAG..."
  run_perf  "$OUT" ./needle_serial_o2 "$NEEDLE_N" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED"
  run_timev "$OUT" ./needle_serial_o2 "$NEEDLE_N" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED"
fi

if check_bin needle_threads_o2; then
  for th in "${THREADS_TO_TEST[@]}"; do
    TAG="needle_threads_t${th}"
    OUT="$OUTDIR/${TAG}"
    echo "[RUN] $TAG..."
    run_perf  "$OUT" ./needle_threads_o2 "$NEEDLE_N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED"
    run_timev "$OUT" ./needle_threads_o2 "$NEEDLE_N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED"
  done
fi

if check_bin needle_fork_o2; then
  for th in "${THREADS_TO_TEST[@]}"; do
    TAG="needle_fork_p${th}"
    OUT="$OUTDIR/${TAG}"
    echo "[RUN] $TAG..."
    run_perf  "$OUT" ./needle_fork_o2 "$NEEDLE_N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED"
    run_timev "$OUT" ./needle_fork_o2 "$NEEDLE_N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED"
  done
fi

if check_bin needle_omp_o2; then
  for th in "${THREADS_TO_TEST[@]}"; do
    TAG="needle_omp_t${th}"
    OUT="$OUTDIR/${TAG}"
    echo "[RUN] $TAG..."
    OMP_NUM_THREADS=$th run_perf  "$OUT" ./needle_omp_o2 "$NEEDLE_N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED"
    OMP_NUM_THREADS=$th run_timev "$OUT" ./needle_omp_o2 "$NEEDLE_N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED"
  done
fi

# ==========================
# 3. SUMMARY
# ==========================
SUMMARY="$OUTDIR/SUMMARY.txt"
echo "[INFO] Generando $SUMMARY"
{
  echo "PROFILE SUMMARY - $(date)"
  echo "Host: $HOST"
  echo "DART_N=$DART_N  NEEDLE_N=$NEEDLE_N"
  echo

  for f in "$OUTDIR"/*.time; do
    base=${f%.time}
    tag=$(basename "$base")
    summary_line "$tag" "$f" "$base.perf"
  done
} > "$SUMMARY"

echo "[DONE] Perfiles en: $OUTDIR"
