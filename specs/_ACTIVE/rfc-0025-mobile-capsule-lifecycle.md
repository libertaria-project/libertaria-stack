# RFC-0025: Mobile Capsule Lifecycle
**Status:** WAITING FOR MARKUS SPECIFICATION  
**Layer:** L0-L1 Hybrid  
**Assigned To:** Markus Maiwald (specification)  
**Implementation:** Janus (after spec complete)  
**Date:** 2026-02-10  
**Depends On:** RFC-0020 (OPQ), RFC-0015 (MIMIC), RFC-0000 (Wire Frame)  
**Inspired By:** Holepunch/Keet interview analysis (Claude)

---

## ⏸️ PLACEHOLDER

This RFC is **waiting for Markus' specification**.

**Do NOT implement from this placeholder.**

---

## CONTEXT (from Holepunch Analysis)

**Problem:** Mathias (Holepunch) spent 4 years making P2P work on mobile. iOS and Android aggressively throttle background processes.

**Required Sections (for Markus to specify):**

1. **Wake-on-Push Computation Windows**
   - Push notification triggers
   - Time-boxed execution
   - Priority escalation

2. **Blind Peer Relay Selection**
   - Automatic relay discovery for DMs
   - Rotation policy
   - Failover handling

3. **Background Sync Budgeting**
   - Battery constraints
   - Network type awareness
   - Adaptive frequency

4. **Graceful Degradation**
   - State preservation
   - Next wake scheduling
   - User notification

---

## REFERENCE

Internal analysis available in operations documentation.

---

🜏 **Waiting for the Architect.**
