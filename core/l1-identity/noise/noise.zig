// Noise Protocol Implementation
// RFC-0010: Noise_XX handshake for L0 Transport
// No questions, just code. 🦞

const std = @import("std");

/// Noise Protocol Constants
pub const NOISE_PROTOCOL_NAME = "Noise_XX_25519_ChaChaPoly_BLAKE2b";
pub const NOISE_HASH_LEN = 32;  // BLAKE2b output
pub const NOISE_KEY_LEN = 32;   // X25519 key
pub const NOISE_TAG_LEN = 16;   // Poly1305 tag
pub const NOISE_NONCE_LEN = 12; // ChaCha20 nonce

/// Noise State Machine
pub const NoiseState = enum {
    Uninitialized,
    Initialized,
    SentEphemeral,
    ReceivedEphemeral,
    HandshakeComplete,
    TransportReady,
    Failed,
};

/// X25519 Keypair
pub const KeyPair = struct {
    private: [32]u8,
    public: [32]u8,
    
    pub fn generate() !KeyPair {
        var kp: KeyPair = undefined;
        // Generate random private key
        std.crypto.random.bytes(&kp.private);
        // Clamp and generate public
        std.crypto.ecc.X25519.clamp(&kp.private);
        kp.public = std.crypto.ecc.X25519.recoverPublicKey(kp.private) catch return error.KeyGenFailed;
        return kp;
    }
};

/// Noise Session
pub const NoiseSession = struct {
    state: NoiseState,
    
    // Keys
    ephemeral: ?KeyPair,
    static: ?KeyPair,
    remote_ephemeral: ?[32]u8,
    remote_static: ?[32]u8,
    
    // Symmetric state
    chaining_key: [32]u8,
    hash: [32]u8,
    
    // Transport keys (after handshake)
    send_key: ?[32]u8,
    recv_key: ?[32]u8,
    send_nonce: u64,
    recv_nonce: u64,
    
    pub fn init() NoiseSession {
        return .{
            .state = .Uninitialized,
            .ephemeral = null,
            .static = null,
            .remote_ephemeral = null,
            .remote_static = null,
            .chaining_key = [_]u8{0} ** 32,
            .hash = [_]u8{0} ** 32,
            .send_key = null,
            .recv_key = null,
            .send_nonce = 0,
            .recv_nonce = 0,
        };
    }
    
    /// Initialize with protocol name
    pub fn initialize(self: *NoiseSession) !void {
        if (self.state != .Uninitialized) return error.InvalidState;
        
        // chaining_key = HASH(protocol_name)
        var h = std.crypto.hash.blake2.Blake2b256.init(.{});
        h.update(NOISE_PROTOCOL_NAME);
        h.final(&self.chaining_key);
        
        // hash = HASH(chaining_key)
        var h2 = std.crypto.hash.blake2.Blake2b256.init(.{});
        h2.update(&self.chaining_key);
        h2.final(&self.hash);
        
        self.state = .Initialized;
    }
    
    /// Send -> e (first message pattern)
    pub fn writeMessageE(self: *NoiseSession, message: []u8) !usize {
        if (self.state != .Initialized) return error.InvalidState;
        if (message.len < 32) return error.BufferTooSmall;
        
        // Generate ephemeral keypair
        self.ephemeral = try KeyPair.generate();
        
        // Append ephemeral public key
        @memcpy(message[0..32], &self.ephemeral.?.public);
        
        // MixHash(ephemeral_public)
        self.mixHash(&self.ephemeral.?.public);
        
        self.state = .SentEphemeral;
        return 32;
    }
    
    /// Receive <- e (first response pattern)
    pub fn readMessageE(self: *NoiseSession, message: []const u8) !void {
        if (self.state != .SentEphemeral) return error.InvalidState;
        if (message.len < 32) return error.MessageTooShort;
        
        // Store remote ephemeral
        var remote_eph: [32]u8 = undefined;
        @memcpy(&remote_eph, message[0..32]);
        self.remote_ephemeral = remote_eph;
        
        // MixHash(ephemeral_public)
        self.mixHash(&remote_eph);
        
        // DH(e, re) -> MixKey
        if (self.ephemeral) |e| {
            const shared = std.crypto.ecc.X25519.scalarmult(e.private, remote_eph) catch return error.DHFailed;
            self.mixKey(&shared);
        }
        
        self.state = .ReceivedEphemeral;
    }
    
    /// Mix hash with data
    fn mixHash(self: *NoiseSession, data: []const u8) void {
        var h = std.crypto.hash.blake2.Blake2b256.init(.{});
        h.update(&self.hash);
        h.update(data);
        h.final(&self.hash);
    }
    
    /// Mix key with DH result
    fn mixKey(self: *NoiseSession, dh_result: *[32]u8) void {
        // ck, temp_k = HKDF(ck, dh_result, 2)
        var out: [64]u8 = undefined;
        std.crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&out, &self.chaining_key, dh_result, "");
        
        @memcpy(&self.chaining_key, out[0..32]);
        // temp_k = out[32..64] for encryption
        _ = out[32..64];
    }
    
    /// Finalize handshake, derive transport keys
    pub fn finalizeHandshake(self: *NoiseSession) !void {
        if (self.state != .ReceivedEphemeral) return error.InvalidState;
        
        // Derive send and receive keys from chaining_key
        var keys: [64]u8 = undefined;
        std.crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&keys, &self.chaining_key, &[_]u8{}, "LibertariaNoise");
        
        var send: [32]u8 = undefined;
        var recv: [32]u8 = undefined;
        @memcpy(&send, keys[0..32]);
        @memcpy(&recv, keys[32..64]);
        
        self.send_key = send;
        self.recv_key = recv;
        self.state = .TransportReady;
    }
    
    /// Encrypt transport message
    pub fn encrypt(self: *NoiseSession, plaintext: []const u8, ciphertext: []u8) !usize {
        if (self.state != .TransportReady) return error.InvalidState;
        if (ciphertext.len < plaintext.len + NOISE_TAG_LEN) return error.BufferTooSmall;
        
        const key = self.send_key.?;
        
        // Build nonce from send_nonce (little endian, padded)
        var nonce = [_]u8{0} ** NOISE_NONCE_LEN;
        std.mem.writeInt(u64, nonce[4..12], self.send_nonce, .little);
        
        // Encrypt
        var tag: [NOISE_TAG_LEN]u8 = undefined;
        std.crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(
            ciphertext[0..plaintext.len],
            &tag,
            plaintext,
            &[_]u8{}, // no AAD
            nonce,
            key,
        );
        
        @memcpy(ciphertext[plaintext.len..][0..NOISE_TAG_LEN], &tag);
        self.send_nonce += 1;
        
        return plaintext.len + NOISE_TAG_LEN;
    }
    
    /// Decrypt transport message
    pub fn decrypt(self: *NoiseSession, ciphertext: []const u8, plaintext: []u8) !usize {
        if (self.state != .TransportReady) return error.InvalidState;
        if (ciphertext.len < NOISE_TAG_LEN) return error.MessageTooShort;
        if (plaintext.len < ciphertext.len - NOISE_TAG_LEN) return error.BufferTooSmall;
        
        const key = self.recv_key.?;
        
        // Build nonce
        var nonce = [_]u8{0} ** NOISE_NONCE_LEN;
        std.mem.writeInt(u64, nonce[4..12], self.recv_nonce, .little);
        
        const payload_len = ciphertext.len - NOISE_TAG_LEN;
        var tag: [NOISE_TAG_LEN]u8 = undefined;
        @memcpy(&tag, ciphertext[payload_len..][0..NOISE_TAG_LEN]);
        
        // Decrypt
        std.crypto.aead.chacha_poly.ChaCha20Poly1305.decrypt(
            plaintext[0..payload_len],
            ciphertext[0..payload_len],
            tag,
            &[_]u8{}, // no AAD
            nonce,
            key,
        ) catch return error.DecryptionFailed;
        
        self.recv_nonce += 1;
        return payload_len;
    }
};

// === TESTS ===

test "Noise handshake XX pattern" {
    // Initiator
    var init = NoiseSession.init();
    try init.initialize();
    
    // -> e
    var msg1: [32]u8 = undefined;
    const len1 = try init.writeMessageE(&msg1);
    try std.testing.expectEqual(@as(usize, 32), len1);
    try std.testing.expectEqual(NoiseState.SentEphemeral, init.state);
    
    // Responder receives
    var resp = NoiseSession.init();
    try resp.initialize();
    try resp.readMessageE(&msg1);
    try std.testing.expectEqual(NoiseState.ReceivedEphemeral, resp.state);
    
    // <- e (responder sends)
    var msg2: [32]u8 = undefined;
    const len2 = try resp.writeMessageE(&msg2);
    try std.testing.expectEqual(@as(usize, 32), len2);
    
    // Initiator receives
    try init.readMessageE(&msg2);
    
    // Finalize both
    try init.finalizeHandshake();
    try resp.finalizeHandshake();
    
    try std.testing.expectEqual(NoiseState.TransportReady, init.state);
    try std.testing.expectEqual(NoiseState.TransportReady, resp.state);
}

test "Noise transport encryption" {
    // Setup sessions
    var alice = NoiseSession.init();
    var bob = NoiseSession.init();
    
    // ... handshake ...
    try alice.initialize();
    try bob.initialize();
    
    var msg1: [32]u8 = undefined;
    _ = try alice.writeMessageE(&msg1);
    try bob.readMessageE(&msg1);
    
    var msg2: [32]u8 = undefined;
    _ = try bob.writeMessageE(&msg2);
    try alice.readMessageE(&msg2);
    
    try alice.finalizeHandshake();
    try bob.finalizeHandshake();
    
    // Encrypt from Alice
    const plaintext = "Hello Noise!";
    var ciphertext: [100]u8 = undefined;
    const ct_len = try alice.encrypt(plaintext, &ciphertext);
    
    // Decrypt by Bob
    var decrypted: [100]u8 = undefined;
    const pt_len = try bob.decrypt(ciphertext[0..ct_len], &decrypted);
    
    try std.testing.expectEqual(plaintext.len, pt_len);
    try std.testing.expectEqualStrings(plaintext, decrypted[0..pt_len]);
}
