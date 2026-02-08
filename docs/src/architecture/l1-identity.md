# L1: Identity Layer

> Self-sovereign keys. No platform controls your identity.

The L1 Identity layer provides cryptographic identity, trust computation, and betrayal detection.

---

## SoulKey: Hierarchical Identity

A **SoulKey** is a deterministic, hierarchical identity system.

### Key Derivation

```
Root Key = Argon2id(seed, salt, params)
  │
  ├── SoulKey("identity")  → DID master key
  ├── SoulKey("work")      → Professional context
  ├── SoulKey("personal")  → Personal context
  ├── SoulKey("device-1")  → Per-device keys
  └── ... unlimited derived keys
```

### Properties

| Property | Description |
|:---------|:------------|
| **Deterministic** | Same seed + context = same keys |
| **Hierarchical** | Unlimited keys from single seed |
| **Context-Separated** | Work/personal/hobby are unlinkable |
| **Recoverable** | BIP-39 mnemonic backup |
| **Burnable** | Irrevocable deactivation possible |

### Key Types

| Type | Algorithm | Purpose |
|:-----|:----------|:--------|
| Authentication | Ed25519 | DID auth, signatures |
| Agreement | X25519 | Key exchange, encryption |
| Assertion | Ed25519 | Verifiable credentials |
| Capability | Ed25519 | Authorization tokens |
| Post-Quantum | ML-KEM-768 | Quantum-resistant KEM |

---

## DID:libertaria Method

```
did:libertaria:z8m9n0p2q4r6s8t0u2v4w6x8y0z2a4b6c8d0e2f4g6h8i0
```

### Method-Specific ID Generation

```
initial_key = SoulKey(seed, context="identity")
method-specific-id = multibase(base58btc, BLAKE3-256(initial_key.public_key))
```

### DID Document

```json
{
  "@context": ["https://www.w3.org/ns/did/v1"],
  "id": "did:libertaria:z8m9n0p2q4r...",
  "verificationMethod": [{
    "id": "did:libertaria:z8m9n...#auth-1",
    "type": "Ed25519VerificationKey2020",
    "controller": "did:libertaria:z8m9n...",
    "publicKeyMultibase": "z6Mk..."
  }],
  "authentication": ["did:libertaria:z8m9n...#auth-1"],
  "keyAgreement": ["did:libertaria:z8m9n...#key-1"],
  "service": [{
    "id": "did:libertaria:z8m9n...#capsule",
    "type": "CapsuleNode",
    "serviceEndpoint": "https://capsule.libertaria.app/z8m9n..."
  }],
  "qvl": {
    "trustScore": 0.87,
    "betrayalRisk": "low",
    "chapters": ["chapter://berlin/core"]
  }
}
```

---

## QVL: Quasar Vector Lattice

The **QVL** is Libertaria's trust computation engine.

### Trust Graph

```rust
pub struct TrustEdge {
    pub source: DidId,           // Who trusts
    pub target: DidId,           // Who is trusted
    pub weight: f64,             // -1.0 (distrust) to +1.0 (trust)
    pub timestamp: Timestamp,    // When established
    pub decay_rate: f64,         // Temporal decay half-life
    pub proof: Option<Signature>, // Cryptographic attestation
}

pub struct TrustGraph {
    pub edges: Vec<TrustEdge>,
    pub nodes: HashSet<DidId>,
}
```

### Temporal Decay

Trust decays over time:

```
Effective_Weight = Weight * exp(-λ * Δt)

Where:
  λ = decay_rate (configured per edge)
  Δt = time since timestamp
```

### Trust Score Computation

```rust
fn compute_trust(graph: &TrustGraph, source: DidId, target: DidId) -> TrustScore {
    // 1. Find all paths (max depth 6)
    let paths = graph.find_all_paths(source, target, max_depth=6);
    
    // 2. Compute path weights with decay
    let path_scores: Vec<f64> = paths.iter()
        .map(|p| p.edges.iter()
            .map(|e| e.weight * temporal_decay(e.timestamp))
            .product())
        .collect();
    
    // 3. Aggregate (parallel resistance model)
    TrustScore::aggregate(path_scores)
}
```

---

## Betrayal Detection

### The Problem

Trust loops can be exploited:

```
Alice trusts Bob (+0.8)
Bob trusts Carol (+0.8)
Carol trusts Alice (+0.8)

If Carol defects: She gains from Alice's trust without reciprocating
```

### Bellman-Ford Detection

We detect **negative cycles** in the trust graph:

```rust
// Standard Bellman-Ford algorithm
// If negative cycle exists: betrayal risk detected

pub fn detect_betrayal_risk(graph: &TrustGraph) -> Vec<BetrayalRisk> {
    let mut risks = Vec::new();
    
    // Run Bellman-Ford on transformed graph
    // Negative cycle = profitable betrayal loop
    if let Some(cycle) = bellman_ford_negative_cycle(graph) {
        risks.push(BetrayalRisk {
            cycle: cycle.nodes,
            severity: compute_severity(cycle),
            evidence: generate_evidence(cycle),
        });
    }
    
    risks
}
```

### Severity Levels

| Level | Condition | Action |
|:------|:----------|:-------|
| **Warn** | Minor negative cycle | Log, notify |
| **Quarantine** | Moderate risk | Restrict permissions |
| **Slash** | Serious risk | Burn stake, broadcast |
| **Exile** | Confirmed betrayal | Permanent exclusion |

---

## Entropy Stamps

Proof-of-work for spam resistance:

```rust
pub struct EntropyStamp {
    pub hash: [u8; 32],
    pub salt: [u8; 16],
    pub difficulty: u8,
    pub timestamp: Timestamp,
}

// Kenya-compliant parameters
pub const KENYA_CONFIG: Argon2Config = Argon2Config {
    time_cost: 2,        // iterations
    memory_cost: 2048,   // 2 MB
    parallelism: 1,      // single thread
};
```

**Target:** <100ms on ARM Cortex-A53 @ 1.4 GHz

---

## Implementation

| Component | Location | Status |
|:----------|:---------|:-------|
| SoulKey | `core/l1-identity/soulkey.zig` | ✅ Stable |
| DID | `core/l1-identity/did.zig` | 🚧 In Progress |
| QVL Core | `core/l1-identity/qvl/` | ✅ Stable |
| Betrayal Detection | `core/l1-identity/qvl/betrayal.zig` | ✅ 47/47 tests |
| Entropy Stamps | `core/l1-identity/argon2.zig` | ✅ Stable |
| PQXDH | `core/l1-identity/pqxdh.zig` | ✅ Stable |

---

## Further Reading

- [RFC-0140: Libertaria SSI Stack](../rfcs/RFC-0140_Libertaria_SSI_Stack.md)

---

*Your keys. Your identity. Your sovereignty.* ⚡
