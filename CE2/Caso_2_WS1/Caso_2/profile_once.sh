#!/usr/bin/env bash
# profile_once.sh — Perfilado reproducible en una máquina
# Reúne: ficha HW/SW, perf stat, perf record/report, valgrind massif y /usr/bin/time -v
# Salida en: results/${HOST}/
set -euo pipefail

# ---------- Parámetros (puedes sobrescribir por env) ----------
N_MED=${N_MED:-2048}
N_LARGE=${N_LARGE:-4096}
BLOCK_SIZE=${BLOCK_SIZE:-128}
OMP_THREADS_MAX=${OMP_THREADS_MAX:-$(nproc)}
OPENMP_BT_BIN=${OPENMP_BT_BIN:-./mm_openmp_bt}
OPENMP_BLK_BIN=${OPENMP_BLK_BIN:-./mm_openmp_blocked}

# ---------- Preparación ----------
HOST=$(hostname)
OUTDIR="results/${HOST}"
mkdir -p "${OUTDIR}" info

# Afinidad OpenMP por defecto (se puede sobrescribir por env)
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

# GNU time o gtime si está disponible
if command -v /usr/bin/time >/dev/null 2>&1; then
  TIME_CMD="/usr/bin/time -v"
elif command -v gtime >/dev/null 2>&1; then
  TIME_CMD="gtime -v"
else
  TIME_CMD=""
fi

# ---------- Compilación (si faltan binarios) ----------
need_build=0
[[ -x "${OPENMP_BT_BIN}" ]] || need_build=1
[[ -x "${OPENMP_BLK_BIN}" ]] || need_build=1
if [[ "$need_build" -eq 1 ]]; then
  echo "[*] Compilando binarios OpenMP…"
  if command -v make >/dev/null 2>&1 && [[ -f Makefile ]]; then
    make
  else
    gcc -O3 -march=native -ffast-math -fopenmp mm_openmp_bt.c -o mm_openmp_bt
    gcc -O3 -march=native -ffast-math -fopenmp mm_openmp_blocked.c -o mm_openmp_blocked
  fi
fi

# ---------- Ficha HW/SW ----------
{
  echo "=== ${HOST} ==="
  date
  uname -a
  command -v lscpu >/dev/null 2>&1 && lscpu || true
  command -v free  >/dev/null 2>&1 && free -h || true
  gcc -v 2>&1 || true
} > "info/${HOST}_hw_sw.txt"

# ---------- Función helper perf stat ----------
run_perf_stat() {
  local label="$1"; shift
  local cmd=("$@")
  if ! command -v perf >/dev/null 2>&1; then
    echo "[!] 'perf' no disponible; omitiendo perf stat ($label)"
    return 0
  fi
  echo "[*] perf stat ($label) → ${OUTDIR}/perf_stat_${label}.txt"
  # -d: resumen extendido; eventos comunes adicionales
  perf stat -d -e task-clock,cycles,instructions,branches,branch-misses,cache-references,cache-misses \
    -- "${cmd[@]}" 1>/dev/null 2> "${OUTDIR}/perf_stat_${label}.txt" || true
}

# ---------- Función helper perf record/report ----------
run_perf_record() {
  local label="$1"; shift
  local cmd=("$@")
  if ! command -v perf >/dev/null 2>&1; then
    echo "[!] 'perf' no disponible; omitiendo perf record/report ($label)"
    return 0
  fi
  echo "[*] perf record/report ($label)"
  local data="${OUTDIR}/perf_${label}.data"
  perf record -F 400 --call-graph=dwarf -o "${data}" -- "${cmd[@]}" >/dev/null
  perf report --stdio -i "${data}" > "${OUTDIR}/perf_report_${label}.txt"
}

# ---------- Función helper Massif y /usr/bin/time -v ----------
run_memory_tools() {
  local label="$1"; shift
  local cmd=("$@")

  # /usr/bin/time -v
  if [[ -n "$TIME_CMD" ]]; then
    echo "[*] ${TIME_CMD} ($label) → ${OUTDIR}/time_${label}.txt"
    ${TIME_CMD} -- "${cmd[@]}" 1>/dev/null 2> "${OUTDIR}/time_${label}.txt" || true
  else
    echo "[!] /usr/bin/time no disponible; omitiendo (RSS)"
  fi

  # Valgrind Massif
  if command -v valgrind >/dev/null 2>&1; then
    echo "[*] valgrind massif ($label)"
    valgrind --tool=massif --time-unit=ms -- "${cmd[@]}" 1>/dev/null 2>&1 || true
    # Renombrar el último massif.out
    mfile=$(ls -1t massif.out.* 2>/dev/null | head -n1 || true)
    if [[ -n "$mfile" ]]; then
      mv "$mfile" "${OUTDIR}/massif_${label}.out"
      if command -v ms_print >/dev/null 2>&1; then
        ms_print "${OUTDIR}/massif_${label}.out" > "${OUTDIR}/massif_${label}.txt"
      fi
    fi
  else
    echo "[!] valgrind no disponible; omitiendo massif"
  fi
}

# ---------- Perfilado: OpenMP BLOQUEADO (recomendado) ----------
echo "[*] Perfilando OpenMP (blocked)"
run_perf_stat "omp_blocked_n${N_MED}_t1"        "${OPENMP_BLK_BIN}" "${N_MED}" 1 "${BLOCK_SIZE}"
run_perf_stat "omp_blocked_n${N_MED}_t${OMP_THREADS_MAX}" "${OPENMP_BLK_BIN}" "${N_MED}" "${OMP_THREADS_MAX}" "${BLOCK_SIZE}"

# Hotspots con tamaño grande y todos los hilos
run_perf_record "omp_blocked_n${N_LARGE}_t${OMP_THREADS_MAX}" "${OPENMP_BLK_BIN}" "${N_LARGE}" "${OMP_THREADS_MAX}" "${BLOCK_SIZE}"

# Memoria (RSS, page faults, Massif) en tamaño grande y todos los hilos
run_memory_tools "omp_blocked_n${N_LARGE}_t${OMP_THREADS_MAX}" "${OPENMP_BLK_BIN}" "${N_LARGE}" "${OMP_THREADS_MAX}" "${BLOCK_SIZE}"

# ---------- Perfilado: OpenMP BT (contraste de locality) ----------
echo "[*] Perfilando OpenMP (BT)"
run_perf_stat "omp_bt_n${N_MED}_t1"        "${OPENMP_BT_BIN}" "${N_MED}" 1
run_perf_stat "omp_bt_n${N_MED}_t${OMP_THREADS_MAX}" "${OPENMP_BT_BIN}" "${N_MED}" "${OMP_THREADS_MAX}"

# ---------- Resumen ----------
echo
echo "== Artefactos generados en ${OUTDIR} =="
ls -1 "${OUTDIR}" || true
echo
echo "Ficha de HW/SW: info/${HOST}_hw_sw.txt"
echo "[OK] Perfilado completado."
