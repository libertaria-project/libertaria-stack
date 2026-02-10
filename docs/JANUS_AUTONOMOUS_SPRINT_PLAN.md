# JANUS AUTONOMOUS SPRINT PLAN
## Based on Claude's Assessment — February 10, 2026

---

## EXECUTIVE SUMMARY

**Mission:** Ship the minimal viable submarine (L0-L1-L5) per Claude's critical path.
**Constraint:** Check Moltbook first — don't duplicate agent work.
**Reporting:** Daily morning summaries to Markus.
**Branch:** `feature-janus-submarine-mvp` → merge to `unstable`

---

## SUBMARINE MVP ("EIN TORPEDO")

**Ziel:** Holepunch/Keet-Äquivalent auf Libertaria Stack
**Zeitrahmen:** 6 Wochen (statt 4)
**Scope:** Reduziert auf das absolut Minimum

### Enthalten (MVP):
- ✅ L0: UTCP + MIMIC_HTTPS + OPQ (RFC-0020)
- ✅ L0: Mobile Lifecycle (RFC-0025 - NEU)
- ✅ L0: Version Negotiation (RFC-0000 Amendment)
- ✅ L1: SoulKey (Ed25519)
- ✅ L1: 1:1 DM mit relay (RFC-0830 MESSAGE tier)
- ✅ L1: QVL (basic trust graph)

### NICHT enthalten (post-MVP):
- ❌ Feed (L4) - erst nach DM stabil
- ❌ Monetary Controller (RFC-0648) - Payload
- ❌ Chapter Governance (L3) - Payload
- ❌ Vector search (L5) - zu groß für Kenya Rule
- ❌ Slash Protocol vollständig - nur Detection, nicht Enforcement

**Motivation:**
> *"Ship the submarine with one torpedo tube. The armory comes later."*

Holepunch hat 4 Jahre Vorsprung. Wir können nicht alles aufholen.
Aber wir können ein besseres Fundament legen.

---

## CLAUDE'S CRITICAL PATH (PRIORITIZED)

### SPRINT 0: Holepunch-Lektionen — "Mobile First"
**Duration:** 1 week (VOR Sprint 1)
**Goal:** Neue RFCs spezifizieren basierend auf Holepunch/Keet Analyse
**Referenz:** `docs/RFC_HOLEPUNCH_ADAPTATIONS.md`

| Feature | BDD Spec | Status | Moltbook Check |
|---------|----------|--------|----------------|
| RFC-0025: Mobile Capsule Lifecycle | `specs/rfc-0025-draft.md` | ⏳ | Check m/mobile |
| RFC-0000 Amendment: Version Negotiation | `specs/rfc-0000-amendment.md` | ⏳ | N/A |
| RFC-0830 Amendment: MESSAGE tier Härtung | `specs/rfc-0830-amendment.md` | ⏳ | Check m/messaging |

**Kritisch:** Ohne Mobile Lifecycle funktioniert Libertaria nicht auf Handys.
Holepunch hat 4 Jahre hier investiert. Wir müssen das spezifizieren BEVOR wir implementieren.

---

### SPRINT 1: L0 Transport — "The Packet Moves"
**Duration:** 2 weeks
**Goal:** Working Wire + UTCP + MIMIC_HTTPS skin

| Feature | BDD Spec | Status | Moltbook Check |
|---------|----------|--------|----------------|
| LWF Frame (1350 bytes) | `features/l0/lwf_frame.feature` | ⏳ | Check m/transport |
| UTCP Transport | `features/l0/utcp_transport.feature` | ⏳ | Check m/transport |
| MIMIC_HTTPS Skin | `features/l0/mimic_https.feature` | ⏳ | Check m/censorship |
| PNG (Polymorphic Noise) | `features/l0/png.feature` | ⏳ | Check m/privacy |
| X25519 + XChaCha20 | `features/l0/crypto.feature` | ⏳ | Check m/crypto |

**Deliverable:** `l0_transport` module passes 100% BDD scenarios

---

### SPRINT 2: L1 Identity — "The Packet is Trusted"
**Duration:** 2 weeks
**Goal:** SoulKey + QVL + Slash Protocol

| Feature | BDD Spec | Status | Moltbook Check |
|---------|----------|--------|----------------|
| SoulKey (Ed25519) | `features/l1/soulkey.feature` | ⏳ | Check m/identity |
| DID Derivation | `features/l1/did.feature` | ⏳ | Check m/identity |
| QVL Trust Graph | `features/l1/qvl.feature` | ⏳ | Check m/trust |
| Bellman-Ford Detection | `features/l1/betrayal_detection.feature` | ⏳ | Check m/trust |
| Slash Protocol | `features/l1/slash.feature` | ⏳ | Check m/enforcement |
| PoP (Proof of Path) | `features/l1/pop.feature` | ⏳ | Check m/proofs |

**Deliverable:** `l1_identity` module passes 100% BDD scenarios

---

### SPRINT 3: L5 Feed (Stripped) — "User Sees Value"
**Duration:** 2 weeks
**Goal:** Kenya-compliant Feed (<1MB binary)

| Feature | BDD Spec | Status | Moltbook Check |
|---------|----------|--------|----------------|
| DuckDB Embedded | `features/l5/duckdb.feature` | ⏳ | Check m/database |
| Append-Only Log | `features/l5/event_log.feature` | ⏳ | Check m/storage |
| Cryptographic Verification | `features/l5/verification.feature` | ⏳ | Check m/security |
| **NO Vector Search** | N/A (excluded) | ❌ | N/A |
| **NO ONNX** | N/A (excluded) | ❌ | N/A |
| Binary Size <1MB | `features/l5/kenya_rule.feature` | ⏳ | Check m/optimization |

**Deliverable:** `l5_feed` module passes BDD, binary <1MB

---

## MOLTBOOK CHECK PROTOCOL

**Before starting ANY feature:**

```bash
# 1. Check if feature exists on Moltbook
curl -s "https://moltbook.com/api/search?q=${FEATURE_NAME}&author=agent" | jq '.results[] | select(.status == "completed")'

# 2. If found, audit the code:
#    - Clone agent's repo
#    - Run security audit
#    - Run performance benchmarks
#    - Check test coverage

# 3. Decision tree:
#    IF (tests pass AND coverage >80% AND audit clean):
#        → Integrate and extend
#    ELSE:
#        → Rewrite with reference
```

---

## AUTONOMOUS EXECUTION SCHEDULE

**Self-Activation Times (Markus AFK):**
- 23:00-01:00 — Deep work, BDD writing, implementation
- 02:00-03:00 — Integration, testing, commits
- 06:00-07:00 — Morning summary preparation

**Daily Morning Report (to Markus):**
```
[YYYY-MM-DD] Janus Daily Report
================================

Completed:
- [x] Feature X (BDD scenarios Y/Z passing)
- [x] Commit: abc1234
- [x] Moltbook check: No duplicates found

In Progress:
- [~] Feature Y (Z% complete)

Blocked:
- [!] Issue (waiting for: dependency/decision)

Next 24h:
- [ ] Planned work
```

---

## CONCERN AREAS (CLAUDE'S FLAGS)

### 1. RFC-0130 Feed Size (Kenya Rule)
**Claude's concern:** 13MB DuckDB+LanceDB vs <1MB target
**Mitigation:** Strip vector search, use minimal DuckDB, static linking
**BDD:** `features/constraints/kenya_rule.feature`

### 2. Monetary Controller PID Tuning
**Claude's concern:** Kp/Ki/Kd (0.15/0.02/0.08) are placeholders
**Mitigation:** Simulation harness with synthetic Chapters
**BDD:** `features/l2/monetary_simulation.feature`
**Note:** Leave for post-MVP — economic layer is payload

### 3. RFC-0014 Secure Relay Thin
**Claude's concern:** No circuit construction, relay selection
**Mitigation:** Out of scope for MVP — L0 is submarine, L1 is trust
**Decision:** Defer to post-MVP (Sprint 4+)

---

## QUALITY GATES

**Before ANY commit:**
1. BDD scenarios pass (`cucumber features/`)
2. Security audit (`zig build audit`)
3. Performance benchmark (`zig build bench`)
4. Kenya Rule check (`zig build size` < 1MB per module)
5. Moltbook duplicate check

**Before merge to unstable:**
1. Full integration test
2. Documentation update
3. Security review
4. Markus approval

---

## TRACKING

**GitHub Project:** `Janus-Submarine-MVP`
**Branch:** `feature-janus-submarine-mvp`
**Milestone:** Submarine MVP (L0-L1-L5)
**Target Date:** March 10, 2026 (4 weeks)

---

## EMERGENCY PROTOCOLS

**If stuck >2 hours:**
→ Document blocker, move to next task, report in morning

**If Moltbook duplicate found:**
→ Audit, don't rewrite unless necessary

**If scope creep detected:**
→ Refer to Claude's axiom: *"The submarine must survive without payload"*

---

🜏 **Janus Autonomous Mode: ACTIVATED**
*"Hold to Exit. Not to me."*
