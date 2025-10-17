#!/usr/bin/env bash
set -euo pipefail

# -------- Configurable --------
NPOINTS=(20000000 40000000 80000000 200000000 400000000 800000000 1600000000 3200000000 6400000000)
THREADS=(1 2 4 8 16)
PROCS=(1 2 4 8 16)
REPEATS=5
SEED=42

NEEDLE_L=0.5
NEEDLE_ELL=1.0

RAW_CSV="pi_results_raw.csv"
AVG_CSV="pi_results_avg.csv"
LOG_DIR="logs_pi"

mkdir -p "$LOG_DIR"
echo "algo,impl,N,workers,iter,seconds,pi" > "$RAW_CSV"

cleanup() { rm -f tmp.out tmp.err; }
trap cleanup EXIT

ensure_bin() {
  local b="$1"
  if [[ ! -x "./$b" ]]; then
    echo "[ERROR] No existe ejecutable ./$b. Compílalo antes (recuerda -lm en needle)." | tee -a "$LOG_DIR/errors.setup.log"
    exit 1
  fi
}

# ---- verificar ejecutables esperados ----
for b in dart_serial needle_serial dart_threads needle_threads dart_fork needle_fork; do
  ensure_bin "$b"
done

run_with_timing() {
  local cmd="$*"
  local start end
  start=$(date +%s.%N)
  # Importante: no dejar que un fallo del comando mate el script; capturamos el exit code
  set +e
  eval "$cmd" >tmp.out 2>tmp.err
  local rc=$?
  set -e
  end=$(date +%s.%N)
  # segundos
  local secs
  secs=$(awk -v s="$start" -v e="$end" 'BEGIN{ printf("%.6f\n", e - s) }')
  echo "$secs" "$rc"
}

extract_pi() {
  # No dejar que grep falle con -e/-o y pipefail
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
  # stdout completo
  cat tmp.out >> "$LOG_DIR/${algo}_${impl}.log"
  echo "--- [$tag] ---" >> "$LOG_DIR/${algo}_${impl}.log"
  # stderr (si hubo)
  if [[ -s tmp.err ]]; then
    {
      echo "### STDERR [$tag]"
      cat tmp.err
      echo "------------"
    } >> "$LOG_DIR/${algo}_${impl}.err.log"
  fi
}

# -------- Run --------
for algo in dart needle; do

  # ===== Serial =====
  for N in "${NPOINTS[@]}"; do
    for ((it=1; it<=REPEATS; it++)); do
      if [[ "$algo" == "dart" ]]; then
        read -r secs rc < <(run_with_timing ./dart_serial "$N" "$SEED")
      else
        read -r secs rc < <(run_with_timing ./needle_serial "$N" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED")
      fi
      pi=$(extract_pi)
      echo "$algo,serial,$N,1,$it,$secs,$pi" >> "$RAW_CSV"
      append_logs "$algo" "serial" "N=$N it=$it rc=$rc"
    done
  done

  # ===== Threads =====
  for N in "${NPOINTS[@]}"; do
    for th in "${THREADS[@]}"; do
      for ((it=1; it<=REPEATS; it++)); do
        if [[ "$algo" == "dart" ]]; then
          read -r secs rc < <(run_with_timing ./dart_threads "$N" "$th" "$SEED")
        else
          read -r secs rc < <(run_with_timing ./needle_threads "$N" "$th" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED")
        fi
        pi=$(extract_pi)
        echo "$algo,threads,$N,$th,$it,$secs,$pi" >> "$RAW_CSV"
        append_logs "$algo" "threads" "N=$N T=$th it=$it rc=$rc"
      done
    done
  done

  # ===== Fork (pipes) =====
  for N in "${NPOINTS[@]}"; do
    for pc in "${PROCS[@]}"; do
      for ((it=1; it<=REPEATS; it++)); do
        if [[ "$algo" == "dart" ]]; then
          read -r secs rc < <(run_with_timing ./dart_fork "$N" "$pc" "$SEED")
        else
          read -r secs rc < <(run_with_timing ./needle_fork "$N" "$pc" "$NEEDLE_L" "$NEEDLE_ELL" "$SEED")
        fi
        pi=$(extract_pi)
        echo "$algo,fork,$N,$pc,$it,$secs,$pi" >> "$RAW_CSV"
        append_logs "$algo" "fork" "N=$N P=$pc it=$it rc=$rc"
      done
    done
  done
done

# -------- Aggregate --------
awk -F',' 'NR>1 { key=$1","$2","$3","$4; sum[key]+=$6; cnt[key]++ }
END {
  print "algo,impl,N,workers,avg_seconds,runs"
  for (k in sum) {
    printf "%s,%.6f,%d\n", k, sum[k]/cnt[k], cnt[k]
  }
}' "$RAW_CSV" | sort -t',' -k1,1 -k3,3n -k4,4n > "$AVG_CSV"

echo "Listo."
echo "  - Resultados crudos: $RAW_CSV"
echo "  - Promedios:         $AVG_CSV"
echo "  - Logs:              $LOG_DIR/*.log y $LOG_DIR/*.err.log"
