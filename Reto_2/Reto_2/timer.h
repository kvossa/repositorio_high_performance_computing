#ifndef TIMER_H
#define TIMER_H
#include <time.h>

static inline double now_sec(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec*1e-9;
}
#endif