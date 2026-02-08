# L4: Applications Layer

> Build on sovereign ground.

The L4 Applications layer provides SDKs and frameworks for building applications that inherit sovereignty from L0-L3.

---

## L4 Feed

A **temporal event store** for sovereign applications.

### Architecture

```rust
pub struct L4Feed {
    pub backend: FeedBackend,
    pub events: EventLog,
    pub index: QueryIndex,
}

pub enum FeedBackend {
    DuckDB,       // Embedded analytics
    LanceDB,      // Vector search
    Libmdbx,      // Single-file storage
}
```

### Event Structure

```rust
pub struct Event {
    pub id: EventId,                    // BLAKE3 hash
    pub timestamp: SovereignTimestamp,  // Nanosecond precision
    pub author: Did,                    // Self-sovereign identity
    pub type: EventType,
    pub payload: Vec<u8>,
    pub signature: Ed25519Signature,
    pub parents: Vec<EventId>,          // DAG structure
}

pub enum EventType {
    Message,      // Encrypted content
    State,        // Application state update
    Credential,   // Verifiable credential
    Contract,     // State channel update
}
```

### Query Interface

```rust
// GQL: Graph Query Language (ISO/IEC 39075:2024)
let results = feed.query(r#"
    MATCH (e:Event)
    WHERE e.author = "did:libertaria:z8m9n..."
      AND e.timestamp > $since
      AND e.type = "Message"
    RETURN e.id, e.timestamp, e.payload
    ORDER BY e.timestamp DESC
    LIMIT 100
"#, params!{"since": last_check});
```

---

## SDK Components

### Janus SDK

Language bindings for the Janus programming language:

```rust
// Rust example (libertaria-sdk-rs)
use libertaria::{SoulKey, Chapter, Feed};

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    // Generate identity
    let key = SoulKey::generate();
    let did = key.derive_did("identity")?;
    
    // Join Chapter
    let berlin = Chapter::connect("chapter://berlin/core").await?;
    berlin.join(&key, min_reputation=0.5).await?;
    
    // Create feed
    let feed = Feed::create(did.clone())?;
    
    // Publish event
    feed.publish(Event::new(
        author: did,
        type: EventType::Message,
        payload: b"Hello, sovereign world!".to_vec(),
    )).await?;
    
    Ok(())
}
```

### C FFI

Stable C interface for other languages:

```c
// C header (libertaria.h)
libertaria_soulkey_t* libertaria_soulkey_generate(
    const uint8_t* seed,
    size_t seed_len
);

libertaria_error_t libertaria_soulkey_derive_did(
    libertaria_soulkey_t* key,
    const char* context,
    char* out_did,
    size_t out_capacity
);

void libertaria_soulkey_free(libertaria_soulkey_t* key);
```

---

## Planned Components

### L5: Agent Runtime

WASM-based sandbox for autonomous agents:

```rust
pub struct AgentRuntime {
    pub wasm_engine: WasmEngine,
    pub capabilities: CapabilitySet,
    pub sandbox: SandboxConfig,
}

pub struct SandboxConfig {
    pub max_memory: usize,        // 100 MB default
    pub max_compute: u64,         // Gas-like limit
    pub allowed_apis: Vec<Api>,
    pub network_access: bool,     // Off by default
}
```

### L6: Application Framework

UI and storage framework:

| Feature | Description | Status |
|:--------|:------------|:-------|
| Local-First Sync | CRDT-based replication | 📋 Planned |
| Sovereign UI | Components with built-in identity | 📋 Planned |
| Capabilities UI | Permission management | 📋 Planned |
| Offline Mode | Full functionality offline | 📋 Planned |

---

## Application Patterns

### Sovereign Social

```
Components:
  - L4 Feed for timeline
  - QVL for follow recommendations
  - Chapters for communities
  - State channels for direct messages

Properties:
  - No platform can ban you
  - No algorithm controls your feed
  - Your social graph is portable
```

### Sovereign Commerce

```
Components:
  - VCs for reputation
  - State channels for escrow
  - Chapters for marketplace governance
  - QVL for trust scoring vendors

Properties:
  - No payment processor can freeze funds
  - No platform can delist you
  - Dispute resolution by trusted Chapters
```

### Sovereign Collaboration

```
Components:
  - L4 Feed for project updates
  - Chapters for team governance
  - State channels for milestone payments
  - QVL for contributor reputation

Properties:
  - No corporate owner can shut down
  - Contributors own their contributions
  - Fork if governance fails
```

---

## Kenya Compliance for Apps

All L4+ applications must maintain Kenya Rule compliance:

| Metric | Target | Enforcement |
|:-------|:-------|:------------|
| Binary Size | < 5 MB (full app) | Build-time check |
| Memory | < 50 MB runtime | Runtime monitor |
| Storage | < 100 MB data | User warning |
| Network | Zero mandatory cloud | Offline-first design |
| Battery | Minimal background activity | OS best practices |

---

## Implementation

| Component | Location | Status |
|:----------|:---------|:-------|
| L4 Feed | `sdk/l4-feed/` | ✅ Stable |
| Janus SDK (Rust) | `sdk/janus-sdk-rs/` | ✅ Stable |
| C FFI | `sdk/ffi/` | ✅ Stable |
| Agent Runtime | `sdk/l5-runtime/` | 📋 Planned |
| App Framework | `sdk/l6-framework/` | 📋 Planned |

---

## Further Reading

- [RFC-0130: L4 Feed](../rfcs/RFC-0130_L4_Feed.md)

---

*Build on sovereign ground. Own what you create.* ⚡
