#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/wait.h>
#include <math.h>
#include "rng.h"
#include "timer.h"


static unsigned long long run_chunk(long long n, uint32_t seed){
    rng32_t r; rng32_seed(&r, seed);
    unsigned long long inside=0ULL;
    for(long long i=0;i<n;i++){
        double x=rng32_next01(&r), y=rng32_next01(&r);
        inside += (x*x + y*y <= 1.0);
    }
    return inside;
}


int main(int argc, char** argv){
    long long N = (argc>1)? atoll(argv[1]) : 100000000LL;
    int P = (argc>2)? atoi(argv[2]) : 4;
    uint32_t seed0 = (argc>3)? (uint32_t)atoi(argv[3]) : 12345u;


    int (*pipes)[2] = malloc(sizeof(int[2])*P);
    long long chunk = (N + P - 1)/P;
    double t0 = now_sec();
    for(int i=0;i<P;i++){
    pipe(pipes[i]);
    pid_t pid = fork();
    if(pid==0){ // child
        close(pipes[i][0]);
        long long start=i*chunk, end=((i+1)*chunk>N?N:(i+1)*chunk);
        unsigned long long inside = run_chunk(end-start, seed0 ^ (0x9E3779B9u*(i+1)));
        write(pipes[i][1], &inside, sizeof(inside));
        close(pipes[i][1]);
        _exit(0);
    } else {
        close(pipes[i][1]);
    }
    }
    unsigned long long inside=0ULL;
    for(int i=0;i<P;i++){
        unsigned long long v; read(pipes[i][0], &v, sizeof(v)); close(pipes[i][0]);
        inside += v; wait(NULL);
    }
    double t1 = now_sec(); free(pipes);
    double pi = 4.0 * (double)inside / (double)N;
    printf("pi=%.9f\tN=%lld\tP=%d\tt=%.3fs\n", pi, N, P, t1-t0);
    return 0;
}