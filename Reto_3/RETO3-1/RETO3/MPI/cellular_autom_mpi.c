#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <mpi.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);

    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc < 3) {
        if (rank == 0) {
            fprintf(stderr, "Uso: %s <number_of_cells> <iterations>\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    int N = atoi(argv[1]);
    int iterations = atoi(argv[2]);

    if (N <= 0 || iterations <= 0) {
        if (rank == 0) {
            fprintf(stderr, "Error: N e iterations deben ser positivos.\n");
        }
        MPI_Finalize();
        return 1;
    }

    // Para simplificar asumimos N divisible por size
    if (N % size != 0) {
        if (rank == 0) {
            fprintf(stderr, "Error: N (%d) debe ser divisible por el número de procesos (%d).\n", N, size);
        }
        MPI_Finalize();
        return 1;
    }

    int local_N = N / size;

    // Arrays locales con halos: 0 y local_N+1 son fantasma
    int *local_road = (int *)malloc((local_N + 2) * sizeof(int));
    int *new_local_road = (int *)malloc((local_N + 2) * sizeof(int));

    if (!local_road || !new_local_road) {
        fprintf(stderr, "Rank %d: error de memoria.\n", rank);
        free(local_road);
        free(new_local_road);
        MPI_Finalize();
        return 1;
    }

    int *global_road = NULL;

    if (rank == 0) {
        // Carretera global sin halos, índices 0..N-1
        global_road = (int *)malloc(N * sizeof(int));
        if (!global_road) {
            fprintf(stderr, "Rank 0: error de memoria para global_road.\n");
            free(local_road);
            free(new_local_road);
            MPI_Finalize();
            return 1;
        }

        srand((unsigned int)time(NULL));
        for (int i = 0; i < N; i++) {
            global_road[i] = rand() % 2;
        }
    }

    // Distribuir el tramo de carretera a cada proceso (parte "real": 1..local_N)
    MPI_Scatter(global_road, local_N, MPI_INT,
                &local_road[1], local_N, MPI_INT,
                0, MPI_COMM_WORLD);

    if (rank == 0) {
        free(global_road);
    }

    // Contar coches locales y reducir a total global
    int total_cars_local = 0;
    for (int i = 1; i <= local_N; i++) {
        total_cars_local += local_road[i];
    }

    int total_cars_global = 0;
    MPI_Allreduce(&total_cars_local, &total_cars_global, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);

    if (total_cars_global == 0) {
        if (rank == 0) {
            printf("0, 0.0, 0.0\n");
        }
        free(local_road);
        free(new_local_road);
        MPI_Finalize();
        return 0;
    }

    int left_neighbor  = (rank == 0) ? size - 1 : rank - 1;
    int right_neighbor = (rank == size - 1) ? 0 : rank + 1;

    long long global_moves = 0;

    double start_time = MPI_Wtime();

    for (int iter = 0; iter < iterations; iter++) {
        int local_moves = 0;

        // Intercambio de halos:
        // - El primer elemento real (1) se envía al vecino izquierdo
        //   y recibimos en local_road[local_N+1] el primero del vecino derecho
        MPI_Sendrecv(&local_road[1], 1, MPI_INT, left_neighbor, 0,
                     &local_road[local_N + 1], 1, MPI_INT, right_neighbor, 0,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        // - El último elemento real (local_N) se envía al vecino derecho
        //   y recibimos en local_road[0] el último del vecino izquierdo
        MPI_Sendrecv(&local_road[local_N], 1, MPI_INT, right_neighbor, 1,
                     &local_road[0], 1, MPI_INT, left_neighbor, 1,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        // Aplicamos la misma regla que en la versión serial (Rule-184-like)
        for (int i = 1; i <= local_N; i++) {
            int L = local_road[i - 1];
            int C = local_road[i];
            int R = local_road[i + 1];

            // C' = 1 si (L=1,C=0) o (C=1,R=1), si no 0
            if ((L == 1 && C == 0) || (C == 1 && R == 1)) {
                new_local_road[i] = 1;
            } else {
                new_local_road[i] = 0;
            }

            // Conteo de coches que se mueven (C=1, R=0)
            if (C == 1 && R == 0) {
                local_moves++;
            }
        }

        // Intercambio de buffers
        int *tmp = local_road;
        local_road = new_local_road;
        new_local_road = tmp;

        // Reducimos el número de movimientos de esta iteración
        int moves_this_iter = 0;
        MPI_Allreduce(&local_moves, &moves_this_iter, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);

        if (rank == 0) {
            global_moves += moves_this_iter;
        }
    }

    double end_time = MPI_Wtime();
    double elapsed_time = end_time - start_time;

    if (rank == 0) {
        double average_velocity = (double)global_moves / (iterations * total_cars_global);
        printf("%lld, %f, %f\n", global_moves, elapsed_time, average_velocity);
    }

    free(local_road);
    free(new_local_road);

    MPI_Finalize();
    return 0;
}
