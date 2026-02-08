# L3: Governance Layer

> Exit-first coordination. Forking is a feature, not a failure.

The L3 Governance layer provides federated organization without global consensus.

---

## Chapters

A **Chapter** is a local sovereign community with transparent governance.

### Structure

```rust
pub struct Chapter {
    pub id: ChapterId,
    pub charter: Constitution,
    pub members: Vec<Did>,
    pub reputation_threshold: f64,     // Minimum QVL score to join
    pub governance: GovernanceModel,
    pub state: ChapterState,
}

pub struct Constitution {
    pub name: String,
    pub purpose: String,
    pub rules: Vec<Rule>,
    pub amendment_process: AmendmentProcess,
}
```

### Governance Models

| Model | Description | Best For |
|:------|:------------|:---------|
| **Direct** | One member, one vote | Small groups (<100) |
| **Liquid** | Delegated voting | Large organizations |
| **Meritocratic** | Weighted by QVL score | Technical projects |
| **Council** | Elected representatives | Regional coordination |
| **None** | Coordination only, no binding decisions | Ad-hoc collaboration |

---

## Exit-First Design

Every Chapter member can:

### 1. Exit with Assets

```rust
impl Chapter {
    fn exit(&self, member: Did) -> ExitPackage {
        ExitPackage {
            identity: member,
            reputation: self.qvl.export_trust_edges(member),
            assets: self.ledger.export_claims(member),
            timestamp: now(),
            proof: self.sign_exit(member),
        }
    }
}
```

No penalty, no permission required.

### 2. Fork the Chapter

```rust
fn fork(&self, fork_name: String, members: Vec<Did>) -> Chapter {
    Chapter {
        id: generate_id(),
        charter: self.charter.clone(),  // Copy constitution
        members: members,
        state: self.state.fork(),       // Copy relevant state
        parent: Some(self.id),          // Track lineage
        created_at: now(),
    }
}
```

Forking is **cheap and encouraged**.

### 3. Join Multiple Chapters

```rust
pub struct MemberProfile {
    pub did: Did,
    pub memberships: Vec<ChapterMembership>,
    // No restriction on number of Chapters
}
```

---

## State Channels

Smart contracts without blockchain:

### Concept

```rust
pub struct StateChannel {
    pub participants: Vec<Did>,
    pub state: ContractState,
    pub sequence: u64,                    // Monotonic version
    pub signatures: Vec<Signature>,      // All must sign
    pub collateral: Vec<Stake>,
    pub dispute_deadline: Timestamp,
}
```

### Lifecycle

```
1. OPEN
   - Participants lock collateral
   - Initial state agreed and signed
   
2. UPDATE
   - Propose new state
   - All participants sign
   - Old state invalidated by sequence number
   
3. CLOSE (mutual)
   - All parties sign final state
   - Collateral distributed
   
4. CLOSE (disputed)
   - Submit to Chapter arbitration
   - Arbiter judges based on evidence
   - Losing party penalized
```

### Settlement Options

| Method | Speed | Trust | Cost |
|:-------|:------|:------|:-----|
| Mutual | Instant | All parties honest | Zero |
| Arbitration | Hours | Chapter arbiter | Small fee |
| Timeout | Automatic | Pre-signed exit state | Zero |

---

## Betrayal Economics

### The Principle

**Defection must be economically irrational.**

```
Defection_Cost = Stake * (1 + Trust_Score) + Reputation_Loss
Defection_Gain = Immediate_Payoff

Rational_Actor_Defects: Defection_Gain > Defection_Cost
Libertaria_Ensures: Defection_Cost > Defection_Gain (by construction)
```

### Enforcement

```rust
pub struct BetrayalEnforcement {
    pub stake_burn: Amount,           // Destroyed
    pub redistribution: Vec<(Did, Amount)>,  // To honest parties
    pub reputation_penalty: f64,      // QVL score reduction
    pub exile: bool,                  // Chapter expulsion
}

impl Chapter {
    fn enforce_betrayal(
        &mut self,
        betrayer: Did,
        evidence: BetrayalEvidence,
    ) {
        // 1. Verify evidence via L1 QVL
        let proof = self.qvl.verify_betrayal(evidence);
        
        // 2. Compute penalties
        let enforcement = self.compute_penalties(betrayer, proof);
        
        // 3. Execute
        self.burn_stake(enforcement.stake_burn);
        self.redistribute(enforcement.redistribution);
        self.qvl.apply_penalty(betrayer, enforcement.reputation_penalty);
        
        if enforcement.exile {
            self.remove_member(betrayer);
        }
        
        // 4. Broadcast proof to network
        self.gossip.broadcast(BetrayalSignal {
            betrayer: betrayer,
            evidence: proof,
            enforcement: enforcement,
        });
    }
}
```

---

## Cross-Chapter Contracts

### Mutual Recognition

```rust
pub struct ChapterFederation {
    pub chapters: Vec<ChapterId>,
    pub mutual_recognition: Vec<(ChapterId, ChapterId)>,
    pub dispute_arbiters: Vec<Did>,  // Trusted by multiple Chapters
}
```

### Example: Cross-Chapter Employment

```
Chapter: BerlinDev (employer)
Chapter: BudapestNomads (employee's home)

Contract:
  - Work delivered via State Channel
  - Payment in mixed: 50% EUR stablecoin, 50% reputation
  - Dispute: Arbiters from both Chapters
  - Exit: Employee keeps reputation, transferable to any Chapter
```

---

## Slash Protocol (RFC-0121)

Autonomous betrayal response at wire speed:

```rust
pub struct SlashSignal {
    pub header: LwfHeader,            // ServiceType 0x0002
    pub betrayer: Did,
    pub severity: SlashSeverity,
    pub evidence_hash: [u8; 32],
    pub proof: Signature,
}

pub enum SlashSeverity {
    Warn = 0x01,          // Log and notify
    Quarantine = 0x02,    // Restrict for 24h
    Slash = 0x03,         // Burn stake
    Exile = 0x04,         // Permanent ban
}
```

**Wire-speed execution:** L0 recognizes ServiceType 0x0002 and prioritizes handling.

---

## Implementation

| Component | Location | Status |
|:----------|:---------|:-------|
| Chapter Core | `core/l3-governance/chapter.zig` | 🚧 Design phase |
| State Channels | `core/l3-governance/channels.zig` | 🚧 Design phase |
| Slash Protocol | `core/l0-transport/slash.zig` | ✅ Stable |
| Federation | `core/l3-governance/federation.zig` | 📋 Planned |

---

## Further Reading

- [RFC-0140: SSI Stack](../rfcs/RFC-0140_Libertaria_SSI_Stack.md) (Section 6)
- [RFC-0141: State Channels](../rfcs/) (planned)
- [RFC-0142: Chapters](../rfcs/) (planned)

---

*Fork freely. Coordinate without control.* ⚡
