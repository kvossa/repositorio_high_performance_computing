#!/bin/bash

# Compilar el programa serial con optimización
gcc -O3 -Wall -o cellular_autom_serial_exe cellular_autom_serial.c
echo "Compilación del programa serial completada."

# Archivo para guardar resultados
echo "Tipo, Tamaño, Repeticion, Movimientos totales, Tiempo total, Velocidad promedio" > results_serial.csv

# Parámetros de simulación
sizes=(100000 200000 300000 400000 500000)
iterations=1000

# Ejecutar simulaciones
for i in {1..10}; do
    echo "Iniciando repetición $i de 10..."
    for N in "${sizes[@]}"; do
        serial_output=$(./cellular_autom_serial_exe "$N" "$iterations")
        echo "Serial, $N, $i, $serial_output" >> results_serial.csv
    done
    echo "" >> results_serial.csv
done

echo "Todas las simulaciones serial han finalizado con éxito."
