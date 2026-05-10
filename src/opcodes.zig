const std = @import("std");

pub const Direction = enum {
    client_to_server,
    server_to_client,
    both,
    local,
    none,
};

pub const Priority = enum(u4) {
    p0 = 0,
    p1 = 1,
    p2 = 2,
    p3 = 3,
    p4 = 4,
    p5 = 5,
    p6 = 6,
    p7 = 7,
    none = 15,
};

pub const Opcode = enum(u8) {
    hello = 0x01,
    welcome = 0x02,
    patch = 0x03,
    ack = 0x04,
    event = 0x05,
    ping = 0x06,
    pong = 0x07,
    fragment = 0x08,
    resync = 0x09,
    error_frame = 0x0A,
    @"resume" = 0x0B,
    migrate = 0x0C,
    drain = 0x0D,
    backpressure = 0x0E,
    slowdown = 0x0F,
    batch_patch = 0x10,
    adc_dict_update = 0x11,
    priority_signal = 0x12,
    grpc_frame = 0x13,
    initial_stream_chunk = 0x14,
    session_fanout = 0x15,
    runtime_config = 0x16,
    power_profile = 0x17,
    viewport_hint = 0x18,
    session_sleep = 0x19,
    locale_hint = 0x1A,
    transport_migrate = 0x1B,
    client_telemetry = 0x1C,
    business_event = 0x1D,
    credential_refresh = 0x1E,
    hello_rebind = 0x1F,
    resume_from_snapshot = 0x20,
    brownout = 0x21,
    fle_ratchet = 0x22,
    session_multiplex = 0x23,
    residency_hint = 0x24,
    gc_pause_hint = 0x25,
    component_hot_reload = 0x26,
    schema_rollback = 0x27,
};

pub const Parsed = union(enum) {
    standard: Opcode,
    plugin: u8,
};

pub fn isPluginByte(value: u8) bool {
    return value >= 0xF0 and value <= 0xFE;
}

pub fn fromRegistryByte(value: u8) !Parsed {
    if (value == 0xFF) return error.ReservedOpcode;
    if (isPluginByte(value)) return .{ .plugin = value };
    const standard = std.enums.fromInt(Opcode, value) orelse return error.InvalidOpcode;
    return .{ .standard = standard };
}

pub fn fromWireByte(value: u8) !Parsed {
    const parsed = try fromRegistryByte(value);
    switch (parsed) {
        .standard => |standard| {
            if (standard == .gc_pause_hint) return error.LocalOpcodeNotTransmitted;
        },
        .plugin => {},
    }
    return parsed;
}

pub fn toByte(parsed: Parsed) u8 {
    return switch (parsed) {
        .standard => |opcode| @as(u8, @intFromEnum(opcode)),
        .plugin => |opcode| opcode,
    };
}

pub fn direction(opcode: Opcode) Direction {
    return switch (opcode) {
        .hello,
        .ack,
        .event,
        .resync,
        .@"resume",
        .priority_signal,
        .viewport_hint,
        .session_sleep,
        .client_telemetry,
        .business_event,
        .credential_refresh,
        .hello_rebind,
        .resume_from_snapshot,
        .residency_hint,
        => .client_to_server,

        .welcome,
        .patch,
        .migrate,
        .drain,
        .backpressure,
        .slowdown,
        .batch_patch,
        .adc_dict_update,
        .initial_stream_chunk,
        .session_fanout,
        .runtime_config,
        .power_profile,
        .transport_migrate,
        .brownout,
        .fle_ratchet,
        .component_hot_reload,
        .schema_rollback,
        => .server_to_client,

        .ping,
        .pong,
        .fragment,
        .error_frame,
        .grpc_frame,
        .locale_hint,
        .session_multiplex,
        => .both,

        .gc_pause_hint => .local,
    };
}

pub fn priority(opcode: Opcode) Priority {
    return switch (opcode) {
        .ping,
        .pong,
        .resync,
        .error_frame,
        .migrate,
        .drain,
        .backpressure,
        .slowdown,
        .brownout,
        => .p0,

        .patch,
        .ack,
        .batch_patch,
        .priority_signal,
        .initial_stream_chunk,
        .session_fanout,
        .runtime_config,
        .session_sleep,
        .credential_refresh,
        .hello_rebind,
        .fle_ratchet,
        .session_multiplex,
        .residency_hint,
        .schema_rollback,
        .transport_migrate,
        => .p1,

        .event,
        .grpc_frame,
        .component_hot_reload,
        => .p2,

        .adc_dict_update,
        .power_profile,
        .viewport_hint,
        .locale_hint,
        => .p3,

        .client_telemetry,
        .business_event,
        => .p5,

        .hello,
        .welcome,
        .fragment,
        .@"resume",
        .resume_from_snapshot,
        .gc_pause_hint,
        => .none,
    };
}

pub fn tagName(parsed: Parsed) []const u8 {
    return switch (parsed) {
        .standard => |opcode| @tagName(opcode),
        .plugin => "plugin",
    };
}

test "registry accepts standard and plugin opcodes" {
    const hello = try fromWireByte(0x01);
    switch (hello) {
        .standard => |standard| try std.testing.expectEqual(Opcode.hello, standard),
        .plugin => return error.TestExpectedStandardOpcode,
    }

    const plugin = try fromWireByte(0xF7);
    switch (plugin) {
        .standard => return error.TestExpectedPluginOpcode,
        .plugin => |value| try std.testing.expectEqual(@as(u8, 0xF7), value),
    }

    try std.testing.expectError(error.ReservedOpcode, fromWireByte(0xFF));
    try std.testing.expectError(error.LocalOpcodeNotTransmitted, fromWireByte(0x25));
}

test "metadata follows opcode table" {
    try std.testing.expectEqual(Direction.client_to_server, direction(.hello));
    try std.testing.expectEqual(Direction.server_to_client, direction(.batch_patch));
    try std.testing.expectEqual(Direction.both, direction(.ping));
    try std.testing.expectEqual(Priority.p0, priority(.ping));
    try std.testing.expectEqual(Priority.p1, priority(.patch));
    try std.testing.expectEqual(Priority.p5, priority(.client_telemetry));
}
