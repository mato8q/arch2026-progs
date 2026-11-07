# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
# a = a0, b = a1, shift = t0
# t1 = a|b, t2 = temp.swap 
gcd_u32_asm:
    beq      a0, x0, .Lalt     # a=0 -> = b
    beq      a1, x0, .Lend     # b=0 -> = a
    addi     t0, x0, 0         # shift ct = 0

.Lboth:
    or       t1, a0, a1         # t1 = a | b
    andi     t1, t1, 1          # t1 = (a|b) & 1
    bne      t1, x0, .Lleft_chk # if (a|b) & 1 != 0, goto Lleft
    srli     a0, a0, 1          # a >>= 1
    srli     a1, a1, 1          # b >>= 1
    addi     t0, t0, 1          # shift++
    jal      x0, .Lboth

.Lleft_chk:                     #a even loop check
    andi    t1, a0, 1           # t1= a & 1
    bne     t1, x0, .Lright_chk # if (a & 1) != 0, goto Lright_chk
.Lleft:
    srli    a0, a0,1                  # a >>= 1
    andi    t1, a0, 1                  # t1 = a & 1
    beq     t1, x0, .Lleft           # if (a & 1) == 0, goto Lleft

.Lright_chk:
    andi    t1, a1, 1                  # t1 = b & 1
    bne     t1, x0, .Lorder       # if (b & 1) != 0, goto Lorder
.Lright:
    srli    a1, a1, 1                  # b >>= 1
    andi    t1, a1, 1                  # t1 = b & 1
    beq     t1, x0, .Lright           # if (b & 1) == 0, goto Lright

.Lorder:
    bgeu     a1, a0, .Lstep            # if (b>=a) goto Lstep
    sub      t2, a0, a1                # t2=a-b
    mv       a0, a1                     # a=b
    mv       a1, t2                     # b=t2
    jal      x0, .Lright                #a-b is even and nonzero: skip the checks

.Lstep:                                 #b -= a; b is now even
    sub      a1, a1, a0                # b -= a
    bne      a1, x0, .Lright           # if (b != 0) goto Lright
    sll     a0, a0, t0                # a <<= shift
    ret
.Lalt:
    addi     a0, a1,0           #return b
    ret

.Lend:
    ret

    .size   gcd_u32_asm, .-gcd_u32_asm
