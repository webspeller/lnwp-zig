const std = @import("std");
const protocol = @import("protocol.zig");

pub const Transport = enum {
    quic_native,
    webtransport,
    quic_websocket,
    http2_sse,
    http1_sse_polling,
};

pub const priority_order = [_]Transport{
    .quic_native,
    .webtransport,
    .quic_websocket,
    .http2_sse,
    .http1_sse_polling,
};

pub fn alpn(transport: Transport) ?[]const u8 {
    return switch (transport) {
        .quic_native, .webtransport, .quic_websocket => protocol.alpn_v5,
        .http2_sse, .http1_sse_polling => null,
    };
}

pub fn allowedForTier(transport: Transport, tier: protocol.ConformanceTier) bool {
    return switch (tier) {
        .nano, .base => transport == .http1_sse_polling,
        .full, .enterprise => true,
    };
}

pub fn select(server_supported: []const Transport, client_supported: []const Transport, tier: protocol.ConformanceTier) ?Transport {
    for (priority_order) |candidate| {
        if (!allowedForTier(candidate, tier)) continue;
        if (contains(server_supported, candidate) and contains(client_supported, candidate)) return candidate;
    }
    return null;
}

fn contains(items: []const Transport, needle: Transport) bool {
    for (items) |item| {
        if (item == needle) return true;
    }
    return false;
}

test "transport selection follows priority and tier restrictions" {
    const server = [_]Transport{ .http1_sse_polling, .webtransport, .quic_native };
    const client = [_]Transport{ .http1_sse_polling, .webtransport };
    try std.testing.expectEqual(Transport.webtransport, select(server[0..], client[0..], .full).?);
    try std.testing.expectEqual(Transport.http1_sse_polling, select(server[0..], client[0..], .nano).?);
}
