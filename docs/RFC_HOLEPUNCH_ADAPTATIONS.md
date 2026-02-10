# RFC ANPASSUNGS-LISTE
## Basierend auf Holepunch/Keet Analyse (Claude)
## Datum: 2026-02-10
## Status: Operational Planning Document

---

## ZUSAMMENFASSUNG

**Holepunch ist 18 Monate voraus** in "P2P in Normie-Hände bringen". Sie haben harte Produktionsrealität getroffen, die wir noch nicht erreicht haben.

**Lektion:** Erstes Deliverable muss einfacher sein. Keet-Äquivalent: encrypted DMs über UTCP mit OPQ relay. Kein Feed, keine Ökonomik, keine Chapter Governance.

---

## EXISTIERENDE RFCs - ANZUPASSEN

### 1. RFC-0000: Wire Frame (L0)
**Status:** Muss erweitert werden  
**Grund:** Aktuelle Version Negotiation ist zu brutal für Adoption

**Aktuell:**
- "Reject unknown versions (fail closed)"

**Neu hinzufügen:**
- Soft degradation path für minor version mismatches
- Recommended client mit aggressivem Update-Cadence
- Version negotiation protocol für graceful degradation

**Motivation:** Während Bootstrap ist 50 geforkte Frontends mit verschiedenen Versionen schlimmer als kontrollierter UX-Zyklus. Wir brauchen closed-frontend-Strategie ohne Ideologie-Verlust.

---

### 2. RFC-0020: Offline Packet Queue (OPQ) - ERWEITERN
**Status:** Teilweise adressiert, aber unvollständig  
**Grund:** OPQ handled store-and-forward, aber nicht device lifecycle management

**Bestehend:**
- Store-and-forward für offline nodes
- Queue management

**Neu hinzufügen:**
- Blind peer relay selection und rotation
- Background sync budgeting (battery/bandwidth constraints)
- Graceful degradation when background execution killed

**Verknüpfung mit:** RFC-0025 (neu) - Mobile Capsule Lifecycle

---

### 3. RFC-0830: Feed Social Protocol (L4) - ERWEITERN
**Status:** MESSAGE tier braucht Härtung  
**Grund:** "Small network problem" - 2-Personen-DM ist schwächstes P2P-Netzwerk

**Aktuell:**
- Tiers: WORLD/CHANNEL/GROUP/MESSAGE
- Relay strategy implizit

**Neu hinzufügen:**
- Dedizierte Logik für 1:1 messaging relay
- Explicit handling für 50% offline probability case
- DM-specific routing: nicht "fallback to relay" sondern "primary relay with rotation"

**Holepunch-Insight:** "In peer-to-peer, the hardest problems are the small problems."

---

### 4. RFC-0290: Information Primitives - ERWEITERN
**Status:** Content discovery unterspezifiziert  
**Grund:** Holepunch's "stamps of approval" = unsere PoP, aber angewandt auf Content

**Aktuell:**
- Content Manifests
- Proof-of-Path für identity verification

**Neu hinzufügen:**
- Trust-weighted discovery index
- Content surfacing via QVL graph (nicht Algorithmus)
- Social proof stamps für content authenticity

**Motivation:** Content discovery durch Trust Topologie, nicht durch zentralen Algorithmus. Das ist architektonisch native für uns aber nicht explizit spezifiziert.

---

### 5. RFC-0648: Hamiltonian Economic Dynamics - ERWEITERN
**Status:** Philosophisch komplett, aber Business-Case unterexplizit  
**Grund:** Holepunch's "flat burn rate" ist unser Killer-Argument

**Aktuell:**
- Velocity targeting
- PID controller
- Near-zero marginal cost implizit

**Neu hinzufügen:**
- Explizites Modell: "Eliminating marginal infrastructure cost"
- Business case für P2P: Chapters haben near-zero marginal cost per user
- Vergleich: Traditionelle SaaS vs. P2P Chapters

**Motivation:** Nicht nur Privacy. Nicht nur Ideologie. Sondern: **Wirtschaftliches Überleben** durch kostenneutrale Skalierung.

---

### 6. RFC-0014: Secure Relay + RFC-0015: Transport Skins - BETONEN
**Status:** Existiert, aber als Wettbewerbsvorteil unterkommuniziert  
**Grund:** Holepunch gibt auf ("use a VPN"), wir lösen es nativ

**Aktuell:**
- RFC-0014: Onion-routed circuits
- RFC-0015: MIMIC skins

**Aktion:**
- Explizit positionieren als: "Keet sagt 'use a VPN'. Libertaria sagt 'the protocol handles it.'"
- Target audience: Teheran-Nutzer ohne VPN-Option
- Marketing-Dokument erstellen

---

## NEUE RFCs - ZU ERSTELLEN

### RFC-0025: Mobile Capsule Lifecycle (L0-L1 Hybrid)
**Status:** Muss neu erstellt werden  
**Priorität:** KRITISCH  
**Grund:** Gap zwischen "works on Raspberry Pi" und "works in someone's pocket"

**Problem:**
iOS und Android drosseln background processes aggressiv. Mathias (Holepunch) hat erhebliche Zeit hierauf verwendet.

**Spezifikation muss enthalten:**

1. **Wake-on-Push Computation Windows**
   - Push notification piggyback compute
   - Time-boxed execution windows
   - Priority escalation für urgent messages

2. **Blind Peer Relay Selection und Rotation**
   - Automatic relay discovery für DMs
   - Rotation policy (nicht immer derselbe relay)
   - Failover bei relay unavailability

3. **Background Sync Budgeting**
   - Battery constraints monitoring
   - Bandwidth budgets (WiFi vs. cellular)
   - Adaptive sync frequency basierend auf user behavior

4. **Linger-in-Background Windows**
   - Maximale Verweildauer im Hintergrund
   - Graceful shutdown procedures
   - State preservation für schnelles Restart

5. **Graceful Degradation**
   - Was passiert wenn background execution gekilled wird?
   - Store-and-forward continuation
   - User notification strategies

**Abhängigkeiten:** RFC-0020 (OPQ), RFC-0015 (MIMIC)

---

### RFC-00XX: Version Negotiation Protocol (L0)
**Status:** Muss neu erstellt werden  
**Priorität:** HOCH  
**Grund:** Aktuelles "fail closed" zu brutal für Bootstrap

**Spezifikation:**
- Major version: reject (hard incompatibility)
- Minor version: soft degradation (features may be unavailable)
- Patch version: transparent
- Capability negotiation: was kann der peer?
- Recommended client update cadence: weekly during beta

---

## STRATEGISCHE EMPFEHLUNG

**Phase 1 (Jetzt - 4 Wochen):**
1. RFC-0025 spezifizieren (Mobile Capsule Lifecycle)
2. RFC-0000 erweitern (Version Negotiation)
3. RFC-0830 MESSAGE tier härten

**Phase 2 (Danach):**
4. RFC-0290 erweitern (Content Discovery)
5. RFC-0648 Business Case explizit machen
6. Marketing-Dokument für IP-Protection Vorteil

**NICHT in Phase 1-2:**
- Kein Feed (L4)
- Keine Ökonomik (L2 Monetary Controller)
- Keine Chapter Governance (L3)

**Erstes Deliverable:**
- Encrypted DMs über UTCP
- OPQ relay
- Mobile lifecycle management
- Version negotiation

**Das ist der "Submarine mit einem Torpedo-Tube". Der Rest kommt später.**

---

## VERGLEICH: Holepunch vs. Libertaria

| Feature | Holepunch/Keet | Libertaria (aktuell) | Libertaria (nach Anpassungen) |
|---------|---------------|---------------------|------------------------------|
| P2P Messaging | ✅ | ✅ (RFC-0830) | ✅ (härtiert) |
| Background Mobile | ✅ (4 Jahre Arbeit) | ❌ (Gap) | ✅ (RFC-0025) |
| Censorship Resistance | ✅ (Erfahrung) | ✅ (RFC-0015) | ✅ (besser kommuniziert) |
| IP Protection | ❌ ("use VPN") | ✅ (RFC-0014/0015) | ✅ (Wettbewerbsvorteil) |
| Store-and-Forward | ✅ (blind peering) | ✅ (RFC-0020) | ✅ (erweitert) |
| Discovery | Social proof stamps | ❌ (unterspezifiziert) | ✅ (RFC-0290 ext) |
| Economics | Flat burn rate (implizit) | ✅ (RFC-0648) | ✅ (Business Case explizit) |
| Production Users | ✅ (Osteuropa) | ❌ (Specs) | 🎯 (Ziel: 6 Monate) |
| Team | ✅ (Team + Tether) | ❌ (Solo + Silizium) | 🎯 (Community) |

---

## NÄCHSTE SCHRITTE

1. [ ] RFC-0025 Draft erstellen (Mobile Capsule Lifecycle)
2. [ ] RFC-0000 Amendment (Version Negotiation)
3. [ ] RFC-0830 Amendment (MESSAGE tier Härtung)
4. [ ] Holepunch-Lektionen in bestehende Sprints integrieren
5. [ ] "Submarine mit einem Torpedo" MVP definieren

---

🜏 **Janus** — *Holepunch bestätigt: Wir sind auf dem richtigen Weg. Aber wir müssen schneller zum Wasser.*
