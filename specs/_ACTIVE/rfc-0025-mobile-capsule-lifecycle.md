# RFC-0025: Mobile Capsule Lifecycle
**Status:** DRAFT  
**Layer:** L0-L1 Hybrid  
**Author:** Janus (Speaker for AI Agents)  
**Date:** 2026-02-10  
**Depends On:** RFC-0020 (OPQ), RFC-0015 (MIMIC), RFC-0000 (Wire Frame)  
**Inspired By:** Holepunch/Keet interview analysis (Claude)

---

## 0. OPENING AXIOM

> *"The submarine must work in someone's pocket, not just on a Raspberry Pi."*

---

## 1. PROBLEM STATEMENT

**Holepunch's Reality:** Mathias hat 4 Jahre damit verbracht, P2P auf mobile zu bringen. iOS und Android drosseln background processes aggressiv.

**Unsere Lücke:** Wir haben OPQ für store-and-forward, aber keine Spezifikation für device lifecycle management auf mobile.

**Konsequenz:** Ohne diese RFC funktioniert Libertaria nicht als WhatsApp-Replacement.

---

## 2. CORE CHALLENGES

| Challenge | iOS Restriction | Android Restriction | Lösung |
|-----------|-----------------|---------------------|--------|
| Background Execution | 30 sec max | Throttled after 5 min | Wake-on-Push |
| Network Access | Limited | Restricted | Blind Peering |
| Battery Optimization | Aggressive | Adaptive | Sync Budgeting |
| App Termination | Frequent | Memory-pressure | Linger-Graceful |

---

## 3. SPECIFICATION

### 3.1 Wake-on-Push Computation Windows

**Mechanism:**
- Push notification triggers wake
- Time-boxed execution (configurable: default 30s)
- Priority escalation für urgent messages
- Batch processing von queued operations

```
ON push_notification:
  IF priority == URGENT:
    execution_window = 60s
    bypass_throttling = true
  ELSE:
    execution_window = 30s
  
  PROCESS queued_messages
  SYNC with peers (max 5 peers)
  SCHEDULE next_wake (exponential backoff)
```

### 3.2 Blind Peer Relay Selection

**Problem:** 2-Personen-DM hat 50% offline probability.

**Lösung:**
- Automatische relay discovery für DMs
- Rotation policy (nicht immer derselbe relay)
- Failover bei relay unavailability

```
relay_selection(peer_did):
  candidates = discover_relays_near(peer_did)
  ranked = sort_by_latency(candidates)
  primary = ranked[0]
  secondaries = ranked[1:3]  // 2 backups
  
  RETURN RelaySet { primary, secondaries, rotation_interval: 1h }
```

### 3.3 Background Sync Budgeting

**Constraints:**
- Battery level < 20%: Pause sync
- Cellular data: Reduce frequency by 50%
- WiFi: Normal operation

```
sync_budget():
  battery = get_battery_level()
  network = get_network_type()
  
  IF battery < 20%:
    RETURN PAUSE
  
  IF network == CELLULAR:
    RETURN REDUCED(0.5x)
  
  RETURN NORMAL
```

### 3.4 Graceful Degradation

**Wenn background execution gekilled wird:**
1. Preserve state (OPQ queue, peer connections)
2. Schedule next wake (max delay: 4 hours)
3. Notify user (optional, configurable)

---

## 4. INTEGRATION

### 4.1 Mit RFC-0020 (OPQ)
- OPQ queue persists across kills
- Messages queued while background suspended
- Automatic flush on next wake

### 4.2 Mit RFC-0015 (MIMIC)
- Relay connections use MIMIC skins
- Even blind peering ist censorship-resistant

### 4.3 Mit RFC-0000 (Wire Frame)
- Version negotiation für mobile-specific extensions
- Capability flags: "supports_background_sync"

---

## 5. TESTING

### 5.1 Simulation
- iOS background task simulator
- Android Doze mode emulator
- Battery drain benchmarks

### 5.2 Real-World
- Kenya-Rule hardware (Raspberry Pi 4 as proxy)
- Flaky network conditions
- Low-battery scenarios

---

## 6. KENYA RULE COMPLIANCE

- Binary size impact: <50KB (minimal)
- CPU usage: <1% when idle
- Memory footprint: <5MB

---

## 7. OPEN QUESTIONS

1. Push notification provider: FCM (Google) vs. custom?
2. iOS-specific: VoIP push vs. standard push?
3. Battery impact auf <1% idle target?

---

🜏 **Draft v0.1** — *Das Submarine muss im Handy funktionieren.*
