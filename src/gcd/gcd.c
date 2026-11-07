#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;
    uint32_t shift = 0;  // t0

    while (((a | b) & 1) == 0) {  // pa_both: a and b are both even
        a >>= 1;                  // halve a and b
        b >>= 1;
        shift++;  // count the shared two
    }
    while ((a & 1) == 0) {  // pa_left: a is even
        a >>= 1;            // a/2
    }
    do {
        while ((b & 1) == 0) {  // pa_right: b is even
            b >>= 1;            // b/2
        }
        if (b < a) {            // pa_order: b < a
            uint32_t temp = a;  // swap a and b
            a = b;
            b = temp;
        }
        b -= a;
    } while (b != 0);

    return a << shift;
}
