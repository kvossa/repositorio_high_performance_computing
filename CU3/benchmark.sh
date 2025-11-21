#!/bin/bash

# Script de benchmarking completo para multiplicación de matrices con MPI
# Autor: [Tu nombre]
# Fecha: Noviembre 2024

export LC_NUMERIC=C
export LC_ALL=C

OUTPUT_DIR="/shared/resultados"
mkdir -p $OUTPUT_DIR

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CSV_FILE="$OUTPUT_DIR/benchmark_$TIMESTAMP.csv"

# Configuración de pruebas
MATRIX_SIZES=(600 1200 1800 2400)
NUM_PROCESSES=(1 2 4 6)
REPETITIONS=10

echo "========================================================"
echo "    BENCHMARK COMPLETO - MULTIPLICACION DE MATRICES"
echo "========================================================"
echo ""
echo "Tamanos de matrices: ${MATRIX_SIZES[@]}"
echo "Numeros de procesos: ${NUM_PROCESSES[@]}"
echo "Repeticiones por configuracion: $REPETITIONS"
echo ""
echo "Archivo de salida: $CSV_FILE"
echo ""
echo "========================================================"
echo ""

# Crear encabezado del CSV
echo "Tamano_Matriz,Num_Procesos,Repeticion,Tiempo_Segundos,GFLOPS" > $CSV_FILE

TOTAL_TESTS=$((${#MATRIX_SIZES[@]} * ${#NUM_PROCESSES[@]} * REPETITIONS))
CURRENT_TEST=0

# Iterar sobre cada tamaño de matriz
for size in "${MATRIX_SIZES[@]}"; do
    echo "================================================"
    echo "  PROBANDO MATRICES DE TAMANO: ${size}x${size}"
    echo "================================================"
    echo ""
    
    # Generar código C con el tamaño actual
    sed "s/SIZE_PLACEHOLDER/$size/g" /shared/matrix_mult_template.c > /shared/matrix_temp.c
    
    # Compilar el programa
    mpicc -o /shared/matrix_temp /shared/matrix_temp.c -lm 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo "Error compilando para tamano $size"
        continue
    fi
    
    # Iterar sobre cada número de procesos
    for np in "${NUM_PROCESSES[@]}"; do
        echo "  Probando con $np proceso(s)..."
        
        # Realizar las repeticiones
        for rep in $(seq 1 $REPETITIONS); do
            CURRENT_TEST=$((CURRENT_TEST + 1))
            PROGRESS=$((CURRENT_TEST * 100 / TOTAL_TESTS))
            
            printf "    Repeticion %2d/%d [Progreso: %3d%%] ... " $rep $REPETITIONS $PROGRESS
            
            # Ejecutar el benchmark
            if [ $np -eq 1 ]; then
                RESULT=$(mpirun -np 1 /shared/matrix_temp 2>/dev/null)
            else
                RESULT=$(mpirun -np $np --hostfile /shared/hostfile /shared/matrix_temp 2>/dev/null)
            fi
            
            # Extraer tiempo y GFLOPS
            TIME=$(echo $RESULT | cut -d',' -f1)
            GFLOPS=$(echo $RESULT | cut -d',' -f2)
            
            # Guardar en CSV
            echo "$size,$np,$rep,$TIME,$GFLOPS" >> $CSV_FILE
            
            printf "Tiempo: %.4fs, GFLOPS: %.2f\n" $TIME $GFLOPS
            
            # Pequeña pausa entre ejecuciones
            sleep 0.5
        done
        echo ""
    done
    echo ""
done

# Limpiar archivos temporales
rm -f /shared/matrix_temp /shared/matrix_temp.c

echo "========================================================"
echo "           BENCHMARKING COMPLETADO"
echo "========================================================"
echo ""
echo "Resultados guardados en: $CSV_FILE"
echo "Total de pruebas realizadas: $CURRENT_TEST"
echo ""

# Generar resumen estadístico si Python está disponible
if command -v python3 &> /dev/null; then
    python3 -c "import pandas" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Generando resumen estadistico..."
        python3 /shared/generate_summary.py $CSV_FILE
    else
        echo "Nota: Instala pandas para generar resumen estadistico:"
        echo "  sudo apt install python3-pandas"
    fi
fi

echo "Para analizar los resultados:"
echo "  cat $CSV_FILE"
echo ""