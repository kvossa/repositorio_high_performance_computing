
#!/usr/bin/env bash
set -euo pipefail

# Configuración por defecto (se puede editar o pasar por env)
SIZES="${SIZES:-512 1024 1536 2048}"
THREADS="${THREADS:-1 2 4 8 16}"
BLOCK_SIZE="${BLOCK_SIZE:-128}"
REPS="${REPS:-3}"
OUT="${OUT:-results.csv}"

# Afinidad y comportamiento de OMP
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

echo "machine,compiler,n,prog,threads,block_size,run,time_s,gflops,transpose_s,checksum" > "$OUT"

machine="$(hostname)"
compiler="$(${CC:-gcc} -v 2>&1 | tail -n1 | sed 's/^Configured with://;s/^[ ]*//g' || true)"

run_prog () {
  local prog="$1"; shift
  local args=("$@")
  # Ejecuta y parsea salida esperada
  # Línea 1: prog=..., n=..., threads=..., [bs=...]
  # Línea 2: Tiempo mult: X s | GFLOPS: Y | Tiempo transpuesta: Z s
  # stderr: checksum=W
  local tmpout tmperr
  tmpout="$(mktemp)"; tmperr="$(mktemp)"
  set +e
  "./$prog" "${args[@]}" >"$tmpout" 2>"$tmperr"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "ERROR: $prog ${args[*]} rc=$rc" >&2
    cat "$tmpout" >&2 || true
    cat "$tmperr" >&2 || true
    rm -f "$tmpout" "$tmperr"
    return $rc
  fi

  local header line2 checksum
  header="$(head -n1 "$tmpout")"
  line2="$(sed -n '2p' "$tmpout")"
  checksum="$(grep -oE 'checksum=[0-9.]+$' "$tmperr" | cut -d= -f2)"
  # Extraer campos
  local prog_name n threads bs=""
  prog_name="$(echo "$header" | sed -n 's/.*prog=\([^,]*\).*/\1/p')"
  n="$(echo "$header" | sed -n 's/.*n=\([0-9]\+\).*/\1/p')"
  threads="$(echo "$header" | sed -n 's/.*threads=\([0-9]\+\).*/\1/p')"
  if [[ "$header" =~ bs= ]]; then
    bs="$(echo "$header" | sed -n 's/.*bs=\([0-9]\+\).*/\1/p')"
  fi
  local t g tT
  t="$(echo "$line2" | sed -n 's/.*Tiempo mult: \([0-9.]\+\) s.*/\1/p')"
  g="$(echo "$line2" | sed -n 's/.*GFLOPS: \([0-9.]\+\).*/\1/p')"
  tT="$(echo "$line2" | sed -n 's/.*Tiempo transpuesta: \([0-9.]\+\) s.*/\1/p')"

  echo "$machine,\"$compiler\",$n,$prog_name,$threads,${bs:-},$run,$t,$g,$tT,$checksum" >> "$OUT"
  rm -f "$tmpout" "$tmperr"
}

for n in $SIZES; do
  for t in $THREADS; do
    for run in $(seq 1 "$REPS"); do
      run_prog mm_openmp_bt "$n" "$t"
      run_prog mm_openmp_blocked "$n" "$t" "$BLOCK_SIZE"
    done
  done
done

echo "Resultados guardados en $OUT"
