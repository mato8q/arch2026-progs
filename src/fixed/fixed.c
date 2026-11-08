#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a ^= b;
        b = c;
        (*n)++;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return ((a ^ b) >> 1) + (a & b);
}
// Q11.20   bit: [1 sign][11 integer][20 fraction]
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    // upper 16 bits (h) + lower 16 bits (l) of a and b
    // a = ah × 2¹⁶ + al
    uint32_t a_l = ua & 0xFFFF;  // lower 16 bits (l)
    uint32_t a_h = ua >> 16;     // upper 16 bits (h)

    // b = bh × 2¹⁶ + bl
    uint32_t b_l = ub & 0xFFFF;  // lower 16 bits (l)
    uint32_t b_h = ub >> 16;     // upper 16 bits (h)

    // a × b = ah·bh × 2³²  +  (ah·bl + al·bh) × 2¹⁶  +  al·bl
    uint64_t c = ((uint64_t) (a_h * b_h) << 32) +
                 ((uint64_t) (a_h * b_l) << 16) +
                 ((uint64_t) (a_l * b_h) << 16) + ((uint64_t) (a_l * b_l));

    // signed fix: neg operand + 2^32
    if (a < 0)
        c -= (uint64_t) ub << 32;
    if (b < 0)
        c -= (uint64_t) ua << 32;
    int64_t c_signed = (int64_t) c;
    return (int32_t) ((c_signed + (1 << 19)) >> 20);
}
