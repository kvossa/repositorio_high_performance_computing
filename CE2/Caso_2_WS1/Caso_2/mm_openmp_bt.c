
// mm_openmp_bt.c — Multiplicación de matrices A x B con B transpuesta (BT) y OpenMP
// Autoría: adaptado para el curso a partir del trabajo previo del equipo (HPCG1).
// Compilar:  gcc -O3 -march=native -ffast-math -fopenmp mm_openmp_bt.c -o mm_openmp_bt
// Uso:       ./mm_openmp_bt <n> <threads>
// Notas:
//  - Datos en doble precisión (double). Cambiar a float si se requiere menor memoria.
//  - Alineación a 64B para mejor vectorización/uso de caché.
//  - Paralelismo por filas y vectorización del bucle interno con omp simd.
//  - Se imprime tiempo, GFLOPS y un checksum simple para evitar eliminación del cálculo.

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
    if (posix_memalign(&p, 64, nbytes)) return NULL; // alineado a 64B
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
    for (size_t i=0;i<n*n;i++) A[i] = (double)(rand()%100)/10.0; // 0..9.9
}

static inline void transpose(const double *B, double *BT, size_t n){
    #pragma omp parallel for schedule(static)
    for (size_t i=0;i<n;i++){
        for (size_t j=0;j<n;j++){
            BT[j*n + i] = B[i*n + j];
        }
    }
}

// A(nxn) * B(nxn)  usando B^T para localidad fila-fila en el bucle interno
static void mm_atimes_bt(const double *A, const double *BT, double *C, size_t n){
    #pragma omp parallel for schedule(static)
    for (size_t i=0;i<n;i++){
        double *Ci = &C[i*n];
        for (size_t k=0;k<n;k++){
            const double aik = A[i*n + k];
            const double *BTk = &BT[k*n];
            #pragma omp simd
            for (size_t j=0;j<n;j++){
                Ci[j] += aik * BTk[j];
            }
        }
    }
}

int main(int argc, char **argv){
    if (argc < 3){
        fprintf(stderr, "Uso: %s <n> <threads>\n", argv[0]);
        return 1;
    }
    size_t n = strtoull(argv[1], NULL, 10);
    int threads = atoi(argv[2]);

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
    mm_atimes_bt(A, BT, C, n);
    double t1 = now_s();

    double secs = t1 - t0;
    double secsT = tT1 - tT0;
    double flops = 2.0 * (double)n * (double)n * (double)n;
    double gflops = (flops / secs) / 1e9;

    printf("prog=mm_openmp_bt, n=%zu, threads=%d\n", n, threads);
    printf("Tiempo mult: %.6f s | GFLOPS: %.3f | Tiempo transpuesta: %.6f s\n",
           secs, gflops, secsT);

    volatile double sink = 0.0;
    for (size_t i=0;i<n*n;i++) sink += C[i];
    fprintf(stderr,"checksum=%.3f\n", sink);

    free(A); free(B); free(BT); free(C);
    return 0;
}
