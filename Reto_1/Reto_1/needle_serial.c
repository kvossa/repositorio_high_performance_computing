#include <stdio.h>
#include "rng.h"
#include "timer.h"
#include <stdlib.h>

#define _USE_MATH_DEFINES
#include <math.h>

int main(int argc, char** argv){
    long long N = (argc>1)? atoll(argv[1]) : 100000000LL;
    double L = (argc>2)? atof(argv[2]) : 0.5; // por defecto L = ell/2 con ell=1
    double ell = (argc>3)? atof(argv[3]) : 1.0;
    uint32_t seed = (argc>4)? (uint32_t)atoi(argv[4]) : 12345u;


    rng32_t rng; rng32_seed(&rng, seed);
    long long crosses = 0;
    double t0 = now_sec();
    for(long long i=0;i<N;i++){
        double x = rng32_next01(&rng) * ell; // x en [0, ell]
        double theta = rng32_next01(&rng) * M_PI; // [0, pi]
        double halfproj = 0.5 * L * sin(theta);
        if (x + halfproj > ell || x - halfproj < 0.0) crosses++;
    }
    double t1 = now_sec();
    double p = (double)crosses / (double)N;
    double pi_est = (2.0*L)/(ell*p); // de P = 2L/(pi*ell)
    printf("pi=%.9f\tN=%lld\tL=%.3f\tell=%.3f\tt=%.3fs\n", pi_est, N, L, ell, t1-t0);
    
    return 0;
}