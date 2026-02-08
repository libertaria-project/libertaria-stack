# Core Concepts

Understanding the fundamental concepts of the Libertaria Stack.

---

## The Layer Model

Libertaria is organized into protocol layers, each building on the one below:

```
L4: Applications — Tools built on sovereign ground
L3: Governance  — Exit-first coordination
L2: Session     — Resilient connections
L1: Identity    — Self-sovereign keys
L0: Transport   — Censorship-resistant communication
```

Each layer is **orthogonal** — you can use L0 transport without L1 identity, or L1 identity without L3 governance.

---

## SoulKey

A **SoulKey** is your sovereign identity. Unlike traditional identities:

- **Self-sovereign:** You generate it. No platform controls it.
- **Deterministic:** Same seed always produces same keys
- **Hierarchical:** Derive unlimited context-specific keys
- **Portable:** Move between applications without permission

### Key Derivation

```
Root Key = Argon2id(seed, salt, params)
SoulKey(context) = HKDF-SHA3-256(Root Key, context, length=32)
DID = did:libertaria:multibase(base58btc, BLAKE3-256(SoulKey("identity")))
```

### Context Separation

Use different contexts for different parts of your life:

| Context | Purpose | Unlinkable |
|:--------|:--------|:-----------|
| `work` | Professional identity | ✅ Yes |
| `personal` | Friends and family | ✅ Yes |
| `activism` | Sensitive coordination | ✅ Yes |
| `shopping` | Commercial activity | ✅ Yes |

---

## QVL: Quasar Vector Lattice

The **QVL** is Libertaria's trust engine. It replaces:

- Centralized reputation systems (Uber, Airbnb ratings)
- Platform-controlled identity verification
- Blockchain-based "trustless" systems

### Trust Graph

```rust
pub struct TrustEdge {
    pub source: DidId,        // Who trusts
    pub target: DidId,        // Who is trusted
    pub weight: f64,          // -1.0 to +1.0
    pub timestamp: Timestamp, // When established
    pub decay_rate: f64,      // Temporal decay
}
```

### Betrayal Detection

The QVL detects **negative cycles** in the trust graph — situations where betraying trust would be profitable:

```rust
// Bellman-Ford algorithm finds these cycles
// If cycle weight < 0: betrayal risk detected
```

### Trust Score Computation

Trust flows through the graph like electrical current through parallel resistors:

1. Find all paths from source to target
2. Compute path weights (with temporal decay)
3. Aggregate using parallel resistance model

---

## MIMIC Skins

**MIMIC** is protocol camouflage. Your sovereign traffic looks like regular internet traffic:

| Skin | Appears As | Use When |
|:-----|:-----------|:---------|
| `MIMIC_HTTPS` | TLS 1.3 + WebSocket | Standard firewalls |
| `MIMIC_DNS` | DNS-over-HTTPS | DNS-only networks |
| `MIMIC_QUIC` | HTTP/3 | QUIC-whitelisted networks |
| `STEGO_IMAGE` | JPEG/PNG images | Total lockdown |

---

## Chapters

A **Chapter** is a local sovereign community with transparent governance.

### Properties

- **Local sovereignty:** Each Chapter owns its state
- **Federated:** Chapters coordinate without global consensus
- **Exit-first:** Any member can fork at any time
- **No global consensus:** Independent operation

### Governance Models

| Model | Description | Best For |
|:------|:------------|:---------|
| Direct | One member, one vote | Small groups |
| Liquid | Delegated voting | Large organizations |
| Meritocratic | Weighted by QVL score | Technical projects |
| None | Coordination only | Ad-hoc collaboration |

---

## Betrayal Economics

The principle that **defection must be economically irrational**.

```
Defection_Cost = Stake * (1 + Trust_Score) + Reputation_Loss
Defection_Gain = Immediate_Payoff

Rational_Actor_Defects: Defection_Gain > Defection_Cost
Libertaria_Ensures: Defection_Cost > Defection_Gain
```

---

## The Kenya Rule

> *"If it doesn't run on a solar-powered phone in Mombasa, it doesn't run at all."*

All Libertaria software must meet these constraints:

| Metric | Target |
|:-------|:-------|
| Binary Size | < 200KB |
| Memory Usage | < 10MB |
| Storage | Single-file |
| Cloud Calls | Zero |
| Build Time | < 30s |

---

## Exit as Architecture

**Exit is not an afterthought.** It is built into every layer:

| Layer | Exit Mechanism |
|:------|:---------------|
| L0 | Switch transport skins; change networks |
| L1 | Rotate keys; burn old identity |
| L2 | Migrate sessions; change peers |
| L3 | Fork Chapter; take state with you |
| L4 | Export data; move to different app |

---

## Key Terminology

| Term | Definition |
|:-----|:-----------|
| **DID** | Decentralized Identifier — your sovereign identity |
| **Capsule** | Reference node implementation |
| **LWF** | Libertaria Wire Frame — L0 protocol |
| **OPQ** | Offline Packet Queue — resilient messaging |
| **PQXDH** | Post-Quantum X25519 + Kyber handshake |
| **Chapter** | Federated sovereign community |
| **SoulKey** | Hierarchical deterministic identity |
| **QVL** | Quasar Vector Lattice — trust graph engine |

---

*Understand the concepts. Build the future.* ⚡
