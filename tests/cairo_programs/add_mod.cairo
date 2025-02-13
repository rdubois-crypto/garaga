%builtins output range_check bitwise

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256
from src.fq import fq, fq_poly, Polyfelt, fq_bigint3
from src.u255 import Uint512
from starkware.cairo.common.cairo_secp.bigint import (
    BigInt3,
    uint256_to_bigint,
    bigint_to_uint256,
    UnreducedBigInt5,
    bigint_mul,
    nondet_bigint3,
)

func main{output_ptr: felt*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    // __setup__();
    %{
        def bin_c(u):
            b=bin(u)
            f = b[0:10] + ' ' + b[10:19] + '...' + b[-16:-8] + ' ' + b[-8:]
            return f

        def bin_64(u):
            b=bin(u)
            little = '0b'+b[2:][::-1]
            f='0b'+' '.join([b[2:][i:i+64] for i in range(0, len(b[2:]), 64)])
            return f
        def bin_8(u):
            b=bin(u)
            little = '0b'+b[2:][::-1]
            f="0b"+' '.join([little[2:][i:i+8] for i in range(0, len(little[2:]), 8)])
            return f

        def print_u_256_info(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un}_{u.bit_length()}bits = {bin_c(u)}")
            print(f" {un} = {u}")

        def print_felt_info(u, un):
            print(f" {un}_{u.bit_length()}bits = {bin_8(u)}")
            print(f" {un} = {u}")
            #print(f" {un} = {int.to_bytes(u, 8, 'little')}")

        def evaluate(p, un):
            t=4965661367192848881
            stark=3618502788666131213697322783095070105623107215331596699973092056135872020481
            return print_felt_info(p.p00 + p.p10*t+ p.p20*t**2+p.p30*t**3 + p.p40*t**4, un)
    %}
    alloc_locals;
    let X = Uint256(
        201385395114098847380338600778089168076, 64323764613183177041862057485226039389
    );
    let Y = Uint256(75392519548959451050754627114999798041, 55134655382728437464453192130193748048);
    let res: Uint256 = fq.slow_add(X, Y);
    let res0: Uint256 = fq.add(X, Y);
    let res1: Uint256 = fq.add_fast(X, Y);
    let res2 = fq.add_blasted(X, Y);
    let (X_bigint) = uint256_to_bigint(X);
    let (Y_bigint) = uint256_to_bigint(Y);
    let res3 = fq_bigint3.add(X_bigint, Y_bigint);

    return ();
}
