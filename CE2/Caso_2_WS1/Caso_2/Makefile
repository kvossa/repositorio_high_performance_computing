
CC ?= gcc
CFLAGS ?= -O3 -march=native -ffast-math -fopenmp

all: mm_openmp_bt mm_openmp_blocked

mm_openmp_bt: mm_openmp_bt.c
	$(CC) $(CFLAGS) $< -o $@

mm_openmp_blocked: mm_openmp_blocked.c
	$(CC) $(CFLAGS) $< -o $@

clean:
	rm -f mm_openmp_bt mm_openmp_blocked
