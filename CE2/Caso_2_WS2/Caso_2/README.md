
# Matmul OpenMP (BT y Bloques)

## Compilación
```bash
make
```

## Ejemplos rápidos
```bash
# Variante A x BT
./mm_openmp_bt 1024 8

# Variante bloqueada (tiling)
./mm_openmp_blocked 2048 8 128
```

## Benchmark automatizado
```bash
chmod +x run_bench.sh
# Variables opcionales: SIZES, THREADS, BLOCK_SIZE, REPS, OUT
SIZES="512 1024 1536 2048" THREADS="1 2 4 8 16" BLOCK_SIZE=128 REPS=3 ./run_bench.sh
# Ver resultados
column -s, -t results.csv | less -S
```

## Sugerencias
- Ajustar `BLOCK_SIZE` según caché L2/L3 de la máquina (64–256 suele ir bien).
- Para matrices muy grandes, considerar `float` en lugar de `double`.
- Afinidad OpenMP recomendada:
  ```bash
  export OMP_PLACES=cores
  export OMP_PROC_BIND=close
  export OMP_DYNAMIC=false
  ```
