#!/bin/bash

# Compilar el programa MPI con optimización
mpicc -O3 -Wall -o cellular_autom_mpi_exe cellular_autom_mpi.c
echo "Compilación del programa MPI completada."

# Archivo para guardar resultados
echo "Tipo, Tamaño, Repeticion, Movimientos totales, Tiempo total, Velocidad promedio" > results_mpi.csv

# Parámetros de simulación
sizes=(100000 200000 300000 400000 500000)
iterations=1000
num_procs=4

# Ejecutar simulaciones MPI
if command -v mpirun >/dev/null 2>&1; then
    for i in {1..10}; do
        echo "Iniciando repetición $i de 10..."
        for N in "${sizes[@]}"; do
            mpi_output=$(mpirun -np "$num_procs" ./cellular_autom_mpi_exe "$N" "$iterations")
            if [ $? -eq 0 ]; then
                echo "MPI, $N, $i, $mpi_output" >> results_mpi.csv
            else
                echo "Fallo en la ejecución MPI para N = $N"
            fi
        done
        echo "" >> results_mpi.csv
    done
    echo "Todas las simulaciones MPI han finalizado con éxito."
else
    echo "MPI no está disponible, omitiendo la ejecución MPI."
fi
