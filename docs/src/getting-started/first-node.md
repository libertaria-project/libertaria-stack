# Your First Node

This guide walks you through running your first Libertaria Capsule node.

---

## What is a Capsule Node?

A **Capsule** is a reference implementation of a Libertaria node. It bundles:

- L0 Transport (MIMIC skins, LWF protocol)
- L1 Identity (SoulKey, QVL trust graph)
- L2 Session management
- L3 Chapter federation (optional)

Capsules are designed to run on minimal hardware — from a $5 Raspberry Pi to a datacenter server.

---

## Starting Your Node

### 1. Build the Capsule

```bash
cd libertaria-stack
zig build capsule
```

### 2. Generate an Identity

```bash
# Create a new SoulKey identity
./zig-out/bin/capsule keygen --output ~/.libertaria/identity.json

# Backup your mnemonic!
# Write down the 20-word recovery phrase
```

### 3. Configure

Create `~/.libertaria/config.toml`:

```toml
[node]
name = "my-first-node"
did = "did:libertaria:z8m9n0p2q4r..."

[transport]
# MIMIC skin for camouflage
skin = "MIMIC_HTTPS"
port = 4430

[peering]
# Bootstrap nodes (optional for first run)
bootstrap = [
  "/dns/capsule.libertaria.app/tcp/4430"
]

[storage]
# Single-file database
path = "~/.libertaria/data.mdb"
```

### 4. Run

```bash
# Start the node
./zig-out/bin/capsule run --config ~/.libertaria/config.toml

# Expected output:
# [INFO] Capsule starting...
# [INFO] L0 transport bound to 0.0.0.0:4430
# [INFO] L1 identity loaded: did:libertaria:z8m9n...
# [INFO] Node ready. Press Ctrl+C to stop.
```

---

## Verify It's Working

### Check Node Status

```bash
# In another terminal
./zig-out/bin/capsule status

# Expected:
# Node: my-first-node
# DID: did:libertaria:z8m9n...
# Peers: 0 (waiting for connections)
# Uptime: 0:02:15
```

### Test Local Services

```bash
# Check health endpoint
curl http://localhost:8080/health

# Expected:
# {"status":"healthy","layers":{"l0":true,"l1":true,"l2":true}}
```

---

## Connecting to the Network

### Manual Peering

```bash
# Connect to a specific peer
./zig-out/bin/capsule peer add /ip4/192.168.1.100/tcp/4430/p2p/did:libertaria:z7k8j...
```

### Automatic Discovery

Enable mDNS for local network discovery:

```toml
[peering]
discovery = ["mdns", "bootstrap"]
mdns = true
```

---

## Common Operations

### Stop the Node

Press `Ctrl+C` or:
```bash
./zig-out/bin/capsule stop
```

### View Logs

```bash
# Follow logs
tail -f ~/.libertaria/capsule.log

# Filter by layer
tail -f ~/.libertaria/capsule.log | grep "\[L1\]"
```

### Backup Identity

```bash
# Your identity is in:
~/.libertaria/identity.json

# IMPORTANT: Also backup your recovery mnemonic!
# Without it, identity cannot be recovered.
```

---

## Troubleshooting

### "Address already in use"

Another process is using port 4430:
```bash
# Find and kill it
lsof -i :4430
kill -9 <PID>

# Or use a different port in config.toml
port = 4431
```

### "Permission denied"

```bash
# Ensure the binary is executable
chmod +x ./zig-out/bin/capsule

# Ensure data directory exists
mkdir -p ~/.libertaria
```

### "Failed to parse identity"

```bash
# Regenerate identity
./zig-out/bin/capsule keygen --force --output ~/.libertaria/identity.json
```

---

## Next Steps

- **[Concepts](concepts.md)** — Learn about SoulKeys, QVL, and Chapters
- Explore the [Architecture](../architecture/) documentation
- Read the [RFCs](../../rfcs/) for technical specifications

---

*Your node is running. You are sovereign.* ⚡
