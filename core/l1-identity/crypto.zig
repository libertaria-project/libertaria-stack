//! RFC-0830 Section 2.4: Encryption Primitives
//!
//! This module implements the cryptographic primitives for Libertaria:
//! - X25519: Elliptic Curve Diffie-Hellman key agreement
//! - XChaCha20-Poly1305: Authenticated encryption with associated data (AEAD)
//! - Ed25519: Digital signatures (via soulkey.zig)
//!
//! All encryption in Libertaria uses XChaCha20-Poly1305 for AEAD.
//! Key agreement uses X25519 (classical) or PQXDH (post-quantum, future).

const std = @import("std");
const crypto = std.crypto;

// Ensure crypto FFI exports are compiled when this module is used
// This makes Zig-exported C functions available to C code
// Ensure crypto FFI exports are compiled when this module is used
// This makes Zig-exported C functions available to C code
const _ = @import("crypto_exports");

// Post-Quantum XDH (RFC-0830)
pub const pqxdh = @import("pqxdh");

/// RFC-0830 Section 2.6: WORLD_PUBLIC_KEY
/// This is the well-known public key used for World Feed encryption.
/// Everyone can decrypt World posts, but ISPs see only ciphertext.
pub const WORLD_PUBLIC_KEY: [32]u8 = [_]u8{
    0x4c, 0x69, 0x62, 0x65, 0x72, 0x74, 0x61, 0x72, // "Libertar"
    0x69, 0x61, 0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64, // "ia World"
    0x20, 0x46, 0x65, 0x65, 0x64, 0x20, 0x47, 0x65, // " Feed Ge"
    0x6e, 0x65, 0x73, 0x69, 0x73, 0x20, 0x4b, 0x65, // "nesis Ke"
};

/// Encrypted payload structure with AAD (Additional Authenticated Data)
pub const EncryptedPayload = struct {
    ephemeral_pubkey: [32]u8, // Sender's ephemeral public key
    timestamp: u64, // Unix timestamp for replay protection
    service_type: u8, // Service type for context binding
    nonce: [24]u8, // XChaCha20 nonce (never reused)
    ciphertext: []u8, // Encrypted data + 16-byte auth tag

    /// Service type constants
    pub const SERVICE_WORLD: u8 = 0;
    pub const SERVICE_FEED: u8 = 1;
    pub const SERVICE_MESSAGE: u8 = 2;
    pub const SERVICE_DIRECT: u8 = 3;

    /// Free ciphertext memory
    pub fn deinit(self: *EncryptedPayload, allocator: std.mem.Allocator) void {
        allocator.free(self.ciphertext);
    }

    /// Total size when serialized
    pub fn size(self: *const EncryptedPayload) usize {
        return 32 + 8 + 1 + 24 + self.ciphertext.len;
    }

    /// Serialize to bytes
    pub fn toBytes(self: *const EncryptedPayload, allocator: std.mem.Allocator) ![]u8 {
        const total_size = self.size();
        var buffer = try allocator.alloc(u8, total_size);

        @memcpy(buffer[0..32], &self.ephemeral_pubkey);
        std.mem.writeInt(u64, buffer[32..40], self.timestamp, .big);
        buffer[40] = self.service_type;
        @memcpy(buffer[41..65], &self.nonce);
        @memcpy(buffer[65..], self.ciphertext);

        return buffer;
    }

    /// Deserialize from bytes
    pub fn fromBytes(allocator: std.mem.Allocator, data: []const u8) !EncryptedPayload {
        if (data.len < 65) {
            return error.PayloadTooSmall;
        }

        const ephemeral_pubkey = data[0..32].*;
        const timestamp = std.mem.readInt(u64, data[32..40], .big);
        const service_type = data[40];
        const nonce = data[41..65].*;
        const ciphertext = try allocator.alloc(u8, data.len - 65);
        @memcpy(ciphertext, data[65..]);

        return EncryptedPayload{
            .ephemeral_pubkey = ephemeral_pubkey,
            .timestamp = timestamp,
            .service_type = service_type,
            .nonce = nonce,
            .ciphertext = ciphertext,
        };
    }

    /// Build AAD (Additional Authenticated Data) from header fields
    /// Binds ciphertext to: sender (ephemeral_pubkey), time (timestamp), context (service_type)
    pub fn buildAAD(self: *const EncryptedPayload, buffer: *[41]u8) []const u8 {
        @memcpy(buffer[0..32], &self.ephemeral_pubkey);
        std.mem.writeInt(u64, buffer[32..40], self.timestamp, .big);
        buffer[40] = self.service_type;
        return buffer[0..41];
    }
};

/// Generate a random 24-byte nonce for XChaCha20
pub fn generateNonce() [24]u8 {
    var nonce: [24]u8 = undefined;
    crypto.random.bytes(&nonce);
    return nonce;
}

/// Encrypt payload using X25519-XChaCha20-Poly1305 with AAD
///
/// This is the standard encryption for all Libertaria tiers except MESSAGE
/// (MESSAGE uses PQXDH → Double Ratchet via LatticePost).
///
/// Steps:
/// 1. Generate ephemeral keypair for sender
/// 2. Perform X25519 key agreement with recipient's public key
/// 3. Build AAD from header (ephemeral_pubkey, timestamp, service_type)
/// 4. Encrypt plaintext with XChaCha20-Poly1305 using shared secret and AAD
/// 5. Return ephemeral pubkey + timestamp + service_type + nonce + ciphertext
pub fn encryptPayload(
    plaintext: []const u8,
    recipient_pubkey: [32]u8,
    sender_private: [32]u8,
    service_type: u8,
    allocator: std.mem.Allocator,
) !EncryptedPayload {
    // X25519 key agreement
    const shared_secret = try crypto.dh.X25519.scalarmult(sender_private, recipient_pubkey);

    // Derive ephemeral public key from sender's private key
    const ephemeral_pubkey = try crypto.dh.X25519.recoverPublicKey(sender_private);

    // Get current timestamp for replay protection
    const timestamp = @as(u64, @intCast(std.time.timestamp()));

    // Generate random nonce
    const nonce = generateNonce();

    // Allocate ciphertext buffer (plaintext + 16-byte auth tag)
    const ciphertext = try allocator.alloc(u8, plaintext.len + 16);

    // Build AAD to bind ciphertext to context
    var aad_buffer: [41]u8 = undefined;
    var payload_for_aad = EncryptedPayload{
        .ephemeral_pubkey = ephemeral_pubkey,
        .timestamp = timestamp,
        .service_type = service_type,
        .nonce = nonce,
        .ciphertext = &[_]u8{}, // Empty for AAD calculation
    };
    const aad = payload_for_aad.buildAAD(&aad_buffer);

    // XChaCha20-Poly1305 AEAD encryption with AAD
    crypto.aead.chacha_poly.XChaCha20Poly1305.encrypt(
        ciphertext[0..plaintext.len],
        ciphertext[plaintext.len..][0..16],
        plaintext,
        aad, // AAD binds ciphertext to sender, timestamp, and service type
        nonce,
        shared_secret,
    );

    return EncryptedPayload{
        .ephemeral_pubkey = ephemeral_pubkey,
        .timestamp = timestamp,
        .service_type = service_type,
        .nonce = nonce,
        .ciphertext = ciphertext,
    };
}

/// Decrypt payload using X25519-XChaCha20-Poly1305 with AAD verification
///
/// Steps:
/// 1. Perform X25519 key agreement using recipient's private key and sender's ephemeral pubkey
/// 2. Rebuild AAD from header fields
/// 3. Decrypt ciphertext with XChaCha20-Poly1305 using shared secret and AAD
/// 4. Verify authentication tag (fails if AAD doesn't match)
/// 5. Return plaintext
pub fn decryptPayload(
    encrypted: *const EncryptedPayload,
    recipient_private: [32]u8,
    expected_service_type: u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    // X25519 key agreement
    const shared_secret = try crypto.dh.X25519.scalarmult(recipient_private, encrypted.ephemeral_pubkey);

    // Verify service type matches (context binding)
    if (encrypted.service_type != expected_service_type) {
        return error.ServiceTypeMismatch;
    }

    // Check for replay attacks (timestamp should be within reasonable window)
    const current_time = @as(u64, @intCast(std.time.timestamp()));
    const timestamp = encrypted.timestamp;
    // Allow 5 minutes of clock skew
    const max_age = 5 * 60;
    if (current_time > timestamp + max_age) {
        return error.TimestampTooOld;
    }
    if (timestamp > current_time + 60) { // 1 minute future tolerance
        return error.TimestampInFuture;
    }

    // Rebuild AAD from header fields
    var aad_buffer: [41]u8 = undefined;
    const aad = encrypted.buildAAD(&aad_buffer);

    // Calculate plaintext length (ciphertext - 16-byte auth tag)
    const plaintext_len = encrypted.ciphertext.len - 16;
    const plaintext = try allocator.alloc(u8, plaintext_len);

    // XChaCha20-Poly1305 AEAD decryption with AAD verification
    crypto.aead.chacha_poly.XChaCha20Poly1305.decrypt(
        plaintext,
        encrypted.ciphertext[0..plaintext_len],
        encrypted.ciphertext[plaintext_len..][0..16].*, // Auth tag
        aad, // AAD must match what was used during encryption
        encrypted.nonce,
        shared_secret,
    ) catch |err| {
        // Clear plaintext buffer on failure to avoid partial data exposure
        @memset(plaintext, 0);
        allocator.free(plaintext);
        return err;
    };

    return plaintext;
}

/// Convenience: Encrypt to WORLD tier (uses WORLD_PUBLIC_KEY as shared secret)
/// Special case: WORLD_PUBLIC_KEY is used directly as the encryption key
/// This allows anyone who knows WORLD_PUBLIC_KEY to decrypt (obfuscation, not true security)
pub fn encryptWorld(
    plaintext: []const u8,
    sender_private: [32]u8,
    allocator: std.mem.Allocator,
) !EncryptedPayload {
    _ = sender_private; // Not used for World encryption

    // Use WORLD_PUBLIC_KEY directly as shared secret (symmetric-like encryption)
    const shared_secret = WORLD_PUBLIC_KEY;

    // Get current timestamp
    const timestamp = @as(u64, @intCast(std.time.timestamp()));

    // Generate random nonce
    const nonce = generateNonce();

    // Allocate ciphertext buffer (plaintext + 16-byte auth tag)
    const ciphertext = try allocator.alloc(u8, plaintext.len + 16);

    // Build AAD for World tier
    var aad_buffer: [41]u8 = undefined;
    var payload_for_aad = EncryptedPayload{
        .ephemeral_pubkey = WORLD_PUBLIC_KEY,
        .timestamp = timestamp,
        .service_type = EncryptedPayload.SERVICE_WORLD,
        .nonce = nonce,
        .ciphertext = &[_]u8{},
    };
    const aad = payload_for_aad.buildAAD(&aad_buffer);

    // XChaCha20-Poly1305 AEAD encryption with AAD
    crypto.aead.chacha_poly.XChaCha20Poly1305.encrypt(
        ciphertext[0..plaintext.len],
        ciphertext[plaintext.len..][0..16],
        plaintext,
        aad,
        nonce,
        shared_secret,
    );

    // For WORLD encryption, ephemeral_pubkey is WORLD_PUBLIC_KEY itself
    // This signals that it's world-readable (no ECDH needed)
    return EncryptedPayload{
        .ephemeral_pubkey = WORLD_PUBLIC_KEY,
        .timestamp = timestamp,
        .service_type = EncryptedPayload.SERVICE_WORLD,
        .nonce = nonce,
        .ciphertext = ciphertext,
    };
}

/// Convenience: Decrypt from WORLD tier (uses WORLD_PUBLIC_KEY as shared secret)
/// Special case: Uses WORLD_PUBLIC_KEY directly as decryption key
pub fn decryptWorld(
    encrypted: *const EncryptedPayload,
    recipient_private: [32]u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    _ = recipient_private; // Not used for World decryption

    // Use WORLD_PUBLIC_KEY directly as shared secret
    const shared_secret = WORLD_PUBLIC_KEY;

    // Verify this is actually a WORLD tier payload
    if (encrypted.service_type != EncryptedPayload.SERVICE_WORLD) {
        return error.ServiceTypeMismatch;
    }

    // Check timestamp for replay protection
    const current_time = @as(u64, @intCast(std.time.timestamp()));
    const max_age = 5 * 60; // 5 minutes
    if (current_time > encrypted.timestamp + max_age) {
        return error.TimestampTooOld;
    }

    // Rebuild AAD
    var aad_buffer: [41]u8 = undefined;
    const aad = encrypted.buildAAD(&aad_buffer);

    // Calculate plaintext length (ciphertext - 16-byte auth tag)
    const plaintext_len = encrypted.ciphertext.len - 16;
    const plaintext = try allocator.alloc(u8, plaintext_len);

    // XChaCha20-Poly1305 AEAD decryption
    crypto.aead.chacha_poly.XChaCha20Poly1305.decrypt(
        plaintext,
        encrypted.ciphertext[0..plaintext_len],
        encrypted.ciphertext[plaintext_len..][0..16].*, // Auth tag
        aad,
        encrypted.nonce,
        shared_secret,
    ) catch |err| {
        @memset(plaintext, 0);
        allocator.free(plaintext);
        return err;
    };

    return plaintext;
}

// ============================================================================
// Tests
// ============================================================================

test "encryptPayload/decryptPayload roundtrip with AAD" {
    const allocator = std.testing.allocator;

    // Generate keypairs
    var sender_private: [32]u8 = undefined;
    var recipient_private: [32]u8 = undefined;
    crypto.random.bytes(&sender_private);
    crypto.random.bytes(&recipient_private);

    const recipient_public = try crypto.dh.X25519.recoverPublicKey(recipient_private);

    // Encrypt
    const plaintext = "Hello, Libertaria!";
    var encrypted = try encryptPayload(plaintext, recipient_public, sender_private, EncryptedPayload.SERVICE_FEED, allocator);
    defer encrypted.deinit(allocator);

    try std.testing.expect(encrypted.ciphertext.len > plaintext.len); // Has auth tag
    try std.testing.expectEqual(@as(u8, EncryptedPayload.SERVICE_FEED), encrypted.service_type);

    // Decrypt
    const decrypted = try decryptPayload(&encrypted,
        recipient_private,
        EncryptedPayload.SERVICE_FEED, // Correct service type
        allocator,
    );
    defer allocator.free(decrypted);

    // Verify
    try std.testing.expectEqualStrings(plaintext, decrypted);
}

test "decryptPayload fails with wrong service type" {
    const allocator = std.testing.allocator;

    // Generate keypairs
    var sender_private: [32]u8 = undefined;
    var recipient_private: [32]u8 = undefined;
    crypto.random.bytes(&sender_private);
    crypto.random.bytes(&recipient_private);

    const recipient_public = try crypto.dh.X25519.recoverPublicKey(recipient_private);

    // Encrypt for FEED service
    const plaintext = "Hello, Libertaria!";
    var encrypted = try encryptPayload(plaintext, recipient_public, sender_private, EncryptedPayload.SERVICE_FEED, allocator);
    defer encrypted.deinit(allocator);

    // Decrypt with wrong service type should fail
    const result = decryptPayload(&encrypted,
        recipient_private,
        EncryptedPayload.SERVICE_MESSAGE, // Wrong service type
        allocator,
    );
    try std.testing.expectError(error.ServiceTypeMismatch, result);
}

test "encryptWorld/decryptWorld roundtrip" {
    const allocator = std.testing.allocator;

    // Generate keypair
    var private_key: [32]u8 = undefined;
    crypto.random.bytes(&private_key);

    // Encrypt to World
    const plaintext = "Hello, World Feed!";
    var encrypted = try encryptWorld(plaintext, private_key, allocator);
    defer encrypted.deinit(allocator);

    // Verify service type
    try std.testing.expectEqual(@as(u8, EncryptedPayload.SERVICE_WORLD), encrypted.service_type);

    // Decrypt from World
    const decrypted = try decryptWorld(&encrypted, private_key, allocator);
    defer allocator.free(decrypted);

    // Verify
    try std.testing.expectEqualStrings(plaintext, decrypted);
}

test "EncryptedPayload serialization with AAD fields" {
    const allocator = std.testing.allocator;

    // Create encrypted payload
    var encrypted = EncryptedPayload{
        .ephemeral_pubkey = [_]u8{0xAA} ** 32,
        .timestamp = 1234567890,
        .service_type = EncryptedPayload.SERVICE_MESSAGE,
        .nonce = [_]u8{0xBB} ** 24,
        .ciphertext = try allocator.alloc(u8, 48), // 32 bytes + 16 auth tag
    };
    defer encrypted.deinit(allocator);
    @memset(encrypted.ciphertext, 0xCC);

    // Serialize
    const bytes = try encrypted.toBytes(allocator);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(usize, 32 + 8 + 1 + 24 + 48), bytes.len);

    // Deserialize
    var deserialized = try EncryptedPayload.fromBytes(allocator, bytes);
    defer deserialized.deinit(allocator);

    try std.testing.expectEqualSlices(u8, &encrypted.ephemeral_pubkey, &deserialized.ephemeral_pubkey);
    try std.testing.expectEqual(encrypted.timestamp, deserialized.timestamp);
    try std.testing.expectEqual(encrypted.service_type, deserialized.service_type);
    try std.testing.expectEqualSlices(u8, &encrypted.nonce, &deserialized.nonce);
    try std.testing.expectEqualSlices(u8, encrypted.ciphertext, deserialized.ciphertext);
}

test "AAD binds to correct context" {
    const allocator = std.testing.allocator;

    // Generate keypairs
    var sender_private: [32]u8 = undefined;
    var recipient_private: [32]u8 = undefined;
    crypto.random.bytes(&sender_private);
    crypto.random.bytes(&recipient_private);

    const recipient_public = try crypto.dh.X25519.recoverPublicKey(recipient_private);

    // Encrypt
    const plaintext = "Secret message";
    var encrypted = try encryptPayload(plaintext, recipient_public, sender_private, EncryptedPayload.SERVICE_DIRECT, allocator);
    defer encrypted.deinit(allocator);

    // Build AAD and verify it contains expected data
    var aad_buffer: [41]u8 = undefined;
    const aad = encrypted.buildAAD(&aad_buffer);

    // AAD should be 41 bytes: 32 (pubkey) + 8 (timestamp) + 1 (service_type)
    try std.testing.expectEqual(@as(usize, 41), aad.len);

    // First 32 bytes should be ephemeral pubkey
    try std.testing.expectEqualSlices(u8, &encrypted.ephemeral_pubkey, aad[0..32]);

    // Byte 40 should be service type
    try std.testing.expectEqual(encrypted.service_type, aad[40]);
}

test "nonce generation is random" {
    const nonce1 = generateNonce();
    const nonce2 = generateNonce();

    // Extremely unlikely to be equal if truly random
    try std.testing.expect(!std.mem.eql(u8, &nonce1, &nonce2));
}
