// needle_omp.c
#define _GNU_SOURCE
#define _USE_MATH_DEFINES
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <omp.h>
#include "rng.h"
#include "timer.h"

int main(int argc, char** argv) {
    // N = número de lanzamientos de aguja
    long long N    = (argc > 1) ? atoll(argv[1]) : 100000000LL;
    // T = hilos
    int T          = (argc > 2) ? atoi(argv[2]) : 4;
    // longitud de la aguja
    double L       = (argc > 3) ? atof(argv[3]) : 0.5;
    // distancia entre líneas
    double ell     = (argc > 4) ? atof(argv[4]) : 1.0;
    // semilla base
    uint32_t seed0 = (argc > 5) ? (uint32_t)atoi(argv[5]) : 12345u;

    double t0 = now_sec();
    unsigned long long crosses = 0ULL;

    #pragma omp parallel num_threads(T) reduction(+:crosses)
    {
        int tid = omp_get_thread_num();
        uint32_t myseed = seed0 ^ (0x9E3779B9u * (tid + 1));
        rng32_t rng;
        rng32_seed(&rng, myseed);

        #pragma omp for schedule(static)
        for (long long i = 0; i < N; i++) {
            // x: posición de la mitad de la aguja respecto a una línea
            double x     = rng32_next01(&rng) * ell;
            // theta: ángulo de la aguja
            double theta = rng32_next01(&rng) * M_PI;
            // proyección de la mitad de la aguja
            double halfproj = 0.5 * L * sin(theta);

            if (x + halfproj > ell || x - halfproj < 0.0)
                crosses++;
        }
    }

    double t1 = now_sec();
    double p = (double)crosses / (double)N;
    double pi_est = (2.0 * L) / (ell * p);
    printf("pi=%.9f\tN=%lld\tT=%d\tL=%.3f\tell=%.3f\tt=%.3fs\n",
           pi_est, N, T, L, ell, t1 - t0);
    return 0;
}
