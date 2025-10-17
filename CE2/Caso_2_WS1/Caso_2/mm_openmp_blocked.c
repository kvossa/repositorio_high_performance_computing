
// mm_openmp_blocked.c — Multiplicación de matrices con bloqueo (tiling) y OpenMP
// Autoría: adaptado para el curso a partir del trabajo previo del equipo (HPCG1).
// Compilar:  gcc -O3 -march=native -ffast-math -fopenmp mm_openmp_blocked.c -o mm_openmp_blocked
// Uso:       ./mm_openmp_blocked <n> <threads> <block_size>
// Notas:
//  - Se usa B transpuesta (BT) y bloqueo en i,j,k para mejorar localidad de caché.
//  - Se paraleliza por bloques (i0,j0) con collapse(2).
//  - Datos en double; considere float para matrices muy grandes si falta RAM.

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <omp.h>

static inline double now_s(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + 1e-9*ts.tv_nsec;
}

static inline void *xaligned_alloc(size_t nbytes){
    void *p = NULL;
    if (posix_memalign(&p, 64, nbytes)) return NULL;
    return p;
}

static inline double *alloc_mat(size_t n, int zero){
    double *m = (double*)xaligned_alloc(n*n*sizeof(double));
    if (!m) return NULL;
    if (zero) memset(m, 0, n*n*sizeof(double));
    return m;
}

static inline void fill_rand(double *A, size_t n, unsigned seed){
    srand(seed);
    for (size_t i=0;i<n*n;i++) A[i] = (double)(rand()%100)/10.0;
}

static inline void transpose(const double *B, double *BT, size_t n){
    #pragma omp parallel for schedule(static)
    for (size_t i=0;i<n;i++){
        for (size_t j=0;j<n;j++){
            BT[j*n + i] = B[i*n + j];
        }
    }
}

static void mm_blocked(const double *A, const double *BT, double *C, size_t n, size_t bs){
    #pragma omp parallel for collapse(2) schedule(static)
    for (size_t i0=0;i0<n;i0+=bs){
        for (size_t j0=0;j0<n;j0+=bs){
            for (size_t k0=0;k0<n;k0+=bs){
                size_t i_max = (i0+bs<n)? i0+bs : n;
                size_t j_max = (j0+bs<n)? j0+bs : n;
                size_t k_max = (k0+bs<n)? k0+bs : n;
                for (size_t i=i0;i<i_max;i++){
                    double *Ci = &C[i*n + j0];
                    for (size_t k=k0;k<k_max;k++){
                        const double aik = A[i*n + k];
                        const double *BTk = &BT[k*n + j0];
                        #pragma omp simd
                        for (size_t j=0;j<j_max-j0;j++){
                            Ci[j] += aik * BTk[j];
                        }
                    }
                }
            }
        }
    }
}

int main(int argc, char **argv){
    if (argc < 4){
        fprintf(stderr, "Uso: %s <n> <threads> <block_size>\n", argv[0]);
        return 1;
    }
    size_t n = strtoull(argv[1], NULL, 10);
    int threads = atoi(argv[2]);
    size_t bs = strtoull(argv[3], NULL, 10);
    if (bs==0){ fprintf(stderr,"block_size debe ser > 0\n"); return 1; }

    omp_set_num_threads(threads);
    omp_set_dynamic(0);

    double *A = alloc_mat(n, 0);
    double *B = alloc_mat(n, 0);
    double *BT = alloc_mat(n, 0);
    double *C = alloc_mat(n, 1);
    if(!A||!B||!BT||!C){
        fprintf(stderr,"Fallo de memoria (n=%zu)\n", n);
        return 2;
    }

    fill_rand(A,n,1234); fill_rand(B,n,5678);

    double tT0 = now_s();
    transpose(B, BT, n);
    double tT1 = now_s();

    double t0 = now_s();
    mm_blocked(A, BT, C, n, bs);
    double t1 = now_s();

    double secs = t1 - t0;
    double secsT = tT1 - tT0;
    double flops = 2.0 * (double)n * (double)n * (double)n;
    double gflops = (flops / secs) / 1e9;

    printf("prog=mm_openmp_blocked, n=%zu, threads=%d, bs=%zu\n", n, threads, bs);
    printf("Tiempo mult: %.6f s | GFLOPS: %.3f | Tiempo transpuesta: %.6f s\n",
           secs, gflops, secsT);

    volatile double sink = 0.0;
    for (size_t i=0;i<n*n;i++) sink += C[i];
    fprintf(stderr,"checksum=%.3f\n", sink);

    free(A); free(B); free(BT); free(C);
    return 0;
}
