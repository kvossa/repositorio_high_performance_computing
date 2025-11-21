/**
 * Multiplicación de Matrices Paralela con MPI
 * 
 * Descripción: Implementa la multiplicación de matrices C = A × B
 * usando paralelismo con MPI distribuyendo filas de la matriz A
 * entre múltiples procesos.
 * 
 * Autor: [Tu nombre]
 * Fecha: Noviembre 2024
 */

#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define N SIZE_PLACEHOLDER

/**
 * Inicializa una matriz con valores aleatorios entre 0 y 9
 */
void initialize_matrix(double *matrix, int rows, int cols) {
    for (int i = 0; i < rows * cols; i++) {
        matrix[i] = (double)(rand() % 10);
    }
}

int main(int argc, char *argv[]) {
    int rank, size_proc;
    double *A = NULL;       // Matriz A (completa, solo en rank 0)
    double *B = NULL;       // Matriz B (completa, en todos los procesos)
    double *C = NULL;       // Matriz resultado (completa, solo en rank 0)
    double *local_A = NULL; // Porción de A para cada proceso
    double *local_C = NULL; // Porción de C para cada proceso
    double start_time, end_time, total_time;
    
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size_proc);
    
    // Verificar que N sea divisible por el número de procesos
    if (N % size_proc != 0) {
        MPI_Finalize();
        return 1;
    }
    
    int rows_per_process = N / size_proc;
    
    // Inicializar matrices en el proceso maestro (rank 0)
    if (rank == 0) {
        A = (double *)malloc(N * N * sizeof(double));
        B = (double *)malloc(N * N * sizeof(double));
        C = (double *)malloc(N * N * sizeof(double));
        
        srand(time(NULL));
        initialize_matrix(A, N, N);
        initialize_matrix(B, N, N);
    }
    
    // Todos los procesos necesitan la matriz B completa
    if (rank != 0) {
        B = (double *)malloc(N * N * sizeof(double));
    }
    
    // Broadcast: enviar matriz B a todos los procesos
    MPI_Bcast(B, N * N, MPI_DOUBLE, 0, MPI_COMM_WORLD);
    
    // Cada proceso recibe su porción de A y reserva espacio para su porción de C
    local_A = (double *)malloc(rows_per_process * N * sizeof(double));
    local_C = (double *)malloc(rows_per_process * N * sizeof(double));
    
    // Sincronizar antes de medir tiempo
    MPI_Barrier(MPI_COMM_WORLD);
    start_time = MPI_Wtime();
    
    // Scatter: distribuir filas de A entre los procesos
    MPI_Scatter(A, rows_per_process * N, MPI_DOUBLE,
                local_A, rows_per_process * N, MPI_DOUBLE,
                0, MPI_COMM_WORLD);
    
    // Cada proceso calcula su porción de C = local_A × B
    for (int i = 0; i < rows_per_process; i++) {
        for (int j = 0; j < N; j++) {
            local_C[i * N + j] = 0.0;
            for (int k = 0; k < N; k++) {
                local_C[i * N + j] += local_A[i * N + k] * B[k * N + j];
            }
        }
    }
    
    // Gather: recolectar resultados parciales en el proceso maestro
    MPI_Gather(local_C, rows_per_process * N, MPI_DOUBLE,
               C, rows_per_process * N, MPI_DOUBLE,
               0, MPI_COMM_WORLD);
    
    // Sincronizar después del cálculo
    MPI_Barrier(MPI_COMM_WORLD);
    end_time = MPI_Wtime();
    total_time = end_time - start_time;
    
    // El proceso maestro imprime los resultados
    if (rank == 0) {
        double gflops = (2.0 * N * N * N) / (total_time * 1e9);
        printf("%.6f,%.2f\n", total_time, gflops);
    }
    
    // Liberar memoria
    free(local_A);
    free(local_C);
    free(B);
    if (rank == 0) {
        free(A);
        free(C);
    }
    
    MPI_Finalize();
    return 0;
}