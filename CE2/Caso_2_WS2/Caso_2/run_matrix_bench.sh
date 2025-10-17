#!/usr/bin/env bash
set -euo pipefail

# -------- Configurable parameters --------
# Matrix sizes to test
SIZES=(${SIZES:-200 400 800 1200 2000 2400 3000 4000})
# Repetitions per configuration
REPEATS=${REPEATS:-10}
# Thread counts for Hilos.c / OpenMP
THREADS=(${THREADS:-1 2 4 8 16 32})
# Process counts for Procesos.c (include 0 for single-process baseline inside the program)
PROCS=(${PROCS:-0 2 4 8 16 32})

# Output files
RAW_CSV="${RAW_CSV:-results_raw.csv}"
AVG_CSV="${AVG_CSV:-results_avg.csv}"
LOG_DIR="${LOG_DIR:-logs}"

# -------- Helpers --------

log() { printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*"; }

# Prefer GNU time if available for high-resolution elapsed time.
# On macOS, you can `brew install gnu-time` (gtime).
if command -v /usr/bin/time >/dev/null 2>&1; then
  TIME_BIN="/usr/bin/time"
elif command -v gtime >/dev/null 2>&1; then
  TIME_BIN="gtime"
else
  TIME_BIN=""
fi

run_with_timing() {
  local cmd="$*"
  # Use GNU time if available, otherwise fall back to shell timing.
  if [[ -n "${TIME_BIN:-}" ]]; then
    local tf
    tf="$(mktemp)"
    # Run the command, discard its stdout/err; have 'time' write ONLY to tmpfile.
    set +e
    "${TIME_BIN}" -f %e -o "$tf" bash -c "$cmd" >/dev/null 2>/dev/null
    local rc=$?
    set -e
    # Read elapsed seconds (may contain comma decimal on some locales)
    local elapsed
    elapsed="$(tr ',' '.' < "$tf" | tr -d ' \t\r\n')"
    rm -f "$tf"
    # Fallback if for some reason elapsed is empty
    if [[ -z "$elapsed" ]]; then
      local start end
      start=$(date +%s%N)
      set +e; bash -c "$cmd" >/dev/null 2>/dev/null; set -e
      end=$(date +%s%N)
      elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN{ printf("%.6f\n", (e - s)/1e9) }')
    fi
    echo "$elapsed"
  else
    local start end
    start=$(date +%s%N)
    set +e; bash -c "$cmd" >/dev/null 2>/dev/null; set -e
    end=$(date +%s%N)
    awk -v s="$start" -v e="$end" 'BEGIN{ printf("%.6f\n", (e - s)/1e9) }'
  fi
}

# -------- Build --------
log "Compilando ejecutables…"

# Hilos
if [[ -f Hilos.c ]]; then
  gcc -O3 -march=native -ffast-math -pthread Hilos.c -o hilos
  HAVE_HILOS=1
else
  log "ADVERTENCIA: Hilos.c no encontrado. Se omiten pruebas de hilos."
  HAVE_HILOS=0
fi

# Procesos
if [[ -f Procesos.c ]]; then
  gcc -O3 -march=native -ffast-math Procesos.c -o procesos
  HAVE_PROCESOS=1
else
  log "ADVERTENCIA: Procesos.c no encontrado. Se omiten pruebas de procesos."
  HAVE_PROCESOS=0
fi

# Secuencial (opcional)
if [[ -f Secuencial.c ]]; then
  gcc -O3 -march=native -ffast-math Secuencial.c -o secuencial
  HAVE_SECUENCIAL=1
else
  log "INFO: Secuencial.c no encontrado. Se omiten pruebas secuenciales."
  HAVE_SECUENCIAL=0
fi

# OpenMP (BT y Bloques)
if [[ -f mm_openmp_bt.c ]]; then
  gcc -O3 -march=native -ffast-math -fopenmp mm_openmp_bt.c -o mm_openmp_bt
  HAVE_OMP_BT=1
else
  log "ADVERTENCIA: mm_openmp_bt.c no encontrado. Se omite OpenMP (BT)."
  HAVE_OMP_BT=0
fi

if [[ -f mm_openmp_blocked.c ]]; then
  gcc -O3 -march=native -ffast-math -fopenmp mm_openmp_blocked.c -o mm_openmp_blocked
  HAVE_OMP_BLOCKED=1
else
  log "ADVERTENCIA: mm_openmp_blocked.c no encontrado. Se omite OpenMP (blocked)."
  HAVE_OMP_BLOCKED=0
fi

log "Compilación completada."

# -------- Prepare outputs --------
mkdir -p "$LOG_DIR"
echo "impl,size,workers,iter,seconds" > "$RAW_CSV"

# Afinidad y comportamiento recomendado de OpenMP (sobrescribible por env)
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

# -------- Run: HILOS (pthread) --------
if [[ "$HAVE_HILOS" -eq 1 ]]; then
  log "Ejecutando pruebas: hilos (pthread)"
  : > "$LOG_DIR/hilos.log"
  for size in "${SIZES[@]}"; do
    for th in "${THREADS[@]}"; do
      for ((it=1; it<=REPEATS; it++)); do
        secs=$(run_with_timing ./hilos "$size" "$th")
        echo "hilos,$size,$th,$it,$secs" >> "$RAW_CSV"
        echo "hilos size=$size threads=$th iter=$it -> $secs s" >> "$LOG_DIR/hilos.log"
      done
    done
  done
fi

# -------- Run: PROCESOS (fork) --------
if [[ "$HAVE_PROCESOS" -eq 1 ]]; then
  log "Ejecutando pruebas: procesos (fork)"
  : > "$LOG_DIR/procesos.log"
  for size in "${SIZES[@]}"; do
    for pc in "${PROCS[@]}"; do
      for ((it=1; it<=REPEATS; it++)); do
        secs=$(run_with_timing ./procesos "$size" "$pc")
        echo "procesos,$size,$pc,$it,$secs" >> "$RAW_CSV"
        echo "procesos size=$size procs=$pc iter=$it -> $secs s" >> "$LOG_DIR/procesos.log"
      done
    done
  done
fi

# -------- Run: SECUENCIAL --------
if [[ "$HAVE_SECUENCIAL" -eq 1 ]]; then
  log "Ejecutando pruebas: secuencial"
  : > "$LOG_DIR/secuencial.log"
  for size in "${SIZES[@]}"; do
    for ((it=1; it<=REPEATS; it++)); do
      secs=$(run_with_timing ./secuencial "$size")
      echo "secuencial,$size,1,$it,$secs" >> "$RAW_CSV"
      echo "secuencial size=$size iter=$it -> $secs s" >> "$LOG_DIR/secuencial.log"
    done
  done
fi

# -------- Run: OPENMP (BT y BLOCKED) --------
if [[ "$HAVE_OMP_BT" -eq 1 || "$HAVE_OMP_BLOCKED" -eq 1 ]]; then
  log "Ejecutando pruebas: OpenMP (bt / blocked)"
  : > "$LOG_DIR/openmp.log"
  for size in "${SIZES[@]}"; do
    for th in "${THREADS[@]}"; do
      for ((it=1; it<=REPEATS; it++)); do
        if [[ "$HAVE_OMP_BT" -eq 1 ]]; then
          secs=$(run_with_timing ./mm_openmp_bt "$size" "$th")
          echo "openmp_bt,$size,$th,$it,$secs" >> "$RAW_CSV"
          echo "openmp_bt size=$size threads=$th iter=$it -> $secs s" >> "$LOG_DIR/openmp.log"
        fi
        if [[ "$HAVE_OMP_BLOCKED" -eq 1 ]]; then
          bs="${BLOCK_SIZE:-128}"
          secs=$(run_with_timing ./mm_openmp_blocked "$size" "$th" "$bs")
          echo "openmp_blocked,$size,$th,$it,$secs" >> "$RAW_CSV"
          echo "openmp_blocked size=$size threads=$th bs=$bs iter=$it -> $secs s" >> "$LOG_DIR/openmp.log"
        fi
      done
    done
  done
fi

# -------- Aggregate (average per impl,size,workers) --------
log "Calculando promedios…"
awk -F',' 'NR>1 { key=$1","$2","$3; sum[key]+=$5; cnt[key]++ }
END {
  print "impl,size,workers,avg_seconds,runs"
  n=asorti(sum, keys)
  for (i=1; i<=n; i++) {
    k=keys[i]
    printf "%s,%.6f,%d\n", k, sum[k]/cnt[k], cnt[k]
  }
}' "$RAW_CSV" | sort -t',' -k1,1 -k2,2n -k3,3n > "$AVG_CSV"

log "Listo. Resultados:"
log "  - Crudos:   $RAW_CSV"
log "  - Promedio: $AVG_CSV"
log "  - Logs:     $LOG_DIR/*.log"
log "  - Respaldo del script original: run_matrix_bench.original.sh"
