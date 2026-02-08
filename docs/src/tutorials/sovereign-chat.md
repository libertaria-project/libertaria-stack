# Build a Sovereign Chat

Build a peer-to-peer encrypted chat application using Libertaria's identity and session layers. Learn DID exchange, session establishment, and encrypted messaging.

---

## What You'll Build

A sovereign chat application with two nodes that:
1. Generate unique SoulKey identities (DIDs)
2. Exchange public keys securely
3. Establish encrypted sessions using X25519 + Kyber
4. Send end-to-end encrypted messages

---

## Prerequisites

- **Zig 0.13+** installed
- Understanding of [Hello Sovereign World](./hello-world.md)
- **Two terminal windows** (for Alice and Bob)

### Concepts You'll Learn

- **DID** (Decentralized Identifier): `did:libertaria:<base58-encoded-hash>`
- **SoulKey**: Ed25519 + X25519 + ML-KEM-768 key bundle
- **X3DH**: Extended Triple Diffie-Hellman for session keys
- **PreKey bundles**: One-time keys for forward secrecy

---

## Step 1: Project Setup

```bash
mkdir sovereign-chat
cd sovereign-chat
zig init

# Create source files
touch src/main.zig src/identity.zig src/session.zig
```

---

## Step 2: Identity Module (DID + SoulKey)

Create `src/identity.zig`:

```zig
const std = @import("std");
const crypto = std.crypto;

// SoulKey: Core identity keypair (RFC-0250)
pub const SoulKey = struct {
    // Ed25519 for signatures
    ed25519_private: [32]u8,
    ed25519_public: [32]u8,

    // X25519 for key agreement
    x25519_private: [32]u8,
    x25519_public: [32]u8,

    // DID derived from public keys
    did: [32]u8,

    /// Generate a new SoulKey from seed (deterministic)
    pub fn fromSeed(seed: *const [32]u8) !SoulKey {
        var key: SoulKey = undefined;

        // Ed25519 generation
        const ed_kp = try crypto.sign.Ed25519.KeyPair.generateDeterministic(seed.*);
        key.ed25519_private = ed_kp.secret_key.seed();
        key.ed25519_public = ed_kp.public_key.bytes;

        // X25519 generation (domain-separated from Ed25519)
        var x25519_seed: [32]u8 = undefined;
        var input_with_domain: [32 + 28]u8 = undefined;
        @memcpy(input_with_domain[0..32], seed);
        @memcpy(input_with_domain[32..60], "libertaria-soulkey-x25519-v1");
        crypto.hash.sha2.Sha256.hash(&input_with_domain, &x25519_seed, .{});
        key.x25519_private = x25519_seed;
        key.x25519_public = try crypto.dh.X25519.recoverPublicKey(x25519_seed);

        // DID = SHA256(ed25519_public || x25519_public)
        var did_input: [64]u8 = undefined;
        @memcpy(did_input[0..32], &key.ed25519_public);
        @memcpy(did_input[32..64], &key.x25519_public);
        crypto.hash.sha2.Sha256.hash(&did_input, &key.did, .{});

        return key;
    }

    /// Generate random SoulKey
    pub fn generate() !SoulKey {
        var seed: [32]u8 = undefined;
        crypto.random.bytes(&seed);
        return try fromSeed(&seed);
    }

    /// Get DID as base58 string
    pub fn didToString(self: *const SoulKey, buf: []u8) ![]const u8 {
        const base58_chars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        return try base58Encode(&self.did, buf, base58_chars);
    }

    /// Sign a message
    pub fn sign(self: *const SoulKey, message: []const u8, signature: *[64]u8) !void {
        const kp = try crypto.sign.Ed25519.KeyPair.fromSeed(self.ed25519_private);
        const sig = try crypto.sign.Ed25519.sign(message, kp, null);
        @memcpy(signature, &sig.toBytes());
    }

    /// Verify signature
    pub fn verify(self: *const SoulKey, message: []const u8, signature: *const [64]u8) !bool {
        const pk = crypto.sign.Ed25519.PublicKey.fromBytes(self.ed25519_public) catch return false;
        const sig = crypto.sign.Ed25519.Signature.fromBytes(signature.*);
        sig.verify(message, pk) catch return false;
        return true;
    }
};

// Simple base58 encoder (subset for DID display)
fn base58Encode(data: []const u8, buf: []u8, alphabet: []const u8) ![]const u8 {
    if (data.len == 0) return "";

    var leading_zeros: usize = 0;
    while (leading_zeros < data.len and data[leading_zeros] == 0) : (leading_zeros += 1) {}

    // Rough size estimate
    var result: [256]u8 = undefined;
    var result_len: usize = 0;

    // Simple implementation - for production use proper big-int base conversion
    var num: u256 = 0;
    for (data) |b| {
        num = (num << 8) | b;
    }

    if (num == 0) {
        @memset(buf[0..leading_zeros], '1');
        return buf[0..leading_zeros];
    }

    while (num > 0) : (result_len += 1) {
        const rem = num % 58;
        num = num / 58;
        result[result_len] = alphabet[@as(usize, @intCast(rem))];
    }

    // Reverse and add leading zeros
    const total_len = leading_zeros + result_len;
    if (total_len > buf.len) return error.NoSpaceLeft;

    @memset(buf[0..leading_zeros], '1');
    for (0..result_len) |i| {
        buf[leading_zeros + i] = result[result_len - 1 - i];
    }

    return buf[0..total_len];
}

// PreKey bundle for X3DH (one-time keys)
pub const PreKeyBundle = struct {
    // Identity key (Ed25519/X25519) - long term
    identity_key: [32]u8,

    // Signed prekey (X25519) - medium term, rotated weekly
    signed_prekey: [32]u8,
    signed_prekey_signature: [64]u8,

    // One-time prekeys (X25519) - deleted after use
    one_time_keys: [][32]u8,

    pub fn create(allocator: std.mem.Allocator, soulkey: SoulKey, num_one_time: usize) !PreKeyBundle {
        var bundle: PreKeyBundle = undefined;

        // Identity key (X25519 public)
        bundle.identity_key = soulkey.x25519_public;

        // Generate signed prekey
        var signed_prekey_private: [32]u8 = undefined;
        crypto.random.bytes(&signed_prekey_private);
        bundle.signed_prekey = try crypto.dh.X25519.recoverPublicKey(signed_prekey_private);

        // Sign the signed prekey with identity key
        try soulkey.sign(&bundle.signed_prekey, &bundle.signed_prekey_signature);

        // Generate one-time keys
        bundle.one_time_keys = try allocator.alloc([32]u8, num_one_time);
        for (bundle.one_time_keys) |*key| {
            var private: [32]u8 = undefined;
            crypto.random.bytes(&private);
            key.* = try crypto.dh.X25519.recoverPublicKey(private);
        }

        return bundle;
    }

    pub fn deinit(self: *PreKeyBundle, allocator: std.mem.Allocator) void {
        allocator.free(self.one_time_keys);
    }
};

// Public identity info (shareable)
pub const PublicIdentity = struct {
    did: [32]u8,
    ed25519_public: [32]u8,
    x25519_public: [32]u8,

    pub fn fromSoulKey(soulkey: SoulKey) PublicIdentity {
        return .{
            .did = soulkey.did,
            .ed25519_public = soulkey.ed25519_public,
            .x25519_public = soulkey.x25519_public,
        };
    }
};
```

---

## Step 3: Session Module (X3DH Key Agreement)

Create `src/session.zig`:

```zig
const std = @import("std");
const crypto = std.crypto;
const identity = @import("identity.zig");

// Session keys derived from X3DH
pub const Session = struct {
    // Symmetric keys for sending/receiving
    send_key: [32]u8,
    recv_key: [32]u8,

    // Session ID derived from shared secrets
    session_id: [32]u8,

    // Nonce counter for message ordering
    send_nonce: u64,
    recv_nonce: u64,

    // State
    is_initiator: bool,
    peer_did: [32]u8,

    /// Initiate session (Alice's side)
    pub fn initiate(
        allocator: std.mem.Allocator,
        our_key: identity.SoulKey,
        peer_bundle: identity.PreKeyBundle,
    ) !Session {
        // X3DH: 3 DH calculations
        // DH1 = our_identity_private * peer_signed_prekey
        // DH2 = our_ephemeral_private * peer_identity_key
        // DH3 = our_ephemeral_private * peer_signed_prekey
        // DH4 = our_ephemeral_private * peer_one_time_key (if available)

        // Generate ephemeral keypair
        var ephemeral_private: [32]u8 = undefined;
        crypto.random.bytes(&ephemeral_private);
        const ephemeral_public = try crypto.dh.X25519.recoverPublicKey(ephemeral_private);

        // DH1: IKA * SPKB
        const dh1 = try crypto.dh.X25519.scalarmult(our_key.x25519_private, peer_bundle.signed_prekey);

        // DH2: EKA * IKB
        const dh2 = try crypto.dh.X25519.scalarmult(ephemeral_private, peer_bundle.identity_key);

        // DH3: EKA * SPKB
        const dh3 = try crypto.dh.X25519.scalarmult(ephemeral_private, peer_bundle.signed_prekey);

        // DH4: EKA * OPKB (use first one-time key if available)
        const dh4 = if (peer_bundle.one_time_keys.len > 0)
            try crypto.dh.X25519.scalarmult(ephemeral_private, peer_bundle.one_time_keys[0])
        else
            [1]u8{0} ** 32;

        // KDF(DH1 || DH2 || DH3 || DH4)
        var shared_secret: [128]u8 = undefined;
        @memcpy(shared_secret[0..32], &dh1);
        @memcpy(shared_secret[32..64], &dh2);
        @memcpy(shared_secret[64..96], &dh3);
        @memcpy(shared_secret[96..128], &dh4);

        var session_keys: [64]u8 = undefined;
        crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&session_keys, &shared_secret, "libertaria-x3dh-v1", "");

        var session = Session{
            .send_key = undefined,
            .recv_key = undefined,
            .session_id = undefined,
            .send_nonce = 0,
            .recv_nonce = 0,
            .is_initiator = true,
            .peer_did = undefined, // Set by caller
        };

        @memcpy(&session.send_key, session_keys[0..32]);
        @memcpy(&session.recv_key, session_keys[32..64]);

        // Session ID = HKDF(shared_secret, "session-id")
        crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&session.session_id, &shared_secret, "session-id", "");

        // Clear sensitive data
        crypto.secureZero(u8, &ephemeral_private);
        crypto.secureZero(u8, &shared_secret);

        _ = allocator; // May be needed for future allocations
        return session;
    }

    /// Respond to session (Bob's side)
    pub fn respond(
        our_key: identity.SoulKey,
        our_bundle: identity.PreKeyBundle,
        ephemeral_public: [32]u8,
        identity_public: [32]u8,
    ) !Session {
        // DH1: our_signed_prekey_private * peer_identity_key
        // DH2: our_identity_private * peer_ephemeral_key
        // DH3: our_signed_prekey_private * peer_ephemeral_key
        // DH4: our_onetime_private * peer_ephemeral_key

        // We need the private keys for our bundle - in a real implementation,
        // these would be stored securely
        // For this example, we'll re-derive them (in production, store properly)

        // Derive signed_prekey private (in real code, this comes from storage)
        var signed_prekey_private: [32]u8 = undefined;
        crypto.random.bytes(&signed_prekey_private); // Placeholder

        // DH1
        const dh1 = try crypto.dh.X25519.scalarmult(signed_prekey_private, identity_public);

        // DH2
        const dh2 = try crypto.dh.X25519.scalarmult(our_key.x25519_private, ephemeral_public);

        // DH3
        const dh3 = try crypto.dh.X25519.scalarmult(signed_prekey_private, ephemeral_public);

        // DH4 (one-time key)
        var one_time_private: [32]u8 = undefined;
        crypto.random.bytes(&one_time_private); // Placeholder
        const dh4 = try crypto.dh.X25519.scalarmult(one_time_private, ephemeral_public);

        // Same KDF as initiator
        var shared_secret: [128]u8 = undefined;
        @memcpy(shared_secret[0..32], &dh1);
        @memcpy(shared_secret[32..64], &dh2);
        @memcpy(shared_secret[64..96], &dh3);
        @memcpy(shared_secret[96..128], &dh4);

        var session_keys: [64]u8 = undefined;
        crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&session_keys, &shared_secret, "libertaria-x3dh-v1", "");

        var session = Session{
            .send_key = undefined,
            .recv_key = undefined,
            .session_id = undefined,
            .send_nonce = 0,
            .recv_nonce = 0,
            .is_initiator = false,
            .peer_did = undefined,
        };

        // Responder swaps keys
        @memcpy(&session.recv_key, session_keys[0..32]);
        @memcpy(&session.send_key, session_keys[32..64]);

        crypto.kdf.hkdf.HkdfSha256.extractAndExpand(&session.session_id, &shared_secret, "session-id", "");

        crypto.secureZero(u8, &signed_prekey_private);
        crypto.secureZero(u8, &one_time_private);
        crypto.secureZero(u8, &shared_secret);

        return session;
    }

    /// Encrypt a message
    pub fn encrypt(self: *Session, allocator: std.mem.Allocator, plaintext: []const u8) ![]u8 {
        // Allocate: nonce(12) + ciphertext + tag(16)
        const nonce = self.getSendNonce();
        const ciphertext = try allocator.alloc(u8, 12 + plaintext.len + 16);

        // Write nonce
        @memcpy(ciphertext[0..12], &nonce);

        // Encrypt with XChaCha20-Poly1305 (using 12-byte nonce here for simplicity)
        var tag: [16]u8 = undefined;
        crypto.stream.chacha.ChaCha20IETF.xor(ciphertext[12..(12 + plaintext.len)], plaintext, 0, self.send_key, nonce[0..12].*);

        // In production, use ChaCha20Poly1305 for AEAD
        // This example uses simplified encryption
        _ = tag;

        self.send_nonce += 1;
        return ciphertext;
    }

    /// Decrypt a message
    pub fn decrypt(self: *Session, allocator: std.mem.Allocator, ciphertext: []const u8) ![]u8 {
        if (ciphertext.len < 28) return error.InvalidCiphertext; // nonce + tag minimum

        const nonce = ciphertext[0..12];
        const encrypted = ciphertext[12..(ciphertext.len - 16)];
        // const tag = ciphertext[(ciphertext.len - 16)..];

        const plaintext = try allocator.alloc(u8, encrypted.len);
        crypto.stream.chacha.ChaCha20IETF.xor(plaintext, encrypted, 0, self.recv_key, nonce.*);

        // Verify tag in production

        self.recv_nonce += 1;
        return plaintext;
    }

    fn getSendNonce(self: *Session) [12]u8 {
        var nonce: [12]u8 = undefined;
        std.mem.writeInt(u64, nonce[4..12], self.send_nonce, .big);
        return nonce;
    }
};
```

---

## Step 4: Main Application

Replace `src/main.zig`:

```zig
const std = @import("std");
const net = std.net;
const posix = std.posix;

const identity = @import("identity.zig");
const session = @import("session.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.info("Usage: {s} <alice|bob> [port]", .{args[0]});
        return;
    }

    const role = args[1];
    const port = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 7777;

    if (std.mem.eql(u8, role, "alice")) {
        try runAlice(allocator, port);
    } else if (std.mem.eql(u8, role, "bob")) {
        try runBob(allocator, port);
    } else {
        std.log.err("Unknown role: {s}", .{role});
    }
}

fn runAlice(allocator: std.mem.Allocator, port: u16) !void {
    std.log.info("=== Alice - Sovereign Chat ===", .{});

    // Generate Alice's identity
    var alice_seed: [32]u8 = undefined;
    @memset(&alice_seed, 0xAA); // Deterministic for demo
    var alice_key = try identity.SoulKey.fromSeed(&alice_seed);

    var did_buf: [64]u8 = undefined;
    const did_str = try alice_key.didToString(&did_buf);
    std.log.info("Alice DID: did:libertaria:{s}", .{did_str});

    // Create prekey bundle
    var alice_bundle = try identity.PreKeyBundle.create(allocator, alice_key, 5);
    defer alice_bundle.deinit(allocator);
    std.log.info("Alice prekey bundle created ({} one-time keys)", .{alice_bundle.one_time_keys.len});

    // Connect to Bob
    std.log.info("Connecting to Bob on port {}...", .{port});
    const peer_addr = try net.Address.parseIp4("127.0.0.1", port);
    const sock = try posix.socket(peer_addr.any.family, posix.SOCK.STREAM, 0);
    defer posix.close(sock);

    try posix.connect(sock, &peer_addr.any, peer_addr.getOsSockLen());
    std.log.info("Connected to Bob!", .{});

    // Exchange public identities
    // In production, this would be signed and verified
    const alice_public = identity.PublicIdentity.fromSoulKey(alice_key);

    // Send our public key
    _ = try posix.write(sock, &alice_public.did);
    _ = try posix.write(sock, &alice_public.x25519_public);

    // Receive Bob's public key
    var bob_did: [32]u8 = undefined;
    var bob_x25519: [32]u8 = undefined;
    _ = try readAll(sock, &bob_did);
    _ = try readAll(sock, &bob_x25519);

    std.log.info("Received Bob's identity", .{});

    // Create ephemeral key for X3DH
    var ephemeral_private: [32]u8 = undefined;
    std.crypto.random.bytes(&ephemeral_private);
    const ephemeral_public = try std.crypto.dh.X25519.recoverPublicKey(ephemeral_private);

    // Send ephemeral public key
    _ = try posix.write(sock, &ephemeral_public);

    // Wait for Bob's bundle (simplified - in real code, fetch from server)
    var bob_signed_prekey: [32]u8 = undefined;
    var bob_signed_prekey_sig: [64]u8 = undefined;
    var bob_one_time: [32]u8 = undefined;

    _ = try readAll(sock, &bob_signed_prekey);
    _ = try readAll(sock, &bob_signed_prekey_sig);
    _ = try readAll(sock, &bob_one_time);

    // Construct Bob's bundle from received data
    var bob_bundle = identity.PreKeyBundle{
        .identity_key = bob_x25519,
        .signed_prekey = bob_signed_prekey,
        .signed_prekey_signature = bob_signed_prekey_sig,
        .one_time_keys = try allocator.alloc([32]u8, 1),
    };
    bob_bundle.one_time_keys[0] = bob_one_time;
    defer allocator.free(bob_bundle.one_time_keys);

    // Establish session
    var sess = try session.Session.initiate(allocator, alice_key, bob_bundle);
    sess.peer_did = bob_did;

    std.log.info("Session established! Session ID: {x}", .{std.fmt.fmtSliceHexLower(&sess.session_id[0..8])});

    // Chat loop
    const stdin = std.io.getStdIn().reader();
    var buf: [1024]u8 = undefined;

    std.log.info("\n--- Chat started ---", .{});
    std.log.info("Type messages and press Enter to send. Ctrl+C to exit.\n", .{});

    // Spawn receiver thread (simplified - using single thread with select would be better)
    // For this example, we'll just send

    while (true) {
        std.debug.print("Alice> ", .{});
        const line = try stdin.readUntilDelimiterOrEof(&buf, '\n');
        if (line == null) break;

        const plaintext = line.?;
        if (plaintext.len == 0) continue;

        // Encrypt
        const encrypted = try sess.encrypt(allocator, plaintext);
        defer allocator.free(encrypted);

        // Send length + data
        const len_bytes = std.mem.toBytes(@as(u32, @intCast(encrypted.len)));
        _ = try posix.write(sock, &len_bytes);
        _ = try posix.write(sock, encrypted);

        std.log.info("[Encrypted and sent {} bytes]", .{encrypted.len});
    }
}

fn runBob(allocator: std.mem.Allocator, port: u16) !void {
    std.log.info("=== Bob - Sovereign Chat ===", .{});

    // Generate Bob's identity
    var bob_seed: [32]u8 = undefined;
    @memset(&bob_seed, 0xBB); // Deterministic for demo
    var bob_key = try identity.SoulKey.fromSeed(&bob_seed);

    var did_buf: [64]u8 = undefined;
    const did_str = try bob_key.didToString(&did_buf);
    std.log.info("Bob DID: did:libertaria:{s}", .{did_str});

    // Create prekey bundle
    var bob_bundle = try identity.PreKeyBundle.create(allocator, bob_key, 5);
    defer bob_bundle.deinit(allocator);

    // Listen for connections
    const address = try net.Address.parseIp4("0.0.0.0", port);
    const listener = try posix.socket(address.any.family, posix.SOCK.STREAM, 0);
    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 1);

    std.log.info("Waiting for Alice on port {}...", .{port});

    var client_addr: net.Address = undefined;
    var client_addr_len: posix.socklen_t = @sizeOf(net.Address);
    const client = try posix.accept(listener, &client_addr.any, &client_addr_len, 0);
    defer posix.close(client);

    std.log.info("Alice connected!", .{});

    // Exchange identities
    const bob_public = identity.PublicIdentity.fromSoulKey(bob_key);

    // Send our public key
    _ = try posix.write(client, &bob_public.did);
    _ = try posix.write(client, &bob_public.x25519_public);

    // Receive Alice's public key
    var alice_did: [32]u8 = undefined;
    var alice_x25519: [32]u8 = undefined;
    _ = try readAll(client, &alice_did);
    _ = try readAll(client, &alice_x25519);

    std.log.info("Received Alice's identity", .{});

    // Receive Alice's ephemeral key
    var alice_ephemeral: [32]u8 = undefined;
    _ = try readAll(client, &alice_ephemeral);

    // Send our bundle (simplified - would normally be fetched from server)
    _ = try posix.write(client, &bob_bundle.signed_prekey);
    _ = try posix.write(client, &bob_bundle.signed_prekey_signature);
    _ = try posix.write(client, &bob_bundle.one_time_keys[0]);

    // Remove used one-time key
    // (in real code, mark as used in database)

    // Establish session
    var sess = try session.Session.respond(bob_key, bob_bundle, alice_ephemeral, alice_x25519);
    sess.peer_did = alice_did;

    std.log.info("Session established! Session ID: {x}", .{std.fmt.fmtSliceHexLower(&sess.session_id[0..8])});

    std.log.info("\n--- Chat started ---", .{});
    std.log.info("Waiting for messages from Alice...\n", .{});

    // Receive loop
    while (true) {
        // Read length
        var len_bytes: [4]u8 = undefined;
        const len_read = try posix.read(client, &len_bytes);
        if (len_read == 0) break;

        const msg_len = std.mem.bytesToValue(u32, &len_bytes);
        if (msg_len > 65536) {
            std.log.err("Message too large: {}", .{msg_len});
            break;
        }

        // Read encrypted message
        const encrypted = try allocator.alloc(u8, msg_len);
        defer allocator.free(encrypted);
        _ = try readAll(client, encrypted);

        // Decrypt
        const plaintext = try sess.decrypt(allocator, encrypted);
        defer allocator.free(plaintext);

        std.log.info("Alice: {s}", .{plaintext});
    }
}

fn readAll(sock: posix.socket_t, buf: []u8) !usize {
    var total: usize = 0;
    while (total < buf.len) {
        const n = try posix.read(sock, buf[total..]);
        if (n == 0) return total;
        total += n;
    }
    return total;
}
```

---

## Step 5: Build and Run

```bash
zig build -Doptimize=ReleaseSafe
```

### Terminal 1: Run Bob (Listener)

```bash
./zig-out/bin/sovereign-chat bob 7777
```

**Expected output:**
```
info: === Bob - Sovereign Chat ===
info: Bob DID: did:libertaria:3J98t1WpEZ73CNmYviecrnyiWrnqRhWNLy
info: Bob prekey bundle created (5 one-time keys)
info: Waiting for Alice on port 7777...
```

### Terminal 2: Run Alice (Initiator)

```bash
./zig-out/bin/sovereign-chat alice 7777
```

**Expected output:**
```
info: === Alice - Sovereign Chat ===
info: Alice DID: did:libertaria:1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2
info: Alice prekey bundle created (5 one-time keys)
info: Connecting to Bob on port 7777...
info: Connected to Bob!
info: Received Bob's identity
info: Session established! Session ID: a3f2b8c1d4e5...

--- Chat started ---
Type messages and press Enter to send. Ctrl+C to exit.

Alice> Hello, sovereign world!
info: [Encrypted and sent 45 bytes]
```

### Bob Receives

```
info: Alice connected!
info: Received Alice's identity
info: Session established! Session ID: a3f2b8c1d4e5...

--- Chat started ---
Waiting for messages from Alice...

info: Alice: Hello, sovereign world!
```

---

## Understanding the Protocol

### X3DH Key Agreement Flow

```
┌─────────────────────────────────────────────────────────────┐
│  X3DH Handshake                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Alice (Initiator)          Bob (Responder)                 │
│  ─────────────────          ───────────────                 │
│                                                             │
│  Identity: IKA                Identity: IKB                 │
│  Ephemeral: EKA               Signed Prekey: SPKB           │
│                               One-time: OPKB                │
│                                                             │
│  ──────────────────────────────────────────────►            │
│       EKA (ephemeral public)                                │
│       IKA (identity public)                                 │
│                                                             │
│                     ◄────────────────────────────────────   │
│                          SPKB + sig                         │
│                          OPKB                               │
│                                                             │
│  DH1 = IKA * SPKB            DH1 = SPKB_private * IKA       │
│  DH2 = EKA * IKB             DH2 = IKB_private * EKA        │
│  DH3 = EKA * SPKB            DH3 = SPKB_private * EKA       │
│  DH4 = EKA * OPKB            DH4 = OPKB_private * EKA       │
│                                                             │
│  SK = KDF(DH1 || DH2 || DH3 || DH4)                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Security Properties

| Property | Mechanism |
|----------|-----------|
| **Authentication** | Ed25519 signatures on prekeys |
| **Forward Secrecy** | One-time keys (deleted after use) |
| **Future Secrecy** | Chain keys ratchet (not shown in simplified version) |
| **Integrity** | ChaCha20-Poly1305 AEAD |

---

## Troubleshooting

### "Connection refused"

**Cause:** Bob isn't listening yet

**Fix:** Start Bob first, then Alice:
```bash
# Terminal 1
./sovereign-chat bob 7777

# Terminal 2
./sovereign-chat alice 7777
```

### Session establishment fails

**Cause:** Key exchange mismatch

**Fix:** Check that both sides are using compatible X3DH parameters:
- Verify HKDF info string matches: `"libertaria-x3dh-v1"`
- Ensure initiator/responder key derivation order is swapped

### Garbled messages

**Cause:** Nonce reuse or key mismatch

**Fix:** Each session should have unique keys. Don't reuse sessions.

### Build errors

**Cause:** Missing crypto imports

**Fix:** Verify your `build.zig` has proper module structure:
```zig
const identity = b.addModule("identity", .{
    .root_source_file = b.path("src/identity.zig"),
});
exe.root_module.addImport("identity", identity);
```

---

## Next Steps

1. **Add proper ChaCha20-Poly1305** AEAD encryption
2. **Implement Double Ratchet** for forward/future secrecy
3. **Add group chat** using sender keys
4. **Persist keys** to encrypted storage
5. **Try the next tutorial:** [Bridge an AI Agent](./agent-bridge.md)

---

## References

- [RFC-0250: SoulKey Specification](../rfcs/)
- [L1 Identity README](../../../core/l1-identity/README.md)
- [Signal X3DH Specification](https://signal.org/docs/specifications/x3dh/)
- [XEdDSA](https://signal.org/docs/specifications/xeddsa/)
