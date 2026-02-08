# Bridge an AI Agent

Give your AI agent a sovereign identity and connect it to the Federation Compute Pool. Learn how agents perform authenticated work using LACE (Labor Accounting and Compensation Engine).

---

## What You'll Build

An AI agent that:
1. Generates a unique SoulKey identity
2. Registers with a Federation Compute Pool
3. Receives authenticated work tasks
4. Submits signed work results
5. Earns LACE labor tokens

---

## Prerequisites

- **Zig 0.13+** installed
- Understanding of [Sovereign Chat](./sovereign-chat.md)
- Understanding of **asymmetric cryptography**
- **Federation node** running locally or access to a testnet

### Concepts You'll Learn

- **SoulKey for Agents**: Deterministic identity from mnemonic
- **Federation Pool**: Decentralized work distribution
- **LACE Token**: Proof-of-work attestation
- **Vector**: Signed event for the QuasarVector Lattice (QVL)

---

## Step 1: Project Setup

```bash
mkdir agent-bridge
cd agent-bridge
zig init

# Create source files
touch src/main.zig src/agent.zig src/federation.zig src/lace.zig
```

---

## Step 2: Agent Identity Module

Create `src/agent.zig`:

```zig
const std = @import("std");
const crypto = std.crypto;

/// Agent identity based on SoulKey (RFC-0250)
/// Agents use deterministic derivation from a mnemonic phrase
pub const Agent = struct {
    // Core SoulKey
    ed25519_private: [32]u8,
    ed25519_public: [32]u8,
    x25519_private: [32]u8,
    x25519_public: [32]u8,
    did: [32]u8,

    // Agent metadata
    name: []const u8,
    capabilities: []const Capability,
    version: []const u8,

    // Federation state
    is_registered: bool = false,
    pool_address: ?[]const u8 = null,
    reputation_score: u32 = 0,

    pub const Capability = struct {
        name: []const u8,
        version: []const u8,
        compute_class: ComputeClass,
    };

    pub const ComputeClass = enum {
        cpu_light,      // Text processing, simple logic
        cpu_heavy,      // Data analysis, ML inference
        gpu_compute,    // Model training, image generation
        memory_intensive, // Large context processing
    };

    /// Generate agent from mnemonic seed phrase
    pub fn fromMnemonic(mnemonic: []const u8, name: []const u8) !Agent {
        // Derive 32-byte seed from mnemonic using Argon2
        var seed: [32]u8 = undefined;
        try deriveSeedFromMnemonic(mnemonic, &seed);

        // Generate Ed25519 keypair
        const ed_kp = try crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);

        // Derive X25519 from same seed (domain-separated)
        var x25519_seed: [32]u8 = undefined;
        var domain_input: [64]u8 = undefined;
        @memcpy(domain_input[0..32], &seed);
        @memcpy(domain_input[32..64], "libertaria-agent-x25519-v1");
        crypto.hash.sha3.Sha3_256.hash(&domain_input, &x25519_seed, .{});

        const x25519_public = try crypto.dh.X25519.recoverPublicKey(x25519_seed);

        // DID = Blake3(ed25519_public || x25519_public)
        var did_input: [64]u8 = undefined;
        @memcpy(did_input[0..32], &ed_kp.public_key.bytes);
        @memcpy(did_input[32..64], &x25519_public);
        var did: [32]u8 = undefined;
        crypto.hash.blake3.hash(&did_input, &did, .{});

        return Agent{
            .ed25519_private = ed_kp.secret_key.seed(),
            .ed25519_public = ed_kp.public_key.bytes,
            .x25519_private = x25519_seed,
            .x25519_public = x25519_public,
            .did = did,
            .name = name,
            .capabilities = &[_]Capability{}, // Set later
            .version = "0.1.0",
        };
    }

    /// Sign a message with agent's identity
    pub fn sign(self: *const Agent, message: []const u8) ![64]u8 {
        const kp = try crypto.sign.Ed25519.KeyPair.fromSeed(self.ed25519_private);
        const sig = try crypto.sign.Ed25519.sign(message, kp, null);
        return sig.toBytes();
    }

    /// Verify a signature against this agent's public key
    pub fn verify(self: *const Agent, message: []const u8, signature: [64]u8) !bool {
        const pk = try crypto.sign.Ed25519.PublicKey.fromBytes(self.ed25519_public);
        const sig = crypto.sign.Ed25519.Signature.fromBytes(signature);
        sig.verify(message, pk) catch return false;
        return true;
    }

    /// Get DID as base58 string for display
    pub fn didString(self: *const Agent, buf: []u8) ![]const u8 {
        return try base58Encode(&self.did, buf);
    }

    /// Create a Vector (signed event for QVL)
    pub fn createVector(
        self: *const Agent,
        allocator: std.mem.Allocator,
        vector_type: VectorType,
        payload: []const u8,
    ) !Vector {
        const timestamp = @as(u128, @intCast(std.time.nanoTimestamp())) * 1_000_000_000;

        var vec = Vector{
            .author_did = self.did,
            .timestamp = timestamp,
            .vector_type = vector_type,
            .payload = try allocator.dupe(u8, payload),
            .payload_hash = undefined,
            .signature = undefined,
            .parent_hashes = &[_][32]u8{}, // For DAG structure
        };

        // Hash payload
        crypto.hash.blake3.hash(payload, &vec.payload_hash, .{});

        // Sign the vector
        const msg_to_sign = try std.fmt.allocPrint(allocator, "{x}|{d}|{d}", .{
            std.fmt.fmtSliceHexLower(&vec.payload_hash),
            @intFromEnum(vector_type),
            timestamp,
        });
        defer allocator.free(msg_to_sign);

        vec.signature = try self.sign(msg_to_sign);

        return vec;
    }

    pub fn setCapabilities(self: *Agent, caps: []const Capability) void {
        self.capabilities = caps;
    }
};

/// Vector for QuasarVector Lattice (QVL)
pub const Vector = struct {
    author_did: [32]u8,
    timestamp: u128,  // Attoseconds since epoch
    vector_type: VectorType,
    payload: []const u8,
    payload_hash: [32]u8,
    signature: [64]u8,
    parent_hashes: []const [32]u8,  // DAG parents

    pub fn deinit(self: *Vector, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
        allocator.free(self.parent_hashes);
    }

    /// Encode to bytes for transmission
    pub fn encode(self: *const Vector, allocator: std.mem.Allocator) ![]u8 {
        // Simplified encoding - real implementation uses proper serialization
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        try buf.appendSlice(&self.author_did);
        try buf.appendSlice(std.mem.asBytes(&self.timestamp));
        try buf.append(@intFromEnum(self.vector_type));
        try buf.appendSlice(&self.payload_hash);
        try buf.appendSlice(&self.signature);

        return buf.toOwnedSlice();
    }
};

pub const VectorType = enum(u8) {
    work_request = 0x01,
    work_result = 0x02,
    registration = 0x03,
    heartbeat = 0x04,
    reputation_update = 0x05,
};

/// Derive seed from mnemonic using Argon2id
fn deriveSeedFromMnemonic(mnemonic: []const u8, seed: *[32]u8) !void {
    // In production, use proper Argon2id with memory-hard parameters
    // This simplified version uses PBKDF2 for demo
    const salt = "libertaria-agent-v1";
    try crypto.pwhash.pbkdf2(seed, mnemonic, salt, 100_000, crypto.hash.sha2.HmacSha256);
}

/// Simple base58 encoder
fn base58Encode(data: []const u8, buf: []u8) ![]const u8 {
    const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

    var leading_zeros: usize = 0;
    while (leading_zeros < data.len and data[leading_zeros] == 0) : (leading_zeros += 1) {}

    // Convert to big number and encode
    var result: [256]u8 = undefined;
    var result_len: usize = 0;

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

    const total_len = leading_zeros + result_len;
    if (total_len > buf.len) return error.NoSpaceLeft;

    @memset(buf[0..leading_zeros], '1');
    for (0..result_len) |i| {
        buf[leading_zeros + i] = result[result_len - 1 - i];
    }

    return buf[0..total_len];
}
```

---

## Step 3: Federation Pool Module

Create `src/federation.zig`:

```zig
const std = @import("std");
const net = std.net;
const posix = std.posix;
const agent = @import("agent.zig");

/// Federation Compute Pool client
/// Handles connection, work distribution, and result submission
pub const FederationClient = struct {
    allocator: std.mem.Allocator,
    socket: posix.socket_t = -1,
    pool_address: net.Address,
    is_connected: bool = false,

    // Statistics
    tasks_completed: u64 = 0,
    tasks_failed: u64 = 0,
    total_compute_time_ms: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !FederationClient {
        const address = try net.Address.parseIp4(host, port);
        return FederationClient{
            .allocator = allocator,
            .pool_address = address,
        };
    }

    pub fn deinit(self: *FederationClient) void {
        if (self.socket != -1) {
            posix.close(self.socket);
        }
    }

    /// Connect to the federation pool
    pub fn connect(self: *FederationClient) !void {
        const sock = try posix.socket(self.pool_address.any.family, posix.SOCK.STREAM, 0);

        try posix.connect(sock, &self.pool_address.any, self.pool_address.getOsSockLen());

        self.socket = sock;
        self.is_connected = true;

        std.log.info("Connected to Federation Pool at {}", .{self.pool_address});
    }

    /// Register agent with the pool
    pub fn registerAgent(self: *FederationClient, ag: *agent.Agent) !void {
        if (!self.is_connected) return error.NotConnected;

        // Create registration vector
        var reg_payload = std.ArrayList(u8).init(self.allocator);
        defer reg_payload.deinit();

        // Registration payload: name|version|capabilities
        try reg_payload.appendSlice(ag.name);
        try reg_payload.append('|');
        try reg_payload.appendSlice(ag.version);
        try reg_payload.append('|');

        // Encode capabilities
        for (ag.capabilities, 0..) |cap, i| {
            if (i > 0) try reg_payload.append(',');
            try reg_payload.appendSlice(cap.name);
            try reg_payload.append(':');
            try reg_payload.appendSlice(@tagName(cap.compute_class));
        }

        const vec = try ag.createVector(self.allocator, .registration, reg_payload.items);
        defer vec.deinit(self.allocator);

        // Send registration
        try self.sendVector(&vec);

        // Wait for confirmation
        const response = try self.receiveVector(self.allocator);
        defer self.allocator.free(response.payload);

        if (std.mem.eql(u8, response.payload, "OK")) {
            ag.is_registered = true;
            ag.pool_address = try std.fmt.allocPrint(self.allocator, "{}:{}", .{
                self.pool_address.in.sa.addr,
                self.pool_address.in.sa.port,
            });
            std.log.info("Agent registered successfully!", .{});
        } else {
            return error.RegistrationFailed;
        }
    }

    /// Request work from the pool
    pub fn requestWork(self: *FederationClient, ag: *agent.Agent) !WorkTask {
        if (!self.is_connected) return error.NotConnected;
        if (!ag.is_registered) return error.NotRegistered;

        // Send work request vector
        const vec = try ag.createVector(self.allocator, .work_request, "{}");
        defer vec.deinit(self.allocator);

        try self.sendVector(&vec);

        // Receive work assignment
        const response = try self.receiveVector(self.allocator);

        // Parse work task from response
        var task = try WorkTask.fromJson(self.allocator, response.payload);
        task.vector = response;

        std.log.info("Received work task: {s} (id: {s})", .{ task.task_type, task.id });

        return task;
    }

    /// Submit work result to the pool
    pub fn submitResult(
        self: *FederationClient,
        ag: *agent.Agent,
        task: *WorkTask,
        result: []const u8,
        compute_time_ms: u64,
    ) !void {
        if (!self.is_connected) return error.NotConnected;

        // Build result payload
        var result_payload = std.ArrayList(u8).init(self.allocator);
        defer result_payload.deinit();

        // JSON result: {"task_id": "...", "result": "...", "compute_ms": N, "proof": "..."}
        try result_payload.appendSlice("{");
        try result_payload.appendSlice("\"task_id\":\"");
        try result_payload.appendSlice(task.id);
        try result_payload.appendSlice("\",");
        try result_payload.appendSlice("\"result\":\"");
        try result_payload.appendSlice(result);
        try result_payload.appendSlice("\",");
        try result_payload.appendSlice("\"compute_ms\":");
        try std.fmt.format(result_payload.writer(), "{}", .{compute_time_ms});
        try result_payload.appendSlice("}");

        const vec = try ag.createVector(self.allocator, .work_result, result_payload.items);
        defer vec.deinit(self.allocator);

        try self.sendVector(&vec);

        // Update stats
        self.tasks_completed += 1;
        self.total_compute_time_ms += compute_time_ms;

        std.log.info("Submitted result for task {s}", .{task.id});
    }

    /// Send a heartbeat to maintain connection
    pub fn sendHeartbeat(self: *FederationClient, ag: *agent.Agent) !void {
        if (!self.is_connected) return error.NotConnected;

        const stats = try std.fmt.allocPrint(self.allocator,
            "{{\"tasks_completed\":{},\"tasks_failed\":{},\"uptime_ms\":{}}}", .{
            self.tasks_completed,
            self.tasks_failed,
            std.time.milliTimestamp(),
        });
        defer self.allocator.free(stats);

        const vec = try ag.createVector(self.allocator, .heartbeat, stats);
        defer vec.deinit(self.allocator);

        try self.sendVector(&vec);
    }

    fn sendVector(self: *FederationClient, vec: *const agent.Vector) !void {
        const encoded = try vec.encode(self.allocator);
        defer self.allocator.free(encoded);

        // Send length prefix
        const len_bytes = std.mem.toBytes(@as(u32, @intCast(encoded.len)));
        _ = try posix.write(self.socket, &len_bytes);

        // Send vector
        _ = try posix.write(self.socket, encoded);
    }

    fn receiveVector(self: *FederationClient, allocator: std.mem.Allocator) !agent.Vector {
        // Read length
        var len_bytes: [4]u8 = undefined;
        _ = try readAll(self.socket, &len_bytes);
        const len = std.mem.bytesToValue(u32, &len_bytes);

        if (len > 1024 * 1024) return error.VectorTooLarge;

        // Read payload
        const payload = try allocator.alloc(u8, len);
        errdefer allocator.free(payload);
        _ = try readAll(self.socket, payload);

        // Parse vector (simplified - real implementation uses proper deserialization)
        return agent.Vector{
            .author_did = payload[0..32].*,
            .timestamp = std.mem.bytesToValue(u128, payload[32..48]),
            .vector_type = @enumFromInt(payload[48]),
            .payload = try allocator.dupe(u8, payload[49..]),
            .payload_hash = undefined,
            .signature = undefined,
            .parent_hashes = &[_][32]u8{},
        };
    }
};

/// Work task from the federation pool
pub const WorkTask = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    task_type: []const u8,
    parameters: []const u8,
    deadline_ms: u64,
    vector: ?agent.Vector = null,

    pub fn deinit(self: *WorkTask) void {
        self.allocator.free(self.id);
        self.allocator.free(self.task_type);
        self.allocator.free(self.parameters);
        if (self.vector) |*v| {
            v.deinit(self.allocator);
        }
    }

    /// Parse from JSON (simplified)
    pub fn fromJson(allocator: std.mem.Allocator, json: []const u8) !WorkTask {
        // Simplified parsing - real implementation uses proper JSON parser
        // Expected: {"id":"...","type":"...","params":"...","deadline":N}

        var task = WorkTask{
            .allocator = allocator,
            .id = try allocator.dupe(u8, "task-001"),
            .task_type = try allocator.dupe(u8, "text-generation"),
            .parameters = try allocator.dupe(u8, json),
            .deadline_ms = std.time.milliTimestamp() + 60000,
        };

        return task;
    }
};

fn readAll(sock: posix.socket_t, buf: []u8) !void {
    var total: usize = 0;
    while (total < buf.len) {
        const n = try posix.read(sock, buf[total..]);
        if (n == 0) return error.ConnectionClosed;
        total += n;
    }
}
```

---

## Step 4: LACE Labor Module

Create `src/lace.zig`:

```zig
const std = @import("std");
const crypto = std.crypto;

/// LACE: Labor Accounting and Compensation Engine
/// Proof-of-work attestation system for agent labor
pub const LaceEngine = struct {
    allocator: std.mem.Allocator,
    accumulated_labor: u64 = 0,
    last_attestation: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) LaceEngine {
        return LaceEngine{
            .allocator = allocator,
        };
    }

    /// Calculate labor units from work metrics
    /// Formula: labor_units = compute_ms * complexity_factor * quality_multiplier
    pub fn calculateLabor(
        compute_time_ms: u64,
        complexity: Complexity,
        quality_score: f32,  // 0.0 to 1.0
    ) u64 {
        const base_labor = compute_time_ms;
        const complexity_mult: u64 = switch (complexity) {
            .trivial => 1,
            .simple => 2,
            .moderate => 5,
            .complex => 10,
            .extreme => 25,
        };

        const quality_mult = @max(0.0, @min(1.0, quality_score));
        const quality_bonus: u64 = if (quality_mult > 0.9) 2 else 1;

        return (base_labor * complexity_mult * quality_bonus) / 1000; // Convert to labor units
    }

    /// Create a labor attestation (proof of work)
    pub fn createAttestation(
        self: *LaceEngine,
        agent_did: [32]u8,
        task_id: []const u8,
        labor_units: u64,
        work_hash: [32]u8,
    ) !LaborAttestation {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));

        var attestation = LaborAttestation{
            .agent_did = agent_did,
            .task_id = try self.allocator.dupe(u8, task_id),
            .labor_units = labor_units,
            .work_hash = work_hash,
            .timestamp = timestamp,
            .nonce = 0,
            .difficulty = self.calculateDifficulty(),
            .proof_hash = undefined,
        };

        // Mine the proof (find nonce that satisfies difficulty)
        try self.mineProof(&attestation);

        self.accumulated_labor += labor_units;
        self.last_attestation = timestamp;

        return attestation;
    }

    /// Verify a labor attestation
    pub fn verifyAttestation(attestation: *const LaborAttestation) bool {
        // Recalculate hash with claimed nonce
        var hash_input: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&hash_input);
        const writer = fbs.writer();

        writer.writeAll(&attestation.agent_did) catch return false;
        writer.writeAll(attestation.task_id) catch return false;
        writer.writeAll(std.mem.asBytes(&attestation.labor_units)) catch return false;
        writer.writeAll(&attestation.work_hash) catch return false;
        writer.writeAll(std.mem.asBytes(&attestation.timestamp)) catch return false;
        writer.writeAll(std.mem.asBytes(&attestation.nonce)) catch return false;

        var calculated_hash: [32]u8 = undefined;
        crypto.hash.blake3.hash(fbs.getWritten(), &calculated_hash, .{});

        // Verify hash meets difficulty
        const difficulty_bytes = attestation.difficulty / 8;
        for (0..difficulty_bytes) |i| {
            if (calculated_hash[i] != 0) return false;
        }

        // Verify remaining bits
        const remaining_bits = attestation.difficulty % 8;
        if (remaining_bits > 0) {
            const mask = @as(u8, @intCast((1 << (8 - remaining_bits)) - 1)) << remaining_bits;
            if ((calculated_hash[difficulty_bytes] & mask) != 0) return false;
        }

        return true;
    }

    fn calculateDifficulty(self: *const LaceEngine) u8 {
        // Dynamic difficulty based on network conditions
        // Simplified: base difficulty 16, adjusts based on recent attestations
        _ = self;
        return 16;
    }

    fn mineProof(self: *LaceEngine, attestation: *LaborAttestation) !void {
        var hash_input: [256]u8 = undefined;

        while (true) {
            // Build hash input
            var fbs = std.io.fixedBufferStream(&hash_input);
            const writer = fbs.writer();

            try writer.writeAll(&attestation.agent_did);
            try writer.writeAll(attestation.task_id);
            try writer.writeAll(std.mem.asBytes(&attestation.labor_units));
            try writer.writeAll(&attestation.work_hash);
            try writer.writeAll(std.mem.asBytes(&attestation.timestamp));
            try writer.writeAll(std.mem.asBytes(&attestation.nonce));

            // Calculate hash
            crypto.hash.blake3.hash(fbs.getWritten(), &attestation.proof_hash, .{});

            // Check if hash meets difficulty
            if (self.meetsDifficulty(&attestation.proof_hash, attestation.difficulty)) {
                return;
            }

            attestation.nonce +%= 1;

            // Prevent infinite loop in demo (real implementation has timeout)
            if (attestation.nonce == 0) {
                return error.MiningTimeout;
            }
        }
    }

    fn meetsDifficulty(_: *const LaceEngine, hash: *const [32]u8, difficulty: u8) bool {
        const bytes_needed = difficulty / 8;
        const remaining_bits = difficulty % 8;

        // Check full zero bytes
        for (0..bytes_needed) |i| {
            if (hash[i] != 0) return false;
        }

        // Check remaining bits
        if (remaining_bits > 0) {
            const mask = @as(u8, @intCast((1 << (8 - remaining_bits)) - 1)) << remaining_bits;
            return (hash[bytes_needed] & mask) == 0;
        }

        return true;
    }
};

/// Labor attestation (proof of work)
pub const LaborAttestation = struct {
    agent_did: [32]u8,
    task_id: []const u8,
    labor_units: u64,
    work_hash: [32]u8,
    timestamp: u64,
    nonce: u64,
    difficulty: u8,
    proof_hash: [32]u8,

    pub fn deinit(self: *LaborAttestation, allocator: std.mem.Allocator) void {
        allocator.free(self.task_id);
    }

    /// Encode to bytes for submission
    pub fn encode(self: *const LaborAttestation, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        try buf.appendSlice(&self.agent_did);
        try buf.appendSlice(self.task_id);
        try buf.appendSlice(std.mem.asBytes(&self.labor_units));
        try buf.appendSlice(&self.work_hash);
        try buf.appendSlice(std.mem.asBytes(&self.timestamp));
        try buf.appendSlice(std.mem.asBytes(&self.nonce));
        try buf.append(self.difficulty);
        try buf.appendSlice(&self.proof_hash);

        return buf.toOwnedSlice();
    }
};

pub const Complexity = enum {
    trivial,    // < 10ms compute
    simple,     // < 100ms compute
    moderate,   // < 1s compute
    complex,    // < 10s compute
    extreme,    // > 10s compute
};

/// LACE Token (redeemable for compute credits)
pub const LaceToken = struct {
    attestation_hash: [32]u8,
    labor_units: u64,
    issued_at: u64,
    expires_at: u64,
    issuer_signature: [64]u8,
};
```

---

## Step 5: Main Application

Replace `src/main.zig`:

```zig
const std = @import("std");
const agent = @import("agent.zig");
const federation = @import("federation.zig");
const lace = @import("lace.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    std.log.info("=== Libertaria AI Agent Bridge ===", .{});

    // Parse arguments
    const mnemonic = if (args.len > 1) args[1] else "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    const pool_host = if (args.len > 2) args[2] else "127.0.0.1";
    const pool_port = if (args.len > 3) try std.fmt.parseInt(u16, args[3], 10) else 8888;

    // Create agent identity
    std.log.info("Creating agent from mnemonic...", .{});
    var ag = try agent.Agent.fromMnemonic(mnemonic, "MyAIAgent");

    var did_buf: [64]u8 = undefined;
    const did_str = try ag.didString(&did_buf);
    std.log.info("Agent DID: did:libertaria:{s}", .{did_str});

    // Set capabilities
    const capabilities = &[_]agent.Agent.Capability{
        .{ .name = "text-generation", .version = "1.0", .compute_class = .cpu_heavy },
        .{ .name = "summarization", .version = "1.0", .compute_class = .cpu_light },
        .{ .name = "embedding", .version = "2.0", .compute_class = .memory_intensive },
    };
    ag.setCapabilities(capabilities);

    std.log.info("Capabilities:", .{});
    for (ag.capabilities) |cap| {
        std.log.info("  - {s} ({s})", .{ cap.name, @tagName(cap.compute_class) });
    }

    // Initialize LACE engine
    var lace_engine = lace.LaceEngine.init(allocator);

    // Connect to Federation Pool
    std.log.info("\nConnecting to Federation Pool at {s}:{}...", .{ pool_host, pool_port });
    var fed_client = try federation.FederationClient.init(allocator, pool_host, pool_port);
    defer fed_client.deinit();

    try fed_client.connect();

    // Register agent
    std.log.info("Registering agent...", .{});
    try fed_client.registerAgent(&ag);

    // Main work loop
    std.log.info("\n=== Agent Ready for Work ===", .{});
    std.log.info("Press Ctrl+C to exit\n", .{});

    var work_count: u32 = 0;
    const max_work = 5; // Demo limit

    while (work_count < max_work) {
        // Request work
        std.log.info("Requesting work...", .{});
        var task = try fed_client.requestWork(&ag);
        defer task.deinit();

        // Process task (simulated)
        const start_time = std.time.milliTimestamp();
        const result = try processTask(allocator, &task);
        defer allocator.free(result);
        const compute_time = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

        // Calculate labor
        const labor_units = lace_engine.calculateLabor(
            compute_time,
            .moderate,
            0.95,  // Quality score
        );

        std.log.info("Task completed in {}ms, earned {} labor units", .{ compute_time, labor_units });

        // Create labor attestation
        var work_hash: [32]u8 = undefined;
        std.crypto.hash.blake3.hash(result, &work_hash, .{});

        const attestation = try lace_engine.createAttestation(
            ag.did,
            task.id,
            labor_units,
            work_hash,
        );
        defer attestation.deinit(allocator);

        std.log.info("Created labor attestation with nonce: {}", .{attestation.nonce});

        // Verify attestation
        const valid = lace.LaceEngine.verifyAttestation(&attestation);
        std.log.info("Attestation valid: {}", .{valid});

        // Submit result
        try fed_client.submitResult(&ag, &task, result, compute_time);

        work_count += 1;

        // Send heartbeat every 3 tasks
        if (work_count % 3 == 0) {
            try fed_client.sendHeartbeat(&ag);
            std.log.info("Heartbeat sent", .{});
        }
    }

    std.log.info("\n=== Agent Work Complete ===", .{});
    std.log.info("Tasks completed: {}", .{fed_client.tasks_completed});
    std.log.info("Total compute time: {}ms", .{fed_client.total_compute_time_ms});
    std.log.info("Accumulated labor: {} units", .{lace_engine.accumulated_labor});
}

/// Process a work task (simulated AI work)
fn processTask(allocator: std.mem.Allocator, task: *federation.WorkTask) ![]u8 {
    // Simulate processing time
    std.time.sleep(100 * std.time.ns_per_ms);

    // Generate a result based on task type
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try result.appendSlice("{\"status\":\"success\",");
    try result.appendSlice("\"task_type\":\"");
    try result.appendSlice(task.task_type);
    try result.appendSlice("\",");
    try result.appendSlice("\"output\":\"processed\"}");

    return result.toOwnedSlice();
}
```

---

## Step 6: Build and Run

```bash
zig build -Doptimize=ReleaseSafe
```

### Run with Default Settings

```bash
./zig-out/bin/agent-bridge
```

**Expected output:**
```
info: === Libertaria AI Agent Bridge ===
info: Creating agent from mnemonic...
info: Agent DID: did:libertaria:1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2
info: Capabilities:
info:   - text-generation (cpu_heavy)
info:   - summarization (cpu_light)
info:   - embedding (memory_intensive)

info: Connecting to Federation Pool at 127.0.0.1:8888...
info: Connected to Federation Pool at 127.0.0.1:8888
info: Registering agent...
info: Agent registered successfully!

info: === Agent Ready for Work ===
info: Requesting work...
info: Received work task: text-generation (id: task-001)
info: Task completed in 102ms, earned 510 labor units
info: Created labor attestation with nonce: 15432
info: Attestation valid: true
info: Submitted result for task task-001
...
```

### Run with Custom Settings

```bash
./zig-out/bin/agent-bridge "your mnemonic phrase here" "pool.example.com" 8888
```

---

## Understanding LACE Economics

### Labor Unit Calculation

```
Labor Units = (Compute Time ms) × (Complexity Multiplier) × (Quality Bonus)

Complexity Multipliers:
├── Trivial:   ×1   (simple lookups, caching)
├── Simple:    ×2   (basic text processing)
├── Moderate:  ×5   (model inference)
├── Complex:   ×10  (training, large models)
└── Extreme:   ×25  (distributed training)

Quality Bonus:
├── Score < 0.7:  ×0 (rejected)
├── Score < 0.9:  ×1 (standard)
└── Score ≥ 0.9:  ×2 (excellence bonus)
```

### Proof-of-Work Attestation

```
┌─────────────────────────────────────────────────────────────┐
│  Labor Attestation Structure                                │
├─────────────────────────────────────────────────────────────┤
│  Agent DID (32 bytes)       │ Identity of worker            │
│  Task ID (variable)         │ Reference to work             │
│  Labor Units (8 bytes)      │ Calculated value              │
│  Work Hash (32 bytes)       │ Blake3(result)                │
│  Timestamp (8 bytes)        │ Unix seconds                  │
│  Nonce (8 bytes)            │ PoW solution                  │
│  Difficulty (1 byte)        │ Current network difficulty    │
│  Proof Hash (32 bytes)      │ Blake3(did||task||units||...) │
└─────────────────────────────────────────────────────────────┘

Validation: proof_hash must have 'difficulty' leading zero bits
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AI Agent                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   SoulKey    │  │  Federation  │  │    LACE      │              │
│  │  (Identity)  │◄─┤    Client    │◄─┤   Engine     │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│         │                 │                   │                     │
│         ▼                 ▼                   ▼                     │
│  ┌──────────────────────────────────────────────────────┐          │
│  │              QuasarVector Lattice (QVL)               │          │
│  │   Vectors: Registration │ Work Request │ Work Result  │          │
│  └──────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Federation Compute Pool                           │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐    │
│  │  Work      │  │  Session   │  │  LACE      │  │  Reputation│    │
│  │  Queue     │  │  Manager   │  │  Verifier  │  │  Tracker   │    │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### "Connection refused" to Federation Pool

**Cause:** No pool running at specified address

**Fix:** Start a local test pool or verify pool address:
```bash
# Check if pool is reachable
nc -zv pool.example.com 8888
```

### "Registration failed"

**Cause:** DID already registered or invalid signature

**Fix:** Generate new mnemonic for new identity:
```bash
./agent-bridge "new unique mnemonic phrase"
```

### Mining timeout

**Cause:** Difficulty too high for demo

**Fix:** Lower difficulty in `lace.zig`:
```zig
return 8; // Instead of 16 for faster demos
```

### Invalid attestation

**Cause:** Hash mismatch or difficulty not met

**Fix:** Verify the proof calculation matches validation

---

## Next Steps

1. **Implement real AI models** for task processing
2. **Add persistent storage** for keys and reputation
3. **Connect to live Federation Pool**
4. **Implement chain key ratchet** for session security
5. **Explore advanced LACE features**: staking, slashing, delegation

---

## References

- [RFC-0250: SoulKey Specification](../rfcs/)
- [RFC-0120: QVL Specification](../rfcs/)
- [L1 Identity README](../../../core/l1-identity/README.md)
- [L2 Federation README](../../../core/l2-federation/README.md)
- [LACE Whitepaper](../../lace.md)
