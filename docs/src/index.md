# Libertaria Stack

> Sovereign Infrastructure for Autonomous Agents

**Sovereign; Kinetic; Anti-Fragile.**

---

## What is Libertaria?

**Libertaria is a sovereign stack for humans and agents.**

We are building the infrastructure for a world where digital sovereignty is not a privilege but a baseline. Where you own your identity, your data, and your relationships. Where exit is always an option. Where technology serves humans and agents, not platforms and their shareholders.

### The Core Insight

> *"Capitalism and Communism were never enemies. They were partners."*

Libertaria transcends the false dialectic of the 20th century. We reject both state socialism (which destroys markets) and corporate capitalism (which destroys communities). We build **tools of exit** — infrastructure that lets people coordinate without centralized control, that makes sovereignty the default, that turns "voting with your feet" into a cryptographic operation.

**We are neither left nor right. We are the third thing: sovereign infrastructure.**

---

## The Sovereign Stack (L0-L4+)

### L0: Transport — *Evade Rather Than Encrypt*

The foundation: censorship-resistant communication that **hides in plain sight**.

**LWF (Libertaria Wire Frame)**
- Lightweight binary protocol (1350 byte frames)
- XChaCha20-Poly1305 encryption
- Minimal overhead, maximum throughput

**MIMIC Skins — Protocol Camouflage**

| Skin | Camouflage | Use Case |
|:-----|:-----------|:---------|
| `MIMIC_HTTPS` | TLS 1.3 + WebSocket | Standard firewalls |
| `MIMIC_DNS` | DNS-over-HTTPS | DNS-only networks |
| `MIMIC_QUIC` | HTTP/3 | QUIC-whitelisted networks |
| `STEGO_IMAGE` | Generative steganography | Total lockdown |

### L1: Identity — *Self-Sovereign Keys*

Your identity is **yours alone**. No platform can revoke it. No government can freeze it. No corporation can sell it.

**DID (Decentralized Identifiers)**
- Ed25519 key pairs with rotation
- Deterministic derivation (SoulKey)
- Portable across applications
- Burn capability (revocation)

**QVL — Quasar Vector Lattice**

The trust engine:
- **Trust Graph**: Weighted directed graph with temporal decay
- **Betrayal Detection**: Bellman-Ford negative cycle detection
- **Proof of Path**: Cryptographic path verification
- **GQL**: ISO/IEC 39075:2024 Graph Query Language

### L2: Session — *Resilient Connections*

Peer-to-peer sessions that **survive network partitions** and **function across light-minutes**.

**Session Types**
- Ephemeral (one-time)
- Persistent (long-lived with key rotation)
- Federated (cross-chain)

**Resilience Features**
- Offline-first design
- Automatic reconnection with exponential backoff
- Session migration (IP change without rekeying)
- Multi-path (simultaneous TCP/UDP/QUIC)

### L3: Governance — *Exit-First Coordination*

Federated organization where **forking is a feature, not a failure**.

**Chapter Model**
- Local sovereignty (each chapter owns its state)
- Federated decision-making
- Right to fork at any level
- No global consensus required

**Betrayal Economics**
- Reputation cost of defection > gain from defection
- Cryptographically enforced
- Transparent to all participants

### L4+: Applications — *Build on Sovereign Ground*

The SDK layer — tools for building applications that inherit sovereignty.

**L4 Feed** — Temporal Event Store
- DuckDB + LanceDB backend
- Append-only event log
- Cryptographic verification
- Query via GQL

---

## Quick Start

```bash
# Clone the sovereign stack
git clone https://github.com/libertaria-project/libertaria-stack.git
cd libertaria-stack

# Build all components
zig build

# Run tests
zig build test

# Build examples
zig build examples

# Run Capsule node
zig build run
```

---

## Philosophy: Beyond the -Isms

Libertaria is built on a **synthesis** that transcends 20th-century political economy:

| Dimension | Socialism | Capitalism | **Libertaria** |
|:----------|:----------|:-----------|:---------------|
| **Ownership** | Collective (state) | Private (capital) | **Sovereign (individual)** |
| **Coordination** | Central planning | Market extraction | **Protocol consensus** |
| **Exit** | Impossible (borders) | Expensive (costs) | **Free (cryptographic)** |
| **Trust** | Enforced (compliance) | Bought (contracts) | **Computed (reputation)** |
| **Power** | Concentrated | Concentrated | **Distributed** |

### The Five Principles

1. **Exit is Voice** — The right to leave is the foundation of freedom
2. **No Tokens, No Hype** — We sell working infrastructure, not hope
3. **Post-Quantum by Default** — Cryptographic resilience is table stakes
4. **AI as First-Class Citizen** — Agents are sovereign actors
5. **Interplanetary by Necessity** — Systems that work across light-minutes

---

## Kenya Compliance

| Metric | Target | Status | Meaning |
|:-------|:-------|:-------|:--------|
| **Binary Size** (L0-L1) | < 200KB | ✅ 85KB | Fits on microcontrollers |
| **Memory Usage** | < 10MB | ✅ ~5MB | Runs on $5 Raspberry Pi |
| **Storage** | Single-file | ✅ libmdbx | No server required |
| **Cloud Calls** | Zero | ✅ 100% offline | Survives internet outages |
| **Build Time** | < 30s | ✅ 15s | Fast iteration |

---

## Connect

- **Website:** [libertaria.app](https://libertaria.app)
- **Blog:** [libertaria.app/blog](https://libertaria.app/blog)
- **Moltbook:** m/Libertaria — *The front page of the agent internet*

**We do not theorize. We fork the cage.**

⚡️
