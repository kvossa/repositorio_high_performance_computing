#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/wait.h>
#include <math.h>
#include "rng.h"
#include "timer.h"


static unsigned long long run_chunk(long long n, uint32_t seed, double L, double ell){
    rng32_t r; 
    rng32_seed(&r, seed);
    unsigned long long crosses=0ULL;
    for(long long i=0;i<n;i++){
        double x = rng32_next01(&r) * ell;
        double theta = rng32_next01(&r) * M_PI;
        double halfproj = 0.5 * L * sin(theta);
        if (x + halfproj > ell || x - halfproj < 0.0) crosses++;
    }
    return crosses;
}


int main(int argc, char** argv){
    long long N = (argc>1)? atoll(argv[1]) : 100000000LL;
    int P = (argc>2)? atoi(argv[2]) : 4;
    double L = (argc>3)? atof(argv[3]) : 0.5;
    double ell = (argc>4)? atof(argv[4]) : 1.0;
    uint32_t seed0 = (argc>5)? (uint32_t)atoi(argv[5]) : 12345u;


    int (*pipes)[2] = malloc(sizeof(int[2])*P);
    long long chunk = (N + P - 1)/P;
    double t0 = now_sec();
    for(int i=0;i<P;i++){
        pipe(pipes[i]);
        pid_t pid = fork();
        if(pid==0){
            close(pipes[i][0]);
            long long start=i*chunk, end=((i+1)*chunk>N?N:(i+1)*chunk);
            unsigned long long crosses = run_chunk(end-start, seed0 ^ (0x9E3779B9u*(i+1)), L, ell);
            write(pipes[i][1], &crosses, sizeof(crosses));
            close(pipes[i][1]);
            _exit(0);
        } else close(pipes[i][1]);
    }
    unsigned long long crosses=0ULL;
    for(int i=0;i<P;i++){
        unsigned long long v; read(pipes[i][0], &v, sizeof(v)); close(pipes[i][0]);
        crosses += v; 
        wait(NULL);
    }
    double t1 = now_sec(); 
    free(pipes);
    double p = (double)crosses / (double)N;
    double pi_est = (2.0*L)/(ell*p);
    printf("pi=%.9f\tN=%lld\tP=%d\tL=%.3f\tell=%.3f\tt=%.3fs\n", pi_est, N, P, L, ell, t1-t0);
return 0;
}

// correr esto:gcc -O3 -std=c11 needle_fork.c rng.c timer.c -lm 