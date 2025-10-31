#!/usr/bin/env bash
# summarize_profiles.sh — Extrae métricas clave de results/<HOST> y produce un CSV
# Lee: perf_stat_*.txt, time_*.txt, massif_*.txt
# Opcional: re-ejecuta mm_openmp_bt / mm_openmp_blocked para capturar GFLOPS de 2048 (t1 y tmax)
set -euo pipefail

# ---------- Parámetros ----------
N_MED=${N_MED:-2048}
N_LARGE=${N_LARGE:-4096}
BLOCK_SIZE=${BLOCK_SIZE:-128}
OMP_THREADS_MAX=${OMP_THREADS_MAX:-$(nproc)}
OPENMP_BT_BIN=${OPENMP_BT_BIN:-./mm_openmp_bt}
OPENMP_BLK_BIN=${OPENMP_BLK_BIN:-./mm_openmp_blocked}
OUT_CSV="${OUT_CSV:-profile_summary_all.csv}"

# Afinidad OpenMP por defecto (se puede sobrescribir por env)
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

# ---------- Helpers ----------
to_seconds() {
  # Convierte "H:MM:SS" o "M:SS" o "S" en segundos (float si trae decimales)
  local t="$1"
  t="${t/,/.}"
  local cnt=$(awk -F: '{print NF-1}' <<< "$t")
  if [[ "$cnt" -eq 0 ]]; then
    awk -v x="$t" 'BEGIN{ printf("%.3f\n", x+0) }'
  elif [[ "$cnt" -eq 1 ]]; then
    awk -F: '{m=$1; s=$2; if(s=="") s=0; printf("%.3f\n", m*60 + s+0)}' <<< "$t"
  else
    awk -F: '{h=$1; m=$2; s=$3; if(m=="") m=0; if(s=="") s=0; printf("%.3f\n", h*3600 + m*60 + s+0)}' <<< "$t"
  fi
}

extract_perf_field() {
  local file="$1"; shift
  local pat="$1"; shift
  if [[ -f "$file" ]]; then
    local val=$(grep -m1 -E "$pat" "$file" | awk '{print $1}' | tr ',' '.')
    [[ -n "$val" ]] && echo "$val" || echo ""
  else
    echo ""
  fi
}

extract_perf_count() {
  local file="$1"; shift
  local pat="$1"; shift
  if [[ -f "$file" ]]; then
    local val=$(grep -m1 -E "$pat" "$file" | awk '{print $1}' | tr -d ',' )
    [[ -n "$val" ]] && echo "$val" || echo ""
  else
    echo ""
  fi
}

extract_time_and_rss() {
  local file="$1"
  local elapsed=$(grep -m1 "Elapsed (wall clock) time" "$file" 2>/dev/null | awk '{print $8}')
  local rss=$(grep -m1 "Maximum resident set size" "$file" 2>/dev/null | awk '{print $6}')
  if [[ -n "$elapsed" ]]; then
    elapsed=$(to_seconds "$elapsed")
  fi
  echo "${elapsed:-},${rss:-}"
}

extract_massif_peak() {
  local file="$1"
  if [[ -f "$file" ]]; then
    awk -F'=' '/mem_heap_B=/{print $2}' "$file" | sort -n | tail -n1
  else
    echo ""
  fi
}

capture_gflops() {
  local impl="$1"; shift
  local n="$1"; shift
  local th="$1"; shift
  if [[ "$impl" == "openmp_blocked" ]]; then
    local out="$($OPENMP_BLK_BIN "$n" "$th" "$BLOCK_SIZE" 2>/dev/null || true)"
  else
    local out="$($OPENMP_BT_BIN "$n" "$th" 2>/dev/null || true)"
  fi
  grep -m1 -E "GFLOPS:" <<< "$out" | sed -n 's/.*GFLOPS: \([0-9.]\+\).*/\1/p'
}

# ---------- Detecta hosts ----------
HOSTS=()
if [[ -d results ]]; then
  while IFS= read -r -d '' d; do
    HOSTS+=("$(basename "$d")")
  done < <(find results -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi
if [[ ${#HOSTS[@]} -eq 0 ]]; then
  HOSTS+=("$(hostname)")
fi

# ---------- CSV header ----------
echo "host,impl,n,threads,elapsed_s,max_rss_kb,ipc,instructions,cycles,cache_misses,cache_refs,task_clock_ms,gflops" > "$OUT_CSV"

# ---------- Recorre cada host ----------
for host in "${HOSTS[@]}"; do
  d="results/$host"
  f_blk_t1="$d/perf_stat_omp_blocked_n${N_MED}_t1.txt"
  f_blk_tn="$d/perf_stat_omp_blocked_n${N_MED}_t${OMP_THREADS_MAX}.txt"
  f_bt_t1="$d/perf_stat_omp_bt_n${N_MED}_t1.txt"
  f_bt_tn="$d/perf_stat_omp_bt_n${N_MED}_t${OMP_THREADS_MAX}.txt"

  for impl in "openmp_blocked:$f_blk_t1:1" "openmp_blocked:$f_blk_tn:${OMP_THREADS_MAX}" "openmp_bt:$f_bt_t1:1" "openmp_bt:$f_bt_tn:${OMP_THREADS_MAX}"; do
    IFS=: read -r name file th <<< "$impl"
    [[ -f "$file" ]] || continue

    ipc=$(extract_perf_field "$file" "insn per cycle")
    instr=$(extract_perf_count "$file" "instructions")
    cycles=$(extract_perf_count "$file" "cycles")
    cmiss=$(extract_perf_count "$file" "cache-misses")
    cref=$(extract_perf_count "$file" "cache-references")
    tclk=$(extract_perf_count "$file" "task-clock")

    gflops=$(capture_gflops "$name" "$N_MED" "$th")

    echo "$host,$name,$N_MED,$th,,,$ipc,$instr,$cycles,$cmiss,$cref,$tclk,$gflops" >> "$OUT_CSV"
  done

  timef="$d/time_omp_blocked_n${N_LARGE}_t${OMP_THREADS_MAX}.txt"
  massif_txt="$d/massif_omp_blocked_n${N_LARGE}_t${OMP_THREADS_MAX}.txt"
  if [[ -f "$timef" ]]; then
    IFS=, read -r elapsed rss <<< "$(extract_time_and_rss "$timef")"
    gflops=$(capture_gflops "openmp_blocked" "$N_LARGE" "$OMP_THREADS_MAX")
    echo "$host,openmp_blocked,$N_LARGE,${OMP_THREADS_MAX},$elapsed,${rss:-},,,,,,,$gflops" >> "$OUT_CSV"
  fi
  if [[ -f "$massif_txt" ]]; then
    peak=$(extract_massif_peak "$massif_txt")
    echo "# ${host} massif peak heap (bytes) n=${N_LARGE} t=${OMP_THREADS_MAX}: ${peak}" >> "$OUT_CSV"
  fi
done

echo "[OK] Resumen escrito en $OUT_CSV"
