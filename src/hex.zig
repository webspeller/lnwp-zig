const std = @import("std");

pub fn decodedLen(hex: []const u8) !usize {
    if ((hex.len % 2) != 0) return error.InvalidHex;
    return hex.len / 2;
}

pub fn encodedLen(bytes: []const u8) usize {
    return bytes.len * 2;
}

pub fn decodeInto(out: []u8, hex: []const u8) ![]u8 {
    const len = try decodedLen(hex);
    if (out.len < len) return error.NoSpaceLeft;
    for (out[0..len], 0..) |*byte, i| {
        const high = try nibble(hex[i * 2]);
        const low = try nibble(hex[i * 2 + 1]);
        byte.* = (high << 4) | low;
    }
    return out[0..len];
}

pub fn decodeAlloc(allocator: std.mem.Allocator, hex: []const u8) ![]u8 {
    const len = try decodedLen(hex);
    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);
    _ = try decodeInto(out, hex);
    return out;
}

pub fn encodeInto(out: []u8, bytes: []const u8) ![]u8 {
    const len = encodedLen(bytes);
    if (out.len < len) return error.NoSpaceLeft;
    for (bytes, 0..) |byte, i| {
        out[i * 2] = digit(byte >> 4);
        out[i * 2 + 1] = digit(byte & 0x0F);
    }
    return out[0..len];
}

pub fn encodeAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, encodedLen(bytes));
    errdefer allocator.free(out);
    _ = try encodeInto(out, bytes);
    return out;
}

fn digit(value: u8) u8 {
    return switch (value) {
        0...9 => '0' + value,
        10...15 => 'a' + (value - 10),
        else => unreachable,
    };
}

fn nibble(byte: u8) !u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => error.InvalidHex,
    };
}

test "hex encode and decode roundtrip" {
    var decoded_buf: [4]u8 = undefined;
    const decoded = try decodeInto(decoded_buf[0..], "0A0bff10");
    try std.testing.expectEqualSlices(u8, &.{ 0x0A, 0x0B, 0xFF, 0x10 }, decoded);

    var encoded_buf: [8]u8 = undefined;
    const encoded = try encodeInto(encoded_buf[0..], decoded);
    try std.testing.expectEqualSlices(u8, "0a0bff10", encoded);
}
