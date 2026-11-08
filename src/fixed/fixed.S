# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

# t0 = pass count, a0 = a, a1= b
#t1 = carry, a2 = n
    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    addi    t0, x0, 0           #n=0
    beq     a1, x0, .op1end     #if (b == 0) goto op1end


.op1Loop:
    and     t1, a0, a1          #t1=a0&a1
    slli    t1, t1, 1           #t1<<=1
    xor     a0, a0, a1          #a0=a0^a
    addi    a1, t1, 0           #b=c
    addi    t0, t0, 1           #n++
    bne     a1, x0, .op1Loop     #if (a1 != 0) repeat it again
.op1end:
    sw      t0, 0(a2)             #store *n =n
    jalr    x0, 0(ra)             #return a0 

    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1          #a0=a0-a1
    jalr    x0, 0(ra)
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    xor     t0, a0, a1          #t0=a0^a1
    srli    t0, t0, 1           #t0>>=1
    and     a0, a0, a1          #t1=a0&a1
    add     a0, a0, t0          #a0=t1+t0
    jalr    x0, 0(ra)

    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm: # M_low = a = t0, M_high = 0 = t1
# Q = b = t2, P_low = 0 = a2, P_high = 0 = a3
# t2=Q, P: a2 =lower bits, a3 = upper bits
# t3=carry 
    addi    t0, a0, 0           #t0=0= M_low
    addi    t1, x0, 0           #t1=0= M_high
    addi    t2, a1, 0           #t2=Q=b
    addi    a2, x0, 0           #a2=P_l=0
    addi    a3, x0, 0           #a3=P_h=0
    beq     t2, x0, .qmend   #if (Q == 0) goto q_mul_end

.qmloop: #t3 = บิตขวาสุดของ Q ถ้าเป็น 0 ข้ามไป qmskip
# P=P+M (4ins)
    andi    t3, t2, 1           #t3 = Q & 1
    beq     t3, x0, .qmskip     #if (Q & 1) == 0 goto qmskip
    add     a2, a2, t0          #P_low+=M_low
    sltu    t3, a2, t0          #t3 = (P_low < M_low) ? 1 : 0
    add     a3, a3, t1          #P_high+=M_high
    add     a3, a3, t3          #P_high+=carry

.qmskip:
#M=M<<1 (4ins)
    srli    t3, t0, 31          #t3 = M_low>>31 (บิตบนสุดของ M_low 0 หรือ 1)
    slli    t1, t1, 1           #M_high<<= 1 (บิต0ว่าง)
    or      t1, t1, t3          #t1=M_high|M_low>>31
    slli    t0, t0, 1           #M_low<<=1
#Q=Q>>1
    srli    t2, t2, 1           #Q>>=1
    bne     t2, x0, .qmloop     #if (Q != 0) goto qmloop
.qmend:
    bge     a0, x0, .qmapos        #if (a >= 0) goto qmapos
    sub     a3, a3, a1             #P_h-=b
.qmapos:
    bge     a1, x0, .qmbpos        #if (b >= 0) goto qmbpos 
    sub     a3, a3, a0             #P_h-=a
.qmbpos: #round +2^19 and shift>>20
    lui    t3, 0x80            #t3=2^19
    add    a2, a2, t3             #P_l+=2^19
    sltu   t3, a2, t3             #t3 = (P_l < 2^19) ? 1 : 0
    add    a3, a3, t3             #P_h+=carry

    #shift>>20
    srli   a2, a2, 20             #P_l>>=20
    slli   a3, a3, 12             #P_h<<=12
    or     a0, a2, a3             #a0 = P_l | P_h
    jalr  x0, 0(ra)              #return a0

    .size   q_mul_asm, .-q_mul_asm
    
