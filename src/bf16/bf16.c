#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    // inf or NaN
    if (((f32bits >> 23) & 0xFF) == 0xFF)
        return (uint16_t) (f32bits >> 16);
    // round to nearest even
    f32bits += (f32bits >> 16 & 1) + 0x7FFF;
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    // 3 parts: sign, exponent, mantissa
    uint16_t sign = (a ^ b) & 0x8000;
    int32_t exp_a = (a >> 7) & 0xFF, exp_b = (b >> 7) & 0xFF;
    uint32_t mant_a = a & 0x7F, mant_b = b & 0x7F;

    // special case: zero, inf, NaN
    if (exp_a == 0xFF) {
        if (mant_a != 0)
            return a;  // NaN
        if (exp_b == 0 && mant_b == 0)
            return 0x7FC0;     // inf*0=NaN
        return sign | 0x7F80;  // inf
    }
    if (exp_b == 0xFF) {
        if (mant_b != 0)
            return b;  // NaN
        if (exp_a == 0 && mant_a == 0)
            return 0x7FC0;     // 0*inf=NaN
        return sign | 0x7F80;  // inf
    }
    if ((exp_a == 0 && mant_a == 0) || (exp_b == 0 && mant_b == 0))
        return sign;

    // return 1
    int32_t adj = 0;   // adjust excludes from exp
    if (exp_a == 0) {  // denorm a
        while (!(mant_a & 0x80)) {
            mant_a <<= 1;
            adj--;
        }
        exp_a = 1;
    } else {
        mant_a |= 0x80;
    }

    if (exp_b == 0) {  // denorm b
        while (!(mant_b & 0x80)) {
            mant_b <<= 1;
            adj--;
        }
        exp_b = 1;
    } else {
        mant_b |= 0x80;
    }

    uint32_t m = mant_a * mant_b;  // 8*8 bits <= 16 bits
    int32_t e = exp_a + exp_b - 127 + adj;
    if (m & 0x8000) {
        m = (m >> 8) & 0x7F;
        e++;
    } else {
        m = (m >> 7) & 0x7F;
    }

    if (e >= 0xFF)
        return sign | 0x7F80;  // too big -> inf
    if (e <= 0) {
        if (e < -6)
            return sign;  // too small =0
        m >>= (1 - e);    // become denorm
        e = 0;
    }
    return (uint16_t) (sign | (e << 7) | m);
}
uint16_t bf16_sqrt(uint16_t a)
{
    // √(m × 2^e) = √m × 2^(e/2)
    // if e is odd -> divides and leaves a remainder
    // sol: add 2 -> m*(2^3) = (2*m)*(2^2)
    uint32_t sign = (a >> 15) & 1;
    int32_t exp = (a >> 7) & 0xFF;
    uint32_t mant = a & 0x7F;

    // followed by header
    if (exp == 0xFF) {
        if (mant != 0)
            return a;  // return NaN
        if (sign)
            return 0x7FC0;  //-inf->NaN
        return a;           // return inf
    }
    if (exp == 0 && mant == 0)
        return 0;  //+-= -> +0
    if (sign)
        return 0x7FC0;  // neg -> NaN
    if (exp == 0)
        return 0;  // denorm

    // separated exp -> return  hidden 1 -> e odd
    int32_t e = exp - 127, new_exp;
    uint32_t m = mant | 0x80;
    if (e & 1) {
        m <<= 1;
        new_exp = ((e - 1) >> 1) + 127;
    } else {
        new_exp = (e >> 1) + 127;
    }

    // binary search
    uint32_t low = 90, high = 256, result = 128;
    while (low <= high) {  // quiz Part 7
        // B22 = 128, B23 = +, B24 = -
        uint32_t mid = (low + high) / 2;
        if (((mid * mid) / 128) <= m) {
            result = mid;   // mid fits-> remember it
            low = mid + 1;  // try higher
        } else {
            high = mid - 1;
        }  // mid too big-> try lower
    }

    // merge everything like a lego
    return (uint16_t) ((new_exp << 7) |
                       (result &
                        0x7F));  // 181 = 1011 0101 -> & 0x7F = 011 0101 = 53
}
