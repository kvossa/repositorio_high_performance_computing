#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include "rng.h"
#include "timer.h"


int main(int argc, char** argv){
    long long N = (argc>1)? atoll(argv[1]) : 100000000LL; // 1e8 por defecto
    uint32_t seed = (argc>2)? (uint32_t)atoi(argv[2]) : 12345u;
    rng32_t rng; rng32_seed(&rng, seed);


    long long inside = 0;
    double t0 = now_sec();
    for(long long i=0;i<N;i++){
        double x = rng32_next01(&rng);
        double y = rng32_next01(&rng);
        if (x*x + y*y <= 1.0) inside++;
    }
    double t1 = now_sec();
    double pi = 4.0 * (double)inside / (double)N;
    printf("pi=%.9f\tN=%lld\tt=%.3fs\n", pi, N, t1-t0);
    return 0;
}