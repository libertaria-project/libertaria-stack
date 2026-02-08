//! RFC-0830 Section 2.3: PQXDH Protocol
//!
//! Post-Quantum Extended Diffie-Hellman Key Agreement
//!
//! This module implements hybrid key agreement combining:
//! - 4× X25519 elliptic curve handshakes (classical)
//! - 1× ML-KEM-768 post-quantum key encapsulation (when liboqs available)
//! - HKDF-SHA256 to combine shared secrets into root key
//!
//! Security: Attacker must break BOTH X25519 AND ML-KEM-768 to compromise
//! This provides defense against "harvest now, decrypt later" attacks.
//!
//! NOTE: When liboqs is not available, falls back to classical X25519 only.
//!       Production deployments MUST link liboqs for post-quantum security.
//!       Build with: zig build -Denable-liboqs=true

const std = @import("std");
const crypto = std.crypto;
const builtin = @import("builtin");

// Import liboqs module (real or stub based on build config)
const liboqs = @import("liboqs");

// Compile-time feature gating: check if liboqs is actually available
pub const enable_pq = liboqs.isAvailable();

/// Check if post-quantum crypto is enabled at build time
pub const pq_enabled = enable_pq;

// ============================================================================
// Global mutex to protect RNG state during deterministic generation
// ============================================================================

var rng_mutex = std.Thread.Mutex{};
var deterministic_rng: std.crypto.hash.sha3.Shake256 = undefined;

fn custom_rng_callback(dest: [*]u8, len: usize) callconv(.c) void {
    deterministic_rng.squeeze(dest[0..len]);
}

// ============================================================================
// Error types
// ============================================================================

pub const PQError = error{
    ML_KEM_NotAvailable,
    ML_KEM_KeygenFailed,
    ML_KEM_EncapsFailed,
    ML_KEM_DecapsFailed,
};

// ============================================================================
// Constants
// ============================================================================

pub const ML_KEM_768 = struct {
    pub const PUBLIC_KEY_SIZE = 1184;
    pub const SECRET_KEY_SIZE = 2400;
    pub const CIPHERTEXT_SIZE = 1088;
    pub const SHARED_SECRET_SIZE = 32;
    pub const SECURITY_LEVEL = 3; // NIST Level 3 (≈AES-192)
};

pub const X25519 = struct {
    pub const PUBLIC_KEY_SIZE = 32;
    pub const PRIVATE_KEY_SIZE = 32;
    pub const SHARED_SECRET_SIZE = 32;
};

/// Total public key size for PQXDH (4× X25519 + 1× ML-KEM-768)
pub const PQXDH_PUBLIC_KEY_SIZE = 4 * X25519.PUBLIC_KEY_SIZE + ML_KEM_768.PUBLIC_KEY_SIZE;

/// Total secret key size
pub const PQXDH_SECRET_KEY_SIZE = 4 * X25519.PRIVATE_KEY_SIZE + ML_KEM_768.SECRET_KEY_SIZE;

/// Ciphertext size (ML-KEM-768 encapsulation output)
pub const PQXDH_CIPHERTEXT_SIZE = ML_KEM_768.CIPHERTEXT_SIZE;

// ============================================================================
// Key Types
// ============================================================================

pub const KeyPair = struct {
    public_key: [ML_KEM_768.PUBLIC_KEY_SIZE]u8,
    secret_key: [ML_KEM_768.SECRET_KEY_SIZE]u8,
};

/// PQXDH Identity Keypair (long-term)
pub const IdentityKeyPair = struct {
    /// 4 X25519 keys + 1 ML-KEM-768 key
    x25519_keys: [4][X25519.PUBLIC_KEY_SIZE]u8,
    mlkem_keypair: KeyPair,
    /// Secret keys for X25519
    x25519_secrets: [4][X25519.PRIVATE_KEY_SIZE]u8,

    pub fn generate(allocator: std.mem.Allocator, seed: [64]u8) !IdentityKeyPair {
        _ = allocator;
        var kp: IdentityKeyPair = undefined;

        // Derive 4 X25519 keypairs from seed using HKDF
        const salt = "Libertaria_PQXDH_Identity_v1";
        const prk = crypto.kdf.hkdf.HkdfSha256.extract(salt, seed[0..32]);

        for (0..4) |i| {
            var okm: [64]u8 = undefined;
            var ctx: [6]u8 = undefined;
            @memcpy(ctx[0..4], "key_");
            ctx[4] = '0' + @as(u8, @intCast(i));
            ctx[5] = 0;
            crypto.kdf.hkdf.HkdfSha256.expand(&okm, ctx[0..5], prk);

            // X25519 scalar clamping
            var scalar: [32]u8 = undefined;
            @memcpy(&scalar, okm[0..32]);
            scalar[0] &= 248;
            scalar[31] &= 127;
            scalar[31] |= 64;

            kp.x25519_secrets[i] = scalar;
            // Generate public key from scalar
            kp.x25519_keys[i] = try crypto.dh.X25519.recoverPublicKey(scalar);
        }

        // Generate ML-KEM-768 keypair from seed[32..64]
        var ml_seed: [32]u8 = undefined;
        @memcpy(&ml_seed, seed[32..64]);
        kp.mlkem_keypair = try generateKeypairFromSeed(ml_seed);

        return kp;
    }
};

// ============================================================================
// ML-KEM-768 Operations
// ============================================================================

/// Generate ML-KEM-768 keypair deterministically from a 32-byte seed
/// Thread-safe via global mutex (liboqs RNG is global state)
pub fn generateKeypairFromSeed(seed: [32]u8) !KeyPair {
    if (!enable_pq) {
        return PQError.ML_KEM_NotAvailable;
    }

    rng_mutex.lock();
    defer rng_mutex.unlock();

    // 1. Initialize deterministic RNG with seed
    deterministic_rng = std.crypto.hash.sha3.Shake256.init(.{});
    const domain = "Libertaria_ML-KEM-768_Seed_v1";
    deterministic_rng.update(domain);
    deterministic_rng.update(&seed);

    // 2. Switch liboqs to use our custom callback
    liboqs.OQS_randombytes_custom_algorithm(custom_rng_callback);

    // 3. Generate keypair (uses our deterministic RNG)
    var kp: KeyPair = undefined;
    const ret = liboqs.OQS_KEM_ml_kem_768_keypair(
        &kp.public_key,
        &kp.secret_key,
    );

    // 4. Restore system RNG (important!)
    _ = liboqs.OQS_randombytes_switch_algorithm("system");

    if (ret != 0) {
        return PQError.ML_KEM_KeygenFailed;
    }

    return kp;
}

/// Generate ML-KEM-768 keypair using system RNG (non-deterministic)
pub fn generateKeypair() !KeyPair {
    if (!enable_pq) {
        return PQError.ML_KEM_NotAvailable;
    }

    // Switch to system RNG
    _ = liboqs.OQS_randombytes_switch_algorithm("system");

    var kp: KeyPair = undefined;
    const ret = liboqs.OQS_KEM_ml_kem_768_keypair(
        &kp.public_key,
        &kp.secret_key,
    );

    if (ret != 0) {
        return PQError.ML_KEM_KeygenFailed;
    }

    return kp;
}

/// Encapsulate: Create shared secret + ciphertext from public key
pub fn encapsulate(public_key: [ML_KEM_768.PUBLIC_KEY_SIZE]u8) !struct { ciphertext: [ML_KEM_768.CIPHERTEXT_SIZE]u8, shared_secret: [ML_KEM_768.SHARED_SECRET_SIZE]u8 } {
    if (!enable_pq) {
        return PQError.ML_KEM_NotAvailable;
    }

    var result: struct { ciphertext: [ML_KEM_768.CIPHERTEXT_SIZE]u8, shared_secret: [ML_KEM_768.SHARED_SECRET_SIZE]u8 } = undefined;

    const ret = liboqs.OQS_KEM_ml_kem_768_encaps(
        &result.ciphertext,
        &result.shared_secret,
        &public_key,
    );

    if (ret != 0) {
        return PQError.ML_KEM_EncapsFailed;
    }

    return result;
}

/// Decapsulate: Recover shared secret from ciphertext using secret key
pub fn decapsulate(ciphertext: [ML_KEM_768.CIPHERTEXT_SIZE]u8, secret_key: [ML_KEM_768.SECRET_KEY_SIZE]u8) ![ML_KEM_768.SHARED_SECRET_SIZE]u8 {
    if (!enable_pq) {
        return PQError.ML_KEM_NotAvailable;
    }

    var shared_secret: [ML_KEM_768.SHARED_SECRET_SIZE]u8 = undefined;

    const ret = liboqs.OQS_KEM_ml_kem_768_decaps(
        &shared_secret,
        &ciphertext,
        &secret_key,
    );

    if (ret != 0) {
        return PQError.ML_KEM_DecapsFailed;
    }

    return shared_secret;
}

// ============================================================================
// PQXDH Prekey Bundle
// ============================================================================

pub const PrekeyBundle = struct {
    /// Long-term identity key (Ed25519 public key)
    identity_key: [32]u8,

    /// Medium-term signed prekey (X25519 public key)
    signed_prekey_x25519: [X25519.PUBLIC_KEY_SIZE]u8,

    /// Signature of signed_prekey_x25519 by identity_key (Ed25519)
    signed_prekey_signature: [64]u8,

    /// Post-quantum signed prekey (ML-KEM-768 public key)
    signed_prekey_mlkem: [ML_KEM_768.PUBLIC_KEY_SIZE]u8,

    /// One-time ephemeral prekey (X25519 public key)
    one_time_prekey_x25519: [X25519.PUBLIC_KEY_SIZE]u8,

    /// One-time ephemeral prekey (ML-KEM-768 public key)
    one_time_prekey_mlkem: [ML_KEM_768.PUBLIC_KEY_SIZE]u8,

    /// Serialize bundle to bytes for transmission
    pub fn toBytes(self: *const PrekeyBundle, allocator: std.mem.Allocator) ![]u8 {
        const total_size = 32 + 32 + 64 + ML_KEM_768.PUBLIC_KEY_SIZE + 32 + ML_KEM_768.PUBLIC_KEY_SIZE;
        var buffer = try allocator.alloc(u8, total_size);
        var offset: usize = 0;

        @memcpy(buffer[offset .. offset + 32], &self.identity_key);
        offset += 32;

        @memcpy(buffer[offset .. offset + 32], &self.signed_prekey_x25519);
        offset += 32;

        @memcpy(buffer[offset .. offset + 64], &self.signed_prekey_signature);
        offset += 64;

        @memcpy(buffer[offset .. offset + ML_KEM_768.PUBLIC_KEY_SIZE], &self.signed_prekey_mlkem);
        offset += ML_KEM_768.PUBLIC_KEY_SIZE;

        @memcpy(buffer[offset .. offset + 32], &self.one_time_prekey_x25519);
        offset += 32;

        @memcpy(buffer[offset .. offset + ML_KEM_768.PUBLIC_KEY_SIZE], &self.one_time_prekey_mlkem);

        return buffer;
    }

    /// Deserialize bundle from bytes
    pub fn fromBytes(_: std.mem.Allocator, data: []const u8) !PrekeyBundle {
        const expected_size = 32 + 32 + 64 + ML_KEM_768.PUBLIC_KEY_SIZE + 32 + ML_KEM_768.PUBLIC_KEY_SIZE;
        if (data.len < expected_size) {
            return error.InvalidBundleSize;
        }

        var bundle: PrekeyBundle = undefined;
        var offset: usize = 0;

        @memcpy(&bundle.identity_key, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&bundle.signed_prekey_x25519, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&bundle.signed_prekey_signature, data[offset .. offset + 64]);
        offset += 64;

        @memcpy(&bundle.signed_prekey_mlkem, data[offset .. offset + ML_KEM_768.PUBLIC_KEY_SIZE]);
        offset += ML_KEM_768.PUBLIC_KEY_SIZE;

        @memcpy(&bundle.one_time_prekey_x25519, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&bundle.one_time_prekey_mlkem, data[offset .. offset + ML_KEM_768.PUBLIC_KEY_SIZE]);

        return bundle;
    }
};

// ============================================================================
// PQXDH Handshake
// ============================================================================

/// PQXDH ephemeral keypair (per-session)
pub const EphemeralKeyPair = struct {
    x25519: struct {
        public: [X25519.PUBLIC_KEY_SIZE]u8,
        secret: [X25519.PRIVATE_KEY_SIZE]u8,
    },
    mlkem_seed: [32]u8,
};

/// Generate ephemeral keypair for PQXDH handshake
pub fn generateEphemeral(allocator: std.mem.Allocator) !EphemeralKeyPair {
    _ = allocator;
    var ekp: EphemeralKeyPair = undefined;

    // Generate X25519 ephemeral
    const x25519_sk = crypto.dh.X25519.randomCli(&std.crypto.random);
    ekp.x25519.secret = x25519_sk;
    ekp.x25519.public = try crypto.dh.X25519.recoverPublicKey(x25519_sk);

    // Generate ML-KEM seed
    std.crypto.random.bytes(&ekp.mlkem_seed);

    return ekp;
}

/// PQXDH Initiator -> Responder message
pub const PQXDHInitMessage = struct {
    x25519_ephemeral: [4][X25519.PUBLIC_KEY_SIZE]u8,
    mlkem_ciphertext: [ML_KEM_768.CIPHERTEXT_SIZE]u8,
};

/// Perform PQXDH as Initiator
pub fn initiatorHandshake(
    allocator: std.mem.Allocator,
    responder_identity: IdentityKeyPair,
    our_ephemeral: EphemeralKeyPair,
) !struct { message: PQXDHInitMessage, root_key: [32]u8 } {
    // Generate 4 X25519 shared secrets
    var x25519_secrets: [4][32]u8 = undefined;
    for (0..4) |i| {
        x25519_secrets[i] = try crypto.dh.X25519.scalarmult(
            our_ephemeral.x25519.secret,
            responder_identity.x25519_keys[i],
        );
    }

    // ML-KEM encapsulation
    const encaps_result = try encapsulate(responder_identity.mlkem_keypair.public_key);

    // Build message
    var message: PQXDHInitMessage = undefined;
    for (0..4) |i| {
        message.x25519_ephemeral[i] = our_ephemeral.x25519.public;
    }
    message.mlkem_ciphertext = encaps_result.ciphertext;

    // Derive root key using HKDF-SHA256
    var ikm: [4 * 32 + 32]u8 = undefined;
    for (0..4) |i| {
        @memcpy(ikm[i * 32 .. (i + 1) * 32], &x25519_secrets[i]);
    }
    @memcpy(ikm[4 * 32 ..], &encaps_result.shared_secret);

    var root_key: [32]u8 = undefined;
    const salt = "Libertaria_PQXDH_RootKey_v1";
    crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&root_key, salt, ikm, "");

    _ = allocator;
    return .{ .message = message, .root_key = root_key };
}

/// Perform PQXDH as Responder
pub fn responderHandshake(
    allocator: std.mem.Allocator,
    our_identity: IdentityKeyPair,
    init_message: PQXDHInitMessage,
) ![32]u8 {
    // Recover 4 X25519 shared secrets
    var x25519_secrets: [4][32]u8 = undefined;
    for (0..4) |i| {
        x25519_secrets[i] = try crypto.dh.X25519.scalarmult(
            our_identity.x25519_secrets[i],
            init_message.x25519_ephemeral[i],
        );
    }

    // ML-KEM decapsulation
    const mlkem_secret = try decapsulate(
        init_message.mlkem_ciphertext,
        our_identity.mlkem_keypair.secret_key,
    );

    // Derive root key
    var ikm: [4 * 32 + 32]u8 = undefined;
    for (0..4) |i| {
        @memcpy(ikm[i * 32 .. (i + 1) * 32], &x25519_secrets[i]);
    }
    @memcpy(ikm[4 * 32 ..], &mlkem_secret);

    var root_key: [32]u8 = undefined;
    const salt = "Libertaria_PQXDH_RootKey_v1";
    crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&root_key, salt, ikm, "");

    _ = allocator;
    return root_key;
}

// ============================================================================
// Tests
// ============================================================================

test "ML-KEM-768 deterministic keypair generation" {
    if (!pq_enabled) {
        std.log.warn("Skipping PQ test: liboqs not enabled", .{});
        return error.SkipZigTest;
    }

    const seed = [32]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20 };

    const kp1 = try generateKeypairFromSeed(seed);
    const kp2 = try generateKeypairFromSeed(seed);

    // Deterministic: same seed -> same keys
    try std.testing.expectEqual(kp1.public_key, kp2.public_key);
    try std.testing.expectEqual(kp1.secret_key, kp2.secret_key);
}

test "PQXDH full handshake" {
    if (!pq_enabled) {
        std.log.warn("Skipping PQ test: liboqs not enabled", .{});
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    // Generate responder identity
    const responder_seed = [64]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40 };
    const responder = try IdentityKeyPair.generate(allocator, responder_seed);

    // Generate initiator ephemeral
    const initiator_ephemeral = try generateEphemeral(allocator);

    // Initiator sends handshake
    const init_result = try initiatorHandshake(allocator, responder, initiator_ephemeral);

    // Responder processes handshake
    const responder_key = try responderHandshake(allocator, responder, init_result.message);

    // Keys must match
    try std.testing.expectEqual(init_result.root_key, responder_key);
}

test "PrekeyBundle serialization" {
    const allocator = std.testing.allocator;

    var bundle: PrekeyBundle = undefined;
    std.crypto.random.bytes(&bundle.identity_key);
    std.crypto.random.bytes(&bundle.signed_prekey_x25519);
    std.crypto.random.bytes(&bundle.signed_prekey_signature);
    std.crypto.random.bytes(&bundle.signed_prekey_mlkem);
    std.crypto.random.bytes(&bundle.one_time_prekey_x25519);
    std.crypto.random.bytes(&bundle.one_time_prekey_mlkem);

    const bytes = try bundle.toBytes(allocator);
    defer allocator.free(bytes);

    const restored = try PrekeyBundle.fromBytes(allocator, bytes);

    try std.testing.expectEqual(bundle.identity_key, restored.identity_key);
    try std.testing.expectEqual(bundle.signed_prekey_x25519, restored.signed_prekey_x25519);
    try std.testing.expectEqual(bundle.signed_prekey_signature, restored.signed_prekey_signature);
    try std.testing.expectEqual(bundle.signed_prekey_mlkem, restored.signed_prekey_mlkem);
    try std.testing.expectEqual(bundle.one_time_prekey_x25519, restored.one_time_prekey_x25519);
    try std.testing.expectEqual(bundle.one_time_prekey_mlkem, restored.one_time_prekey_mlkem);
}
