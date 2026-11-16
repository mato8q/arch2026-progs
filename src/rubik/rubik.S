# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.
# Same algorithm as rubik.c: iterative deepening A* over the coordinates
# p (permutation rank), o (twist rank), a and b (position << 2 | twist of
# cubies 0 and 1), with the tables of rubik_tables.S. A state at distance 11
# first moves to a neighbor that is not in rt_far.
#stack_frame 224 bytes:
#     0..6   perm[7]           8..14  ori[7]
#    16      out               20     cap
#    28..43  saved s0..s3      47     first move of a distance-11 state
#    48..223 eleven search records of 16 bytes:
#             0 p   2 o   4 a   5 b    state after k turns of face f
#             6 f   7 k                next face to try, turns done
#             8 p  10 o  12 a  13 b    parent state
#            14 face of the move into this record (3 at the root)
#            15 move from this record, f << 2 | k
#
# Registers in the search:
#    a0 p, a1 o, a2 a, a6 b        the state being turned
#    a3 rt_h_o, a4 rt_h_n, a5 .Lrows
#    s0 current record, s2 bound - depth - 1, s3 bound
#    t5 f, t6 k

# t0, t1, t2 = rows of face \f in rt_perm, rt_ori and rt_cub
    .macro  ROWS f
    slli    t3, \f, 3
    slli    t0, \f, 2
    add     t3, t3, t0            # f * 12
    add     t3, t3, a5
    lw      t0, 0(t3)
    lw      t1, 4(t3)
    lw      t2, 8(t3)
    .endm

# One quarter turn of the face whose rows are in t0, t1, t2
    .macro  QTURN
    slli    t3, a0, 1
    add     t3, t3, t0
    lhu     a0, 0(t3)             # p = permutation[f][p]
    slli    t3, a1, 1
    add     t3, t3, t1
    lhu     a1, 0(t3)             # o = orientation[f][o]
    add     t3, a2, t2
    lbu     a2, 0(t3)             # a = cub_move[f][a]
    add     t3, a6, t2
    lbu     a6, 0(t3)             # b = cub_move[f][b]
    .endm

# t4 = max(h_O[o], h_N[p * 9 + (a & 3) * 3 + (b & 3)])
    .macro  HEUR
    add     t3, a1, a3
    lbu     t4, 0(t3)             # h_O[o]
    slli    t3, a0, 3
    add     t3, t3, a0            # p * 9
    andi    a7, a2, 3
    add     t3, t3, a7
    slli    a7, a7, 1
    add     t3, t3, a7            # + (a & 3) * 3
    andi    a7, a6, 3
    add     t3, t3, a7            # + (b & 3)
    add     t3, t3, a4
    lbu     a7, 0(t3)             # h_N[...]
    bgeu    t4, a7, 1f
    addi    t4, a7, 0
1:
    .endm

# Binary search of p * 729 + o in rt_far; uses t0..t6
    .macro  FAR found, missing
    slli    t0, a0, 9
    slli    t1, a0, 7
    add     t0, t0, t1
    slli    t1, a0, 6
    add     t0, t0, t1
    slli    t1, a0, 4
    add     t0, t0, t1
    slli    t1, a0, 3
    add     t0, t0, t1
    add     t0, t0, a0            # p * 729 = p * (512 + 128 + 64 + 16 + 8 + 1)
    add     t0, t0, a1            # key
    lui     t3, %hi(rt_far)
    addi    t3, t3, %lo(rt_far)
    addi    t1, x0, 0             # lo
    lui     t2, 0x1
    addi    t2, t2, -1453         # hi = 4096 - 1453 = 2643
1:
    blt     t2, t1, \missing
    add     t5, t1, t2
    srli    t5, t5, 1             # mid
    slli    t6, t5, 2
    add     t6, t6, t3
    lw      t6, 0(t6)
    beq     t6, t0, \found
    bltu    t6, t0, 2f
    addi    t2, t5, -1
    jal     x0, 1b
2:
    addi    t1, t5, 1
    jal     x0, 1b
    .endm

    .section .rodata
    .align  2
.Lrows:                           # per face: its row in rt_perm, rt_ori, rt_cub
    .word   rt_perm, rt_ori, rt_cub
    .word   rt_perm + 10080, rt_ori + 1458, rt_cub + 28
    .word   rt_perm + 20160, rt_ori + 2916, rt_cub + 56
.Lletters:
    .byte   82, 66, 68            # R B D

    .text
    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi    sp, sp, -224
    sw      s0, 28(sp)
    sw      s1, 32(sp)
    sw      s2, 36(sp)
    sw      s3, 40(sp)
    sw      a1, 16(sp)
    sw      a2, 20(sp)
    sb      x0, 47(sp)            # no first move yet

# 1. Validate: seven distinct cubies '1'..'7', seven twists '1'..'3'
    addi    t4, x0, 0             # i
    addi    t5, x0, 0             # seen
    addi    t6, x0, 0             # sum of twists
    addi    t2, x0, 7
.Lv_perm:
    add     t0, a0, t4
    lbu     t1, 0(t0)
    addi    t1, t1, -49           # d = state[i] - '1'
    bgeu    t1, t2, .Linvalid     # also catches d < 0
    addi    t3, x0, 1
    sll     t3, t3, t1
    and     t0, t5, t3
    bne     t0, x0, .Linvalid     # repeated cubie
    or      t5, t5, t3
    add     t0, sp, t4
    sb      t1, 0(t0)             # perm[i]
    addi    t4, t4, 1
    blt     t4, t2, .Lv_perm
    addi    t2, x0, 3
    addi    t3, x0, 14
.Lv_ori:
    add     t0, a0, t4
    lbu     t1, 0(t0)
    addi    t1, t1, -49
    bgeu    t1, t2, .Linvalid
    add     t6, t6, t1
    add     t0, sp, t4
    sb      t1, 1(t0)             # ori[i - 7] at 8 + i - 7
    addi    t4, t4, 1
    blt     t4, t3, .Lv_ori
    add     t0, a0, t4
    lbu     t1, 0(t0)
    bne     t1, x0, .Linvalid     # longer than 14
.Lv_mod:
    bltu    t6, t2, .Lv_moddone
    addi    t6, t6, -3            # sum <= 12, no remainder instruction
    jal     x0, .Lv_mod
.Lv_moddone:
    bne     t6, x0, .Linvalid

# 2. Coordinates: p (Lehmer rank), o (base 3), a, b
    addi    a0, x0, 0
    addi    a1, x0, 0
    addi    a2, x0, 0
    addi    a6, x0, 0
    addi    t4, x0, 0             # i
    addi    t6, x0, 7
.Lr_loop:
    add     t0, sp, t4
    lbu     t1, 0(t0)             # perm[i]
    lbu     t2, 8(t0)             # ori[i]
    addi    t3, x0, 0             # smaller
    addi    t5, t4, 1             # j
    bge     t5, t6, .Lr_cnt_done
.Lr_cnt:
    add     a7, sp, t5
    lbu     a7, 0(a7)
    sltu    a7, a7, t1
    add     t3, t3, a7
    addi    t5, t5, 1
    blt     t5, t6, .Lr_cnt
.Lr_cnt_done:
    sub     t5, t6, t4            # 7 - i, at least 1
    addi    a7, x0, 0
.Lr_mul:
    add     a7, a7, a0            # p * (7 - i) by repeated addition
    addi    t5, t5, -1
    bne     t5, x0, .Lr_mul
    add     a0, a7, t3
    addi    t5, x0, 6
    bge     t4, t5, .Lr_no_o
    slli    a7, a1, 1
    add     a1, a1, a7
    add     a1, a1, t2            # o = o * 3 + ori[i]
.Lr_no_o:
    slli    a7, t4, 2
    or      a7, a7, t2            # i << 2 | ori[i]
    bne     t1, x0, .Lr_not_a
    addi    a2, a7, 0
.Lr_not_a:
    addi    t5, x0, 1
    bne     t1, t5, .Lr_not_b
    addi    a6, a7, 0
.Lr_not_b:
    addi    t4, t4, 1
    blt     t4, t6, .Lr_loop

    lui     a3, %hi(rt_h_o)
    addi    a3, a3, %lo(rt_h_o)
    lui     a4, %hi(rt_h_n)
    addi    a4, a4, %lo(rt_h_n)
    lui     a5, %hi(.Lrows)
    addi    a5, a5, %lo(.Lrows)
    sh      a0, 56(sp)            # root record parent = start
    sh      a1, 58(sp)
    sb      a2, 60(sp)
    sb      a6, 61(sp)

# 3a. Distance 11: step to the first neighbor that is not in rt_far
    FAR     .Lfar, .Lnear
.Lfar:
    addi    s1, x0, 0             # f
.Lf_face:
    lhu     a0, 56(sp)
    lhu     a1, 58(sp)
    lbu     a2, 60(sp)
    lbu     a6, 61(sp)
    addi    s2, x0, 0             # k
.Lf_turn:
    ROWS    s1
    QTURN
    addi    s2, s2, 1
    FAR     .Lf_next, .Lf_found
.Lf_next:
    addi    t0, x0, 3
    blt     s2, t0, .Lf_turn
    addi    s1, s1, 1
    jal     x0, .Lf_face
.Lf_found:
    slli    t0, s1, 2
    or      t0, t0, s2
    sb      t0, 47(sp)            # first move, f << 2 | k
    sh      a0, 56(sp)
    sh      a1, 58(sp)
    sb      a2, 60(sp)
    sb      a6, 61(sp)
.Lnear:

# 3b. Iterative deepening A*
    HEUR
    addi    s3, t4, 0             # bound = h(start)
    addi    t1, x0, 0             # n = 0 if solved
    beq     t4, x0, .Lout
.Lbound:
    addi    s0, sp, 48
    sb      x0, 6(s0)
    sb      x0, 7(s0)
    addi    t0, x0, 3
    sb      t0, 14(s0)            # root: no previous face
    addi    s2, s3, -1            # bound - depth - 1
.Lnode:
    lbu     t5, 6(s0)             # f
    lbu     t6, 7(s0)             # k
    addi    t0, x0, 3
    bne     t6, t0, .Lsame_face
    addi    t5, t5, 1             # face done: next face
    addi    t6, x0, 0
.Lsame_face:
    bne     t6, x0, .Lcontinue
.Lnew_face:
    beq     t5, t0, .Lpop         # all faces tried
    lbu     t1, 14(s0)
    bne     t5, t1, .Lstart
    addi    t5, t5, 1             # never turn the same face twice
    jal     x0, .Lnew_face
.Lstart:
    lhu     a0, 8(s0)             # first turn starts from the parent
    lhu     a1, 10(s0)
    lbu     a2, 12(s0)
    lbu     a6, 13(s0)
    jal     x0, .Lturn
.Lcontinue:
    lhu     a0, 0(s0)             # later turns continue from the last one
    lhu     a1, 2(s0)
    lbu     a2, 4(s0)
    lbu     a6, 5(s0)
.Lturn:
    ROWS    t5
    QTURN
    addi    t6, t6, 1
    sh      a0, 0(s0)
    sh      a1, 2(s0)
    sb      a2, 4(s0)
    sb      a6, 5(s0)
    sb      t5, 6(s0)
    sb      t6, 7(s0)
    HEUR
    blt     s2, t4, .Lnode        # depth + 1 + h > bound: prune
    slli    t0, t5, 2
    or      t0, t0, t6
    sb      t0, 15(s0)            # move = f << 2 | k
    beq     t4, x0, .Lfound
    addi    s0, s0, 16            # push the child
    sh      a0, 8(s0)
    sh      a1, 10(s0)
    sb      a2, 12(s0)
    sb      a6, 13(s0)
    sb      t5, 14(s0)
    sb      x0, 6(s0)
    sb      x0, 7(s0)
    addi    s2, s2, -1
    jal     x0, .Lnode
.Lpop:
    addi    s0, s0, -16
    addi    s2, s2, 1
    addi    t0, sp, 48
    bgeu    s0, t0, .Lnode
    addi    s3, s3, 1             # nothing within bound: deepen
    jal     x0, .Lbound
.Lfound:
    addi    t0, sp, 48
    sub     t1, s0, t0
    srli    t1, t1, 4
    addi    t1, t1, 1             # n = depth + 1

# 4. Output: moves of records [t3, t3 + 16 * t1), byte 15 each
.Lout:
    addi    t3, sp, 48
    lbu     t2, 47(sp)
    beq     t2, x0, .Lno_first
    addi    t3, sp, 32            # the first move sits at 47 = 32 + 15
    addi    t1, t1, 1
.Lno_first:
    addi    t4, x0, 1             # bytes needed, NUL included
    addi    t5, x0, 0
    beq     t1, x0, .Lneed_done
.Lneed:
    slli    t6, t5, 4
    add     t6, t6, t3
    lbu     t6, 15(t6)
    andi    t6, t6, 3             # k
    addi    t4, t4, 2             # letter and separator
    addi    a7, x0, 1
    beq     t6, a7, .Lneed_one
    addi    t4, t4, 1             # '2' or '\''
.Lneed_one:
    addi    t5, t5, 1
    blt     t5, t1, .Lneed
    addi    t4, t4, -1            # n - 1 separators
.Lneed_done:
    lw      a1, 16(sp)
    lw      a2, 20(sp)
    bgeu    a2, t4, .Lwrite
    beq     a2, x0, .Lsmall
    sb      x0, 0(a1)
.Lsmall:
    addi    a0, x0, -2
    jal     x0, .Lret
.Lwrite:
    lui     t0, %hi(.Lletters)
    addi    t0, t0, %lo(.Lletters)
    addi    t5, x0, 0
    beq     t1, x0, .Lw_done
.Lw:
    beq     t5, x0, .Lw_letter
    addi    t6, x0, 32            # ' '
    sb      t6, 0(a1)
    addi    a1, a1, 1
.Lw_letter:
    slli    t6, t5, 4
    add     t6, t6, t3
    lbu     t6, 15(t6)
    srli    a7, t6, 2
    add     a7, a7, t0
    lbu     a7, 0(a7)
    sb      a7, 0(a1)
    addi    a1, a1, 1
    andi    t6, t6, 3
    addi    a7, x0, 1
    beq     t6, a7, .Lw_next      # quarter turn: no suffix
    addi    a7, x0, 50            # '2'
    addi    a6, x0, 2
    beq     t6, a6, .Lw_suffix
    addi    a7, x0, 39            # '\''
.Lw_suffix:
    sb      a7, 0(a1)
    addi    a1, a1, 1
.Lw_next:
    addi    t5, t5, 1
    blt     t5, t1, .Lw
.Lw_done:
    sb      x0, 0(a1)
    addi    a0, t1, 0
.Lret:
    lw      s0, 28(sp)
    lw      s1, 32(sp)
    lw      s2, 36(sp)
    lw      s3, 40(sp)
    addi    sp, sp, 224
    jalr    x0, 0(ra)
.Linvalid:
    addi    a0, x0, -1
    jal     x0, .Lret
    
    .size   rubik_solve_asm, .-rubik_solve_asm
