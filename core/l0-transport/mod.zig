// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Libertaria Contributors
// This file is part of the Libertaria Core, licensed under
// The Libertaria Commonwealth License v1.0.


const std = @import("std");

// LWF types - re-exported directly AND under lwf namespace for compatibility
pub const LWFHeader = @import("lwf.zig").LWFHeader;
pub const LWFTrailer = @import("lwf.zig").LWFTrailer;
pub const LWFFrame = @import("lwf.zig").LWFFrame;
pub const LWFFlags = @import("lwf.zig").LWFFlags;
pub const FrameClass = @import("lwf.zig").FrameClass;

// LWF namespace for backward compatibility
pub const lwf = struct {
    pub const LWFHeader = @import("lwf.zig").LWFHeader;
    pub const LWFTrailer = @import("lwf.zig").LWFTrailer;
    pub const LWFFrame = @import("lwf.zig").LWFFrame;
    pub const LWFFlags = @import("lwf.zig").LWFFlags;
    pub const FrameClass = @import("lwf.zig").FrameClass;
};

// Note: time is imported as a standalone module, not re-exported here
// to avoid module ownership conflicts

// Note: utcp is a separate module, not re-exported here

// Note: opq/service tested separately via their own modules
// (avoiding circular module dependencies)

// Re-export Transport Skins (DPI evasion)
pub const skins = @import("transport_skins.zig");
pub const mimic_https = @import("mimic_https.zig");
pub const mimic_dns = @import("mimic_dns.zig");
pub const mimic_quic = @import("mimic_quic.zig");

// Re-export Noise Protocol Framework (Signal/WireGuard crypto)
pub const noise = @import("noise.zig");

// Re-export Polymorphic Noise Generator (traffic shaping)
pub const png = @import("png.zig");

// Re-export DHT (Distributed Hash Table)
pub const dht = @import("dht.zig");

// Re-export Gateway (NAT traversal)
pub const gateway = @import("gateway.zig");

// Re-export Relay (Onion routing)
pub const relay = @import("relay.zig");

// Re-export Quarantine (Security lockdown)
pub const quarantine = @import("quarantine.zig");

test {
    // Test individual components
    // Note: opq/service/utcp tested separately via their own modules
    _ = skins;
    _ = mimic_https;
    _ = mimic_dns;
    _ = mimic_quic;
    _ = noise;
    _ = png;
    _ = dht;
    _ = gateway;
    _ = relay;
    _ = quarantine;
}
