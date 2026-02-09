# **RFC-0910: FIRST-CLASS MESSAGING SYSTEM**

## The Submarine's Nervous System

**Version:** 0.2.0  
**Status:** DRAFT  
**Layer:** L0-L1 (Transport — Internal Process Communication)  
**Class:** ARCHITECTURAL  
**Author:** Markus Maiwald  
**Date:** 2026-02-09  

---

## 0. ABSTRACT

This document specifies the **First-Class Messaging System** for internal process communication within Libertaria nodes. After architectural review, we converge on **Zenoh-only** (via zenoh-pico) as the unified messaging layer.

**Key Principles:**
- **No-broker sovereignty:** No Kafka, no RabbitMQ, no central daemon
- **Kenya compliance:** ~50KB footprint (zenoh-pico)
- **Unified semantics:** Everything is a key-space query
- **Pattern unification:** PUB/SUB, REQ/REP, SURVEY all map to `z_get()` with different key patterns
- **Single library:** One mental model, one failure mode, one update cycle

**Correction from v0.1.0:** Dual-plane (Zenoh + NNG) was rejected. For solo development, two libraries = two failure modes = too much complexity. Zenoh's key-space query unifies all messaging patterns.

---

## 1. MOTIVATION

### 1.1 The Gap
Libertaria L0 (UTCP, LWF) handles *inter-node* communication. But *intra-node* communication—between Membrane Agent, Feed processor, Sensor Oracle, and cognitive streams—lacks a first-class solution.

WebSockets are inappropriate (HTTP upgrade semantics where HTTP has no business). Raw TCP is too low-level. We need:
- **Brokerless operation** (sovereignty requirement)
- **Unified patterns** (PUB/SUB, REQ/REP, SURVEY as one semantic)
- **Content-based routing** (subscribe to `sensor/berlin/pm25/**`)
- **Kenya compliance** (embedded-friendly footprint)

### 1.2 The Zenoh-Only Insight
After evaluating dual-plane (Zenoh + NNG), we reject it. **Two libraries = two failure modes = too much complexity for solo development.**

The key realization: **Zenoh's key-space query unifies all messaging patterns.**

| Pattern | Zenoh Equivalent |
|---------|------------------|
| PUB/SUB | `z_subscribe("sensor/berlin/pm25/*")` |
| REQ/REP | `z_get("query/qvl/trust/did:xxx")` (specific key) |
| SURVEY | `z_get("health/**")` with timeout (wildcard + aggregation) |

> **Law: Everything is a key-space query. The pattern is in the key, not the library.**

### 1.3 Why Not NNG?
NNG's PIPELINE pattern seems attractive for Membrane processing stages, but:
- **The Pipeline is not a network problem.** It's sequential function calls within a process.
- **Stages run synchronously** in the same address space. You need `fn process_frame()`, not a socket.
- **Adding NNG adds complexity** without solving a real problem.

> **Principle: Don't use message passing where function calls suffice.**

---

## 2. ZENOH: THE UNIFIED MESSAGING LAYER

### 2.1 What is Zenoh?
Zero-overhead pub/sub with query semantics. Rust core, Eclipse Foundation lineage.

### 2.2 Why Zenoh-Only?
- **Single mental model:** Everything is a key-space query
- **Pattern unification:** PUB/SUB, REQ/REP, SURVEY all via `z_get()` with different key patterns
- **Peer-to-peer AND routed:** Brokerless by default, routers for scale
- **Wire efficiency:** 4-8 bytes overhead per message (binary protocol)
- **Storage alignment:** Built-in persistence backends (RocksDB, memory)
- **zenoh-pico:** C library, ~50KB footprint (Kenya-compliant)

### 2.3 Pattern Mapping: Zenoh Replaces All

#### PUB/SUB → `z_subscribe()`
```zig
// Subscribe to all PM2.5 sensors
var sub = try session.declare_subscriber("sensor/+/pm25", .{
    .callback = onSensorReading,
});

// Publisher
var pub = try session.declare_publisher("sensor/berlin/pm25");
try pub.put("42.3");
```

#### REQ/REP → `z_get()` on specific key
```zig
// Requester: Query specific trust distance
var reply = try session.get("query/qvl/trust/did:libertaria:abc123");
const trust_score = reply.payload; // "0.87"

// Replier: Declare queryable
var queryable = try session.declare_queryable("query/qvl/trust/*", .{
    .callback = onTrustQuery,
});
```

#### SURVEY → `z_get()` with wildcards + timeout
```zig
// Surveyor: Ask all health modules, aggregate responses
var replies = try session.get("health/**", .{.timeout_ms = 500});
while (replies.next()) |reply| {
    std.log.info("{s}: {s}", .{reply.key, reply.payload});
}
// Automatically aggregates all matching responses within deadline
```

### 2.4 Namespace Design (LWF Service-Type Registry)
The Zenoh key-space **IS** the LWF Service-Type Registry, only readable.

```
$MEMBRANE/           ← L0/L1 Signals
  defcon/current     ← Current defense level
  defcon/history     ← Level history (queryable)
  pattern/alert/*    ← Pattern detection events
  stats/throughput   ← Real-time metrics

$AGENT/              ← L1 Agent Communication
  {did}/caps         ← Agent capabilities
  {did}/negotiate    ← Negotiation channel
  {did}/status       ← Online/Offline/Occupied

$SENSOR/             ← RFC-0295 Sensor Oracle
  {geohash}/{metric}          ← sensor/u33dc0/pm25
  {geohash}/{metric}/history  ← Queryable storage

$FEED/               ← RFC-0830 Feed Protocol
  {chapter}/world/{post_id}   ← World posts
  {chapter}/channel/{chan_id} ← Channel posts
  {chapter}/group/{group_id}  ← Group messages
  {chapter}/dm/{thread_id}    ← E2E encrypted DMs

$QUERY/              ← REQ/REP Replacement
  qvl/trust/{did}             ← Trust graph query
  economy/scrap/velocity      ← Economic metrics
  health/{module}             ← Health check responses
```

### 2.5 Integration Points
| Component | Subscription | Publication/Query |
|-----------|-------------|-------------------|
| Membrane Agent | `sensor/+/pm25`, `$MEMBRANE/defcon` | Filtered items to `$FEED/` |
| Sensor Oracle | `sensor/+/+` (all sensors) | Normalized readings |
| Feed Relay | `$FEED/{chapter}/+` | Relayed posts |
| Economic Engine | `economy/scrap/**` | Velocity updates |
| Health Monitor | `health/**` (SURVEY mode) | Aggregated status |

---

## 3. ARCHITECTURE

### 3.1 Node Interior Layout
```
┌─────────────────────────────────────────────────────────┐
│ LIBERTARIA NODE — Zenoh-Only Architecture                │
│                                                          │
│  ZENOH KEY-SPACE (Unified Messaging)                     │
│  ┌──────────────────────────────────────────────────┐   │
│  │ $MEMBRANE/                                       │   │
│  │   defcon/current                                 │   │
│  │   pattern/alert/*                                │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ $SENSOR/                                         │   │
│  │   {geohash}/{metric}                             │   │
│  │   {geohash}/{metric}/history (queryable)         │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ $FEED/                                           │   │
│  │   {chapter}/world/{post_id}                      │   │
│  │   {chapter}/channel/{chan_id}                    │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ $QUERY/                                          │   │
│  │   qvl/trust/{did} (REQ/REP pattern)              │   │
│  │   health/** (SURVEY pattern with timeout)        │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  COMPONENTS                                              │
│  ┌─────────────────┐  ┌─────────────────┐               │
│  │ Membrane Agent  │  │ Sensor Oracle   │               │
│  │ (sub+pub)       │  │ (sub+pub)       │               │
│  └─────────────────┘  └─────────────────┘               │
│  ┌─────────────────┐  ┌─────────────────┐               │
│  │ Feed Processor  │  │ Health Monitor  │               │
│  │ (sub+pub)       │  │ (SURVEY queries)│               │
│  └─────────────────┘  └─────────────────┘               │
│                                                          │
│  NOTE: Membrane Pipeline = Function calls, not sockets   │
│  ┌──────────────────────────────────────────────────┐   │
│  │ fn process_frame()                                │   │
│  │   Stage 0: Triage (validate)                      │   │
│  │   Stage 1: Context (build_context)                │   │
│  │   Stage 2: Decide (policy_engine)                 │   │
│  │   Stage 3: Commit (state_manager)                 │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Transport Selection Decision Tree
```
Is the communication:
├── Content-defined? (sensor/berlin/pm25)
│   └── Use ZENOH (key-expression routing)
├── High-frequency + small payload?
│   └── ZENOH (4-8 byte overhead)
├── Must survive intermittent connectivity?
│   └── ZENOH (designed for this)
├── Must guarantee delivery ordering?
│   └── ZENOH with reliability QoS
└── Is it internal pipeline stages?
    └── Function calls, NOT message passing
```

---

## 4. SECURITY: LWF ENCRYPTION OVERLAY

Zenoh does not provide native encryption satisfying Libertaria's sovereignty requirements. Use **LWF encryption overlay** (RFC-0000).

### 4.1 Zenoh + LWF
```
Zenoh payload structure:
┌─────────────────────────────────────────────────────┐
│ LWF Header (72 bytes)                               │
│ ├── Version, Frame Type, Session ID                 │
│ ├── Sequence, Timestamp                             │
│ └── Payload Length                                  │
├─────────────────────────────────────────────────────┤
│ Encrypted Payload (XChaCha20-Poly1305)              │
│ └── Contains: Zenoh binary message                  │
├─────────────────────────────────────────────────────┤
│ MAC (16 bytes)                                      │
└─────────────────────────────────────────────────────┘
```

**Key Derivation:** Per-session keys from X3DH handshake (RFC-0140), rotated per RFC-0010 epoch.

---

## 5. IMPLEMENTATION

### 5.1 Dependencies
```zig
// build.zig
const zenoh_pico = b.dependency("zenoh-pico", .{
    .target = target,
    .optimize = optimize,
});

exe.addModule("zenoh", zenoh_pico.module("zenoh"));
```

### 5.2 Zig API Example
```zig
const zenoh = @import("zenoh");

// Initialize session
var session = try zenoh.open(allocator, .{.mode = .peer});

// PUB/SUB: Subscribe to sensors
var sub = try session.declare_subscriber("sensor/+/pm25", .{
    .callback = onSensorReading,
});

fn onSensorReading(sample: zenoh.Sample) void {
    std.log.info("{s}: {s}", .{sample.key, sample.payload});
}

// PUB/SUB: Publish reading
var pub = try session.declare_publisher("sensor/berlin/pm25");
try pub.put("42.3");

// REQ/REP: Query trust distance
var reply = try session.get("query/qvl/trust/did:libertaria:abc123");
std.log.info("Trust: {s}", .{reply.payload});

// SURVEY: Health check all modules
var replies = try session.get("health/**", .{.timeout_ms = 500});
var healthy: usize = 0;
while (replies.next()) |r| {
    if (std.mem.eql(u8, r.payload, "OK")) healthy += 1;
}
std.log.info("{d}/{d} modules healthy", .{healthy, replies.total});
```

---

## 6. KENYA COMPLIANCE

| Metric | Value | Status |
|--------|-------|--------|
| **Footprint** | ~50KB (zenoh-pico) | ✅ Compliant |
| **No broker** | Peer-to-peer by default | ✅ Compliant |
| **Offline tolerance** | Designed for intermittent | ✅ Compliant |
| **C ABI** | Native `@cImport` | ✅ Compliant |

---

## 7. MIGRATION PATH

### Phase 1 (v0.5.0; ~15h): Zenoh-Pico Binding + First Channel
- Build zenoh-pico Zig binding
- Implement `$MEMBRANE/defcon` as first live channel
- Proof: Membrane Agent publishes defcon changes

### Phase 2 (v0.6.0; ~15h): Sensor + Query Namespace
- `$SENSOR/` namespace for Sensor Oracle
- `$QUERY/qvl/trust/{did}` for trust graph queries
- Pattern Detection (RFC-0115) publishes to `$MEMBRANE/pattern/alert/*`

### Phase 3 (v0.7.0; ~10h): Feed Integration
- `$FEED/` namespace for Feed Social Protocol (RFC-0830)
- Gossip-Relay via Zenoh-Router

### Phase 4 (v0.8.0; ~10h): LWF Encryption Overlay
- Add XChaCha20-Poly1305 encryption to Zenoh payloads
- Key rotation per RFC-0010 epochs
- Security audit

---

## 8. CONCLUSION

> **Zenoh-only is the right knife.**

The dual-plane approach (Zenoh + NNG) was architecturally valid but practically wrong for solo development. Two libraries = two failure modes = too much complexity.

The insight: **Zenoh's key-space IS the LWF Service-Type Registry, only readable.**

| Pattern | Old Approach | Zenoh-Only |
|---------|--------------|------------|
| PUB/SUB | `z_subscribe()` | `z_subscribe()` ✓ |
| REQ/REP | NNG REQ/REP | `z_get(specific_key)` ✓ |
| SURVEY | NNG SURVEY | `z_get(wildcard, timeout)` ✓ |
| PIPELINE | NNG PIPELINE | Function calls ✓ |

One library. One namespace. One mental model.

The submarine does not merely transport messages. It *thinks* through them.

---

## APPENDIX: COMPARISON WITH v0.1.0

| Aspect | v0.1.0 (Dual-Plane) | v0.2.0 (Zenoh-Only) |
|--------|---------------------|---------------------|
| Libraries | 2 (Zenoh + NNG) | 1 (Zenoh) |
| Mental Models | 2 | 1 |
| Failure Modes | 2 | 1 |
| Update Cycles | 2 | 1 |
| Pipeline | NNG PIPELINE | Function calls |
| Complexity | Higher | Lower |
| Solo-Dev Fit | Poor | Excellent |

---

## APPENDIX: DEPENDENCIES

### Zenoh-Pico
- **URL:** https://github.com/eclipse-zenoh/zenoh-pico
- **License:** EPL-2.0 OR Apache-2.0
- **Zig binding:** Direct C API via `@cImport`
- **Footprint:** ~50KB

---

**End of RFC-0910 v0.2.0**  
*The submarine's nervous system is unified.* 🜏
