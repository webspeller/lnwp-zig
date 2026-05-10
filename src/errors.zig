const std = @import("std");

pub const Category = enum {
    transport,
    auth,
    session,
    protocol,
    unknown,
};

pub const ErrorCode = enum(u16) {
    version_mismatch = 1001,
    frame_too_large = 1002,
    invalid_opcode = 1003,
    malformed_frame = 1004,
    crc_mismatch = 1005,

    auth_failed = 2001,
    jwt_expired = 2002,
    channel_binding_required = 2003,
    auth_rate_limited = 2004,
    credential_refresh_required = 2005,

    server_overloaded = 3001,
    session_not_found = 3002,
    seq_gap = 3003,
    schema_version_mismatch = 3004,
    ratchet_desynced = 3005,
    adc_dict_corrupt = 3006,
    grpc_cb_open = 3007,
    rate_limited = 3008,
    schema_cas_conflict = 3009,
    fanout_limit = 3010,
    brownout_active = 3011,
    qos_exceeded = 3012,
    syncing_timeout = 3013,
    rollback_pending = 3014,
    debug_denied = 3015,
    cdp_unsupported = 3016,
    wt_downgrade = 3017,
    cluster_brownout = 3018,
    config_rejected = 3019,
    locale_unsupported = 3020,
    fanout_leader_conflict = 3021,
    integrity_mac_failed = 3022,
    multiplex_limit = 3023,
    residency_violation = 3024,
    conflict_unresolvable = 3025,
    plugin_rejected = 3026,
    encoding_unsupported = 3027,
    initial_stream_interrupted = 3028,

    reserved_opcode = 4000,
    capability_mismatch = 4001,
    snapshot_hash_invalid = 4002,
    viewport_hmac_invalid = 4003,
    ipc_auth_failed = 4004,
};

pub fn categoryForInt(code: u16) Category {
    return switch (code) {
        1000...1999 => .transport,
        2000...2999 => .auth,
        3000...3999 => .session,
        4000...4999 => .protocol,
        else => .unknown,
    };
}

pub fn fromInt(code: u16) ?ErrorCode {
    return std.enums.fromInt(ErrorCode, code);
}

pub fn category(code: ErrorCode) Category {
    return categoryForInt(@as(u16, @intFromEnum(code)));
}

pub fn nameFromInt(code: u16) []const u8 {
    if (fromInt(code)) |known| return @tagName(known);
    return "unknown";
}

test "error categories match registry ranges" {
    try std.testing.expectEqual(Category.transport, category(.frame_too_large));
    try std.testing.expectEqual(Category.auth, category(.jwt_expired));
    try std.testing.expectEqual(Category.session, category(.integrity_mac_failed));
    try std.testing.expectEqual(Category.protocol, category(.reserved_opcode));
    try std.testing.expectEqual(Category.unknown, categoryForInt(9000));
}
