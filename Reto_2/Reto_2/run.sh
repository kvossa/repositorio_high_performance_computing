#!/usr/bin/env bash
set -euo pipefail

# =========================================
# CONFIGURACIÓN
# =========================================
NPOINTS=(20000000 40000000 80000000 200000000 400000000 800000000 1600000000)
THREADS=(1 2 4 8 16)
PROCS=(1 2 4 8 16)
REPEATS=5
SEED=42

NEEDLE_L=0.5
NEEDLE_ELL=1.0

RAW_CSV="pi_results_raw.csv"
AVG_CSV="pi_results_avg.csv"
LOG_DIR="logs_pi"

# ==================================================
# 1. COMPILACIÓN
# ==================================================
echo "[INFO] Compilando binarios..."
mkdir -p "$LOG_DIR"

# Puedes cambiar este valor a -O3 o -Ofast según lo que quieras probar
OPT_LEVEL="-O3"

CC=${CC:-gcc}

# ---- fuentes ----
# Asumo que tienes en el mismo dir:
#  dart_serial.c dart_threads.c dart_fork.c
#  needle_serial.c needle_threads.c needle_fork.c
#  dart_omp.c needle_omp.c
#  rng.h timer.h
# Si tuvieran otros nombres, cámbialos aquí.
compile() {
  local src="$1"
  local out="$2"
  local extra="$3"
  echo "  $CC $OPT_LEVEL $src -o $out $extra"
  $CC $OPT_LEVEL "$src" -o "$out" $extra
}

# serial
compile dart_serial.c   dart_serial_o2   "-lm"
compile needle_serial.c needle_serial_o2 "-lm"

# pthreads
compile dart_threads.c   dart_threads_o2   "-lm -pthread"
compile needle_threads.c needle_threads_o2 "-lm -pthread"

# fork
compile dart_fork.c   dart_fork_o2   "-lm"
compile needle_fork.c needle_fork_o2 "-lm"

# openmp
compile dart_omp.c   dart_omp_o2   "-lm -fopenmp"
compile needle_omp.c needle_omp_o2 "-lm -fopenmp"

echo "[INFO] Compilación terminada."

# ==================================================
# 2. EJECUCIÓN DE BENCHMARKS
# ==================================================
echo "algo,impl,N,workers,iter,seconds,pi" > "$RAW_CSV"

cleanup() { rm -f tmp.out tmp.err; }
trap cleanup EXIT

ensure_bin() {
  local b="$1"
  if [[ ! -x "./$b" ]]; then
    echo "[ERROR] No existe ejecutable ./$b. Revisa la compilación." | tee -a "$LOG_DIR/errors.setup.log"
    exit 1
  fi
}

run_with_timing() {
  local cmd="$*"
  local start end
  start=$(date +%s.%N)
  set +e
  eval "$cmd" >tmp.out 2>tmp.err
  local rc=$?
  set -e
  end=$(date +%s.%N)
  local secs
  secs=$(awk -v s="$start" -v e="$end" 'BEGIN{ printf("%.6f\n", e - s) }')
  echo "$secs" "$rc"
}

extract_pi() {
  set +e
  local v
  v=$(grep -o 'pi=[^[:space:]]*' tmp.out | cut -d'=' -f2)
  local rc=$?
  set -e
  if [[ $rc -ne 0 || -z "${v:-}" ]]; then
    echo "NA"
  else
    echo "$v"
  fi
}

append_logs() {
  local algo="$1" impl="$2" tag="$3"
  cat tmp.out >> "$LOG_DIR/${algo}_${impl}.log"
  echo "--- [$tag] ---" >> "$LOG_DIR/${algo}_${impl}.log"
  if [[ -s tmp.err ]]; then
    {
      echo "### STDERR [$tag]"
      cat tmp.err
      echo "------------"
    } >> "$LOG_DIR/${algo}_${impl}.err.log"
  fi
}

# verificar
for b in \
  dart_serial_o2 needle_serial_o2 \
  dart_threads_o2 needle_threads_o2 \
  dart_fork_o2 needle_fork_o2 \
  dart_omp_o2 needle_omp_o2
do
  ensure_bin "$b"
done

echo "[INFO] Iniciando benchmarks..."

for algo in dart needle; do

  # ===== Serial =====
  for N in "${NPOINTS[@]}"; do
    for ((it=1; it<=REPEATS; it++)); do
      if [[ "$algo" == "dart" ]]; then
        read -r secs rc < <(run_with_timing ./dart_serial_o2 "$N" "$SEED")
      else
        read -r secs rc < <(run_with_timing ./needle_serial_o2 "$N" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED")
      fi
      pi=$(extract_pi)
      echo "$algo,serial,$N,1,$it,$secs,$pi" >> "$RAW_CSV"
      append_logs "$algo" "serial" "N=$N it=$it rc=$rc"
    done
  done

  # ===== Threads (pthreads) =====
  for N in "${NPOINTS[@]}"; do
    for th in "${THREADS[@]}"; do
      for ((it=1; it<=REPEATS; it++)); do
        if [[ "$algo" == "dart" ]]; then
          read -r secs rc < <(run_with_timing ./dart_threads_o2 "$N" "$th" "$SEED")
        else
          read -r secs rc < <(run_with_timing ./needle_threads_o2 "$N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED")
        fi
        pi=$(extract_pi)
        echo "$algo,threads,$N,$th,$it,$secs,$pi" >> "$RAW_CSV"
        append_logs "$algo" "threads" "N=$N T=$th it=$it rc=$rc"
      done
    done
  done

  # ===== Fork =====
  for N in "${NPOINTS[@]}"; do
    for pc in "${PROCS[@]}"; do
      for ((it=1; it<=REPEATS; it++)); do
        if [[ "$algo" == "dart" ]]; then
          read -r secs rc < <(run_with_timing ./dart_fork_o2 "$N" "$pc" "$SEED")
        else
          read -r secs rc < <(run_with_timing ./needle_fork_o2 "$N" "$pc" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED")
        fi
        pi=$(extract_pi)
        echo "$algo,fork,$N,$pc,$it,$secs,$pi" >> "$RAW_CSV"
        append_logs "$algo" "fork" "N=$N P=$pc it=$it rc=$rc"
      done
    done
  done

  # ===== OpenMP =====
  for N in "${NPOINTS[@]}"; do
    for th in "${THREADS[@]}"; do
      for ((it=1; it<=REPEATS; it++)); do
        if [[ "$algo" == "dart" ]]; then
          read -r secs rc < <(run_with_timing OMP_NUM_THREADS=$th ./dart_omp_o2 "$N" "$th" "$SEED")
        else
          read -r secs rc < <(run_with_timing OMP_NUM_THREADS=$th ./needle_omp_o2 "$N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED")
        fi
        pi=$(extract_pi)
        echo "$algo,omp,$N,$th,$it,$secs,$pi" >> "$RAW_CSV"
        append_logs "$algo" "omp" "N=$N T=$th it=$it rc=$rc"
      done
    done
  done

done

# ==================================================
# 3. AGREGAR PROMEDIOS
# ==================================================
awk -F',' 'NR>1 {
  key=$1","$2","$3","$4;
  sumt[key]+=$6;
  sump[key]+=$7;
  cnt[key]++;
}
END {
  print "algo,impl,N,workers,avg_seconds,avg_pi,runs";
  for (k in sumt) {
    printf "%s,%.6f,%.9f,%d\n", k, sumt[k]/cnt[k], sump[k]/cnt[k], cnt[k];
  }
}' "$RAW_CSV" | sort -t',' -k1,1 -k3,3n -k4,4n > "$AVG_CSV"

echo "[OK] Listo."
echo "  - Resultados crudos: $RAW_CSV"
echo "  - Promedios:         $AVG_CSV"
echo "  - Logs:              $LOG_DIR/"
