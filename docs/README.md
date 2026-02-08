# Libertaria Stack Documentation

> Sovereign Infrastructure for Autonomous Agents

Welcome to the Libertaria Stack documentation. This site contains comprehensive guides, architecture documentation, and specifications for building on the sovereign stack.

## Quick Navigation

| I want to... | Go to |
|:-------------|:------|
| Get started quickly | [Getting Started Guide](getting-started/index.md) |
| Understand the architecture | [Architecture Overview](architecture/index.md) |
| Set up my first node | [First Node](getting-started/first-node.md) |
| Read technical specifications | [RFCs](../rfcs/) |
| Understand core concepts | [Concepts](getting-started/concepts.md) |

## The Sovereign Stack

Libertaria is organized into protocol layers L0-L4+:

```
┌─────────────────────────────────────┐
│ L4: Applications                    │
│  • L4 Feed (temporal event store)   │
│  • Agent runtime (planned)          │
│  • Application framework (planned)  │
├─────────────────────────────────────┤
│ L3: Governance                      │
│  • Chapter federation               │
│  • Exit-first coordination          │
│  • State channels                   │
├─────────────────────────────────────┤
│ L2: Session                         │
│  • Peer-to-peer sessions            │
│  • Resilient connections            │
│  • Membrane/policy enforcement      │
├─────────────────────────────────────┤
│ L1: Identity                        │
│  • SoulKey (self-sovereign keys)    │
│  • QVL (Quasar Vector Lattice)      │
│  • Trust graph & betrayal detection │
├─────────────────────────────────────┤
│ L0: Transport                       │
│  • LWF (Libertaria Wire Frame)      │
│  • MIMIC protocol camouflage        │
│  • Noise Protocol Framework         │
└─────────────────────────────────────┘
```

## Documentation Structure

- **[Getting Started](getting-started/)** — Installation, first steps, and core concepts
- **[Architecture](architecture/)** — Deep dives into each protocol layer
- **[RFCs](rfcs/)** — Technical specifications and standards
- **[Status Reports](status/)** — Project milestones and progress
- **[Archive](archive/)** — Historical documentation

## Kenya Compliance

All documentation and code adheres to the **Kenya Rule**:

| Metric | Target | Status |
|:-------|:-------|:-------|
| Binary Size (L0-L1) | < 200KB | ✅ 85KB |
| Memory Usage | < 10MB | ✅ ~5MB |
| Storage | Single-file | ✅ libmdbx |
| Cloud Calls | Zero | ✅ 100% offline |
| Build Time | < 30s | ✅ 15s |

> *"If it doesn't run on a solar-powered phone in Mombasa, it doesn't run at all."*

## Contributing

See [ONBOARDING.md](../ONBOARDING.md) for contributor guidelines.

## License

Documentation is licensed under **LUL-1.0 Unbound** — ideas want to be free.

---

*Forge burns bright. Exit is voice.* ⚡
