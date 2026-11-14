# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

#1) t0 =(a0>>23)&0xFF : srli, andi
#2) t0 == 0xFF -> .Lf32_shift : beq w/ t1
#3) t2 = (a0>>16)&1 : srli, andi
#4) t3 = 0x7FFF : lui+ addi
    #lui t3,0x8
    #addi t3, t3, -1
#5) a0 = a0+t2+t3 : add, add
#6) a0=a0>>16 : srli

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    #t0 = exp = (a0>>23) &0xFF
    srli t0, a0, 23     # t0 = exp = a0>>23
    andi t0, t0,0xFF    #t0&0xFF

    #ifexp == 0xFF(Inf/NaN) -> skip round to .Lf32_shift  
    addi t1, x0, 0xFF
    beq t0, t1, .Lf32_shift 

    #t2= 16 bits = (a0>>16) &1
    srli t2, a0, 16     #t2 = (a0>>16)
    andi t2, t2, 1      #t2&1

    #t3 = 0x7FFF : lui+ addi
    lui t3, 0x8
    addi t3, t3, -1

    #a0+=(t2+t3)
    add t2, t2, t3
    add a0, a0, t2

.Lf32_shift:
    #a0>>=16
    srli a0, a0, 16
    jalr x0, 0(ra)    

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor t0, a0, a1
    lui t6, 0x8         #t6= 0x8000
    and t0, t0, t6      #sign =(a^b)&0x8000
    srli t1, a0, 7      
    andi t1, t1, 0xFF    #exp_a
    srli t2, a1, 7
    andi t2, t2, 0xFF   #exp_b
    andi t3, a0, 0x7F   #mant_a
    andi t4, a1, 0x7F   #mant_b

    #inf/NaN jump and 0
    addi t6, x0, 0xFF
    beq t1, t6, .Lm_a_spc   #a=inf or NaN
    beq t2, t6, .Lm_b_spc   #b=inf or NaN
    slli a2, a0, 17         #keep only exp and mant:0 if a is +0 or -0
    beq a2, x0, .Lm_zero
    slli a2, a1, 17         #exp == 0 && mant == 0
    beq a2, x0, .Lm_zero
    bne t1, x0, .Lm_a_norm # if t1!=x0. go to Lm_a_norm
    addi t1, x0, 1          # denorm a: exp=1  
    
.Lm_a_sub:
    slli t3, t3, 1
    addi t1, t1, -1         #adj-- folded into exp
    andi a2, t3, 0x80
    beq a2, x0, .Lm_a_sub
    jal x0, .Lm_b

.Lm_a_norm:
    ori t3, t3, 0x80      #restore hidden one

.Lm_b:
    bne t2, x0, .Lm_b_norm
    addi t2, x0, 1          # t2 =x0 + 1

.Lm_b_sub:
    slli t4, t4, 1
    addi t2, t2, -1
    andi a2, t4, 0x80
    beq  a2, x0, .Lm_b_sub
    jal x0, .Lm_mul

.Lm_b_norm:
    ori t4, t4, 0x80

.Lm_mul:
    addi a3, x0, 0      #m=0

.Lm_mloop:
    andi    a2, t4, 1
    beq     a2, x0, .Lm_mskip
    add a3, a3, t3      #m+=mant_a
    

.Lm_mskip:
    slli    t3, t3, 1
    srli    t4, t4, 1
    bne     t4, x0, .Lm_mloop # if t4 != 0 then .Lm_mloop
    #exp and decrease to 7 fract
    add     t1, t1, t2
    addi    t1, t1, -127       #e= exp_a+exp_b -127
    srli    a2, a3, 15
    beq     a2, x0, .Lm_r7      # if a2 == x0 then .Lm_r7 
    srli    a3, a3, 8    
    addi    t1, t1, 1           # t1 = t1 + 1
    jal     x0 , .Lm_rdone      #jump without saving (x0 discards ra)

.Lm_r7: 
    srli    a3, a3, 7

.Lm_rdone:
    andi    a3, a3, 0x7F    #truncate to 7 fraction bits
    addi    t6, x0, 0xFF
    bge     t1, t6, .Lm_inf     # e>= 255 if t1 >= t6 then .Lm_inf
    blt     x0, t1, .Lm_pack    #e>0 = normal result
    addi    t6, x0, -6           # t6 = x0 + -6    
    blt     t1, t6, .Lm_zero    #e<-6 (zero
    sub     t6, x0, t1          # t6 = x0 - t1
    addi    t6, t6, 1              # t6 = 1-e    
    srl     a3, a3, t6          #denorm
    addi    t1, x0, 0   
.Lm_pack:
    slli  t1, t1, 7
    or    a0, t0, t1
    or    a0, a0, a3
    jalr  x0, 0(ra)
    
.Lm_zero:
    addi  a0, t0, 0              # signed zero
    jalr  x0, 0(ra)
.Lm_inf:
    lui   t6, 0x8
    addi  t6, t6, -128           # t6 = 0x7F80
    or    a0, t0, t6
    jalr  x0, 0(ra)
.Lm_a_spc:
    bne   t3, x0, .Lm_ret        # a is NaN: return a
    slli  a2, a1, 17
    beq   a2, x0, .Lm_nan        # Inf times zero
    jal   x0, .Lm_inf
.Lm_b_spc:
    bne   t4, x0, .Lm_ret_b      # b is NaN: return b
    slli  a2, a0, 17
    beq   a2, x0, .Lm_nan
    jal   x0, .Lm_inf
.Lm_ret_b:
    addi  a0, a1, 0
.Lm_ret:
    jalr  x0, 0(ra)
.Lm_nan:
    lui   a0, 0x8
    addi  a0, a0, -64            # 0x7FC0
    jalr  x0, 0(ra)
    

    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
# i used digit_by_digit
#N   = (m << 7) + 127
#res = 0
#bit = 1 << 14         
#do again till bit = 0:
#    t = res + bit
#    res = res >> 1
#    iff N >= t:
#        N   = N − t
#        res = res + bit
#    bit = bit >> 2
#output = res

#  t1 = exp, t2 = mant
    srli    t1, a0, 7
    andi    t1, t1, 0xFF
    andi    t2, a0, 0x7F
    addi    t6, x0, 0xFF # t6 = x0 + 0xFF
    
    bne     t1, t6, .Ls_fin       # not Inf/NaN
    bne     t2, x0, .Ls_ret       # NaN: return a
    srli    t6, a0, 15
    bne     t6, x0, .Ls_nan       # -Inf: quiet NaN
.Ls_ret:
    jalr    x0, 0(ra)             # +Inf or NaN: return a unchanged
.Ls_fin:
    slli    t6, a0, 17
    beq     t6, x0, .Ls_zero      # +0 or -0: +0
    srli    t6, a0, 15
    bne     t6, x0, .Ls_nan       # negative: quiet NaN
    beq     t1, x0, .Ls_zero      # denormal: +0
    addi    t1, t1, -127          # e = exp - 127
    ori     t2, t2, 0x80          # m = mant | hidden one
    andi    t6, t1, 1
    beq     t6, x0, .Ls_even
    slli    t2, t2, 1             # odd e: m <<= 1
.Ls_even:
    srai    t1, t1, 1             # floor(e / 2), same for odd and even e
    addi    t1, t1, 127           # new_exp
    slli    t2, t2, 7
    addi    t2, t2, 127           # N = 128 * m + 127
    addi    t3, x0, 0             # res = 0
    lui     t4, 0x4               # bit = 1 << 14
.Ls_loop:
    add     t5, t3, t4            # t = res + bit
    srli    t3, t3, 1             # res >>= 1
    bltu    t2, t5, .Ls_skip      # N < t: this bit is 0
    sub     t2, t2, t5            # N -= t
    add     t3, t3, t4            # res += bit
.Ls_skip:
    srli    t4, t4, 2             # bit >>= 2
    bne     t4, x0, .Ls_loop
    andi    t3, t3, 0x7F          # drop the hidden one
    slli    t1, t1, 7
    or      a0, t1, t3
    jalr    x0, 0(ra)
.Ls_zero:
    addi    a0, x0, 0
    jalr    x0, 0(ra)
.Ls_nan:
    lui     a0, 0x8
    addi    a0, a0, -64           # 0x7FC0
    jalr    x0, 0(ra)

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
