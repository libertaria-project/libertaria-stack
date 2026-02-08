# Installation

Detailed installation instructions for the Libertaria Stack.

---

## System Requirements

### Minimum (Kenya Device)

- ARM Cortex-A53 @ 1.4 GHz (Raspberry Pi 3)
- 512 MB RAM
- 100 MB storage
- No internet required for operation

### Recommended

- x86_64 or ARM64 processor
- 2 GB RAM
- 1 GB storage
- Git for updates

---

## Step-by-Step Installation

### 1. Install Zig

**Linux/macOS:**
```bash
# Download from ziglang.org
curl -L https://ziglang.org/download/0.15.2/zig-linux-x86_64-0.15.2.tar.xz | tar xJ
sudo mv zig-linux-x86_64-0.15.2 /opt/zig
export PATH="/opt/zig:$PATH"
```

**Verify:**
```bash
zig version
# Should output: 0.15.2
```

### 2. Clone the Repository

```bash
git clone https://github.com/libertaria-project/libertaria-stack.git
cd libertaria-stack
```

### 3. Initialize Submodules (Optional)

Only needed if you want post-quantum cryptography:

```bash
git submodule update --init --recursive
```

### 4. Build

```bash
# Debug build (faster compile, slower runtime)
zig build

# Release build (slower compile, optimized runtime)
zig build -Doptimize=ReleaseFast

# Small release (best for embedded)
zig build -Doptimize=ReleaseSmall
```

### 5. Verify Installation

```bash
# Run all tests
zig build test

# Expected output:
# All 173 tests passed.
```

---

## Cross-Compilation

Build for different targets without changing hosts:

```bash
# Raspberry Pi 3 (ARMv7)
zig build -Dtarget=arm-linux-gnueabihf -Doptimize=ReleaseSmall

# Budget Android (ARM64)
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall

# Intel Mac
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseFast

# Apple Silicon
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast
```

---

## Installation Verification

Check your build:

```bash
# Binary size
ls -lh zig-out/lib/liblibertaria_*.a

# Should be < 500 KB for L0-L1 combined

# Memory usage
valgrind --tool=massif ./zig-out/bin/test
# Expected: < 50 MB peak
```

---

## Next Steps

- **[First Node](first-node.md)** — Run your first Capsule node
- **[Concepts](concepts.md)** — Learn core concepts
