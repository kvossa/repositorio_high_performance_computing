#!/bin/bash

# ===============================================================
#  Script de perfilamiento para RETO3
#
#  Estructura detectada:
#      RETO3/
#        ├── MPI/
#        │     ├── cellular_autom_mpi.c
#        │     └── run_simulations_mpi.sh
#        └── SERIAL/
#              ├── cellular_autom_serial.c
#              ├── run_simulations_serial.sh
#              └── profiling.sh   (este archivo)
#
#  Este script:
#    1. Compila versiones serial y MPI con -pg para gprof
#    2. Perfila con /usr/bin/time -v
#    3. Perfila con valgrind massif (si está instalado)
#    4. Guarda todo en RETO3/profiling_results/
# ===============================================================

set -e

ROOT_DIR=$(pwd)
SERIAL_DIR="${ROOT_DIR}/SERIAL"
MPI_DIR="${ROOT_DIR}/MPI"
RESULTS_DIR="${ROOT_DIR}/profiling_results"

mkdir -p "$RESULTS_DIR"

echo "========================================="
echo "  INICIANDO PERFILAMIENTO RETO3"
echo "========================================="

# Parámetros de simulación
SIZES=(100000 200000 300000)
ITERATIONS=1000
MPI_PROCS=4

# ===============================================================
# 1) COMPILACIÓN
# ===============================================================

echo "[*] Compilando versión SERIAL con -pg..."
gcc -pg -O2 -Wall \
    -o "${SERIAL_DIR}/cellular_autom_serial_prof" \
    "${SERIAL_DIR}/cellular_autom_serial.c"

echo "[*] Compilando versión MPI con -pg..."
if command -v mpicc >/dev/null 2>&1; then
    mpicc -pg -O2 -Wall \
        -o "${MPI_DIR}/cellular_autom_mpi_prof" \
        "${MPI_DIR}/cellular_autom_mpi.c"
else
    echo "[ADVERTENCIA] MPI no disponible: no se compila la versión MPI"
fi

# ===============================================================
# 2) PERFIL SERIAL
# ===============================================================

echo
echo "========================================="
echo "  PERFILAMIENTO SERIAL"
echo "========================================="

for N in "${SIZES[@]}"; do
    echo
    echo "[SERIAL] N=$N, it=$ITERATIONS"

    BASE="${RESULTS_DIR}/serial_N${N}"

    # 2.1 /usr/bin/time -v
    if command -v /usr/bin/time >/dev/null 2>&1; then
        echo "  - Medición con /usr/bin/time -v"
        /usr/bin/time -v -o "${BASE}_time.txt" \
            "${SERIAL_DIR}/cellular_autom_serial_prof" "$N" "$ITERATIONS" \
            > "${BASE}_output.txt"
    else
        echo "  - /usr/bin/time no disponible"
        "${SERIAL_DIR}/cellular_autom_serial_prof" "$N" "$ITERATIONS" \
            > "${BASE}_output.txt"
    fi

    # 2.2 gprof
    if command -v gprof >/dev/null 2>&1; then
        echo "  - gprof..."
        gprof "${SERIAL_DIR}/cellular_autom_serial_prof" gmon.out \
            > "${BASE}_gprof.txt"
        rm -f gmon.out
    fi

    # 2.3 Valgrind Massif
    if command -v valgrind >/dev/null 2>&1; then
        echo "  - valgrind massif..."
        valgrind --tool=massif \
            --massif-out-file="${BASE}_massif.out" \
            "${SERIAL_DIR}/cellular_autom_serial_prof" "$N" "$ITERATIONS" \
            > "${BASE}_massif_run.txt" 2>&1
    else
        echo "  - Valgrind no disponible"
    fi
done

# ===============================================================
# 3) PERFIL MPI
# ===============================================================

if command -v mpirun >/dev/null 2>&1 && [ -f "${MPI_DIR}/cellular_autom_mpi_prof" ]; then

    echo
    echo "========================================="
    echo "  PERFILAMIENTO MPI (np=$MPI_PROCS)"
    echo "========================================="

    for N in "${SIZES[@]}"; do

        echo
        echo "[MPI] N=$N, it=$ITERATIONS, procs=$MPI_PROCS"

        BASE="${RESULTS_DIR}/mpi_N${N}_P${MPI_PROCS}"

        # 3.1 /usr/bin/time -v
        if command -v /usr/bin/time >/dev/null 2>&1; then
            echo "  - time -v"
            /usr/bin/time -v -o "${BASE}_time.txt" \
                mpirun -np "$MPI_PROCS" \
                "${MPI_DIR}/cellular_autom_mpi_prof" "$N" "$ITERATIONS" \
                > "${BASE}_output.txt"
        else
            mpirun -np "$MPI_PROCS" \
                "${MPI_DIR}/cellular_autom_mpi_prof" "$N" "$ITERATIONS" \
                > "${BASE}_output.txt"
        fi

        # 3.2 gprof
        if command -v gprof >/dev/null 2>&1; then
            echo "  - gprof MPI"
            MPI_GPROF_DIR="${BASE}_gprof"
            mkdir -p "$MPI_GPROF_DIR"

            # Guardar todos los gmon.out* generados por procesos MPI
            mv gmon.out* "$MPI_GPROF_DIR/" 2>/dev/null || true

            for GMON in "$MPI_GPROF_DIR"/gmon.out*; do
                if [ -f "$GMON" ]; then
                    gprof "${MPI_DIR}/cellular_autom_mpi_prof" "$GMON" \
                        > "${GMON}.txt"
                fi
            done
        fi

        # 3.3 Valgrind Massif en 1 proceso
        if command -v valgrind >/dev/null 2>&1; then
            echo "  - valgrind massif (np=1)"
            MASSIF_BASE="${RESULTS_DIR}/mpi_massif_N${N}"
            valgrind --tool=massif \
                --massif-out-file="${MASSIF_BASE}.out" \
                mpirun -np 1 "${MPI_DIR}/cellular_autom_mpi_prof" "$N" "$ITERATIONS" \
                > "${MASSIF_BASE}_run.txt" 2>&1
        fi
    done

else
    echo
    echo "[ADVERTENCIA] mpirun o cellular_autom_mpi_prof no disponible: se omite perfil MPI"
fi

echo
echo "========================================="
echo "  PERFILAMIENTO COMPLETADO"
echo "  Resultados en: $RESULTS_DIR/"
echo "========================================="
