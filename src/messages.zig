const std = @import("std");
const codec = @import("codec.zig");
const errors = @import("errors.zig");
const opcodes = @import("opcodes.zig");
const protocol = @import("protocol.zig");

const zero32 = [_]u8{0} ** 32;

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

fn copy32(bytes: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    @memcpy(out[0..], bytes[0..32]);
    return out;
}

fn copy16(bytes: []const u8) [16]u8 {
    var out: [16]u8 = undefined;
    @memcpy(out[0..], bytes[0..16]);
    return out;
}

pub const Hello = struct {
    proto_version: u16 = protocol.version_5_0,
    session_id: u64 = 0,
    jwt: []const u8,
    jwt_binding_hash: ?[32]u8 = null,
    schema_version: u32 = 0,
    app_version: []const u8 = "",
    capabilities: protocol.Capabilities = .{},
    cdp_tier: protocol.CdpTier = .full_or_enterprise,
    locale: []const u8 = "",
    residency_zone: []const u8 = "",
    encoding: protocol.Encoding = .binary,
    snapshot_seq: ?u32 = null,
    snapshot_hash: ?[32]u8 = null,
    plugin_opcodes: []const u8 = &.{},

    pub fn validate(self: Hello) !void {
        if (self.proto_version == 0) return error.MalformedFrame;
        if (self.jwt.len == 0) return error.MissingJwt;
        if (self.cdp_tier == .reserved) return error.MalformedFrame;
        if (self.cdp_tier == .full_or_enterprise and self.jwt_binding_hash == null) {
            return error.ChannelBindingRequired;
        }
        if (self.snapshot_seq != null and self.snapshot_hash == null) {
            return error.SnapshotHashInvalid;
        }
        if (self.snapshot_seq == null and self.snapshot_hash != null) {
            return error.SnapshotHashInvalid;
        }
        for (self.plugin_opcodes) |opcode| {
            if (!opcodes.isPluginByte(opcode)) return error.PluginOpcodeInvalid;
        }
    }

    pub fn bodyLen(self: Hello) !usize {
        try self.validate();
        return 2 + 8 +
            stringLen(self.jwt) +
            32 +
            4 +
            stringLen(self.app_version) +
            8 +
            1 +
            stringLen(self.locale) +
            stringLen(self.residency_zone) +
            1 +
            4 +
            32 +
            byteArrayLen(self.plugin_opcodes);
    }

    pub fn encodeInto(self: Hello, out: []u8) ![]u8 {
        try self.validate();
        var writer = codec.Writer.init(out);
        try writer.writeU16(self.proto_version);
        try writer.writeU64(self.session_id);
        try writer.writeString(self.jwt);
        if (self.jwt_binding_hash) |hash| {
            try writer.writeRaw(hash[0..]);
        } else {
            try writer.writeRaw(zero32[0..]);
        }
        try writer.writeU32(self.schema_version);
        try writer.writeString(self.app_version);
        try writer.writeU64(self.capabilities.bits);
        try writer.writeU8(@as(u8, @intFromEnum(self.cdp_tier)));
        try writer.writeString(self.locale);
        try writer.writeString(self.residency_zone);
        try writer.writeU8(@as(u8, @intFromEnum(self.encoding)));
        try writer.writeU32(self.snapshot_seq orelse 0);
        if (self.snapshot_hash) |hash| {
            try writer.writeRaw(hash[0..]);
        } else {
            try writer.writeRaw(zero32[0..]);
        }
        try writer.writeByteArray(self.plugin_opcodes);
        return writer.written();
    }
};

pub const HelloView = struct {
    proto_version: u16,
    session_id: u64,
    jwt: []const u8,
    jwt_binding_hash: ?[32]u8,
    schema_version: u32,
    app_version: []const u8,
    capabilities: protocol.Capabilities,
    cdp_tier: protocol.CdpTier,
    locale: []const u8,
    residency_zone: []const u8,
    encoding: protocol.Encoding,
    snapshot_seq: ?u32,
    snapshot_hash: ?[32]u8,
    plugin_opcodes: []const u8,

    pub fn validate(self: HelloView) !void {
        if (self.proto_version == 0) return error.MalformedFrame;
        if (self.jwt.len == 0) return error.MissingJwt;
        if (self.cdp_tier == .reserved) return error.MalformedFrame;
        if (self.cdp_tier == .full_or_enterprise and self.jwt_binding_hash == null) {
            return error.ChannelBindingRequired;
        }
        if (self.snapshot_seq != null and self.snapshot_hash == null) return error.SnapshotHashInvalid;
        if (self.snapshot_seq == null and self.snapshot_hash != null) return error.SnapshotHashInvalid;
    }
};

pub fn decodeHello(body: []const u8) !HelloView {
    var cursor = codec.Cursor.init(body);
    const proto_version = try cursor.readU16();
    const session_id = try cursor.readU64();
    const jwt = try cursor.readString();
    const raw_binding = try cursor.readBytes(32);
    const jwt_binding_hash: ?[32]u8 = if (allZero(raw_binding)) null else copy32(raw_binding);
    const schema_version = try cursor.readU32();
    const app_version = try cursor.readString();
    const capabilities = protocol.Capabilities.init(try cursor.readU64());
    const cdp_tier = try protocol.cdpTierFromByte(try cursor.readU8());
    const locale = try cursor.readString();
    const residency_zone = try cursor.readString();
    const encoding = try protocol.encodingFromByte(try cursor.readU8());
    const raw_snapshot_seq = try cursor.readU32();
    const raw_snapshot_hash = try cursor.readBytes(32);
    const plugin_opcodes = try cursor.readByteArray();

    for (plugin_opcodes) |opcode| {
        if (!opcodes.isPluginByte(opcode)) return error.PluginOpcodeInvalid;
    }
    if (cursor.remaining() != 0) return error.TrailingBytes;

    const snapshot_seq: ?u32 = if (raw_snapshot_seq == 0 and allZero(raw_snapshot_hash)) null else raw_snapshot_seq;
    const snapshot_hash: ?[32]u8 = if (raw_snapshot_seq == 0 and allZero(raw_snapshot_hash)) null else copy32(raw_snapshot_hash);

    const view = HelloView{
        .proto_version = proto_version,
        .session_id = session_id,
        .jwt = jwt,
        .jwt_binding_hash = jwt_binding_hash,
        .schema_version = schema_version,
        .app_version = app_version,
        .capabilities = capabilities,
        .cdp_tier = cdp_tier,
        .locale = locale,
        .residency_zone = residency_zone,
        .encoding = encoding,
        .snapshot_seq = snapshot_seq,
        .snapshot_hash = snapshot_hash,
        .plugin_opcodes = plugin_opcodes,
    };
    try view.validate();
    return view;
}

pub const Ping = struct {
    timestamp_us: u64,

    pub fn encodeInto(self: Ping, out: []u8) ![]u8 {
        if (out.len < 8) return error.NoSpaceLeft;
        try codec.writeU64BE(out[0..8], self.timestamp_us);
        return out[0..8];
    }

    pub fn decode(body: []const u8) !Ping {
        if (body.len != 8) return error.MalformedFrame;
        return .{ .timestamp_us = try codec.readU64BE(body[0..8]) };
    }
};

pub const Ack = struct {
    last_applied_seq: u32,

    pub fn encodeInto(self: Ack, out: []u8) ![]u8 {
        if (out.len < 4) return error.NoSpaceLeft;
        try codec.writeU32BE(out[0..4], self.last_applied_seq);
        return out[0..4];
    }

    pub fn decode(body: []const u8) !Ack {
        if (body.len != 4) return error.MalformedFrame;
        return .{ .last_applied_seq = try codec.readU32BE(body[0..4]) };
    }
};

pub const Event = struct {
    nonce: [16]u8,
    submitted_at_us: u64,
    payload: []const u8,

    pub fn bodyLen(self: Event) usize {
        return 16 + 8 + byteArrayLen(self.payload);
    }

    pub fn encodeInto(self: Event, out: []u8) ![]u8 {
        var writer = codec.Writer.init(out);
        try writer.writeRaw(self.nonce[0..]);
        try writer.writeU64(self.submitted_at_us);
        try writer.writeByteArray(self.payload);
        return writer.written();
    }

    pub fn decode(body: []const u8) !Event {
        var cursor = codec.Cursor.init(body);
        const nonce = copy16(try cursor.readBytes(16));
        const submitted_at_us = try cursor.readU64();
        const payload = try cursor.readByteArray();
        if (cursor.remaining() != 0) return error.TrailingBytes;
        return .{
            .nonce = nonce,
            .submitted_at_us = submitted_at_us,
            .payload = payload,
        };
    }
};

pub const ErrorFrame = struct {
    error_code: errors.ErrorCode,
    message: []const u8 = "",

    pub fn bodyLen(self: ErrorFrame) usize {
        return 2 + stringLen(self.message);
    }

    pub fn encodeInto(self: ErrorFrame, out: []u8) ![]u8 {
        var writer = codec.Writer.init(out);
        try writer.writeU16(@as(u16, @intFromEnum(self.error_code)));
        try writer.writeString(self.message);
        return writer.written();
    }

    pub fn decode(body: []const u8) !ErrorFrame {
        var cursor = codec.Cursor.init(body);
        const code_int = try cursor.readU16();
        const code = errors.fromInt(code_int) orelse return error.UnknownLnwpErrorCode;
        const message = try cursor.readString();
        if (cursor.remaining() != 0) return error.TrailingBytes;
        return .{ .error_code = code, .message = message };
    }
};

pub const Resume = struct {
    session_id: u64,
    last_seq: u32,

    pub fn encodeInto(self: Resume, out: []u8) ![]u8 {
        var writer = codec.Writer.init(out);
        try writer.writeU64(self.session_id);
        try writer.writeU32(self.last_seq);
        return writer.written();
    }

    pub fn decode(body: []const u8) !Resume {
        if (body.len != 12) return error.MalformedFrame;
        var cursor = codec.Cursor.init(body);
        return .{ .session_id = try cursor.readU64(), .last_seq = try cursor.readU32() };
    }
};

pub const ResumeFromSnapshot = struct {
    session_id: u64,
    snapshot_seq: u32,
    snapshot_hash: [32]u8,

    pub fn encodeInto(self: ResumeFromSnapshot, out: []u8) ![]u8 {
        var writer = codec.Writer.init(out);
        try writer.writeU64(self.session_id);
        try writer.writeU32(self.snapshot_seq);
        try writer.writeRaw(self.snapshot_hash[0..]);
        return writer.written();
    }

    pub fn decode(body: []const u8) !ResumeFromSnapshot {
        if (body.len != 44) return error.MalformedFrame;
        var cursor = codec.Cursor.init(body);
        return .{
            .session_id = try cursor.readU64(),
            .snapshot_seq = try cursor.readU32(),
            .snapshot_hash = copy32(try cursor.readBytes(32)),
        };
    }
};

pub fn batchPatchBodyLen(patches: []const []const u8) !usize {
    if (patches.len > 255) return error.TooManyPatches;
    var total: usize = 4 + 1;
    for (patches) |patch| {
        total += byteArrayLen(patch);
    }
    return total;
}

pub fn encodeBatchPatchBody(out: []u8, batch_seq: u32, patches: []const []const u8) ![]u8 {
    if (patches.len > 255) return error.TooManyPatches;
    var writer = codec.Writer.init(out);
    try writer.writeU32(batch_seq);
    try writer.writeU8(@as(u8, @intCast(patches.len)));
    for (patches) |patch| {
        try writer.writeByteArray(patch);
    }
    return writer.written();
}

pub const BatchPatchIterator = struct {
    batch_seq: u32,
    remaining: u8,
    cursor: codec.Cursor,

    pub fn init(body: []const u8) !BatchPatchIterator {
        var cursor = codec.Cursor.init(body);
        const batch_seq = try cursor.readU32();
        const count = try cursor.readU8();
        return .{ .batch_seq = batch_seq, .remaining = count, .cursor = cursor };
    }

    pub fn next(self: *BatchPatchIterator) !?[]const u8 {
        if (self.remaining == 0) return null;
        self.remaining -= 1;
        const patch = try self.cursor.readByteArray();
        return patch;
    }

    pub fn finish(self: BatchPatchIterator) !void {
        if (self.remaining != 0) return error.MalformedFrame;
        if (self.cursor.remaining() != 0) return error.TrailingBytes;
    }
};

pub fn viewportHintBodyLen(visible: []const u32, tier1: []const u32, tier2: []const u32, include_tag: bool) !usize {
    const visible_len = try nodeSetLen(visible);
    const tier1_len = try nodeSetLen(tier1);
    const tier2_len = try nodeSetLen(tier2);
    const base = visible_len + tier1_len + tier2_len;
    const tag_len: usize = if (include_tag) protocol.viewport_hmac_len else 0;
    return base + tag_len;
}

pub fn encodeViewportHintBody(
    out: []u8,
    visible: []const u32,
    tier1: []const u32,
    tier2: []const u32,
    tag: ?[protocol.viewport_hmac_len]u8,
) ![]u8 {
    var writer = codec.Writer.init(out);
    try writeNodeSet(&writer, visible);
    try writeNodeSet(&writer, tier1);
    try writeNodeSet(&writer, tier2);
    if (tag) |hmac| try writer.writeRaw(hmac[0..]);
    return writer.written();
}

pub const ViewportHintView = struct {
    visible: []const u8,
    tier1: []const u8,
    tier2: []const u8,
    tag: ?[protocol.viewport_hmac_len]u8,
};

pub fn decodeViewportHintBody(body: []const u8) !ViewportHintView {
    var cursor = codec.Cursor.init(body);
    const visible = try readNodeSetBytes(&cursor);
    const tier1 = try readNodeSetBytes(&cursor);
    const tier2 = try readNodeSetBytes(&cursor);
    const tag: ?[protocol.viewport_hmac_len]u8 = if (cursor.remaining() == protocol.viewport_hmac_len) blk: {
        var out: [protocol.viewport_hmac_len]u8 = undefined;
        @memcpy(out[0..], (try cursor.readBytes(protocol.viewport_hmac_len))[0..]);
        break :blk out;
    } else null;
    if (cursor.remaining() != 0) return error.TrailingBytes;
    return .{ .visible = visible, .tier1 = tier1, .tier2 = tier2, .tag = tag };
}

fn stringLen(bytes: []const u8) usize {
    return 2 + bytes.len;
}

fn byteArrayLen(bytes: []const u8) usize {
    return 4 + bytes.len;
}

fn nodeSetLen(nodes: []const u32) !usize {
    if (nodes.len > std.math.maxInt(u16)) return error.NodeSetTooLarge;
    return 2 + nodes.len * 4;
}

fn writeNodeSet(writer: *codec.Writer, nodes: []const u32) !void {
    if (nodes.len > std.math.maxInt(u16)) return error.NodeSetTooLarge;
    try writer.writeU16(@as(u16, @intCast(nodes.len)));
    for (nodes) |node_id| {
        try writer.writeU32(node_id);
    }
}

fn readNodeSetBytes(cursor: *codec.Cursor) ![]const u8 {
    const count = try cursor.readU16();
    return cursor.readBytes(@as(usize, count) * 4);
}

test "hello body roundtrips required and optional fields" {
    var caps = protocol.Capabilities.empty();
    caps.set(.batch_capable, true);
    caps.set(.integrity_capable, true);

    const binding = [_]u8{7} ** 32;
    const snapshot = [_]u8{9} ** 32;
    const hello = Hello{
        .jwt = "signed.jwt",
        .jwt_binding_hash = binding,
        .schema_version = 42,
        .app_version = "1.2.3",
        .capabilities = caps,
        .locale = "en-IN",
        .residency_zone = "in-delhi",
        .snapshot_seq = 10,
        .snapshot_hash = snapshot,
        .plugin_opcodes = &[_]u8{ 0xF0, 0xFE },
    };

    var buf: [512]u8 = undefined;
    const encoded = try hello.encodeInto(buf[0..]);
    const decoded = try decodeHello(encoded);

    try std.testing.expectEqual(protocol.version_5_0, decoded.proto_version);
    try std.testing.expectEqualSlices(u8, "signed.jwt", decoded.jwt);
    try std.testing.expect(decoded.capabilities.has(.batch_capable));
    try std.testing.expect(decoded.capabilities.has(.integrity_capable));
    try std.testing.expect(decoded.snapshot_seq != null);
    try std.testing.expectEqual(@as(u32, 10), decoded.snapshot_seq.?);
    const decoded_snapshot = decoded.snapshot_hash.?;
    try std.testing.expectEqualSlices(u8, snapshot[0..], decoded_snapshot[0..]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xF0, 0xFE }, decoded.plugin_opcodes);
}

test "hello requires channel binding for full enterprise tier" {
    const hello = Hello{ .jwt = "signed.jwt" };
    var buf: [256]u8 = undefined;
    try std.testing.expectError(error.ChannelBindingRequired, hello.encodeInto(buf[0..]));
}

test "ping ack event and error frames roundtrip" {
    var buf: [128]u8 = undefined;

    const ping_body = try (Ping{ .timestamp_us = 99 }).encodeInto(buf[0..]);
    try std.testing.expectEqual(@as(u64, 99), (try Ping.decode(ping_body)).timestamp_us);

    const ack_body = try (Ack{ .last_applied_seq = 12 }).encodeInto(buf[0..]);
    try std.testing.expectEqual(@as(u32, 12), (try Ack.decode(ack_body)).last_applied_seq);

    const event = Event{ .nonce = [_]u8{1} ** 16, .submitted_at_us = 1000, .payload = "tap" };
    const event_body = try event.encodeInto(buf[0..]);
    const decoded_event = try Event.decode(event_body);
    try std.testing.expectEqualSlices(u8, "tap", decoded_event.payload);

    const err = ErrorFrame{ .error_code = .frame_too_large, .message = "too large" };
    const err_body = try err.encodeInto(buf[0..]);
    const decoded_err = try ErrorFrame.decode(err_body);
    try std.testing.expectEqual(errors.ErrorCode.frame_too_large, decoded_err.error_code);
}

test "batch patch iterator exposes patch slices" {
    var buf: [64]u8 = undefined;
    const patches = [_][]const u8{ "a", "bc" };
    const body = try encodeBatchPatchBody(buf[0..], 5, patches[0..]);
    var iter = try BatchPatchIterator.init(body);
    try std.testing.expectEqual(@as(u32, 5), iter.batch_seq);
    try std.testing.expectEqualSlices(u8, "a", (try iter.next()).?);
    try std.testing.expectEqualSlices(u8, "bc", (try iter.next()).?);
    try std.testing.expect((try iter.next()) == null);
    try iter.finish();
}
