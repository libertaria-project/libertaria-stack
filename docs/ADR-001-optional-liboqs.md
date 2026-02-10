# ADR-001: Optional liboqs Dependency for Post-Quantum Crypto

**Status:** Accepted  
**Date:** 2026-02-09  
**Author:** Janus (Agent)  
**Scope:** L1 Identity / PQXDH  

## Context

The Libertaria capsule-core build was failing with undefined symbol errors:
- `OQS_KEM_ml_kem_768_keypair`
- `OQS_KEM_ml_kem_768_encaps`
- `OQS_KEM_ml_kem_768_decaps`
- `OQS_randombytes_switch_algorithm`
- `OQS_randombytes_custom_algorithm`

These symbols come from liboqs (Open Quantum Safe), a C library for post-quantum cryptography. The build.zig had the library linking commented out:

```zig
// TODO: Install liboqs for post-quantum crypto support
// exe.linkSystemLibrary("oqs");
```

This blocked all development work on the capsule-core project.

## Decision

Implement a **conditional build system** that:

1. **Uses stub implementations** when liboqs is not available
2. **Links real liboqs** when explicitly enabled (`-Denable-liboqs=true`)
3. **Gracefully degrades** at runtime with clear error messages
4. **Skips PQ-specific tests** when liboqs is disabled

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Build Configuration                      │
├─────────────────────────────────────────────────────────────┤
│  -Denable-liboqs=true  →  liboqs_real.zig  →  link liboqs  │
│  (default: false)      →  liboqs_stub.zig  →  no linking   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      pqxdh.zig                              │
│  Imports liboqs module (real or stub via build_options)    │
│  Checks build_options.liboqs_enabled at compile time        │
└─────────────────────────────────────────────────────────────┘
```

### Files Created/Modified

**New Files:**
- `core/l1-identity/liboqs_real.zig` - Real C FFI declarations
- `core/l1-identity/liboqs_stub.zig` - Stub implementations that log errors

**Modified:**
- `core/l1-identity/pqxdh.zig` - Use module imports instead of direct extern
- `capsule-core/build.zig` - Add `-Denable-liboqs` option, conditional linking

## Consequences

### Positive

- ✅ **Build unblocked** - Developers can build and test without installing liboqs
- ✅ **Clear upgrade path** - Single flag enables post-quantum security
- ✅ **Runtime safety** - Stub functions log clear errors instead of crashing
- ✅ **Test compatibility** - PQ tests skip gracefully when unavailable

### Negative

- ⚠️ **Security degradation** - Without liboqs, PQXDH falls back to X25519 only
- ⚠️ **Production requirement** - Production builds MUST use `-Denable-liboqs=true`

## Usage

### Development (without liboqs)
```bash
cd libertaria-stack/capsule-core
zig build                    # Builds with stub implementations
zig build test              # Runs tests (PQ tests skipped)
```

### Production (with liboqs)
```bash
# Install liboqs first
sudo apt install liboqs  # or build from source

# Build with PQ crypto
cd libertaria-stack/capsule-core
zig build -Denable-liboqs=true
```

## References

- RFC-0830: PQXDH Protocol Specification
- liboqs: https://github.com/open-quantum-safe/liboqs
- FIPS 203: ML-KEM Standard
