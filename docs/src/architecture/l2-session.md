# L2: Session Layer

> Resilient connections that survive network partitions and function across light-minutes.

The L2 Session layer manages peer-to-peer connections with automatic recovery and policy enforcement.

---

## Session Types

### Ephemeral Session

One-time connection for single interaction:

```rust
pub struct EphemeralSession {
    pub session_id: SessionId,
    pub peer_did: Did,
    pub keys: SessionKeys,    // Ephemeral X25519 keys
    pub created_at: Timestamp,
    pub expires_at: Timestamp,
}
```

Use case: Anonymous request/response

### Persistent Session

Long-lived connection with key rotation:

```rust
pub struct PersistentSession {
    pub session_id: SessionId,
    pub peer_did: Did,
    pub state: SessionState,
    pub root_key: RootKey,        // From PQXDH handshake
    pub chain_key: ChainKey,      // For forward secrecy
    pub ratchet: DoubleRatchet,   // Signal Protocol-style
}

pub enum SessionState {
    Handshaking,
    Active,
    Migrating,    // IP change in progress
    Suspended,    // Network partition
    Closing,
}
```

Use case: Regular peer communication

### Federated Session

Cross-chain / cross-protocol bridge:

```rust
pub struct FederatedSession {
    pub session_id: SessionId,
    pub local_peer: Did,
    pub remote_peer: ForeignIdentity,  // Non-Libertaria DID
    pub bridge: BridgeProtocol,
}

pub enum BridgeProtocol {
    Nostr,
    ActivityPub,
    Xmtp,
    Custom(String),
}
```

Use case: Bridge to other networks

---

## Resilience Features

### Automatic Reconnection

```rust
pub struct ReconnectionPolicy {
    pub max_attempts: u32,           // 0 = infinite
    pub initial_delay: Duration,     // Exponential backoff start
    pub max_delay: Duration,         // Backoff cap
    pub backoff_multiplier: f64,     // Typically 2.0
}

// Example: 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s...
```

### Session Migration

Change IP without rekeying:

```
1. Peer A detects IP change
2. A sends MIGRATE message with new endpoint
3. B acknowledges, updates routing
4. Session continues with same keys
5. Old path times out naturally
```

### Multi-Path

Use multiple transports simultaneously:

```rust
pub struct MultipathSession {
    pub paths: Vec<Path>,
    pub strategy: MultipathStrategy,
}

pub enum MultipathStrategy {
    Failover,      // Primary with backup
    LoadBalance,   // Distribute across paths
    Aggregate,     // Bond for higher throughput
}
```

Typical configuration:
- Primary: QUIC direct
- Backup: TCP via relay
- Emergency: Steganographic (STEGO_IMAGE)

---

## Membrane: Policy Enforcement

The **Membrane** is a capability-based access control system.

### Policy Definition

```rust
pub struct MembranePolicy {
    pub capabilities: Vec<Capability>,
    pub constraints: Vec<Constraint>,
    pub expiry: Option<Timestamp>,
}

pub struct Capability {
    pub resource: ResourceId,
    pub action: Action,
    pub conditions: Vec<Condition>,
}

// Examples:
// - "read feed://my-channel"
// - "write chapter://berlin/proposals (if member)"
// - "call service://payment (up to 100 units)"
```

### Policy Enforcement

```rust
impl Membrane {
    fn check_access(
        &self,
        peer: Did,
        capability: &Capability,
    ) -> Result<(), AccessDenied> {
        // 1. Verify peer identity via QVL
        let trust = self.qvl.trust_score(peer)?;
        
        // 2. Check capability grant
        let grant = self.capabilities.get(peer, capability)?;
        
        // 3. Verify constraints
        for constraint in &grant.constraints {
            if !constraint.verify() {
                return Err(AccessDenied::ConstraintFailed);
            }
        }
        
        // 4. Log access (audit trail)
        self.audit_log.record(peer, capability);
        
        Ok(())
    }
}
```

---

## Handshake Flow

### Full PQXDH Handshake

```
Alice (Initiator)                     Bob (Responder)
     |                                       |
     |---- PQXDH Initial Message ----------->|
     |   - Alice ephemeral X25519 key        |
     |   - Alice ephemeral ML-KEM-768 key    |
     |   - Encrypted payload                 |
     |                                       |
     |<--- PQXDH Response --------------------|
     |   - Bob ephemeral keys                |
     |   - Encapsulated shared secret        |
     |                                       |
     |====== Session Established ===========|
     |   - 5 shared secrets combined         |
     |   - HKDF derives root key             |
     |   - Double Ratchet for forward secrecy|
```

### 0-RTT Resumption

```
Alice                               Bob (Pre-key known)
  |                                       |
  |---- Encrypted with PSK -------------->|
  |   - Uses pre-shared key from prior    |
  |     session                           |
  |                                       |
  |<--- Ack + optional update ------------|
  |                                       |
```

---

## Offline-First Design

Sessions survive extended disconnections:

```rust
pub struct OfflineSessionState {
    pub queued_outgoing: Vec<Message>,    // OPQ storage
    pub unacknowledged: Vec<Message>,    // For retry
    pub pending_ack: HashSet<MessageId>,
    pub session_version: u64,              // For sync on reconnect
}

// On reconnection:
// 1. Exchange session versions
// 2. Reconcile missed messages
// 3. Resume from highest common version
```

---

## Implementation

| Component | Location | Status |
|:----------|:---------|:-------|
| Session Manager | `core/l2_session/manager.zig` | ✅ Stable |
| Handshake | `core/l2_session/handshake.zig` | ✅ Stable |
| Membrane | `core/l2-membrane/` | ✅ Stable |
| Reconnection | `core/l2_session/resilience.zig` | ✅ Stable |
| Federation | `core/l2-federation/` | 🚧 Design phase |

---

## Further Reading

- [RFC-0014: Secure Relay](../rfcs/RFC-0014_Secure_Relay.md)

---

*Connections that survive. Sessions that persist.* ⚡
