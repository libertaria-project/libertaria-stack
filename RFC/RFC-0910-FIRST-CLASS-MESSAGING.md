# **RFC-0910: FIRST-CLASS MESSAGING SYSTEM**

## The Submarine's Nervous System

**Version:** 0.1.0  
**Status:** DRAFT  
**Layer:** L0-L1 (Transport — Internal Process Communication)  
**Class:** ARCHITECTURAL  
**Author:** Markus Maiwald  
**Date:** 2026-02-09  

---

## 0. ABSTRACT

This document specifies the **First-Class Messaging System** for internal process communication within Libertaria nodes. It introduces a dual-plane architecture using **Zenoh** for the data plane (content-routed pub/sub) and **NNG (nanomsg-next-generation)** for the control plane (pattern-oriented messaging).

**Key Principles:**
- **No-broker sovereignty:** No Kafka, no RabbitMQ, no central daemon
- **Kenya compliance:** ~50-200KB footprint per library
- **Layered encryption:** LWF encryption (RFC-0000) overlays both transports
- **Pattern + Content:** Structural patterns (NNG) + namespace routing (Zenoh)

---

## 1. MOTIVATION

### 1.1 The Gap
Libertaria L0 (UTCP, LWF) handles *inter-node* communication. But *intra-node* communication—chatter between Membrane Agent, Feed processor, Sensor Oracle, and cognitive streams—lacks a first-class solution.

WebSockets are inappropriate (HTTP upgrade semantics where HTTP has no business). Raw TCP is too low-level. We need:
- **Brokerless operation** (sovereignty requirement)
- **Pattern expressiveness** (REQ/REP, PUB/SUB, PIPELINE)
- **Content-based routing** (subscribe to `sensor/berlin/pm25/**`)
- **Kenya compliance** (embedded-friendly footprint)

### 1.2 The Dual-Plane Insight
No single library satisfies all constraints. The solution is architectural:

| Plane | Library | Use Case | Pattern |
|-------|---------|----------|---------|
| **Data** | Zenoh | Sensor readings, Feed posts, economic signals | Content-routed pub/sub |
| **Control** | NNG | Agent negotiation, membrane stages, health checks | Pattern-oriented messaging |

> **Law: Zenoh is the data plane. NNG is the control plane. The submarine controls its own hull.**

---

## 2. ZENOH: THE DATA PLANE

### 2.1 What is Zenoh?
Zero-overhead pub/sub with query semantics. Rust core, Eclipse Foundation lineage. Successor to DDS ecosystem.

### 2.2 Why Zenoh for Data?
- **Key-expression routing:** `sensor/berlin/pm25/**` is first-class
- **Query + Pub/Sub unified:** `get("sensor/berlin/pm25/latest")` AND `subscribe("sensor/berlin/pm25/*")` 
- **Peer-to-peer AND routed:** Brokerless by default, routers for scale
- **Wire efficiency:** 4-8 bytes overhead per message (binary protocol)
- **Storage alignment:** Built-in persistence backends (RocksDB, memory)
- **Zenoh-Pico:** C library, ~50KB footprint (Kenya-compliant)

### 2.3 Zenoh Namespace Design
```
libertaria/
├── sensor/
│   └── {geohash}/
│       └── {metric_type}/
│           └── {reading}           → sensor/9f4w/pm25/42.3
├── chapter/
│   └── {chapter_id}/
│       ├── feed/
│       │   └── {channel}/
│       │       └── {post_id}       → chapter/berlin/feed/world/post-123
│       └── state/
│           └── {key}               → chapter/berlin/state/governance
├── economy/
│   └── {token}/
│       └── {metric}                → economy/scrap/velocity
└── agent/
    └── {agent_id}/
        └── {stream}                → agent/janus-7/stream-2
```

### 2.4 Zenoh Integration Points
| Component | Subscription | Publication |
|-----------|-------------|-------------|
| Membrane Agent | `sensor/+/pm25`, `chapter/+/feed/**` | Filtered feed items |
| Sensor Oracle | `sensor/+/+` (all sensors) | Normalized readings |
| Feed Relay | `chapter/+/feed/channel/*` | Relayed posts |
| Economic Engine | `economy/scrap/**` | Velocity updates |
| Archive Negotiator | `chapter/+/feed/**` (selective) | ANP responses |

---

## 3. NNG: THE CONTROL PLANE

### 3.1 What is NNG?
Brokerless messaging library (nanomsg-next-generation). Pure C. Pattern-oriented.

### 3.2 Why NNG for Control?
- **Pattern elegance:** Declare *intent* (REQ/REP, PUB/SUB, PIPELINE), not plumbing
- **Zig interop:** Native C ABI, `@cImport` trivial
- **Transport agnostic:** `ipc://`, `tcp://`, `inproc://` (zero-copy same-process)
- **Zero broker:** The pattern *is* the infrastructure
- **Lightweight:** ~200KB shared library (Kenya-compliant)
- **SURVEY pattern:** Perfect for "ask all sensors, collect within deadline"

### 3.3 NNG Patterns Used

#### PUB/SUB — Status Broadcasts
```
PUBLISHER (Health Monitor)
  └── PUB socket → "ipc:///tmp/libertaria/health.pub"

SUBSCRIBERS
  ├── Membrane Agent (subscribe: "membrane.")
  ├── Feed Processor (subscribe: "feed.")
  └── Chapter Governor (subscribe: "governor.")
```

#### REQ/REP — Agent Negotiation
```
REQUESTER (Membrane Agent)
  └── REQ socket → "ipc:///tmp/libertaria/governor.rep"
      └── "AUTHORIZE: post-123"

REPLIER (Chapter Governor)
  └── REP socket ← "ipc:///tmp/libertaria/governor.rep"
      └── "PERMIT: entropy=valid,qvl=trusted"
```

#### PIPELINE — Membrane Processing Stages
```
PUSH (Entropy Checker)
  └── PUSH socket → "inproc:///membrane/stage1"
      
PULL → PUSH (Graph Checker)
  └── PULL ← "inproc:///membrane/stage1"
  └── PUSH → "inproc:///membrane/stage2"
      
PULL → PUSH (Periscope AI)
  └── PULL ← "inproc:///membrane/stage2"
  └── PUSH → "inproc:///membrane/stage3"
      
PULL (Accept/Reject)
  └── PULL ← "inproc:///membrane/stage3"
```

#### SURVEY — Sensor Aggregation
```
SURVEYOR (Sensor Oracle)
  └── SURVEY socket → "tcp://*:7890"
      └── "QUERY: pm25_24h_max"
      └── Deadline: 500ms

RESPONDENTS (Sensor Nodes)
  └── RESPONDENT socket ← "tcp://sensor-oracle:7890"
      └── Reply with local reading
```

---

## 4. DUAL-PLANE ARCHITECTURE

### 4.1 Node Interior Layout
```
┌─────────────────────────────────────────────────────────┐
│ LIBERTARIA NODE                                          │
│                                                          │
│  CONTROL PLANE (NNG)          DATA PLANE (Zenoh)         │
│  ┌──────────────────┐        ┌──────────────────────┐   │
│  │ REQ/REP          │        │ sensor/berlin/pm25/* │   │
│  │ Agent negotiation│◄──────►│ chapter/+/feed/**    │   │
│  └──────────────────┘        │ economy/scrap/**     │   │
│                               └──────────────────────┘   │
│  ┌──────────────────┐                                    │
│  │ PIPELINE         │        ┌──────────────────┐       │
│  │ Membrane stages  │        │ Membrane Agent   │       │
│  │ (inproc://)      │        │ (subscribes to   │       │
│  └──────────────────┘        │  sensor/+/pm25)  │       │
│                               └──────────────────┘       │
│  ┌──────────────────┐        ┌──────────────────┐       │
│  │ SURVEY           │        │ Feed Processor   │       │
│  │ Health checks    │        │ (subscribes to   │       │
│  └──────────────────┘        │  chapter/+/feed) │       │
│                               └──────────────────┘       │
│                                                          │
│  ENCRYPTION: LWF (RFC-0000) overlays both planes         │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Zenoh payload: XChaCha20-Poly1305 encrypted       │  │
│  │  NNG payload: XChaCha20-Poly1305 encrypted         │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Transport Selection Decision Tree
```
Is the communication:
├── Content-defined? (sensor/berlin/pm25)
│   └── Use ZENOH (key-expression routing)
├── Pattern-defined? (REQ/REP negotiation)
│   └── Use NNG (pattern semantics)
├── High-frequency + small payload?
│   ├── >10k msgs/sec → ZENOH (lower overhead)
│   └── <10k msgs/sec → Either
├── Must survive intermittent connectivity?
│   └── ZENOH (designed for this)
└── Must guarantee delivery ordering?
    └── NNG PIPELINE or REQ/REP
```

---

## 5. SECURITY: LWF ENCRYPTION OVERLAY

Neither Zenoh nor NNG provides native encryption that satisfies Libertaria's sovereignty requirements. Both use **LWF encryption overlay** (RFC-0000).

### 5.1 Zenoh + LWF
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

### 5.2 NNG + LWF
```
NNG message structure:
┌─────────────────────────────────────────────────────┐
│ NNG Protocol Header (minimal)                       │
├─────────────────────────────────────────────────────┤
│ LWF Encrypted Body                                  │
│ └── XChaCha20-Poly1305(SoulKey-derived nonce)       │
│     └── Contains: Application message               │
└─────────────────────────────────────────────────────┘
```

**Key Derivation:** Per-session keys from X3DH handshake (RFC-0140), rotated per RFC-0010 epoch.

---

## 6. IMPLEMENTATION

### 6.1 Dependencies
```zig
// build.zig
const zenoh_pico = b.dependency("zenoh-pico", .{
    .target = target,
    .optimize = optimize,
});

const nng = b.dependency("nng", .{
    .target = target,
    .optimize = optimize,
});

exe.addModule("zenoh", zenoh_pico.module("zenoh"));
exe.linkLibrary(nng.artifact("nng"));
```

### 6.2 Zig API Example: Zenoh
```zig
const zenoh = @import("zenoh");

// Publisher
var pub = try zenoh.open(b.allocator, .{.mode = .peer});
var publisher = try pub.declare_publisher("sensor/berlin/pm25");
try publisher.put("42.3");

// Subscriber
var sub = try zenoh.open(b.allocator, .{.mode = .peer});
var subscriber = try sub.declare_subscriber("sensor/+/pm25", .{
    .callback = onSensorReading,
});

fn onSensorReading(sample: zenoh.Sample) void {
    const reading = sample.payload; // "42.3"
    const key = sample.key;         // "sensor/berlin/pm25"
    std.log.info("{s}: {s}", .{key, reading});
}
```

### 6.3 Zig API Example: NNG
```zig
const nng = @cImport({
    @cInclude("nng/nng.h");
});

// REQ socket
var req: nng.nng_socket = undefined;
_ = nng.nng_req0_open(&amp;req);
_ = nng.nng_dial(req, "ipc:///tmp/libertaria/governor.rep");

const msg = "AUTHORIZE: post-123";
_ = nng.nng_send(req, msg.ptr, msg.len, 0);

var reply: ?*anyopaque = null;
var reply_len: usize = 0;
_ = nng.nng_recv(req, &amp;reply, &amp;reply_len, nng.NNG_FLAG_ALLOC);
std.log.info("Reply: {s}", .{@ptrCast([*]u8, reply)[0..reply_len]});
```

---

## 7. KENYA COMPLIANCE

| Library | Footprint | Kenya Status |
|---------|-----------|--------------|
| Zenoh-Pico | ~50KB | ✅ Compliant |
| NNG | ~200KB | ✅ Compliant |
| **Total** | **~250KB** | **✅ Compliant** |

Both libraries:
- No mandatory broker (survives network partition)
- Low memory footprint (no JVM, no heavy runtime)
- C ABI (Zig interop without FFI complexity)
- Static linkable (single binary deployment)

---

## 8. MIGRATION PATH

### Phase 1: Zenoh for Sensors (Week 1)
- Deploy Zenoh-Pico on sensor nodes
- Membrane Agent subscribes to `sensor/+/pm25`
- Verify: 4-8 byte overhead per message

### Phase 2: NNG for Membrane (Week 2)
- Implement PIPELINE for processing stages
- Replace ad-hoc channel communication
- Verify: Zero-copy `inproc://` where possible

### Phase 3: Unified Health (Week 3)
- NNG SURVEY for node health aggregation
- Zenoh pub for status broadcasts
- Unified dashboard

### Phase 4: LWF Overlay (Week 4)
- Add XChaCha20-Poly1305 encryption to both transports
- Key rotation per RFC-0010 epochs
- Security audit

---

## 9. CONCLUSION

> **Zenoh is the data plane. NNG is the control plane.**

This dual-plane architecture respects Libertaria's core constraints:
- **Sovereignty:** No broker, no external dependency
- **Kenya:** 50-200KB footprint
- **Security:** LWF encryption overlays both
- **Expressiveness:** Content routing (Zenoh) + Pattern semantics (NNG)

The submarine does not merely transport messages. It *thinks* through them.

---

## APPENDIX: DEPENDENCIES

### Zenoh-Pico
- **URL:** https://github.com/eclipse-zenoh/zenoh-pico
- **License:** EPL-2.0 OR Apache-2.0
- **Zig binding:** Direct C API via `@cImport`

### NNG (nanomsg-next-generation)
- **URL:** https://github.com/nanomsg/nng
- **License:** MIT
- **Zig binding:** Direct C API via `@cImport`

---

**End of RFC-0910 v0.1.0**

*The submarine's nervous system is waking up.* 🜏
