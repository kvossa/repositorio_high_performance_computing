#ifndef RNG_H
#define RNG_H
#include <stdint.h>


typedef struct { uint32_t s; } rng32_t;
static inline void rng32_seed(rng32_t* r, uint32_t seed) { 
    r->s = seed ? seed : 0x9E3779B9u; 
}
static inline uint32_t rng32_next(rng32_t* r) {
    uint32_t x = r->s;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5; r->s = x; return x;
}
static inline double rng32_next01(rng32_t* r) {
    // 53-bit mantissa approx: usar 24 bits es suficiente p/ [0,1)
    return (rng32_next(r) >> 8) * (1.0/16777216.0);
}
#endif