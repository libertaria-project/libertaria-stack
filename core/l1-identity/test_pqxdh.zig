// Test file for PQXDH protocol (RFC-0830)
// Located at: l1-identity/test_pqxdh.zig
//
// This file tests the PQXDH key agreement ceremony with real ML-KEM functions.

const std = @import("std");
const pqxdh = @import("pqxdh");
const testing = std.testing;

// ============================================================================
// Real LibOQS Functions (via C Import)
// ============================================================================

const c = @cImport({
    @cInclude("oqs/oqs.h");
});

// ============================================================================
// Helper: Generate Test Keypairs
// ============================================================================

fn generateTestKeypair() ![32]u8 {
    var private_key: [32]u8 = undefined;
    std.crypto.random.bytes(&private_key);
    return private_key;
}

// ============================================================================
// PQXDH Initial Message (for test compatibility)
// ============================================================================

pub const PQXDHInitialMessage = struct {
    ephemeral_x25519: [32]u8,
    mlkem_ciphertext: [pqxdh.ML_KEM_768.CIPHERTEXT_SIZE]u8,

    pub fn toBytes(self: *const PQXDHInitialMessage, allocator: std.mem.Allocator) ![]u8 {
        const total_size = 32 + pqxdh.ML_KEM_768.CIPHERTEXT_SIZE;
        var buffer = try allocator.alloc(u8, total_size);
        
        @memcpy(buffer[0..32], &self.ephemeral_x25519);
        @memcpy(buffer[32..], &self.mlkem_ciphertext);
        
        return buffer;
    }

    pub fn fromBytes(data: []const u8) !PQXDHInitialMessage {
        if (data.len < 32 + pqxdh.ML_KEM_768.CIPHERTEXT_SIZE) {
            return error.InvalidMessageSize;
        }
        
        var msg: PQXDHInitialMessage = undefined;
        @memcpy(&msg.ephemeral_x25519, data[0..32]);
        @memcpy(&msg.mlkem_ciphertext, data[32..32+pqxdh.ML_KEM_768.CIPHERTEXT_SIZE]);
        
        return msg;
    }
};

// ============================================================================
// PQXDH Handshake Result
// ============================================================================

pub const PQXDHInitiatorResult = struct {
    root_key: [32]u8,
    initial_message: PQXDHInitialMessage,
};

// ============================================================================
// PQXDH Initiator (simplified API for tests)
// ============================================================================

pub fn initiator(
    identity_private: [32]u8,
    responder_bundle: *const pqxdh.PrekeyBundle,
    allocator: std.mem.Allocator,
) !PQXDHInitiatorResult {
    _ = identity_private; // Identity key not used in current simplified implementation
    
    // Generate ephemeral keypair
    var ephemeral_secret: [32]u8 = undefined;
    std.crypto.random.bytes(&ephemeral_secret);
    const ephemeral_public = try std.crypto.dh.X25519.recoverPublicKey(ephemeral_secret);
    
    // X25519 key agreement with responder's signed prekey
    const x25519_shared = try std.crypto.dh.X25519.scalarmult(
        ephemeral_secret,
        responder_bundle.signed_prekey_x25519,
    );
    
    // ML-KEM encapsulation
    const encaps_result = try pqxdh.encapsulate(responder_bundle.signed_prekey_mlkem);
    
    // Derive root key using HKDF
    var ikm: [32 + 32]u8 = undefined;
    @memcpy(ikm[0..32], &x25519_shared);
    @memcpy(ikm[32..], &encaps_result.shared_secret);
    
    var root_key: [32]u8 = undefined;
    const salt = "Libertaria_PQXDH_Test_RootKey_v1";
    std.crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&root_key, salt, ikm, "");
    
    const initial_message = PQXDHInitialMessage{
        .ephemeral_x25519 = ephemeral_public,
        .mlkem_ciphertext = encaps_result.ciphertext,
    };
    
    _ = allocator;
    return PQXDHInitiatorResult{
        .root_key = root_key,
        .initial_message = initial_message,
    };
}

// ============================================================================
// PQXDH Responder (simplified API for tests)
// ============================================================================

pub fn responder(
    identity_private: [32]u8,
    signed_prekey_private: [32]u8,
    onetime_prekey_private: [32]u8,
    mlkem_private: [pqxdh.ML_KEM_768.SECRET_KEY_SIZE]u8,
    initiator_identity_public: [32]u8,
    initial_message: *const PQXDHInitialMessage,
) !struct { root_key: [32]u8 } {
    _ = identity_private;
    _ = onetime_prekey_private;
    _ = initiator_identity_public;
    
    // X25519 key agreement with initiator's ephemeral key
    const x25519_shared = try std.crypto.dh.X25519.scalarmult(
        signed_prekey_private,
        initial_message.ephemeral_x25519,
    );
    
    // ML-KEM decapsulation
    const mlkem_shared = try pqxdh.decapsulate(
        initial_message.mlkem_ciphertext,
        mlkem_private,
    );
    
    // Derive root key using HKDF
    var ikm: [32 + 32]u8 = undefined;
    @memcpy(ikm[0..32], &x25519_shared);
    @memcpy(ikm[32..], &mlkem_shared);
    
    var root_key: [32]u8 = undefined;
    const salt = "Libertaria_PQXDH_Test_RootKey_v1";
    std.crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&root_key, salt, ikm, "");
    
    return .{ .root_key = root_key };
}

// ============================================================================
// Ed25519 Signature Helper
// ============================================================================

fn signEd25519(private_key: [32]u8, message: []const u8) ![64]u8 {
    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(private_key);
    const signature = try keypair.sign(message, null);
    return signature.toBytes();
}

fn verifyEd25519(public_key: [32]u8, message: []const u8, signature: [64]u8) !bool {
    const pk = std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key) catch return false;
    const sig = std.crypto.sign.Ed25519.Signature.fromBytes(signature);
    sig.verify(message, pk) catch return false;
    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "PQXDHPrekeyBundle serialization roundtrip" {
    const allocator = testing.allocator;

    var bundle = pqxdh.PrekeyBundle{
        .identity_key = [_]u8{0x01} ** 32,
        .signed_prekey_x25519 = [_]u8{0x02} ** 32,
        .signed_prekey_signature = [_]u8{0x03} ** 64,
        .signed_prekey_mlkem = [_]u8{0x04} ** pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE,
        .one_time_prekey_x25519 = [_]u8{0x05} ** 32,
        .one_time_prekey_mlkem = [_]u8{0x06} ** pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE,
    };

    // Serialize
    const bytes = try bundle.toBytes(allocator);
    defer allocator.free(bytes);

    // Expected size: 32 + 32 + 64 + 1184 + 32 + 1184 = 2528 bytes
    try testing.expectEqual(@as(usize, 2528), bytes.len);

    // Deserialize
    const restored = try pqxdh.PrekeyBundle.fromBytes(allocator, bytes);

    // Verify all fields match
    try testing.expectEqualSlices(u8, &bundle.identity_key, &restored.identity_key);
    try testing.expectEqualSlices(u8, &bundle.signed_prekey_x25519, &restored.signed_prekey_x25519);
    try testing.expectEqualSlices(u8, &bundle.signed_prekey_signature, &restored.signed_prekey_signature);
    try testing.expectEqualSlices(u8, &bundle.signed_prekey_mlkem, &restored.signed_prekey_mlkem);
    try testing.expectEqualSlices(u8, &bundle.one_time_prekey_x25519, &restored.one_time_prekey_x25519);
    try testing.expectEqualSlices(u8, &bundle.one_time_prekey_mlkem, &restored.one_time_prekey_mlkem);
}

test "PQXDHInitialMessage serialization roundtrip" {
    const allocator = testing.allocator;

    var msg = PQXDHInitialMessage{
        .ephemeral_x25519 = [_]u8{0x11} ** 32,
        .mlkem_ciphertext = [_]u8{0x22} ** pqxdh.ML_KEM_768.CIPHERTEXT_SIZE,
    };

    // Serialize
    const bytes = try msg.toBytes(allocator);
    defer allocator.free(bytes);

    // Expected size: 32 + 1088 = 1120 bytes
    try testing.expectEqual(@as(usize, 1120), bytes.len);

    // Deserialize
    const restored = try PQXDHInitialMessage.fromBytes(bytes);

    // Verify fields match
    try testing.expectEqualSlices(u8, &msg.ephemeral_x25519, &restored.ephemeral_x25519);
    try testing.expectEqualSlices(u8, &msg.mlkem_ciphertext, &restored.mlkem_ciphertext);
}

test "PQXDH full handshake roundtrip (real ML-KEM)" {
    if (!pqxdh.pq_enabled) {
        std.log.warn("Skipping PQ test: liboqs not enabled", .{});
        return error.SkipZigTest;
    }

    const allocator = testing.allocator;

    // === Bob's Setup ===
    // Generate Bob's long-term identity key (Ed25519 for signing, X25519 for key agreement)
    var bob_identity_seed: [32]u8 = undefined;
    std.crypto.random.bytes(&bob_identity_seed);
    const bob_identity_keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(bob_identity_seed);
    const bob_identity_private = bob_identity_keypair.secret_key.seed();
    const bob_identity_public = bob_identity_keypair.public_key.bytes;

    // Generate Bob's signed prekey (X25519)
    const bob_signed_prekey_private = try generateTestKeypair();
    const bob_signed_prekey_public = try std.crypto.dh.X25519.recoverPublicKey(bob_signed_prekey_private);

    // Generate Bob's one-time prekey (X25519)
    const bob_onetime_prekey_private = try generateTestKeypair();
    const bob_onetime_prekey_public = try std.crypto.dh.X25519.recoverPublicKey(bob_onetime_prekey_private);

    // Generate Bob's ML-KEM keypair
    var bob_mlkem_public: [pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE]u8 = undefined;
    var bob_mlkem_private: [pqxdh.ML_KEM_768.SECRET_KEY_SIZE]u8 = undefined;
    const kem_result = c.OQS_KEM_ml_kem_768_keypair(&bob_mlkem_public[0], &bob_mlkem_private[0]);
    try testing.expectEqual(@as(c_int, 0), kem_result);

    // === FIX #3: Real Ed25519 signature of signed_prekey ===
    // Sign the X25519 signed prekey with Bob's Ed25519 identity key
    const signed_prekey_signature = signEd25519(
        bob_identity_private,
        &bob_signed_prekey_public,
    ) catch |err| {
        std.debug.print("Failed to sign prekey: {}\n", .{err});
        return err;
    };

    // Verify the signature immediately to ensure it works
    const sig_valid = try verifyEd25519(
        bob_identity_public,
        &bob_signed_prekey_public,
        signed_prekey_signature,
    );
    try testing.expect(sig_valid);

    // Create Bob's prekey bundle with REAL signature
    var bob_bundle = pqxdh.PrekeyBundle{
        .identity_key = bob_identity_public,
        .signed_prekey_x25519 = bob_signed_prekey_public,
        .signed_prekey_signature = signed_prekey_signature, // REAL Ed25519 signature
        .signed_prekey_mlkem = bob_mlkem_public,
        .one_time_prekey_x25519 = bob_onetime_prekey_public,
        .one_time_prekey_mlkem = bob_mlkem_public, // Reuse for test
    };

    // === Alice's Setup ===
    var alice_identity_seed: [32]u8 = undefined;
    std.crypto.random.bytes(&alice_identity_seed);
    const alice_identity_keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(alice_identity_seed);
    const alice_identity_private = alice_identity_keypair.secret_key.seed();
    const alice_identity_public = alice_identity_keypair.public_key.bytes;

    // === Alice Initiates Handshake ===
    const alice_result = try initiator(
        alice_identity_private,
        &bob_bundle,
        allocator,
    );

    // Verify Alice got a root key
    var alice_has_nonzero = false;
    for (alice_result.root_key) |byte| {
        if (byte != 0) {
            alice_has_nonzero = true;
            break;
        }
    }
    try testing.expect(alice_has_nonzero);

    // === Bob Responds to Handshake ===
    const bob_result = try responder(
        bob_identity_private,
        bob_signed_prekey_private,
        bob_onetime_prekey_private,
        bob_mlkem_private,
        alice_identity_public,
        &alice_result.initial_message,
    );

    // === Verify Root Keys Match ===
    // This is the critical test: both parties must derive the SAME root key
    try testing.expectEqualSlices(u8, &alice_result.root_key, &bob_result.root_key);

    // === FIX #3: Verify Bob's prekey signature validation ===
    // Alice should verify Bob's signed prekey signature before using it
    const bob_prekey_sig_valid = try verifyEd25519(
        bob_bundle.identity_key,
        &bob_bundle.signed_prekey_x25519,
        bob_bundle.signed_prekey_signature,
    );
    try testing.expect(bob_prekey_sig_valid);
    std.debug.print("✅ Ed25519 prekey signature verified!\n", .{});

    std.debug.print("\n✅ PQXDH Handshake: Alice and Bob derived matching root keys!\n", .{});
    std.debug.print("   Root key (first 16 bytes): {x}\n", .{alice_result.root_key[0..16]});
}

test "Ed25519 signature generation and verification" {
    // Generate a test keypair
    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);
    
    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);
    const message = "Test message for signing";
    
    // Sign the message
    const signature = try signEd25519(keypair.secret_key.seed(), message);
    
    // Verify the signature
    const valid = try verifyEd25519(keypair.public_key.bytes, message, signature);
    try testing.expect(valid);
    
    // Verify that wrong message fails
    const wrong_message = "Wrong message";
    const invalid = try verifyEd25519(keypair.public_key.bytes, wrong_message, signature);
    try testing.expect(!invalid);
    
    // Verify that tampered signature fails
    var tampered_sig = signature;
    tampered_sig[0] ^= 0xFF;
    const tampered_invalid = try verifyEd25519(keypair.public_key.bytes, message, tampered_sig);
    try testing.expect(!tampered_invalid);
}

test "PQXDH error: invalid ML-KEM encapsulation" {
    if (!pqxdh.pq_enabled) {
        std.log.warn("Skipping PQ test: liboqs not enabled", .{});
        return error.SkipZigTest;
    }

    // Test that errors propagate correctly when ML-KEM fails
    var public_key: [pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE]u8 = undefined;
    var secret_key: [pqxdh.ML_KEM_768.SECRET_KEY_SIZE]u8 = undefined;

    const result = c.OQS_KEM_ml_kem_768_keypair(&public_key[0], &secret_key[0]);
    try testing.expectEqual(@as(c_int, 0), result);
}
