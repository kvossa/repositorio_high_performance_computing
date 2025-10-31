// dart_omp.c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <omp.h>
#include "rng.h"
#include "timer.h"

int main(int argc, char** argv) {
    // N = número de puntos
    long long N = (argc > 1) ? atoll(argv[1]) : 100000000LL;
    // T = número de hilos
    int T = (argc > 2) ? atoi(argv[2]) : 4;
    // semilla base
    uint32_t seed0 = (argc > 3) ? (uint32_t)atoi(argv[3]) : 12345u;

    double t0 = now_sec();
    unsigned long long inside = 0ULL;

    #pragma omp parallel num_threads(T) reduction(+:inside)
    {
        int tid = omp_get_thread_num();
        // semilla distinta por hilo
        uint32_t myseed = seed0 ^ (0x9E3779B9u * (tid + 1));
        rng32_t rng;
        rng32_seed(&rng, myseed);

        #pragma omp for schedule(static)
        for (long long i = 0; i < N; i++) {
            double x = rng32_next01(&rng);
            double y = rng32_next01(&rng);
            if (x * x + y * y <= 1.0)
                inside++;
        }
    }

    double t1 = now_sec();
    double pi = 4.0 * (double)inside / (double)N;
    printf("pi=%.9f\tN=%lld\tT=%d\tt=%.3fs\n", pi, N, T, t1 - t0);
    return 0;
}
