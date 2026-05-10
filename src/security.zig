const std = @import("std");
const codec = @import("codec.zig");
const opcodes = @import("opcodes.zig");
const protocol = @import("protocol.zig");

const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

pub fn hmacSha256(key: []const u8, data: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    HmacSha256.create(&out, data, key);
    return out;
}

pub fn constantTimeEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var diff: u8 = 0;
    for (a, b) |left, right| {
        diff |= left ^ right;
    }
    return diff == 0;
}

pub fn batchPatchMacHmacSha256(session_mac_key: []const u8, batch_seq: u32, batch_payload_without_seq_or_tag: []const u8) [32]u8 {
    var seq: [4]u8 = undefined;
    codec.writeU32BE(seq[0..], batch_seq) catch unreachable;

    var out: [32]u8 = undefined;
    var mac = HmacSha256.init(session_mac_key);
    const opcode = [_]u8{@as(u8, @intFromEnum(opcodes.Opcode.batch_patch))};
    mac.update(opcode[0..]);
    mac.update(seq[0..]);
    mac.update(batch_payload_without_seq_or_tag);
    mac.final(&out);
    return out;
}

pub fn batchPatchMacForEncodedBody(session_mac_key: []const u8, encoded_body_without_tag: []const u8) ![32]u8 {
    if (encoded_body_without_tag.len < 4) return error.MalformedFrame;
    const batch_seq = try codec.readU32BE(encoded_body_without_tag[0..4]);
    return batchPatchMacHmacSha256(session_mac_key, batch_seq, encoded_body_without_tag[4..]);
}

pub fn verifyBatchPatchHmac(session_mac_key: []const u8, batch_seq: u32, payload_without_seq_or_tag: []const u8, expected: []const u8) bool {
    const actual = batchPatchMacHmacSha256(session_mac_key, batch_seq, payload_without_seq_or_tag);
    return constantTimeEqual(actual[0..], expected);
}

pub fn verifyBatchPatchHmacForEncodedBody(session_mac_key: []const u8, encoded_body_without_tag: []const u8, expected: []const u8) bool {
    const actual = batchPatchMacForEncodedBody(session_mac_key, encoded_body_without_tag) catch return false;
    return constantTimeEqual(actual[0..], expected);
}

pub fn snapshotHash(session_mac_key: []const u8, snapshot_seq: u32, tree_root_fingerprint: u64) [32]u8 {
    var data: [12]u8 = undefined;
    codec.writeU32BE(data[0..4], snapshot_seq) catch unreachable;
    codec.writeU64BE(data[4..12], tree_root_fingerprint) catch unreachable;
    return hmacSha256(session_mac_key, data[0..]);
}

pub fn viewportHintTag(session_mac_key: []const u8, viewport_body_without_tag: []const u8) [protocol.viewport_hmac_len]u8 {
    const full = hmacSha256(session_mac_key, viewport_body_without_tag);
    var out: [protocol.viewport_hmac_len]u8 = undefined;
    @memcpy(out[0..], full[0..protocol.viewport_hmac_len]);
    return out;
}

pub fn secureZero(bytes: []u8) void {
    std.crypto.utils.secureZero(u8, bytes);
}

test "constant-time compare reports equality without early result differences" {
    const a = [_]u8{ 1, 2, 3, 4 };
    const b = [_]u8{ 1, 2, 3, 4 };
    const c = [_]u8{ 1, 2, 3, 5 };
    try std.testing.expect(constantTimeEqual(a[0..], b[0..]));
    try std.testing.expect(!constantTimeEqual(a[0..], c[0..]));
    try std.testing.expect(!constantTimeEqual(a[0..], c[0..3]));
}

test "snapshot hash is stable for identical inputs" {
    const first = snapshotHash("key", 7, 0x0102030405060708);
    const second = snapshotHash("key", 7, 0x0102030405060708);
    try std.testing.expectEqualSlices(u8, first[0..], second[0..]);
}
