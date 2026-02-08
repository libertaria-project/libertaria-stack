//! liboqs Stub - Fallback when liboqs isn't available
//!
//! This module provides stub implementations that return errors
//! when liboqs is not linked. This allows the code to compile
//! but PQXDH will fail at runtime with clear errors.
//!
//! For production builds, link liboqs for post-quantum security.

const std = @import("std");

// Return error codes that indicate liboqs is not available
pub const OQS_SUCCESS = 0;
pub const OQS_ERROR = -1;

/// Stub: ML-KEM-768 key generation (returns error)
pub export fn OQS_KEM_ml_kem_768_keypair(public_key: [*]u8, secret_key: [*]u8) c_int {
    _ = public_key;
    _ = secret_key;
    std.log.err("liboqs not linked: ML-KEM-768 unavailable. Build with -Denable-liboqs=true", .{});
    return OQS_ERROR;
}

/// Stub: ML-KEM-768 encapsulation (returns error)
pub export fn OQS_KEM_ml_kem_768_encaps(ciphertext: [*]u8, shared_secret: [*]u8, public_key: [*]const u8) c_int {
    _ = ciphertext;
    _ = shared_secret;
    _ = public_key;
    std.log.err("liboqs not linked: ML-KEM-768 unavailable. Build with -Denable-liboqs=true", .{});
    return OQS_ERROR;
}

/// Stub: ML-KEM-768 decapsulation (returns error)
pub export fn OQS_KEM_ml_kem_768_decaps(shared_secret: [*]u8, ciphertext: [*]const u8, secret_key: [*]const u8) c_int {
    _ = shared_secret;
    _ = ciphertext;
    _ = secret_key;
    std.log.err("liboqs not linked: ML-KEM-768 unavailable. Build with -Denable-liboqs=true", .{});
    return OQS_ERROR;
}

/// Stub: Switch RNG algorithm (no-op)
pub export fn OQS_randombytes_switch_algorithm(algorithm: [*:0]const u8) c_int {
    _ = algorithm;
    return OQS_SUCCESS;
}

/// Stub: Set custom RNG callback (no-op)
pub export fn OQS_randombytes_custom_algorithm(algorithm_ptr: *const fn ([*]u8, usize) callconv(.c) void) void {
    _ = algorithm_ptr;
}

/// Check if liboqs is available (runtime check)
pub fn isAvailable() bool {
    return false;
}
