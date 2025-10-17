#define _GNU_SOURCE
#define _USE_MATH_DEFINES
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include "rng.h"
#include "timer.h"


#ifndef CACHELINE
#define CACHELINE 64
#endif


typedef struct {
    long long start, end;
    double L, ell;
    uint32_t seed;
    _Alignas(CACHELINE) unsigned long long crosses;
} task_t;


static void* worker(void* arg){
    task_t* t = (task_t*)arg;
    rng32_t r; 
    rng32_seed(&r, t->seed);
    unsigned long long local = 0ULL;
    for(long long i=t->start;i<t->end;i++){
        double x = rng32_next01(&r) * t->ell;
        double theta = rng32_next01(&r) * M_PI;
        double halfproj = 0.5 * t->L * sin(theta);
        if (x + halfproj > t->ell || x - halfproj < 0.0) local++;
    }
    t->crosses = local; return NULL;
}


int main(int argc, char** argv){
    long long N = (argc>1)? atoll(argv[1]) : 100000000LL;
    int T = (argc>2)? atoi(argv[2]) : 4;
    double L = (argc>3)? atof(argv[3]) : 0.5;
    double ell = (argc>4)? atof(argv[4]) : 1.0;
    uint32_t seed0 = (argc>5)? (uint32_t)atoi(argv[5]) : 12345u;


    pthread_t* th = calloc(T, sizeof(*th));
    task_t* tasks = aligned_alloc(CACHELINE, T*sizeof(*tasks));


    long long chunk = (N + T - 1)/T;
    double t0 = now_sec();
    for(int i=0;i<T;i++){
        tasks[i] = (task_t){ .start=i*chunk, .end=((i+1)*chunk>N?N:(i+1)*chunk), .L=L, .ell=ell,
        .seed=(seed0 ^ (0x9E3779B9u*(i+1))), .crosses=0ULL };
        pthread_create(&th[i], NULL, worker, &tasks[i]);
    }
    unsigned long long crosses=0ULL;
    for(int i=0;i<T;i++){ 
        pthread_join(th[i], NULL); crosses += tasks[i].crosses; 
    }
    double t1 = now_sec();
    double p = (double)crosses / (double)N;
    double pi_est = (2.0*L)/(ell*p);
    printf("pi=%.9f\tN=%lld\tT=%d\tL=%.3f\tell=%.3f\tt=%.3fs\n", pi_est, N, T, L, ell, t1-t0);
    free(th); 
    free(tasks);
    return 0;
}