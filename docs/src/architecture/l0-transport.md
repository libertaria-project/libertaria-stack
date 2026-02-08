# L0: Transport Layer

> Evade rather than encrypt.

The L0 Transport layer provides censorship-resistant communication that **hides in plain sight**.

---

## Core Components

### LWF: Libertaria Wire Frame

A lightweight binary protocol optimized for minimal overhead.

**Frame Structure:**
```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|     Version   |   Frame Type  |          Flags                |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           Session ID (64 bits)                                |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           Sequence Number (32 bits)                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           Timestamp (64 bits, nanosecond precision)           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           Payload Length (16 bits)                            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                         Payload                               +
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           MAC (128 bits, XChaCha20-Poly1305)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

**Key Properties:**
- **Fixed 72-byte header:** Predictable parsing, cache-friendly
- **1350 byte MTU:** Fits in single Ethernet frame with overhead
- **XChaCha20-Poly1305:** Modern AEAD encryption
- **Nanosecond timestamps:** Sovereign time synchronization

---

## MIMIC Skins: Protocol Camouflage

MIMIC makes sovereign traffic look like regular internet traffic.

### Available Skins

| Skin | Appearance | Detection Risk | Use Case |
|:-----|:-----------|:---------------|:---------|
| `MIMIC_HTTPS` | TLS 1.3 + WebSocket | Low | General use |
| `MIMIC_DNS` | DNS-over-HTTPS | Very Low | Restricted networks |
| `MIMIC_QUIC` | HTTP/3 | Low | Modern firewalls |
| `STEGO_IMAGE` | JPEG/PNG | Minimal | Total lockdown |

### MIMIC_HTTPS Flow

```
Client                           Server
  |                                 |
  |------ TLS 1.3 Handshake ------>|
  |<----- Encrypted Extensions -----|
  |
  |---- WebSocket Upgrade (HTTP) -->|
  |<---- 101 Switching Protocols ---|
  |
  |====== LWF Frames (encrypted) ==|
  |                                 |
```

### Polymorphic Noise Generator (PNG)

Even encrypted traffic has patterns. PNG masks these:

```
Per-Session:
  - Traffic shaping profile (Netflix, YouTube, generic)
  - Epoch rotation (100-1000 packets)
  - Deterministic padding (both peers derive same pattern)
```

---

## Noise Protocol Framework

We use the [Noise Protocol Framework](http://noiseprotocol.org/) for cryptographic handshakes.

### Patterns Used

| Pattern | Use Case | Properties |
|:--------|:---------|:-----------|
| `Noise_XX` | Mutual authentication | Both parties authenticate |
| `Noise_IK` | 0-RTT resumption | Fast reconnection |
| `Noise_NN` | Ephemeral only | Plausible deniability |

### PQXDH: Post-Quantum Extension

Hybrid handshake combining X25519 + ML-KEM-768:

```
Ceremony (4 ECDH + 1 KEM → 5 shared secrets):
1. Alice generates ephemeral X25519 keypair
2. Alice encapsulates to Bob's ML-KEM-768 public key
3. 4 X25519 ECDH operations
4. 1 ML-KEM-768 encapsulation
5. HKDF-SHA256 derives root key from 5 secrets
```

**Kenya Compliance:** <20ms handshake on ARM Cortex-A53

---

## UTCP: Unreliable Transport

UDP-based overlay with reliability semantics:

```
Features:
- Packet fragmentation/reassembly
- Forward error correction (optional)
- Out-of-order delivery handling
- Congestion control (BBR-inspired)
```

---

## OPQ: Offline Packet Queue

Persistent queue for offline-first operation:

```rust
pub struct OfflinePacketQueue {
    wal: WriteAheadLog,       // Append-only durability
    retention: Duration,      // 72h default
    max_size: usize,          // Configurable limit
}

impl OfflinePacketQueue {
    fn enqueue(&mut self, packet: LwfFrame) {
        self.wal.append(packet);
        // Deliver when peer comes online
    }
}
```

---

## Sovereign Time Protocol

Nanosecond-precision time without centralized servers:

```
Mechanism:
1. Each node maintains local clock (hardware or NTP-synced)
2. Peers exchange timestamp samples
3. Apply Marzullo's algorithm for Byzantine fault tolerance
4. Derive confidence intervals, not absolute time
```

See [RFC-0105](../rfcs/RFC-0105_Sovereign_Time_Protocol.md) for full specification.

---

## Implementation

| Component | Location | Status |
|:----------|:---------|:-------|
| LWF Codec | `core/l0-transport/lwf.zig` | ✅ Stable |
| MIMIC Skins | `core/l0-transport/mimic/` | ✅ Stable |
| Noise Integration | `core/l0-transport/noise.zig` | ✅ Stable |
| OPQ | `core/l0-transport/opq.zig` | ✅ Stable |
| Sovereign Time | `core/l0-transport/time.zig` | ✅ Stable |

---

## Further Reading

- [RFC-0015: Transport Skins](../rfcs/RFC-0015_Transport_Skins.md)
- [RFC-0105: Sovereign Time Protocol](../rfcs/RFC-0105_Sovereign_Time_Protocol.md)
- [RFC-0014: Secure Relay](../rfcs/RFC-0014_Secure_Relay.md)

---

*Hide in plain sight. Communicate freely.* ⚡
