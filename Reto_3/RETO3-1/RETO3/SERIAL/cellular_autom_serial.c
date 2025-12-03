#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Uso: %s <number_of_cells> <iterations>\n", argv[0]);
        return 1;
    }

    int N = atoi(argv[1]);
    int iterations = atoi(argv[2]);

    if (N <= 0 || iterations <= 0) {
        fprintf(stderr, "Error: N e iterations deben ser positivos.\n");
        return 1;
    }

    int total_cars = 0;

    // Usamos celdas fantasma: índices reales 1..N, 0 y N+1 como halos
    int *road = (int *)malloc((N + 2) * sizeof(int));
    int *new_road = (int *)malloc((N + 2) * sizeof(int));

    if (!road || !new_road) {
        fprintf(stderr, "Error de memoria.\n");
        free(road);
        free(new_road);
        return 1;
    }

    srand((unsigned int)time(NULL));

    // Inicializar carretera
    for (int i = 1; i <= N; i++) {
        road[i] = rand() % 2;
        total_cars += road[i];
    }

    // Si no hay coches, evitar división por cero después
    if (total_cars == 0) {
        printf("0, 0.0, 0.0\n");
        free(road);
        free(new_road);
        return 0;
    }

    // Condiciones periódicas iniciales
    road[0] = road[N];
    road[N + 1] = road[1];

    long long global_moves = 0;
    clock_t start_time = clock();

    // Bucle de simulación
    for (int iter = 0; iter < iterations; iter++) {
        int local_moves = 0;

        // Actualizar halos para este paso
        road[0] = road[N];
        road[N + 1] = road[1];

        // Aplicar la regla local (tipo Rule-184)
        for (int i = 1; i <= N; i++) {
            int L = road[i - 1];
            int C = road[i];
            int R = road[i + 1];

            // Regla del autómata:
            // C' = 1 si (L=1,C=0) o (C=1,R=1); si no, 0
            if ((L == 1 && C == 0) || (C == 1 && R == 1)) {
                new_road[i] = 1;
            } else {
                new_road[i] = 0;
            }

            // Conteo de coches que se mueven: C=1 y R=0
            if (C == 1 && R == 0) {
                local_moves++;
            }
        }

        global_moves += local_moves;

        // Intercambiar buffers sin hacer malloc/free
        int *tmp = road;
        road = new_road;
        new_road = tmp;
    }

    clock_t end_time = clock();
    double elapsed_time = (double)(end_time - start_time) / CLOCKS_PER_SEC;
    double average_velocity = (double)global_moves / (iterations * total_cars);

    printf("%lld, %f, %f\n", global_moves, elapsed_time, average_velocity);

    free(road);
    free(new_road);
    return 0;
}
