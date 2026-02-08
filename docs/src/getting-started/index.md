# Getting Started

Welcome to Libertaria. This guide will get you from zero to a running sovereign node in under 30 minutes.

---

## Prerequisites

- **Zig 0.15.2+** — [ziglang.org/download](https://ziglang.org/download/)
- **Git** — For version control
- **2+ hours** — To read, build, and understand

Optional but helpful:
- **liboqs** — For post-quantum crypto (see `vendor/liboqs/`)
- **argon2** — For key derivation (bundled in `vendor/argon2/`)

---

## 5-Minute Setup

```bash
# 1. Clone
git clone https://github.com/libertaria-project/libertaria-stack.git
cd libertaria-stack

# 2. Build
zig build

# 3. Test
zig build test

# 4. Run example
zig build examples
./zig-out/bin/lwf_example
```

**Expected:** All tests pass, examples run without errors.

---

## What Next?

- **[Installation](installation.md)** — Detailed setup instructions
- **[First Node](first-node.md)** — Run your first Capsule node
- **[Concepts](concepts.md)** — Core concepts and terminology

---

## Troubleshooting

### Build fails with "undefined reference to argon2"

Ensure vendor libraries are initialized:
```bash
git submodule update --init --recursive
```

### Tests fail on ARM

Some cryptographic tests may fail on older ARM chips. This is expected — the core functionality works, but some optimized paths require ARMv8+.

---

*Forge burns bright.* ⚡
