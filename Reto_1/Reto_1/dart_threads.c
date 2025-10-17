#define _GNU_SOURCE
#define _USE_MATH_DEFINES
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <sched.h>
#include "rng.h"
#include "timer.h"


#ifndef CACHELINE
#define CACHELINE 64
#endif


typedef struct {
    long long start, end;
    uint32_t seed;
    _Alignas(CACHELINE) unsigned long long inside;
} task_t;


static void* worker(void* arg){
    task_t* t = (task_t*)arg;
    rng32_t r; rng32_seed(&r, t->seed);
    unsigned long long local = 0ULL;
    for(long long i=t->start;i<t->end;i++){
    double x = rng32_next01(&r);
    double y = rng32_next01(&r);
    local += (x*x + y*y <= 1.0);
    }
    t->inside = local;
    return NULL;
}


int main(int argc, char** argv){
    long long N = (argc>1)? atoll(argv[1]) : 100000000LL;
    int T = (argc>2)? atoi(argv[2]) : 4;
    uint32_t seed0 = (argc>3)? (uint32_t)atoi(argv[3]) : 12345u;


    pthread_t* th = calloc(T, sizeof(*th));
    task_t* tasks = aligned_alloc(CACHELINE, T*sizeof(*tasks));


    long long chunk = (N + T - 1)/T;
    double t0 = now_sec();
    for(int i=0;i<T;i++){
        tasks[i].start = i*chunk;
        long long end = (i+1)*chunk; if (end>N) end=N; tasks[i].end=end;
        tasks[i].seed = seed0 ^ (0x9E3779B9u * (i+1));
        tasks[i].inside = 0ULL;
        pthread_create(&th[i], NULL, worker, &tasks[i]);
    }
    unsigned long long inside=0ULL;
    for(int i=0;i<T;i++){ 
        pthread_join(th[i], NULL); inside += tasks[i].inside; 
    }
    double t1 = now_sec();
    double pi = 4.0 * (double)inside / (double)N;
    printf("pi=%.9f\tN=%lld\tT=%d\tt=%.3fs\n", pi, N, T, t1-t0);
    free(th); free(tasks);
    return 0;
}