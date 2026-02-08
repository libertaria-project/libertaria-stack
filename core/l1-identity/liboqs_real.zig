//! liboqs Real Bindings - C FFI to liboqs library
//!
//! This module provides real liboqs bindings when liboqs is linked.
//! Use -Denable-liboqs=true when building to enable post-quantum crypto.

const std = @import("std");

/// ML-KEM-768 key generation
pub extern "c" fn OQS_KEM_ml_kem_768_keypair(
    public_key: [*]u8,
    secret_key: [*]u8,
) c_int;

/// ML-KEM-768 encapsulation (creates shared secret + ciphertext)
pub extern "c" fn OQS_KEM_ml_kem_768_encaps(
    ciphertext: [*]u8,
    shared_secret: [*]u8,
    public_key: [*]const u8,
) c_int;

/// ML-KEM-768 decapsulation (recovers shared secret from ciphertext)
pub extern "c" fn OQS_KEM_ml_kem_768_decaps(
    shared_secret: [*]u8,
    ciphertext: [*]const u8,
    secret_key: [*]const u8,
) c_int;

/// Switch liboqs RNG algorithm (e.g., "system", "nist-kat")
pub extern "c" fn OQS_randombytes_switch_algorithm(algorithm: [*:0]const u8) c_int;

/// Set custom RNG callback
pub extern "c" fn OQS_randombytes_custom_algorithm(algorithm_ptr: *const fn ([*]u8, usize) callconv(.c) void) void;

/// Check if liboqs is available (runtime check)
pub fn isAvailable() bool {
    return true;
}
