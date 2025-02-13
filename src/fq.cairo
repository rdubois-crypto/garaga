from starkware.cairo.common.bitwise import bitwise_and, bitwise_or, bitwise_xor
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import (
    assert_in_range,
    assert_le,
    assert_nn_le,
    assert_not_zero,
    assert_le_felt,
    assert_lt_felt,
)
from starkware.cairo.common.math import unsigned_div_rem as felt_divmod
from starkware.cairo.common.math_cmp import is_le, is_nn
from starkware.cairo.common.registers import get_ap, get_fp_and_pc
from starkware.cairo.common.cairo_secp.constants import BASE
from src.u255 import u255, Uint256, Uint512, Uint768
from src.curve import (
    P_low,
    P_high,
    P2_low,
    P2_high,
    P3_low,
    P3_high,
    M_low,
    M_high,
    mu,
    t,
    P0,
    P1,
    P2,
)
from src.uint384 import uint384_lib, Uint384
from starkware.cairo.common.uint256 import SHIFT, uint256_le, uint256_lt, assert_uint256_le
from src.uint256_improvements import uint256_unsigned_div_rem
from src.utils import get_felt_bitlength, pow2, felt_divmod_no_input_check, verify_zero5
from starkware.cairo.common.cairo_secp.bigint import (
    BigInt3,
    uint256_to_bigint,
    bigint_to_uint256,
    UnreducedBigInt5,
    bigint_mul,
    nondet_bigint3,
)

struct Polyfelt {
    p00: felt,
    p10: felt,
    p20: felt,
    p30: felt,
    p40: felt,
}
struct Polyfelt3 {
    low: felt,
    mid: felt,
    high: felt,
}

const RC_BOUND = 2 ** 128;
const SHIFT_MIN_BASE = SHIFT - BASE;
func fq_zero() -> (res: BigInt3) {
    return (BigInt3(0, 0, 0),);
}
func fq_eq_zero(x: BigInt3) -> (res: felt) {
    if (x.d0 != 0) {
        return (res=0);
    }
    if (x.d1 != 0) {
        return (res=0);
    }
    if (x.d2 != 0) {
        return (res=0);
    }
    return (res=1);
}

func add_bigint3{range_check_ptr}(a: BigInt3, b: BigInt3) -> BigInt3 {
    alloc_locals;
    local has_carry_low: felt;
    local has_carry_mid: felt;
    local needs_reduction: felt;
    local sum: BigInt3;

    let sum_low = a.d0 + b.d0;
    let sum_mid = a.d1 + b.d1;
    let sum_high = a.d2 + b.d2;

    %{
        has_carry_low = 1 if ids.sum_low >= ids.BASE else 0
        ids.has_carry_low = has_carry_low
        ids.has_carry_mid = 1 if (ids.sum_mid + has_carry_low) >= ids.BASE else 0
    %}

    if (has_carry_low != 0) {
        if (has_carry_mid != 0) {
            assert sum.d0 = sum_low - BASE;
            assert sum.d1 = sum_mid + 1 - BASE;
            assert sum.d2 = sum_high + 1;
            assert [range_check_ptr] = sum.d0 + (SHIFT_MIN_BASE);
            assert [range_check_ptr + 1] = sum.d1 + (SHIFT_MIN_BASE);
            let range_check_ptr = range_check_ptr + 2;
            return sum;
        } else {
            assert sum.d0 = sum_low - BASE;
            assert sum.d1 = sum_mid + 1;
            assert sum.d2 = sum_high;
            assert [range_check_ptr] = sum.d0 + (SHIFT_MIN_BASE);
            assert [range_check_ptr + 1] = sum.d1 + (SHIFT_MIN_BASE);
            let range_check_ptr = range_check_ptr + 2;
            return sum;
        }
    } else {
        if (has_carry_mid != 0) {
            assert sum.d0 = sum_low;
            assert sum.d1 = sum_mid - BASE;
            assert sum.d2 = sum_high + 1;
            assert [range_check_ptr] = sum.d1 + (SHIFT_MIN_BASE);
            assert [range_check_ptr + 1] = sum.d2 + (SHIFT_MIN_BASE);
            let range_check_ptr = range_check_ptr + 2;
            return sum;
        } else {
            assert sum.d0 = sum_low;
            assert sum.d1 = sum_mid;
            assert sum.d2 = sum_high;
            assert [range_check_ptr] = sum.d0 + (SHIFT_MIN_BASE);
            assert [range_check_ptr + 1] = sum.d1 + (SHIFT_MIN_BASE);
            let range_check_ptr = range_check_ptr + 2;
            return sum;
        }
    }
}
namespace fq_bigint3 {
    func mul{range_check_ptr}(a: BigInt3, b: BigInt3) -> BigInt3 {
        let mul: UnreducedBigInt5 = bigint_mul(a, b);
        %{
            p = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mul = ids.mul.d0 + ids.mul.d1*2**86 + ids.mul.d2*2**172 + ids.mul.d3*2**258 + ids.mul.d4*2**344
            value = mul%p
        %}
        let (result: BigInt3) = nondet_bigint3();
        verify_zero5(
            UnreducedBigInt5(
                d0=mul.d0 - result.d0,
                d1=mul.d1 - result.d1,
                d2=mul.d2 - result.d2,
                d3=mul.d3,
                d4=mul.d4,
            ),
        );
        return result;
    }
    func sub{range_check_ptr}(a: BigInt3, b: BigInt3) -> BigInt3 {
        alloc_locals;
        %{
            p = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47

            sub_mod_p = value = (ids.a.d0 + ids.a.d1*2**86 + ids.a.d2*2**172 - ids.b.d0 - ids.b.d1*2**86 - ids.b.d2*2**172)%p
        %}
        let (sub_mod_p) = nondet_bigint3();
        let check = add_bigint3(b, sub_mod_p);
        assert check.d0 = a.d0;
        assert check.d1 = a.d1;
        assert check.d2 = a.d2;

        return sub_mod_p;
    }
    func add{range_check_ptr}(a: BigInt3, b: BigInt3) -> BigInt3 {
        alloc_locals;
        local needs_reduction: felt;
        let P = BigInt3(P0, P1, P2);
        let sum = add_bigint3(a, b);
        %{
            p = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            sum = ids.sum.d0 + ids.sum.d1*2**86 + ids.sum.d2*2**172
            ids.needs_reduction = 1 if sum>=p else 0
            print(ids.needs_reduction)
        %}

        if (sum.d2 == P2) {
            if (sum.d1 == P1) {
                if (needs_reduction != 0) {
                    assert [range_check_ptr] = sum.d0 - P0;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = sub(sum, P);
                    return res;
                } else {
                    assert [range_check_ptr] = P0 - sum.d0 - 1;
                    let range_check_ptr = range_check_ptr + 1;
                    return sum;
                }
            } else {
                if (needs_reduction != 0) {
                    assert [range_check_ptr] = sum.d1 - P1;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = sub(sum, P);
                    return res;
                } else {
                    %{ print('case 3') %}
                    assert [range_check_ptr] = P1 - sum.d1 - 1;
                    let range_check_ptr = range_check_ptr + 1;
                    return sum;
                }
            }
        } else {
            if (needs_reduction != 0) {
                assert [range_check_ptr] = sum.d2 - P2;
                let range_check_ptr = range_check_ptr + 1;

                let res = sub(sum, P);
                return res;
            } else {
                assert [range_check_ptr] = P2 - sum.d2 - 1;
                let range_check_ptr = range_check_ptr + 1;

                return sum;
            }
        }
    }
}

namespace fq_poly {
    func to_polyfelt{range_check_ptr}(a: Uint256) -> Polyfelt {
        alloc_locals;
        let (a4, r) = uint256_unsigned_div_rem(
            a,
            Uint256(272204382041124684987214825571503402433, 1786771239255088250803009499627505898),
        );
        assert a4.high = 0;
        let (a3, r) = uint256_unsigned_div_rem(
            r, Uint256(331349846221318139915745154521890902225, 359825430517661861)
        );
        // May use felt_divmod here for the last two:
        let (a2, r) = uint256_unsigned_div_rem(
            r, Uint256(24657792813631553165138951344902952161, 0)
        );
        let (a1, a0) = uint256_unsigned_div_rem(r, Uint256(4965661367192848881, 0));

        assert a3.high = 0;
        assert a2.high = 0;
        assert a1.high = 0;
        assert a0.high = 0;

        let a00 = a0.low;
        let a10 = a1.low;
        let a20 = a2.low;
        let a30 = a3.low;
        let a40 = a4.low;

        let res = Polyfelt(a00, a10, a20, a30, a40);
        return res;
    }
    // Returns 1 if a >= 0 (or more precisely 0 <= a < RANGE_CHECK_BOUND).
    // Returns 0 otherwise.
    // @known_ap_change
    // func is_nn{range_check_ptr}(a) -> felt {
    //     %{ memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1 %}
    //     jmp out_of_range if [ap] != 0, ap++;
    //     [range_check_ptr] = a;
    //     ap += 20;
    //     let range_check_ptr = range_check_ptr + 1;
    //     return 1;

    // out_of_range:
    //     %{ memory[ap] = 0 if 0 <= ((-ids.a - 1) % PRIME) < range_check_builtin.bound else 1 %}
    //     jmp need_felt_comparison if [ap] != 0, ap++;
    //     assert [range_check_ptr] = (-a) - 1;
    //     ap += 17;
    //     let range_check_ptr = range_check_ptr + 1;
    //     return 0;

    // need_felt_comparison:
    //     assert_le_felt(RC_BOUND, a);
    //     return 0;
    // }

    // Checks if the unsigned integer lift (as a number in the range [0, PRIME)) of a is lower than
    // or equal to that of b.
    // See split_felt() for more details.
    // Returns 1 if true, 0 otherwise.
    @known_ap_change
    func is_le_felt{range_check_ptr}(a, b) -> felt {
        %{ memory[ap] = 0 if (ids.a % PRIME) <= (ids.b % PRIME) else 1 %}
        jmp not_le if [ap] != 0, ap++;
        ap += 6;
        assert_le_felt(a, b);
        return 1;

        not_le:
        assert_lt_felt(b, a);
        return 0;
    }

    @known_ap_change
    func assert_le_felt{range_check_ptr}(a, b) {
        // ceil(PRIME / 3 / 2 ** 128).
        const PRIME_OVER_3_HIGH = 0x2aaaaaaaaaaaab05555555555555556;
        // ceil(PRIME / 2 / 2 ** 128).
        const PRIME_OVER_2_HIGH = 0x4000000000000088000000000000001;
        // The numbers [0, a, b, PRIME - 1] should be ordered. To prove that, we show that two of the
        // 3 arcs {0 -> a, a -> b, b -> PRIME - 1} are small:
        //   One is less than PRIME / 3 + 2 ** 129.
        //   Another is less than PRIME / 2 + 2 ** 129.
        // Since the sum of the lengths of these two arcs is less than PRIME, there is no wrap-around.
        %{
            import itertools

            from starkware.cairo.common.math_utils import assert_integer
            assert_integer(4407920970296243842837207485651524041978352485963568397222)
            assert_integer(ids.b)
            a = 4407920970296243842837207485651524041978352485963568397222
            b = ids.b % PRIME
            assert a <= b, f'a = {a} is not less than or equal to b = {b}.'

            # Find an arc less than PRIME / 3, and another less than PRIME / 2.
            lengths_and_indices = [(a, 0), (b - a, 1), (PRIME - 1 - b, 2)]
            lengths_and_indices.sort()
            assert lengths_and_indices[0][0] <= PRIME // 3 and lengths_and_indices[1][0] <= PRIME // 2
            excluded = lengths_and_indices[2][1]

            memory[ids.range_check_ptr + 1], memory[ids.range_check_ptr + 0] = (
                divmod(lengths_and_indices[0][0], ids.PRIME_OVER_3_HIGH))
            memory[ids.range_check_ptr + 3], memory[ids.range_check_ptr + 2] = (
                divmod(lengths_and_indices[1][0], ids.PRIME_OVER_2_HIGH))
        %}
        // Guess two arc lengths.
        tempvar arc_short = [range_check_ptr] + [range_check_ptr + 1] * PRIME_OVER_3_HIGH;
        tempvar arc_long = [range_check_ptr + 2] + [range_check_ptr + 3] * PRIME_OVER_2_HIGH;
        let range_check_ptr = range_check_ptr + 4;

        // First, choose which arc to exclude from {0 -> a, a -> b, b -> PRIME - 1}.
        // Then, to compare the set of two arc lengths, compare their sum and product.
        let arc_sum = arc_short + arc_long;
        let arc_prod = arc_short * arc_long;

        // Exclude "0 -> a".
        %{ memory[ap] = 1 if excluded != 0 else 0 %}
        jmp skip_exclude_a if [ap] != 0, ap++;
        assert arc_sum = (-1) - 4407920970296243842837207485651524041978352485963568397222;
        assert arc_prod = (a - b) * (1 + b);
        return ();

        // Exclude "a -> b".
        skip_exclude_a:
        %{ memory[ap] = 1 if excluded != 1 else 0 %}
        jmp skip_exclude_b_minus_a if [ap] != 0, ap++;
        tempvar m1mb = (-1) - b;
        assert arc_sum = a + m1mb;
        assert arc_prod = a * m1mb;
        return ();

        // Exclude "b -> PRIME - 1".
        skip_exclude_b_minus_a:
        %{ assert excluded == 2 %}
        assert arc_sum = b;
        assert arc_prod = a * (b - a);
        ap += 2;
        return ();
    }
    func polyadd{range_check_ptr}(a: Polyfelt, b: Polyfelt) -> Polyfelt {
        alloc_locals;
        const P_of_t_high = 178763809218942559752;  // = 36 + 36*t
        const P_of_t_middle = 119175872812628373150;  // 6 + 24*t
        let c00 = a.p00 + b.p00;
        let c10 = a.p10 + b.p10;
        let c20 = a.p20 + b.p20;
        let c30 = a.p30 + b.p30;
        let c40 = a.p40 + b.p40;
        let C_of_t_middle = c10 + c20 * t;
        let C_of_t_high = c30 + c40 * t;
        local reduction_needed: felt;
        %{
            C=ids.c00 + ids.c10*ids.t + ids.c20*ids.t**2 + ids.c30*ids.t**3 + ids.c40*ids.t**4
            ids.reduction_needed = 1 if C>= 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47 else 0
            print(f"Reduction needed : C(t) >= P(t)")
        %}
        if (C_of_t_high == P_of_t_high) {
            if (C_of_t_middle == P_of_t_middle) {
                if (reduction_needed == 1) {
                    assert [range_check_ptr] = c00 - 1;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                    return res;
                } else {
                    assert [range_check_ptr] = 1 - c00;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = Polyfelt(c00, c10, c20, c30, c40);
                    return res;
                }
            } else {
                if (reduction_needed == 1) {
                    assert [range_check_ptr] = C_of_t_middle - P_of_t_middle;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                    return res;
                } else {
                    assert [range_check_ptr] = P_of_t_middle - C_of_t_middle;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = Polyfelt(c00, c10, c20, c30, c40);
                    return res;
                }
            }
        } else {
            if (reduction_needed == 1) {
                assert [range_check_ptr] = C_of_t_high - P_of_t_high;
                let range_check_ptr = range_check_ptr + 1;
                let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                return res;
            } else {
                assert [range_check_ptr] = P_of_t_high - C_of_t_high;
                let range_check_ptr = range_check_ptr + 1;
                let res = Polyfelt(c00, c10, c20, c30, c40);
                return res;
            }
        }
    }

    func polyadd_3{range_check_ptr}(a: Polyfelt3, b: Polyfelt3) -> Polyfelt3 {
        alloc_locals;
        const P_of_t_high = 178763809218942559752;  // = 36 + 36*t
        const P_of_t_middle = 119175872812628373150;  // 6 + 24*t
        let low = a.low + b.low;
        let mid = a.mid + b.mid;
        let high = a.high + b.high;

        local reduction_needed: felt;
        %{
            C=ids.low + ids.mid*ids.t + ids.high*ids.t**3
            ids.reduction_needed = 1 if C>= 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47 else 0
            print(f"Reduction needed : C(t) >= P(t)")
        %}
        if (high == P_of_t_high) {
            if (mid == P_of_t_middle) {
                if (reduction_needed == 1) {
                    assert [range_check_ptr] = low - 1;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = Polyfelt3(low - 1, mid - P_of_t_middle, high - P_of_t_high);
                    return res;
                } else {
                    assert [range_check_ptr] = 1 - low;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = Polyfelt3(low, mid, high);
                    return res;
                }
            } else {
                if (reduction_needed == 1) {
                    assert [range_check_ptr] = mid - P_of_t_middle;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = Polyfelt3(low - 1, mid - P_of_t_middle, high - P_of_t_high);
                    return res;
                } else {
                    assert [range_check_ptr] = P_of_t_middle - mid;
                    let range_check_ptr = range_check_ptr + 1;
                    let res = Polyfelt3(low, mid, high);
                    return res;
                }
            }
        } else {
            if (reduction_needed == 1) {
                assert [range_check_ptr] = high - P_of_t_high;
                let range_check_ptr = range_check_ptr + 1;
                let res = Polyfelt3(low - 1, mid - P_of_t_middle, high - P_of_t_high);
                return res;
            } else {
                assert [range_check_ptr] = P_of_t_high - high;
                let range_check_ptr = range_check_ptr + 1;
                let res = Polyfelt3(low, mid, high);
                return res;
            }
        }
    }
    func add_reduce_coeffs{range_check_ptr}(a: Polyfelt, b: Polyfelt) -> (
        c0: felt, c1: felt, c2: felt, c3: felt, c4: felt
    ) {
        let c0 = ap;
        [c0] = a.p00 + b.p00, ap++;

        let c1 = ap;
        [c1] = a.p10 + b.p10, ap++;

        let c2 = ap;
        [c2] = a.p20 + b.p20, ap++;

        let c3 = ap;
        [c3] = a.p30 + b.p30, ap++;

        let c4 = ap;
        [c4] = a.p40 + b.p40, ap++;

        let c0_t = ap;
        [c0_t] = [c0] - t, ap++;

        let c1_t = ap;
        [c1_t] = [c1] - t, ap++;

        let c2_t = ap;
        [c2_t] = [c2] - t, ap++;

        let c3_t = ap;
        [c3_t] = [c3] - t, ap++;

        tempvar degree_0_superior_to_t = is_nn([c0_t]);  // if 1, c0>=t, if 0, c0<t
        jmp degree_0xxxx_needs_reduction if degree_0_superior_to_t != 0;
        tempvar degree_1_superior_to_t = is_nn([c1_t]);
        jmp degree_n1xxx_needs_reduction if degree_1_superior_to_t != 0;  // ALL ok
        tempvar degree_2_superior_to_t = is_nn([c2_t]);
        jmp degree_nn2xx_needs_reduction if degree_2_superior_to_t != 0;  // All ok
        tempvar degree_3_superior_to_t = is_nn([c3_t]);
        jmp degree_nnn3x_needs_reduction if degree_3_superior_to_t != 0;  // ALL ok
        return ([c0], [c1], [c2], [c3], [c4]);

        degree_0xxxx_needs_reduction:
        // (c0 - t) already in c0_t
        let c1_plus_one = ap;
        [c1_plus_one] = [c1] + 1, ap++;
        let c1_plus_one_min_t = ap;
        [c1_plus_one_min_t] = [c1_t] + 1, ap++;
        tempvar degree_1_superior_to_t = is_nn([c1_plus_one_min_t]);  // if 1, c1>=t, if 0, c1<t
        jmp degree_01xxx_needs_reduction if degree_1_superior_to_t != 0;

        tempvar degree_2_superior_to_t = is_nn([c2_t]);
        jmp degree_0n2xx_needs_reduction if degree_2_superior_to_t != 0;
        tempvar degree_3_superior_to_t = is_nn([c3_t]);
        jmp degree_0nn3x_needs_reduction if degree_3_superior_to_t != 0;
        return ([c0_t], [c1_plus_one], [c2], [c3], [c4]);

        degree_01xxx_needs_reduction:
        let c2_plus_one = ap;
        [c2_plus_one] = [c2] + 1, ap++;
        let c2_plus_one_min_t = ap;
        [c2_plus_one_min_t] = [c2_t] + 1, ap++;
        let degree_2_superior_to_t = ap;
        tempvar degree_2_superior_to_t = is_nn([c2_plus_one_min_t]);
        jmp degree_012xx_needs_reduction if degree_2_superior_to_t != 0;
        tempvar degree_3_superior_to_t = is_nn([c3_t]);
        jmp degree_01n3x_needs_reduction if degree_3_superior_to_t != 0;
        return ([c0_t], [c1_plus_one_min_t], [c2_plus_one], [c3], [c4]);

        degree_nnn3x_needs_reduction:
        return ([c0], [c1], [c2], [c3_t], [c4] + 1);

        degree_nn2xx_needs_reduction:
        tempvar c3_plus_one = [c3] + 1;
        let c3_plus_one_min_t = ap;
        [c3_plus_one_min_t] = [c3_t] + 1, ap++;
        tempvar degree_3_superior_to_t = is_nn([c3_plus_one_min_t]);
        jmp degree_nn23x_needs_reduction if degree_3_superior_to_t != 0;
        return ([c0], [c1], [c2_t], [c3_plus_one], [c4]);

        degree_nn23x_needs_reduction:
        return ([c0], [c1], [c2_t], [c3_plus_one_min_t], [c4]);

        degree_n1xxx_needs_reduction:
        // (c1 - t) already in c0_t
        let c2_plus_one = ap;
        [c2_plus_one] = [c2] + 1, ap++;
        let c2_plus_one_min_t = ap;
        [c2_plus_one_min_t] = [c2_t] + 1, ap++;
        tempvar degree_2_superior_to_t = is_nn([c2_plus_one_min_t]);
        jmp degree_n12xx_needs_reduction if degree_2_superior_to_t != 0;  // all ok
        tempvar degree_3_superior_to_t = is_nn([c3_t]);
        jmp degree_n1n3x_needs_reduction if degree_3_superior_to_t != 0;  // all ok
        return ([c0], [c1_t], [c2_plus_one], [c3], [c4]);

        degree_n1n3x_needs_reduction:
        return ([c0], [c1_t], [c2_plus_one], [c3_t], [c4] + 1);

        degree_n12xx_needs_reduction:
        // (c2_plus_one_min_t) already in degree_n1xxx_needs_reduction
        let c3_plus_one = ap;
        [c3_plus_one] = [c3] + 1, ap++;
        let c3_plus_one_min_t = ap;
        [c3_plus_one_min_t] = [c3_t] + 1, ap++;
        tempvar degree_3_superior_to_t = is_nn([c3_plus_one_min_t]);
        jmp degree_n123x_needs_reduction if degree_3_superior_to_t != 0;
        return ([c0], [c1_t], [c2_plus_one_min_t], [c3_plus_one], [c4]);

        degree_n123x_needs_reduction:
        // (c3_plus_one_min_t) already in degree_n12xx_needs_reduction
        return ([c0], [c1_t], [c2_plus_one_min_t], [c3_plus_one_min_t], [c4] + 1);

        degree_0nn3x_needs_reduction:
        return ([c0_t], [c1_plus_one], [c2], [c3_t], [c4] + 1);

        degree_01n3x_needs_reduction:
        return ([c0_t], [c1_plus_one_min_t], [c2_plus_one], [c3_t], [c4] + 1);

        degree_0n2xx_needs_reduction:
        let c3_plus_one = ap;
        [c3_plus_one] = [c3] + 1, ap++;
        let c3_plus_one_min_t = ap;
        [c3_plus_one_min_t] = [c3_t] + 1, ap++;
        tempvar degree_3_superior_to_t = is_nn([c3_plus_one_min_t]);
        jmp degree_0n23x_needs_reduction if degree_3_superior_to_t != 0;
        return ([c0_t], [c1_plus_one], [c2_t], [c3_plus_one], [c4]);

        degree_0n23x_needs_reduction:
        return ([c0_t], [c1_plus_one], [c2_t], [c3_plus_one_min_t], [c4] + 1);

        degree_012xx_needs_reduction:
        let c3_plus_one = ap;
        [c3_plus_one] = [c3] + 1, ap++;
        let c3_plus_one_min_t = ap;
        [c3_plus_one_min_t] = [c3_t] + 1, ap++;
        tempvar degree_3_superior_to_t = is_nn([c3_plus_one_min_t]);
        jmp degree_0123x_needs_reduction if degree_3_superior_to_t != 0;
        return ([c0_t], [c1_plus_one_min_t], [c2_plus_one_min_t], [c3_plus_one], [c4]);

        degree_0123x_needs_reduction:
        return ([c0_t], [c1_plus_one_min_t], [c2_plus_one_min_t], [c3_plus_one_min_t], [c4] + 1);
    }
    // Adds two polynomials of the form a(t) = a0 + a1*t + a2*t^2 + a3*t³ + a4*t⁴ with prelimnimary coefficient reduction
    // If c_i = a_i + b_i >= t for i = 0, 1, 2, 3, do c_i=c_i - t; c_i+1 = c_i+1 + 1;
    // This version tries to play with the prover for efficiency. However soundness is not guaranteed. See Todo.
    func add_a{range_check_ptr}(a: Polyfelt, b: Polyfelt) -> Polyfelt {
        alloc_locals;
        // BEGIN0
        // 3. c(t) = c(t) + a(t)bj
        local c00;
        local c10;
        local c20;
        local c30;
        local c40;
        local is_nn0;
        local is_nn1;
        local is_nn2;
        local is_nn3;
        // local is_nn0_inv;
        // local is_nn1_inv;
        // local is_nn2_inv;
        // local is_nn3_inv;

        let c0 = a.p00 + b.p00;
        let c1 = a.p10 + b.p10;
        let c2 = a.p20 + b.p20;
        let c3 = a.p30 + b.p30;
        let c4 = a.p40 + b.p40;

        %{
            is_superior_to_t=1 if (ids.c0) >= ids.t else 0
            ids.is_nn0 = is_superior_to_t
            ids.c00 = (ids.c0) - is_superior_to_t*ids.t
        %}
        %{
            is_superior_to_t=1 if (ids.c1) >= ids.t else 0
            ids.is_nn1 = is_superior_to_t
            ids.c10 = (ids.c1) - is_superior_to_t*ids.t
        %}
        %{
            is_superior_to_t=1 if (ids.c2) >= ids.t else 0                                            
            ids.is_nn2 = is_superior_to_t
            ids.c20 = (ids.c2) - is_superior_to_t*ids.t
        %}
        %{
            is_superior_to_t=1 if (ids.a.p30+ids.b.p30) >= ids.t else 0
            ids.is_nn3 = is_superior_to_t
            ids.c30 = (ids.c3) - is_superior_to_t*ids.t
        %}

        // assert is_nn0 * (1 - is_nn0) + is_nn1 * (1 - is_nn1) + is_nn2 * (1 - is_nn2) + is_nn3 * (1 - is_nn3) = 0;
        // assert all values are either 0 or 1
        assert is_nn0 * is_nn0 = is_nn0;
        assert is_nn1 * is_nn1 = is_nn1;
        assert is_nn2 * is_nn2 = is_nn2;
        assert is_nn3 * is_nn3 = is_nn3;

        // If is_nnx = 1, the prover cannot cheat as cx - t would be < 0,
        // so if the assert cx0 = cx - is_nnx*t passes,
        // the assert 4*t - c00 - c10 - c20 - c30 would be < 0 and program fails.
        // If is_nnx = 0, the prover cannot cheat by setting cx0 = cx when cx>t as cx - t would be > 0
        // so if the assert cx0 = cx passes,
        // the assert 4*t - c00 - c10 - c20 - c30 would be < 0 and program fails.

        // however, prover could cheat by setting is_nn = 0 and cx0 = cx, when cx is not a reduced value.
        // We need to prove the value is indeed not needed to be reduced.
        // If the prover cheat by setting is_nnx = 0 when the value is >=t, then t - cx0 < 0
        assert c00 = c0 - is_nn0 * t;
        let c00_inv = c0 - (1 - is_nn0) * t;
        assert c10 = c1 - is_nn1 * t;
        let c10_inv = c1 - (1 - is_nn1) * t;
        assert c20 = c2 - is_nn2 * t;
        let c20_inv = c2 - (1 - is_nn2) * t;
        assert c30 = c3 - is_nn3 * t;
        let c30_inv = c3 - (1 - is_nn3) * t;
        assert c40 = c4 + is_nn3;

        // sum only coefficients that are supposed to be reduced and check non negative
        // any wrongly reduced value would be < 0 (as is ~64 bits and prime 252 bits, any
        // wrongly reduced value would be would make this sum higher than range check bound
        assert [range_check_ptr] = c00 + c10 + c20 + c30;
        let range_check_ptr = range_check_ptr + 1;
        // TODO :
        // sum only coefficients that are supposed to not be reduced, reduce them and check non negative
        // tempvar sum_inferior_to_4t = is_nn(is_nn0 * c00 + is_nn1 * c10 + is_nn2 * c20 + is_nn3 * c30);
        // assert sum_inferior_to_4t = 1;
        return reduce_if_superior_to_P(c00, c10, c20, c30, c40);
    }

    // Adds two polynomials of the form a(t) = a0 + a1*t + a2*t^2 + a3*t³ + a4*t⁴ with prelimnimary coefficient reduction
    // If c_i = a_i + b_i >= t for i = 0, 1, 2, 3, do c_i=c_i - t; c_i+1 = c_i+1 + 1;
    func add_b{range_check_ptr}(a: Polyfelt, b: Polyfelt) -> Polyfelt {
        alloc_locals;
        local c00;
        local c10;
        local c20;
        local c30;
        local c40;
        local is_nn0;
        local is_nn1;
        local is_nn2;
        local is_nn3;
        let c0 = a.p00 + b.p00;
        let c1 = a.p10 + b.p10;
        let c2 = a.p20 + b.p20;
        let c3 = a.p30 + b.p30;
        let c4 = a.p40 + b.p40;
        assert is_nn0 = is_nn(c0 - t);
        assert c00 = c0 - is_nn0 * t;
        let c1 = c1 + is_nn0;
        assert is_nn1 = is_nn(c1 - t);
        assert c10 = c1 - is_nn1 * t;
        let c2 = c2 + is_nn1;
        assert is_nn2 = is_nn(c2 - t);
        assert c20 = c2 - is_nn2 * t;
        let c3 = c3 + is_nn2;
        assert is_nn3 = is_nn(c3 - t);
        assert c30 = c3 - is_nn3 * t;
        assert c40 = c4 + is_nn3;

        return reduce_if_superior_to_P(c00, c10, c20, c30, c40);
    }

    func add_c{range_check_ptr}(a: Polyfelt, b: Polyfelt) -> Polyfelt {
        alloc_locals;
        let (c00, c10, c20, c30, c40) = add_reduce_coeffs(a, b);
        return reduce_if_superior_to_P(c00, c10, c20, c30, c40);
    }
    // Substract P(t) coefficients to c(t) coefficients if c(t) >= P(t).
    // Assumes c00, ... c30 are reduced to < t.
    // Could be slightly optimized by a one or two low level steps.
    func reduce_if_superior_to_P{range_check_ptr}(c00, c10, c20, c30, c40) -> Polyfelt {
        if (c40 == 36) {
            if (c30 == 36) {
                if (c20 == 24) {
                    if (c10 == 6) {
                        if (c00 == 1) {
                            let res = Polyfelt(c00, c10, c20, c30, c40);
                            return res;
                        } else {
                            // Differs to P only on C00
                            if (c00 == 0) {
                                let res = Polyfelt(c00, c10, c20, c30, c40);
                                return res;
                            } else {
                                // It's higher than P
                                let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                                return res;
                            }
                        }
                    } else {
                        let is_c1_le_6 = is_nn(6 - c10);
                        if (is_c1_le_6 == 1) {
                            let res = Polyfelt(c00, c10, c20, c30, c40);
                            return res;
                        } else {
                            let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                            return res;
                        }
                    }
                } else {
                    let is_c2_le_24 = is_nn(24 - c20);
                    if (is_c2_le_24 == 1) {
                        let res = Polyfelt(c00, c10, c20, c30, c40);
                        return res;
                    } else {
                        let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                        return res;
                    }
                }
            } else {
                let is_c3_le_35 = is_nn(35 - c30);
                if (is_c3_le_35 == 1) {
                    let res = Polyfelt(c00, c10, c20, c30, c40);
                    return res;
                } else {
                    let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                    return res;
                }
            }
        } else {
            let is_c4_le_35 = is_nn(35 - c40);
            if (is_c4_le_35 == 1) {
                let res = Polyfelt(c00, c10, c20, c30, c40);
                return res;
            } else {
                // Handle special case a+b=2*p = 0 mod p
                if (c40 == 72) {
                    if (c30 == 72) {
                        if (c20 == 48) {
                            if (c10 == 12) {
                                if (c00 == 2) {
                                    let res = Polyfelt(0, 0, 0, 0, 0);
                                    return res;
                                } else {
                                    let res = Polyfelt(
                                        c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36
                                    );

                                    return res;
                                }
                            } else {
                                let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                                return res;
                            }
                        } else {
                            let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                            return res;
                        }
                    } else {
                        let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                        return res;
                    }
                } else {
                    let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
                    return res;
                }
            }
        }
    }

    // [DEAD] Tries to guess if c(t)>=P(t) and reduce c(t) by P(t) coefficients if so.
    // [DEAD] However, the implication c(x) > p(x) => c(t) >= P(t) is not true.
    func reduce_if_superior_to_P_blasted{range_check_ptr}(c00, c10, c20, c30, c40) -> Polyfelt {
        alloc_locals;
        let c_of_2_reduced = c00 + c10 * 2 + c20 * 4 + c30 * 8 + c40 * 16 - 973;
        // let c_reduced = c_of_2 - 973;
        let is_superior_to_p_of_2 = is_nn(c_of_2_reduced);
        if (is_superior_to_p_of_2 == 1) {
            let res = Polyfelt(c00 - 1, c10 - 6, c20 - 24, c30 - 36, c40 - 36);
            return res;
        } else {
            let res = Polyfelt(c00, c10, c20, c30, c40);
            return res;
        }
    }
    func mul{range_check_ptr}(a: Polyfelt, b: Polyfelt) -> Polyfelt {
        alloc_locals;
        // BEGIN0
        %{ print('BEGIN0 \n') %}

        // 3. c(t) = c(t) + a(t)bj
        let c00 = a.p00 * b.p00;
        // %{ print_felt_info(ids.c00, "c00") %}
        // 4. mu = c00 // 2**m, gamma = c00%2**m - s*mu
        // let (mu, gamma) = felt_divmod(c00, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c00, 2 ** 63);

        const s = 857;
        let gamma = gamma - s * mu;

        // 5. g(t) = p(t) * gamma
        let (qc00, rc00) = felt_divmod_no_input_check(c00 - gamma, 4965661367192848881);
        let c00 = qc00 + mu;
        // %{ print_felt_info(ids.c00, "c00") %}
        let c1000 = a.p10 * b.p00 - 6 * gamma + c00;
        let c2010 = a.p20 * b.p00 - 24 * gamma;
        let c3020 = a.p30 * b.p00 - 36 * gamma;
        let c4030 = a.p40 * b.p00;

        %{ print_felt_info(ids.c1000, "c1000") %}

        %{ print_felt_info(ids.c2010, "c2010") %}
        %{ print_felt_info(ids.c3020, "c3020") %}
        %{ print_felt_info(ids.c4030, "c4030") %}

        // BEGIN1
        %{ print('BEGIN1 \n') %}

        // 3. c(t) = c(t) + a(t)bj

        let c00 = c1000 + a.p00 * b.p10;
        // %{ print_felt_info(ids.c00, "c00") %}
        // 4. mu = c00 // 2**m, gamma = c00%2**m - s*mu
        // let (mu, gamma) = felt_divmod(c00, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c00, 2 ** 63);

        let gamma = gamma - s * mu;

        // 5. g(t) = p(t) * gamma
        let (qc00, rc00) = felt_divmod_no_input_check(c00 - gamma, 4965661367192848881);
        let c00 = qc00 + mu;
        // %{ print_felt_info(ids.c00, "c00") %}
        let c1000 = c2010 + a.p10 * b.p10 - 6 * gamma + qc00 + mu;
        let c2010 = c3020 + a.p20 * b.p10 - 24 * gamma;
        let c3020 = c4030 + a.p30 * b.p10 - 36 * gamma;
        let c4030 = a.p40 * b.p10;

        // let is_nnk = is_nn(c4030t);
        // local c4030;
        // if (is_nnk == 0) {
        //     assert c4030 = (-1) * c4030t;
        // } else {
        //     assert c4030 = c4030t;
        // }
        // %{ print_felt_info(ids.c1000, "c1000") %}
        // %{ print_felt_info(ids.c2010, "c2010") %}
        // %{ print_felt_info(ids.c3020, "c3020") %}
        %{ print_felt_info(ids.c4030, "c4030") %}

        // BEGIN2
        %{ print('BEGIN2 \n') %}

        // 3. c(t) = c(t) + a(t)bj

        let c00 = c1000 + a.p00 * b.p20;
        // %{ print_felt_info(ids.c00, "c00") %}
        // 4. mu = c00 // 2**m, gamma = c00%2**m - s*mu
        // let (mu, gamma) = felt_divmod(c00, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c00, 2 ** 63);
        let gamma = gamma - s * mu;

        // 5. g(t) = p(t) * gamma
        let (qc00, rc00) = felt_divmod_no_input_check(c00 - gamma, 4965661367192848881);
        let c00 = qc00 + mu;
        // %{ print_felt_info(ids.c00, "c00") %}
        let c1000 = c2010 + a.p10 * b.p20 - 6 * gamma + qc00 + mu;
        let c2010 = c3020 + a.p20 * b.p20 - 24 * gamma;
        let c3020 = c4030 + a.p30 * b.p20 - 36 * gamma;
        let c4030 = a.p40 * b.p20;
        // let is_nnk = is_nn(c4030t);
        // local c4030;
        // if (is_nnk == 0) {
        //     assert c4030 = (-1) * c4030t;
        // } else {
        //     assert c4030 = c4030t;
        // }

        // %{ print_felt_info(ids.c1000, "c1000") %}

        // %{ print_felt_info(ids.c2010, "c2010") %}
        // %{ print_felt_info(ids.c3020, "c3020") %}
        %{ print_felt_info(ids.c4030, "c4030") %}

        // BEGIN3
        %{ print('\n BEGIN3 \n') %}
        // 3. c(t) = c(t) + a(t)bj

        let c00 = c1000 + a.p00 * b.p30;
        // %{ print_felt_info(ids.c00, "c00") %}

        let (mu, gamma) = felt_divmod_no_input_check(c00, 2 ** 63);

        let gamma = gamma - s * mu;

        // 5. g(t) = p(t) * gamma
        let (qc00, rc00) = felt_divmod_no_input_check(c00 - gamma, 4965661367192848881);
        let c00 = qc00 + mu;
        // %{ print_felt_info(ids.c00, "c00") %}
        let c1000 = c2010 + a.p10 * b.p30 - 6 * gamma + qc00 + mu;
        let c2010 = c3020 + a.p20 * b.p30 - 24 * gamma;
        let c3020 = c4030 + a.p30 * b.p30 - 36 * gamma;
        let c4030 = a.p40 * b.p30;
        // let is_nnk = is_nn(c4030t);
        // local c4030;
        // if (is_nnk == 0) {
        //     assert c4030 = (-1) * c4030t;
        // } else {
        //     assert c4030 = c4030t;
        // }

        // %{ print_felt_info(ids.c1000, "c1000") %}

        // %{ print_felt_info(ids.c2010, "c2010") %}
        // %{ print_felt_info(ids.c3020, "c3020") %}
        %{ print_felt_info(ids.c4030, "c4030") %}

        // BEGIN4

        %{ print('\n BEGIN4\n ') %}

        // 3. c(t) = c(t) + a(t)bj

        let c00 = c1000 + a.p00 * b.p40;
        // %{ print_felt_info(ids.c00, "c00") %}
        // 4. mu = c00 // 2**m, gamma = c00%2**m - s*mu
        // let (mu, gamma) = felt_divmod(c00, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c00, 2 ** 63);

        let gamma = gamma - s * mu;

        // 5. g(t) = p(t) * gamma
        let (qc00, rc00) = felt_divmod_no_input_check(c00 - gamma, 4965661367192848881);

        let c00 = qc00 + mu;
        // %{ print_felt_info(ids.c00, "c00") %}
        let c1000 = c2010 + a.p10 * b.p40 - 6 * gamma + qc00 + mu;
        let c2010 = c3020 + a.p20 * b.p40 - 24 * gamma;
        let c3020 = c4030 + a.p30 * b.p40 - 36 * gamma;

        let c4030 = a.p40 * b.p40;
        // let is_nnk = is_nn(c4030t);
        // local c4030;
        // if (is_nnk == 0) {
        //     assert c4030 = (-1) * c4030t;
        // } else {
        //     assert c4030 = c4030t;
        // }

        // %{ print_felt_info(ids.c1000, "c1000") %}
        // %{ print_felt_info(ids.c2010, "c2010") %}
        // %{ print_felt_info(ids.c3020, "c3020") %}
        %{ print_felt_info(ids.c4030, "c4030") %}

        // BEGIN 0
        // let (mu, gamma) = felt_divmod(c1000, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c1000, 2 ** 63);

        let c00 = gamma - s * mu;
        let c10 = c2010 + mu;
        // BEGIN 1
        // let (mu, gamma) = felt_divmod(c10, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c10, 2 ** 63);

        let c10 = gamma - s * mu;
        let c20 = c3020 + mu;
        // BEGIN 2
        // let (mu, gamma) = felt_divmod(c20, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c20, 2 ** 63);

        let c20 = gamma - s * mu;
        let c30 = c4030 + mu;
        // BEGIN 3
        // let (mu, gamma) = felt_divmod(c30, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c30, 2 ** 63);

        let c30 = gamma - s * mu;
        let c40 = mu;

        // BEGIN 0
        // let (mu, gamma) = felt_divmod(c1000, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c00, 2 ** 63);
        let c00 = gamma - s * mu;
        let c10 = c10 + mu;

        // BEGIN 1
        // let (mu, gamma) = felt_divmod(c10, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c10, 2 ** 63);
        let c10 = gamma - s * mu;
        let c20 = c20 + mu;
        // BEGIN 2
        // let (mu, gamma) = felt_divmod(c20, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c20, 2 ** 63);
        let c20 = gamma - s * mu;
        let c30 = c30 + mu;
        // BEGIN 3
        // let (mu, gamma) = felt_divmod(c30, 2 ** 63);
        let (mu, gamma) = felt_divmod_no_input_check(c30, 2 ** 63);
        let c30 = gamma - s * mu;
        let c40 = c40 + mu;

        %{
        %}
        let res = Polyfelt(c00, c10, c20, c30, c40);
        return res;
    }
}

namespace fq {
    // Computes a + b modulo bn254 prime
    // Assumes a+b < 2^256. If a and b both < PRIME, it is ok.
    func slow_add{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        let sum = u255.add(a, b);
        return u255.a_modulo_bn254p(sum);  // uses unsigned div remainder and mul for verification
    }

    // a and b must both be < P
    func add{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        let P = Uint256(P_low, P_high);
        // assert_uint256_le(a, P);
        // assert_uint256_le(b, P);
        let sum: Uint256 = u255.add(a, b);

        let (is_le) = uint256_lt(P, sum);
        if (is_le == 1) {
            let res = u255.sub_b(sum, P);
            return res;
        } else {
            return sum;
        }
    }
    // a+b mod p fast
    func add_fast{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        alloc_locals;
        local needs_reduction;
        let P = Uint256(P_low, P_high);
        let sum: Uint256 = u255.add(a, b);

        %{
            sum=ids.sum.low + ids.sum.high *2**128 
            ids.needs_reduction = 1 if sum>=0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47 else 0
        %}

        if (sum.high == P_high) {
            if (needs_reduction == 1) {
                assert [range_check_ptr] = sum.low - P_low;
                let range_check_ptr = range_check_ptr + 1;
                let res = u255.sub_b(sum, P);
                return res;
            } else {
                assert [range_check_ptr] = P_low - sum.low - 1;
                let range_check_ptr = range_check_ptr + 1;
                return sum;
            }
        } else {
            if (needs_reduction == 1) {
                assert [range_check_ptr] = sum.high - P_high;
                let range_check_ptr = range_check_ptr + 1;
                let res = u255.sub_b(sum, P);
                return res;
            } else {
                assert [range_check_ptr] = P_high - sum.high - 1;
                let range_check_ptr = range_check_ptr + 1;
                return sum;
            }
        }
    }
    // a+b mod p fastest.
    func add_blasted{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        alloc_locals;
        local has_carry_low;
        local sum: Uint256;
        local needs_reduction;
        local res: Uint256;

        let P = Uint256(P_low, P_high);

        let sum_low = a.low + b.low;
        let sum_high = a.high + b.high;

        %{ ids.has_carry_low = 1 if ids.sum_low >= ids.SHIFT else 0 %}

        if (has_carry_low == 1) {
            assert [range_check_ptr] = sum_low - SHIFT;
            let range_check_ptr = range_check_ptr + 1;
            assert sum.low = sum_low - SHIFT;
            assert sum.high = sum_high + 1;
        } else {
            assert [range_check_ptr] = sum_low;
            assert sum.low = sum_low;
            assert sum.high = sum_high;
            let range_check_ptr = range_check_ptr + 1;
        }

        %{
            sum=ids.sum.low + ids.sum.high *2**128 
            ids.needs_reduction = 1 if sum>=0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47 else 0
        %}

        if (sum.high == P_high) {
            if (needs_reduction != 0) {
                assert [range_check_ptr] = sum.low - P_low;
                let range_check_ptr = range_check_ptr + 1;
                let res = Uint256(sum.low - P_low, sum.high - P_high);
                return res;
            } else {
                assert [range_check_ptr] = P_low - sum.low - 1;
                let range_check_ptr = range_check_ptr + 1;
                return sum;
            }
        } else {
            if (needs_reduction != 0) {
                assert [range_check_ptr] = sum.high - P_high;
                let range_check_ptr = range_check_ptr + 1;
                let res = Uint256(sum.low - P_low, sum.high - P_high);
                return res;
            } else {
                assert [range_check_ptr] = P_high - sum.high - 1;
                let range_check_ptr = range_check_ptr + 1;
                return sum;
            }
        }
    }
    // Computes (a - b) modulo p .
    // NOTE: Expects a and b to be reduced modulo p (i.e. between 0 and p-1). The function will revert if a > p.
    // NOTE: To reduce a, take the remainder of uint384_lin.unsigned_div_rem(a, p), and similarly for b.
    // @dev First it computes res =(a-b) mod p in a hint and then checks outside of the hint that res + b = a modulo p
    func sub{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        alloc_locals;
        local res: Uint256;
        local p: Uint256 = Uint256(P_low, P_high);
        %{
            def split(num: int, num_bits_shift: int, length: int):
                a = []
                for _ in range(length):
                    a.append( num & ((1 << num_bits_shift) - 1) )
                    num = num >> num_bits_shift
                return tuple(a)

            def pack(z) -> int:
                return z.low + (z.high << 128)

            a = pack(ids.a)
            b = pack(ids.b)
            p = pack(ids.p)

            res = (a - b) % p

            res_split = split(res, num_bits_shift=128, length=2)

            ids.res.low = res_split[0]
            ids.res.high = res_split[1]
        %}
        %{ print_u_256_info(ids.res, "res") %}

        let b_plus_res: Uint256 = add(b, res);
        assert b_plus_res = a;
        return res;
    }
    // Computes a * b modulo p
    func mul{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        let full_mul_result: Uint512 = u255.mul(a, b);
        // %{ print_u_512_info(ids.full_mul_result, 'full_mul') %}
        return u512_modulo_bn254p(full_mul_result);
    }

    // Computes 2*a*b modulo p
    func mul2ab{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        let full_mul_result: Uint512 = u255.mul2ab(a, b);
        // %{ print_u_512_info(ids.full_mul_result, 'full_mul2') %}
        return u512_modulo_bn254p(full_mul_result);
    }
    func mul_blasted{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        let (a_big: BigInt3) = uint256_to_bigint(a);
        let (b_big: BigInt3) = uint256_to_bigint(b);
        let mul: UnreducedBigInt5 = bigint_mul(a_big, b_big);
        %{
            from starkware.cairo.common.cairo_secp.secp_utils import pack

            p = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mul = ids.mul.d0 + ids.mul.d1*2**86 + ids.mul.d2*2**172 + ids.mul.d3*2**258 + ids.mul.d4*2**344
            value = mul%p
        %}
        let (result: BigInt3) = nondet_bigint3();
        verify_zero5(
            UnreducedBigInt5(
                d0=mul.d0 - result.d0,
                d1=mul.d1 - result.d1,
                d2=mul.d2 - result.d2,
                d3=mul.d3,
                d4=mul.d4,
            ),
        );
        let (res: Uint256) = bigint_to_uint256(result);
        return res;
    }
    // Computes a*a modulo p
    func square{range_check_ptr}(a: Uint256) -> Uint256 {
        let full_mul_result: Uint512 = u255.square(a);
        // %{ print_u_512_info(ids.full_mul_result, 'full_mul2') %}
        return u512_modulo_bn254p(full_mul_result);
    }
    // Computes 2*a*a modulo p
    func square2{range_check_ptr}(a: Uint256) -> Uint256 {
        let full_mul_result: Uint512 = u255.square(a);
        let full_mul_result = u255.double_u511(full_mul_result);
        // %{ print_u_512_info(ids.full_mul_result, 'full_mul2') %}
        return u512_modulo_bn254p(full_mul_result);
    }

    func fast_u512_modulo_bn254p{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
        x: Uint512
    ) -> Uint256 {
        alloc_locals;
        let P = Uint256(P_low, P_high);
        // let d2_bl = get_felt_bitlength(x.d2);

        // let n = pow2(d2_bl);
        // let n2 = pow2(d2_bl - 3);

        // splits first 3 bits (word/2**125) and last (word2)
        assert bitwise_ptr[0].x = x.d2;
        assert bitwise_ptr[0].y = 2 ** 128 - 2 ** 125;  // 2**bl-(2**(bl-3)-1) or 2**128-(2**125-1)

        assert bitwise_ptr[1].x = x.d2;
        assert bitwise_ptr[1].y = 2 ** 125 - 1;

        tempvar word = bitwise_ptr[0].x_and_y;
        tempvar word1 = bitwise_ptr[0].x_or_y - 1;
        tempvar word2 = bitwise_ptr[1].x_and_y;  // x_mod_2**3s

        // let ww = word - 2 ** 125 + 1;
        // let ww2 = x.d2 - 2 ** 126 - 2 ** 125 + 1;  //
        let x_div_23s: felt = x.d3 * 2 ** 3 + word / 2 ** 125;

        %{ print_felt_info(ids.x.d2, 'd2') %}

        %{ print_felt_info(ids.word, 'word') %}
        %{ print_felt_info(ids.word1, 'word1') %}

        %{ print_felt_info(ids.word2, 'word2') %}

        // %{ print_felt_info(ids.ww2, 'ww2') %}

        %{ print_felt_info(ids.x_div_23s, 'x_div_32s') %}
        // parse 3 high bits (cut at 381) of x.d2, multiply x.d3*2**3 + x.d2 high 3 bits
        let M_temp: Uint384 = u255.mul_M_by_u128(x_div_23s);
        local X_mod_23s: Uint384 = Uint384(x.d0, x.d1, word2);

        %{
            def pack(z, num_bits_shift: int) -> int:
                limbs = (z.d0, z.d1, z.d2)
                print(z.d0.bit_length(), z.d1.bit_length(), z.d2.bit_length())
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))
            o=pack(ids.X_mod_23s, 128)
            print('X_mod_32s', o, o.bit_length())
        %}
        let N: Uint384 = uint384_lib._add_no_uint384_check(M_temp, X_mod_23s);
        %{
            o=pack(ids.N, 128)
            print('N', o, o.bit_length())
        %}
        %{ assert ids.N.d2.bit_length()<128 %}

        assert bitwise_ptr[2].x = N.d1;
        assert bitwise_ptr[2].y = 2 ** 128 - 2 ** 126;
        tempvar word3 = bitwise_ptr[2].x_and_y;
        %{ print_felt_info(ids.word3, 'word3') %}

        let N_div_22s: felt = N.d2 * 2 ** 2 + word3 / 2 ** 126;  // + word3 - 2 ** 126 + 1;
        %{ print_felt_info(ids.N_div_22s, "n_div_254") %}

        let bitwise_ptr = bitwise_ptr + 3 * BitwiseBuiltin.SIZE;

        let T_mu_high: felt = u255.mul_mu_by_u128(N_div_22s);
        %{ print_felt_info(ids.T_mu_high, 'T_mu_high') %}
        let T_P: Uint384 = u255.mul_P_by_u128(T_mu_high);

        %{
            o=pack(ids.T_P, 128)
            print('T_P', o, o.bit_length())
        %}
        let R: Uint384 = uint384_lib.sub_b(N, T_P);
        %{
            o=pack(ids.R, 128)
            print('R', o, o.bit_length())
        %}
        // assert R.d2 = 0;
        let res = Uint256(R.d0, R.d1);
        let (is_le) = uint256_lt(P, res);
        if (is_le == 1) {
            let reduced = u255.sub_b(res, P);
            return reduced;
        } else {
            return res;
        }
    }

    func u512_modulo_bn254p{range_check_ptr}(x: Uint512) -> Uint256 {
        alloc_locals;
        local quotient: Uint512;
        local remainder: Uint256;
        local div: Uint256 = Uint256(P_low, P_high);
        %{
            def split(num: int, num_bits_shift: int, length: int):
                a = []
                for _ in range(length):
                    a.append( num & ((1 << num_bits_shift) - 1) )
                    num = num >> num_bits_shift 
                return tuple(a)

            def pack(z, num_bits_shift: int) -> int:
                limbs = (z.low, z.high)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))
                
            def pack_extended(z, num_bits_shift: int) -> int:
                limbs = (z.d0, z.d1, z.d2, z.d3)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            x = pack_extended(ids.x, num_bits_shift = 128)
            div = pack(ids.div, num_bits_shift = 128)

            quotient, remainder = divmod(x, div)

            quotient_split = split(quotient, num_bits_shift=128, length=4)

            ids.quotient.d0 = quotient_split[0]
            ids.quotient.d1 = quotient_split[1]
            ids.quotient.d2 = quotient_split[2]
            ids.quotient.d3 = quotient_split[3]

            remainder_split = split(remainder, num_bits_shift=128, length=2)
            ids.remainder.low = remainder_split[0]
            ids.remainder.high = remainder_split[1]
        %}

        let res_mul: Uint768 = u255.mul_u512_by_u256(quotient, div);

        assert res_mul.d4 = 0;
        assert res_mul.d5 = 0;

        let check_val: Uint512 = u255.add_u512_and_u256(
            Uint512(res_mul.d0, res_mul.d1, res_mul.d2, res_mul.d3), remainder
        );

        // assert add_carry = 0;
        assert check_val = x;

        let is_valid = u255.lt(remainder, div);
        assert is_valid = 1;

        return remainder;
    }

    func u512_unsigned_div_rem{range_check_ptr}(x: Uint512, div: Uint256) -> (
        q: Uint512, r: Uint256
    ) {
        alloc_locals;
        local quotient: Uint512;
        local remainder: Uint256;

        %{
            def split(num: int, num_bits_shift: int, length: int):
                a = []
                for _ in range(length):
                    a.append( num & ((1 << num_bits_shift) - 1) )
                    num = num >> num_bits_shift 
                return tuple(a)

            def pack(z, num_bits_shift: int) -> int:
                limbs = (z.low, z.high)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))
                
            def pack_extended(z, num_bits_shift: int) -> int:
                limbs = (z.d0, z.d1, z.d2, z.d3)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            x = pack_extended(ids.x, num_bits_shift = 128)
            div = pack(ids.div, num_bits_shift = 128)

            quotient, remainder = divmod(x, div)

            quotient_split = split(quotient, num_bits_shift=128, length=4)

            ids.quotient.d0 = quotient_split[0]
            ids.quotient.d1 = quotient_split[1]
            ids.quotient.d2 = quotient_split[2]
            ids.quotient.d3 = quotient_split[3]

            remainder_split = split(remainder, num_bits_shift=128, length=2)
            ids.remainder.low = remainder_split[0]
            ids.remainder.high = remainder_split[1]
        %}

        let res_mul: Uint768 = u255.mul_u512_by_u256(quotient, div);

        assert res_mul.d4 = 0;
        assert res_mul.d5 = 0;

        let check_val: Uint512 = u255.add_u512_and_u256(
            Uint512(res_mul.d0, res_mul.d1, res_mul.d2, res_mul.d3), remainder
        );

        // assert add_carry = 0;
        assert check_val = x;

        let is_valid = u255.lt(remainder, div);
        assert is_valid = 1;

        return (quotient, remainder);
    }
    func inv_mod_p_uint512{range_check_ptr}(x: Uint512) -> Uint256 {
        alloc_locals;
        local x_inverse_mod_p: Uint256;
        local p: Uint256 = Uint256(P_low, P_high);
        // To whitelist
        %{
            def pack_512(u, num_bits_shift: int) -> int:
                limbs = (u.d0, u.d1, u.d2, u.d3)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            x = pack_512(ids.x, num_bits_shift = 128)
            p = ids.p.low + (ids.p.high << 128)
            x_inverse_mod_p = pow(x,-1, p) 

            x_inverse_mod_p_split = (x_inverse_mod_p & ((1 << 128) - 1), x_inverse_mod_p >> 128)

            ids.x_inverse_mod_p.low = x_inverse_mod_p_split[0]
            ids.x_inverse_mod_p.high = x_inverse_mod_p_split[1]
        %}

        let x_times_x_inverse: Uint768 = u255.mul_u512_by_u256(
            x, Uint256(x_inverse_mod_p.low, x_inverse_mod_p.high)
        );
        let x_times_x_inverse_mod_p = u255.u768_modulo_p(x_times_x_inverse);
        assert x_times_x_inverse_mod_p = Uint256(1, 0);

        return x_inverse_mod_p;
    }
    // Computes a * b^{-1} modulo p
    // NOTE: The modular inverse of b modulo p is computed in a hint and verified outside the hind with a multiplicaiton
    func div{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        alloc_locals;
        local p: Uint256 = Uint256(P_low, P_high);
        local b_inverse_mod_p: Uint256;
        // To whitelist
        %{
            from starkware.python.math_utils import div_mod

            def split(a: int):
                return (a & ((1 << 128) - 1), a >> 128)

            def pack(z, num_bits_shift: int) -> int:
                limbs = (z.low, z.high)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            a = pack(ids.a, 128)
            b = pack(ids.b, 128)
            p = pack(ids.p, 128)
            # For python3.8 and above the modular inverse can be computed as follows:
            # b_inverse_mod_p = pow(b, -1, p)
            # Instead we use the python3.7-friendly function div_mod from starkware.python.math_utils
            b_inverse_mod_p = div_mod(1, b, p)

            b_inverse_mod_p_split = split(b_inverse_mod_p)

            ids.b_inverse_mod_p.low = b_inverse_mod_p_split[0]
            ids.b_inverse_mod_p.high = b_inverse_mod_p_split[1]
        %}
        let b_times_b_inverse = mul(b, b_inverse_mod_p);
        assert b_times_b_inverse = Uint256(1, 0);

        let res: Uint256 = mul(a, b_inverse_mod_p);
        return res;
    }

    // Computes (a**exp) % p. Using the exponentiation by squaring algorithm, so it takes at most 256 squarings: https://en.wikipedia.org/wiki/Exponentiation_by_squaring
    func pow{range_check_ptr}(a: Uint256, exp: Uint256) -> Uint256 {
        alloc_locals;
        let is_exp_zero = u255.eq(exp, Uint256(0, 0));

        if (is_exp_zero == 1) {
            let o = Uint256(1, 0);
            return o;
        }

        let is_exp_one = u255.eq(exp, Uint256(1, 0));
        if (is_exp_one == 1) {
            // If exp = 1, it is possible that `a` is not reduced mod p,
            // so we check and reduce if necessary
            let is_a_lt_p = u255.lt(a, Uint256(P_low, P_high));
            if (is_a_lt_p == 1) {
                return a;
            } else {
                let remainder = u255.a_modulo_bn254p(a);
                return remainder;
            }
        }

        let (exp_div_2, remainder) = u255.unsigned_div_rem(exp, Uint256(2, 0));
        let is_remainder_zero = u255.eq(remainder, Uint256(0, 0));

        if (is_remainder_zero == 1) {
            // NOTE: Code is repeated in the if-else to avoid declaring a_squared as a local variable
            let a_squared_mod_p: Uint256 = square(a);
            let res = pow(a_squared_mod_p, exp_div_2);
            return res;
        } else {
            let a_squared_mod_p: Uint256 = square(a);
            let res = pow(a_squared_mod_p, exp_div_2);
            let res_mul = mul(a, res);
            return res_mul;
        }
    }
    // Finds a square of x in F_p, i.e. x ≅ y**2 (mod p) for some y
    // To do so, the following is done in a hint:
    // 0. Assume x is not  0 mod p
    // 1. Check if x is a square, if yes, find a square root r of it
    // 2. If (and only if not), then gx *is* a square (for g a generator of F_p^*), so find a square root r of it
    // 3. Check in Cairo that r**2 = x (mod p) or r**2 = gx (mod p), respectively
    // NOTE: The function assumes that 0 <= x < p
    // func get_square_root{range_check_ptr}(x: Uint256) -> (success: felt, res: Uint256) {
    //     alloc_locals;

    // // TODO: Create an equality function within field_arithmetic to avoid overflow bugs
    //     let is_zero = u255.eq(x, Uint256(0, 0));
    //     if (is_zero == 1) {
    //         return (1, Uint256(0, 0));
    //     }
    //     // let x = Uint384(x.low, x.high, 0);
    //     local p: Uint256 = Uint256(P_low, P_high);

    // local generator: Uint256 = Uint256(P_min_1_div_2_low, P_min_1_div_2_high);
    //     local success_x: felt;
    //     local success_gx: felt;
    //     local sqrt_x: Uint256;
    //     local sqrt_gx: Uint256;

    // // Compute square roots in a hint
    //     // To whitelist
    //     %{
    //         from starkware.python.math_utils import is_quad_residue, sqrt

    // def split(a: int):
    //             return (a & ((1 << 128) - 1), a >> 128)

    // def pack(z) -> int:
    //             return z.low + (z.high << 128)

    // generator = pack(ids.generator)
    //         x = pack(ids.x)
    //         p = pack(ids.p)

    // success_x = is_quad_residue(x, p)
    //         root_x = sqrt(x, p) if success_x else None
    //         success_gx = is_quad_residue(generator*x, p)
    //         root_gx = sqrt(generator*x, p) if success_gx else None

    // # Check that one is 0 and the other is 1
    //         if x != 0:
    //             assert success_x + success_gx == 1

    // # `None` means that no root was found, but we need to transform these into a felt no matter what
    //         if root_x == None:
    //             root_x = 0
    //         if root_gx == None:
    //             root_gx = 0
    //         ids.success_x = int(success_x)
    //         ids.success_gx = int(success_gx)
    //         split_root_x = split(root_x)
    //         print('split root x', split_root_x)
    //         split_root_gx = split(root_gx)
    //         ids.sqrt_x.low = split_root_x[0]
    //         ids.sqrt_x.high = split_root_x[1]
    //         ids.sqrt_gx.low = split_root_gx[0]
    //         ids.sqrt_gx.high = split_root_gx[1]
    //     %}

    // // Verify that the values computed in the hint are what they are supposed to be
    //     %{ print_u_256_info(ids.sqrt_x, 'root') %}
    //     let gx: Uint256 = mul(generator, x);
    //     if (success_x == 1) {
    //         let sqrt_x_squared: Uint256 = mul(sqrt_x, sqrt_x);

    // // Note these checks may fail if the input x does not satisfy 0<= x < p
    //         // TODO: Create a equality function within field_arithmetic to avoid overflow bugs
    //         let check_x = u255.eq(x, sqrt_x_squared);
    //         assert check_x = 1;
    //     } else {
    //         // In this case success_gx = 1
    //         let sqrt_gx_squared: Uint256 = mul(sqrt_gx, sqrt_gx);
    //         let check_gx = u255.eq(gx, sqrt_gx_squared);
    //         assert check_gx = 1;
    //     }

    // // Return the appropriate values
    //     if (success_x == 0) {
    //         // No square roots were found
    //         // Note that Uint256(0, 0) is not a square root here, but something needs to be returned
    //         return (0, Uint256(0, 0));
    //     } else {
    //         return (1, sqrt_x);
    //     }
    // }

    // TODO: not tested
    // RIght now thid function expects a and be to be between 0 and p-1
    func eq{range_check_ptr}(a: Uint256, b: Uint256) -> (res: felt) {
        let (is_a_eq_b) = u255.eq(a, b);
        return (is_a_eq_b,);
    }

    // TODO: not tested
    func is_zero{range_check_ptr}(a: Uint256) -> (bool: felt) {
        let (is_a_zero) = u255.eq(a, Uint256(0, 0));
        if (is_a_zero == 1) {
            return (1,);
        } else {
            return (0,);
        }
    }
}
