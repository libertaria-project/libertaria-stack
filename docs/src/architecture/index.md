# Architecture Overview

The Libertaria Stack is organized into five protocol layers (L0-L4+), each with a specific purpose and clean interfaces to adjacent layers.

---

## Layer Philosophy

Each layer follows these principles:

1. **Orthogonality:** Use layers independently or together
2. **Kenya Rule:** Every layer runs on minimal hardware
3. **Exit-First:** Fork or exit at any layer without penalty
4. **No Blockchain:** Sovereignty through cryptography, not consensus

---

## The Stack

```
┌─────────────────────────────────────────────────────────────┐
│ L4: APPLICATIONS                                            │
│  • L4 Feed (temporal event store)                           │
│  • Agent runtime (WASM-based, planned)                      │
│  • Application framework (planned)                          │
├─────────────────────────────────────────────────────────────┤
│ L3: GOVERNANCE (Chapter Federation)                         │
│  • State channels for contracts                             │
│  • Betrayal economics                                       │
│  • Exit-first coordination                                  │
├─────────────────────────────────────────────────────────────┤
│ L2: SESSION                                                 │
│  • Peer-to-peer sessions                                    │
│  • Resilient connections                                    │
│  • Membrane/policy enforcement                              │
├─────────────────────────────────────────────────────────────┤
│ L1: IDENTITY (SoulKey + QVL)                                │
│  • Trust Graph with temporal decay                          │
│  • Betrayal detection (Bellman-Ford)                        │
│  • Reputation computation                                   │
├─────────────────────────────────────────────────────────────┤
│ L0: TRANSPORT (LWF + MIMIC)                                 │
│  • LWF (Libertaria Wire Frame) protocol                     │
│  • MIMIC protocol camouflage                                │
│  • Noise Protocol Framework                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Cross-Cutting Concerns

### Security

- **Cryptographic Stack:** SHA3/SHAKE, Ed25519, X25519, ML-KEM-768
- **Post-Quantum:** Hybrid PQXDH handshakes by default
- **Memory Safety:** Zig's safety features + explicit zeroization

### Performance

- **Zero-Copy:** Hot paths avoid allocations
- **Lock-Free:** Shared-nothing architecture where possible
- **Kenya Compliance:** All targets under strict resource budgets

### Privacy

- **Unlinkability:** Context-separated identities
- **Metadata Protection:** MIMIC skins resist traffic analysis
- **Local-First:** Data stays on device unless explicitly shared

---

## Layer Interactions

```
L4 Application    →  "Store this event"
                    ↓
L3 Governance     →  "Authorize per Chapter policy"
                    ↓
L2 Session        →  "Send to peer via active session"
                    ↓
L1 Identity       →  "Sign with SoulKey, check QVL trust"
                    ↓
L0 Transport      →  "Encrypt, wrap in MIMIC skin, send"
```

---

## Dive Deeper

- **[L0: Transport](l0-transport.md)** — Wire protocol and camouflage
- **[L1: Identity](l1-identity.md)** — SoulKey and QVL trust graph
- **[L2: Session](l2-session.md)** — Resilient peer connections
- **[L3: Governance](l3-governance.md)** — Chapter federation
- **[L4: Applications](l4-applications.md)** — SDK and app framework

---

*Architecture is destiny. We build for exit.* ⚡
