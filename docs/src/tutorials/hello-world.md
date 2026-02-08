# Hello Sovereign World

Build your first Libertaria application—a simple LWF echo server that demonstrates the fundamentals of the Libertaria Wire Frame (LWF) protocol.

---

## What You'll Build

A TCP echo server that:
1. Listens for LWF frames on port 7777
2. Validates incoming frames
3. Echoes the payload back to the sender
4. Uses proper LWF framing with checksums

---

## Prerequisites

- **Zig 0.13+** installed ([ziglang.org](https://ziglang.org))
- **netcat** (`nc`) or **telnet** for testing
- Basic knowledge of TCP sockets

### Verify Your Environment

```bash
zig version
nc -h  # or: man nc
```

---

## Step 1: Create the Project

```bash
mkdir lwf-echo-server
cd lwf-echo-server
zig init
```

This creates a basic Zig project with `build.zig` and `src/main.zig`.

---

## Step 2: Understand LWF Basics

The **Libertaria Wire Frame (LWF)** protocol (RFC-0000) defines a fixed-size header format optimized for "Fast Drop" routing:

```
┌─────────────────────────────────────────────────────────────┐
│  LWF Header (88 bytes)                                      │
├─────────────────────────────────────────────────────────────┤
│  Magic (4)    │ "LWF\0"                                      │
│  Dest Hint (24)│ Blake3 truncated DID hint                   │
│  Src Hint (24) │ Blake3 truncated DID hint                   │
│  SessionID (16)│ Flow identifier                             │
│  Sequence (4)  │ Frame ordering                              │
│  Service (2)   │ Service type (e.g., 0x0001 = DATA)          │
│  Length (2)    │ Payload length                              │
│  Meta (4)      │ Flags and metadata                          │
│  Timestamp (8) │ Unix nanoseconds                            │
└─────────────────────────────────────────────────────────────┘
│  Payload (variable, up to 1350 bytes for standard frames)   │
├─────────────────────────────────────────────────────────────┤
│  LWF Trailer (36 bytes)                                     │
│  - CRC32-C checksum (4 bytes)                               │
│  - Ed25519 signature (optional, 32 bytes)                   │
└─────────────────────────────────────────────────────────────┘
```

**Key Frame Classes:**
| Class | Max Size | Use Case |
|-------|----------|----------|
| micro | 128 B | Control messages, ACKs |
| mini | 512 B | Small data packets |
| standard | 1350 B | Default (Ethernet MTU) |
| big | 4096 B | Large data transfers |
| jumbo | 9000 B | Jumbo frames |

---

## Step 3: Implement the Echo Server

Replace `src/main.zig` with:

```zig
const std = @import("std");
const net = std.net;
const posix = std.posix;

// LWF Header (88 bytes) - RFC-0000
const LWFHeader = extern struct {
    magic: [4]u8 = "LWF\x00".*,
    dest_hint: [24]u8 = std.mem.zeroes([24]u8),
    source_hint: [24]u8 = std.mem.zeroes([24]u8),
    session_id: [16]u8 = std.mem.zeroes([16]u8),
    sequence: u32 = 0,
    service_type: u16 = std.mem.nativeToBig(u16, 0x0001), // DATA_TRANSPORT
    payload_len: u16 = 0,
    meta: u32 = 0,
    timestamp: u64 = 0,

    pub fn isValid(self: *const LWFHeader) bool {
        return std.mem.eql(u8, &self.magic, "LWF\x00");
    }
};

// LWF Trailer (36 bytes)
const LWFTrailer = extern struct {
    crc32c: u32 = 0,
    signature: [32]u8 = std.mem.zeroes([32]u8),
};

// Standard frame: 88 header + 1350 payload + 36 trailer = 1474 bytes max
const MAX_PAYLOAD_SIZE = 1350;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const port = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else 7777;

    // Create listening socket
    const address = try net.Address.parseIp4("0.0.0.0", port);
    const listener = try posix.socket(address.any.family, posix.SOCK.STREAM, 0);
    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    std.log.info("LWF Echo Server listening on port {}", .{port});

    // Accept connections
    while (true) {
        var client_addr: net.Address = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(net.Address);

        const client = try posix.accept(listener, &client_addr.any, &client_addr_len, 0);
        defer posix.close(client);

        std.log.info("Client connected from {}", .{client_addr});

        // Handle client in a separate scope
        try handleClient(allocator, client);
    }
}

fn handleClient(allocator: std.mem.Allocator, client: posix.socket_t) !void {
    // Buffer for frame: header + max payload + trailer
    var buffer: [88 + MAX_PAYLOAD_SIZE + 36]u8 = undefined;

    // Read header first (88 bytes)
    const header_bytes = try readAll(client, buffer[0..88]);
    if (header_bytes < 88) {
        std.log.warn("Incomplete header received", .{});
        return;
    }

    // Parse header
    const header = std.mem.bytesToValue(LWFHeader, buffer[0..@sizeOf(LWFHeader)]);

    // Validate magic
    if (!header.isValid()) {
        std.log.warn("Invalid LWF magic received", .{});
        return;
    }

    const payload_len = std.mem.bigToNative(u16, header.payload_len);
    if (payload_len > MAX_PAYLOAD_SIZE) {
        std.log.warn("Payload too large: {}", .{payload_len});
        return;
    }

    std.log.info("Received LWF frame: service=0x{X:0>4}, payload_len={}", .{
        std.mem.bigToNative(u16, header.service_type),
        payload_len,
    });

    // Read payload if present
    if (payload_len > 0) {
        const payload_bytes = try readAll(client, buffer[88..(88 + payload_len)]);
        if (payload_bytes < payload_len) {
            std.log.warn("Incomplete payload received", .{});
            return;
        }

        // Log the payload
        const payload = buffer[88..(88 + payload_len)];
        std.log.info("Payload: {s}", .{payload});
    }

    // Read trailer (36 bytes)
    const trailer_start = 88 + payload_len;
    const trailer_bytes = try readAll(client, buffer[trailer_start..(trailer_start + 36)]);
    if (trailer_bytes < 36) {
        std.log.warn("Incomplete trailer received", .{});
        return;
    }

    // Build echo response with same payload
    var response_header = LWFHeader{
        .service_type = std.mem.nativeToBig(u16, 0x0001), // DATA_TRANSPORT
        .payload_len = std.mem.nativeToBig(u16, payload_len),
        .timestamp = std.mem.nativeToBig(u64, @as(u64, @intCast(std.time.milliTimestamp()))),
        .sequence = header.sequence, // Echo back sequence
    };
    @memcpy(&response_header.dest_hint, &header.source_hint);
    @memcpy(&response_header.source_hint, &header.dest_hint);

    // Send response
    _ = try posix.write(client, std.mem.asBytes(&response_header));
    if (payload_len > 0) {
        _ = try posix.write(client, buffer[88..(88 + payload_len)]);
    }
    const trailer = LWFTrailer{}; // Empty trailer for simplicity
    _ = try posix.write(client, std.mem.asBytes(&trailer));

    std.log.info("Echo response sent", .{});
}

fn readAll(sock: posix.socket_t, buf: []u8) !usize {
    var total_read: usize = 0;
    while (total_read < buf.len) {
        const n = try posix.read(sock, buf[total_read..]);
        if (n == 0) return total_read; // Connection closed
        total_read += n;
    }
    return total_read;
}
```

---

## Step 4: Build the Server

```bash
zig build-exe src/main.zig -O ReleaseSafe
```

Or use the build.zig:

```bash
zig build -Doptimize=ReleaseSafe
```

---

## Step 5: Test with Netcat

### Terminal 1: Start the Server

```bash
./lwf-echo-server 7777
```

You should see:
```
info: LWF Echo Server listening on port 7777
```

### Terminal 2: Send a Test Frame

Create a simple LWF frame and send it:

```bash
# Build a minimal LWF frame
# Magic (4) + zeros for rest of header + payload + trailer

python3 << 'EOF'
import struct
import sys

# LWF Header (88 bytes)
magic = b"LWF\x00"
dest_hint = b"\x00" * 24
source_hint = b"\x00" * 24
session_id = b"\x00" * 16
sequence = struct.pack(">I", 1)
service_type = struct.pack(">H", 0x0001)  # DATA_TRANSPORT
payload_len = struct.pack(">H", 13)  # "Hello, World!"
meta = struct.pack(">I", 0)
timestamp = struct.pack(">Q", 0)

header = magic + dest_hint + source_hint + session_id + sequence + service_type + payload_len + meta + timestamp
assert len(header) == 88

# Payload
payload = b"Hello, World!"
assert len(payload) == 13

# Trailer (36 bytes) - simplified, no CRC/signature
trailer = b"\x00" * 36

# Complete frame
frame = header + payload + trailer
sys.stdout.buffer.write(frame)
EOF
```

Save this to a file and pipe to netcat:

```bash
python3 build_frame.py | nc localhost 7777 | xxd
```

Or use a simpler approach with echo and hexdump:

```bash
# Create a raw frame (simplified for testing)
printf 'LWF\x00' > /tmp/frame.raw
# Pad to 88 bytes header
printf '\x00%.0s' {1..84} >> /tmp/frame.raw
# Add payload
printf 'Hello, World!' >> /tmp/frame.raw
# Pad to 36 bytes trailer
printf '\x00%.0s' {1..36} >> /tmp/frame.raw

# Send and receive
cat /tmp/frame.raw | nc localhost 7777 | xxd
```

### Expected Output

**Server console:**
```
info: Client connected from 127.0.0.1:xxxxx
info: Received LWF frame: service=0x0001, payload_len=13
info: Payload: Hello, World!
info: Echo response sent
```

**Client console:**
```
00000000: 4c57 4600 0000 0000 0000 0000 0000 0000  LWF............
00000010: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000020: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000030: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000040: 0000 0000 0000 0000 0000 0001 000d 0000  ................
00000050: 0000 0000 0000 0000 4865 6c6c 6f2c 2057  ........Hello, W
00000060: 6f72 6c64 2100 0000 0000 0000 0000 0000  orld!...........
```

---

## Understanding the Code

### Key Components

1. **LWFHeader struct** - Matches the RFC-0000 specification:
   - `extern struct` ensures C-compatible memory layout
   - Magic bytes `"LWF\0"` identify valid frames
   - Big-endian encoding for network byte order

2. **Frame Validation**:
   ```zig
   if (!header.isValid()) {
       std.log.warn("Invalid LWF magic received", .{});
       return;
   }
   ```

3. **Network Byte Order**:
   ```zig
   const payload_len = std.mem.bigToNative(u16, header.payload_len);
   ```

4. **Modular Arithmetic**:
   ```zig
   buffer[88..(88 + payload_len)]  // Slice from header end
   ```

---

## Troubleshooting

### "Invalid LWF magic received"

**Cause:** The client sent data that doesn't start with `LWF\0`

**Fix:** Ensure your test frame starts with the correct magic bytes:
```python
magic = b"LWF\x00"
```

### "Incomplete header received"

**Cause:** Client disconnected or sent less than 88 bytes

**Fix:** Check your frame construction. The header must be exactly 88 bytes.

### Connection refused

**Cause:** Server not running or wrong port

**Fix:** Verify the server is listening:
```bash
ss -tlnp | grep 7777
```

### Payload garbled in echo

**Cause:** Byte order or buffer slicing issue

**Fix:** Verify you're using `bigToNative` when reading and `nativeToBig` when writing:
```zig
const len = std.mem.bigToNative(u16, header.payload_len);  // Read
header.payload_len = std.mem.nativeToBig(u16, len);        // Write
```

### Build errors

**Cause:** Zig version mismatch

**Fix:** Ensure Zig 0.13+:
```bash
zig version  # Should show 0.13.0 or higher
```

---

## Next Steps

1. **Add CRC32-C verification** using `std.hash.crc.Crc32C`
2. **Implement proper session management** with SessionID tracking
3. **Add Ed25519 signatures** for frame authentication
4. **Try the next tutorial:** [Build a Sovereign Chat](./sovereign-chat.md)

---

## Full Source Code

```zig
// src/main.zig
// Complete LWF Echo Server - RFC-0000

const std = @import("std");
const net = std.net;
const posix = std.posix;

const LWFHeader = extern struct {
    magic: [4]u8 = "LWF\x00".*,
    dest_hint: [24]u8 = std.mem.zeroes([24]u8),
    source_hint: [24]u8 = std.mem.zeroes([24]u8),
    session_id: [16]u8 = std.mem.zeroes([16]u8),
    sequence: u32 = 0,
    service_type: u16 = std.mem.nativeToBig(u16, 0x0001),
    payload_len: u16 = 0,
    meta: u32 = 0,
    timestamp: u64 = 0,

    pub fn isValid(self: *const LWFHeader) bool {
        return std.mem.eql(u8, &self.magic, "LWF\x00");
    }
};

const LWFTrailer = extern struct {
    crc32c: u32 = 0,
    signature: [32]u8 = std.mem.zeroes([32]u8),
};

const MAX_PAYLOAD_SIZE = 1350;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const port = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else 7777;

    const address = try net.Address.parseIp4("0.0.0.0", port);
    const listener = try posix.socket(address.any.family, posix.SOCK.STREAM, 0);
    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    std.log.info("LWF Echo Server listening on port {}", .{port});

    while (true) {
        var client_addr: net.Address = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(net.Address);

        const client = try posix.accept(listener, &client_addr.any, &client_addr_len, 0);
        defer posix.close(client);

        std.log.info("Client connected from {}", .{client_addr});
        try handleClient(allocator, client);
    }
}

fn handleClient(_: std.mem.Allocator, client: posix.socket_t) !void {
    var buffer: [88 + MAX_PAYLOAD_SIZE + 36]u8 = undefined;

    const header_bytes = try readAll(client, buffer[0..88]);
    if (header_bytes < 88) return;

    const header = std.mem.bytesToValue(LWFHeader, buffer[0..@sizeOf(LWFHeader)]);
    if (!header.isValid()) return;

    const payload_len = std.mem.bigToNative(u16, header.payload_len);
    if (payload_len > MAX_PAYLOAD_SIZE) return;

    if (payload_len > 0) {
        _ = try readAll(client, buffer[88..(88 + payload_len)]);
    }
    _ = try readAll(client, buffer[(88 + payload_len)..(88 + payload_len + 36)]);

    // Echo back
    var response_header = LWFHeader{
        .payload_len = std.mem.nativeToBig(u16, payload_len),
        .timestamp = std.mem.nativeToBig(u64, @as(u64, @intCast(std.time.milliTimestamp()))),
        .sequence = header.sequence,
    };
    @memcpy(&response_header.dest_hint, &header.source_hint);

    _ = try posix.write(client, std.mem.asBytes(&response_header));
    if (payload_len > 0) {
        _ = try posix.write(client, buffer[88..(88 + payload_len)]);
    }
    const trailer = LWFTrailer{};
    _ = try posix.write(client, std.mem.asBytes(&trailer));
}

fn readAll(sock: posix.socket_t, buf: []u8) !usize {
    var total_read: usize = 0;
    while (total_read < buf.len) {
        const n = try posix.read(sock, buf[total_read..]);
        if (n == 0) return total_read;
        total_read += n;
    }
    return total_read;
}
```

---

## References

- [RFC-0000: LWF Protocol Specification](../rfcs/)
- [L0 Transport README](../../../core/l0-transport/README.md)
- [Libertaria SDK Integration Guide](../INTEGRATION.md)
