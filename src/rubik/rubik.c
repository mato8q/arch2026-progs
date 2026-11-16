#include "rubik.h"
#include "rubik_tables.h"

enum { CUBIES = 7, MOVES = 9, MAX_DEPTH = 11, FAR_COUNT = 2644 };

static const char move_text[MOVES][2] = {{'R', 0}, {'R', '2'}, {'R', '\''},
                                         {'B', 0}, {'B', '2'}, {'B', '\''},
                                         {'D', 0}, {'D', '2'}, {'D', '\''}};
static const uint8_t face_of[MOVES] = {0, 0, 0, 1, 1, 1, 2, 2, 2};

/* Admissible distance estimate: the larger of the orientation distance and
 * the distance of the permutation together with the twists of cubies 0, 1.
 */
static uint8_t heuristic(uint16_t p, uint16_t o, uint8_t a, uint8_t b)
{
    uint8_t h = h_O[o];
    uint8_t hn = h_N[p * 9 + (a & 3) * 3 + (b & 3)];
    return hn > h ? hn : h;
}

static void turn(uint8_t move, uint16_t *p, uint16_t *o, uint8_t *a, uint8_t *b)
{
    uint8_t face = face_of[move];
    for (int t = move - face * 3; t >= 0; t--) {
        *p = permutation[face][*p];
        *o = orientation[face][*o];
        *a = cub_move[face][*a];
        *b = cub_move[face][*b];
    }
}

/* Binary search in the sorted ranks of the 2,644 states at distance 11. */
static int is_far(uint16_t p, uint16_t o)
{
    uint32_t key = (uint32_t) p * 729 + o;
    int lo = 0, hi = FAR_COUNT - 1;
    while (lo <= hi) {
        int mid = (lo + hi) >> 1;
        if (far_states[mid] == key)
            return 1;
        if (far_states[mid] < key)
            lo = mid + 1;
        else
            hi = mid - 1;
    }
    return 0;
}

/* Iterative deepening A* without recursion; writes the moves to path and
 * returns their number. Every state is within 10 moves here. */
static int ida(uint16_t p, uint16_t o, uint8_t a, uint8_t b, uint8_t *path)
{
    uint16_t sp[MAX_DEPTH], so[MAX_DEPTH];
    uint8_t sa[MAX_DEPTH], sb[MAX_DEPTH], next[MAX_DEPTH];
    int bound = heuristic(p, o, a, b);
    if (bound == 0)
        return 0;
    for (;; bound++) {
        int depth = 0;
        sp[0] = p, so[0] = o, sa[0] = a, sb[0] = b, next[0] = 0;
        while (depth >= 0) {
            if (next[depth] == MOVES) {
                depth--;
                continue;
            }
            uint8_t move = next[depth]++;
            if (depth > 0 && face_of[move] == face_of[path[depth - 1]]) {
                next[depth] = (uint8_t) (face_of[move] * 3 + 3);
                continue;
            }
            uint16_t cp = sp[depth], co = so[depth];
            uint8_t ca = sa[depth], cb = sb[depth];
            turn(move, &cp, &co, &ca, &cb);
            uint8_t h = heuristic(cp, co, ca, cb);
            if (depth + 1 + h > bound)
                continue;
            path[depth] = move;
            if (h == 0)
                return depth + 1;
            depth++;
            sp[depth] = cp, so[depth] = co, sa[depth] = ca, sb[depth] = cb;
            next[depth] = 0;
        }
    }
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint8_t perm[CUBIES], ori[CUBIES];
    unsigned seen = 0, sum = 0;
    for (int i = 0; i < 14; i++) {
        unsigned d = (unsigned) (state[i] - '1');
        if (d >= (i < CUBIES ? 7u : 3u))
            return -1;
        if (i < CUBIES) {
            if (seen & (1u << d))
                return -1;
            seen |= 1u << d;
            perm[i] = (uint8_t) d;
        } else {
            ori[i - CUBIES] = (uint8_t) d;
            sum += d;
        }
    }
    while (sum >= 3) /* sum <= 12, and RV32I has no remainder */
        sum -= 3;
    if (state[14] != '\0' || sum != 0)
        return -1;

    /* Lehmer rank of the permutation, base-3 rank of six orientations, and
     * the position-and-twist coordinate of cubies 0 and 1. */
    uint16_t p = 0, o = 0;
    uint8_t a = 0, b = 0;
    for (int i = 0; i < CUBIES; i++) {
        unsigned smaller = 0;
        for (int j = i + 1; j < CUBIES; j++)
            smaller += perm[j] < perm[i];
        p = (uint16_t) (p * (CUBIES - i) + smaller);
        if (i < 6)
            o = (uint16_t) (o * 3 + ori[i]);
        if (perm[i] == 0)
            a = (uint8_t) (i << 2 | ori[i]);
        if (perm[i] == 1)
            b = (uint8_t) (i << 2 | ori[i]);
    }

    /* A state at distance 11 is the slowest case of the search. Take the
     * first move to a neighbor that is not at distance 11 (so at distance 10)
     * and search from there. */
    uint8_t path[MAX_DEPTH];
    int n;
    if (is_far(p, o)) {
        uint8_t move = 0;
        for (;; move++) {
            uint16_t np = p, no = o;
            uint8_t na = a, nb = b;
            turn(move, &np, &no, &na, &nb);
            if (!is_far(np, no)) {
                p = np, o = no, a = na, b = nb;
                break;
            }
        }
        path[0] = move;
        n = 1 + ida(p, o, a, b, path + 1);
    } else {
        n = ida(p, o, a, b, path);
    }

    size_t need = 1;
    for (int i = 0; i < n; i++)
        need += (size_t) (i > 0) + 1 + (move_text[path[i]][1] != 0);
    if (cap < need) {
        if (cap >= 1)
            out[0] = '\0';
        return -2;
    }
    char *w = out;
    for (int i = 0; i < n; i++) {
        if (i > 0)
            *w++ = ' ';
        *w++ = move_text[path[i]][0];
        if (move_text[path[i]][1])
            *w++ = move_text[path[i]][1];
    }
    *w = '\0';
    return n;
}
