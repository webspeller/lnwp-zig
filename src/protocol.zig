const std = @import("std");

pub const version_5_0: u16 = 0x0500;
pub const alpn_v5 = "lnwp/5";
pub const header_len_v5: usize = 4;
pub const header_len_v4: usize = 5;
pub const max_body_len: usize = 65_535;
pub const max_multiplex_sessions: usize = 256;
pub const broadcast_logical_session_id: u32 = 0xFFFF_FFFF;
pub const snapshot_hash_len: usize = 32;
pub const viewport_hmac_len: usize = 8;
pub const batch_hmac_len: usize = 32;

pub const ConformanceTier = enum {
    nano,
    base,
    full,
    enterprise,

    pub fn requiresPqc(self: ConformanceTier) bool {
        return self == .full or self == .enterprise;
    }

    pub fn supportsQuic(self: ConformanceTier) bool {
        return self == .full or self == .enterprise;
    }
};

pub const CdpTier = enum(u2) {
    full_or_enterprise = 0,
    base = 1,
    nano = 2,
    reserved = 3,
};

pub fn cdpTierFromByte(value: u8) !CdpTier {
    if (value > 3) return error.MalformedFrame;
    return @as(CdpTier, @enumFromInt(@as(u2, @intCast(value))));
}

pub const Encoding = enum(u8) {
    binary = 0,
    cbor = 1,
    message_pack = 2,
};

pub fn encodingFromByte(value: u8) !Encoding {
    return std.enums.fromInt(Encoding, value) orelse error.EncodingUnsupported;
}

pub const Capability = enum(u6) {
    zc_capable = 0,
    batch_capable = 1,
    fanout_capable = 2,
    integrity_capable = 3,
    streaming_capable = 4,
    multiplex_capable = 5,
    telemetry_capable = 6,
    viewport_capable = 7,
    ml_dsa_capable = 8,
    rebind_capable = 9,
    config_reload_capable = 10,
    hot_reload_capable = 11,
    security_critical_aware = 12,
};

pub const Capabilities = struct {
    bits: u64 = 0,

    pub fn init(bits: u64) Capabilities {
        return .{ .bits = bits };
    }

    pub fn empty() Capabilities {
        return .{};
    }

    pub fn has(self: Capabilities, capability: Capability) bool {
        return (self.bits & mask(capability)) != 0;
    }

    pub fn set(self: *Capabilities, capability: Capability, enabled: bool) void {
        if (enabled) {
            self.bits |= mask(capability);
        } else {
            self.bits &= ~mask(capability);
        }
    }

    pub fn with(self: Capabilities, capability: Capability) Capabilities {
        var out = self;
        out.set(capability, true);
        return out;
    }

    fn mask(capability: Capability) u64 {
        return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(capability)));
    }
};

pub fn headerLenForVersion(version: u16) usize {
    if ((version & 0xFF00) == 0x0400) return header_len_v4;
    return header_len_v5;
}

pub fn negotiateVersion(client_version: u16, supported_versions: []const u16) ?u16 {
    var best: ?u16 = null;
    for (supported_versions) |candidate| {
        if (candidate <= client_version and (best == null or candidate > best.?)) {
            best = candidate;
        }
    }
    return best;
}

test "capability bitfield follows spec bit order" {
    var caps = Capabilities.empty();
    caps.set(.zc_capable, true);
    caps.set(.security_critical_aware, true);

    try std.testing.expect(caps.has(.zc_capable));
    try std.testing.expect(caps.has(.security_critical_aware));
    try std.testing.expect(!caps.has(.batch_capable));
    try std.testing.expectEqual(@as(u64, 0b1 | (@as(u64, 1) << 12)), caps.bits);
}

test "version negotiation selects highest compatible version" {
    const supported = [_]u16{ 0x0401, version_5_0 };
    try std.testing.expectEqual(@as(u16, 0x0401), negotiateVersion(0x0405, supported[0..]).?);
    try std.testing.expectEqual(@as(u16, version_5_0), negotiateVersion(version_5_0, supported[0..]).?);
    try std.testing.expect(negotiateVersion(0x0300, supported[0..]) == null);
}
