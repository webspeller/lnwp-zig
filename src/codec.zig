const std = @import("std");

pub const Cursor = struct {
    data: []const u8,
    index: usize = 0,

    pub fn init(data: []const u8) Cursor {
        return .{ .data = data };
    }

    pub fn remaining(self: Cursor) usize {
        return self.data.len - self.index;
    }

    pub fn readU8(self: *Cursor) !u8 {
        const bytes = try self.readBytes(1);
        return bytes[0];
    }

    pub fn readU16(self: *Cursor) !u16 {
        const bytes = try self.readBytes(2);
        return readU16BE(bytes);
    }

    pub fn readU32(self: *Cursor) !u32 {
        const bytes = try self.readBytes(4);
        return readU32BE(bytes);
    }

    pub fn readU64(self: *Cursor) !u64 {
        const bytes = try self.readBytes(8);
        return readU64BE(bytes);
    }

    pub fn readBool(self: *Cursor) !bool {
        return (try self.readU8()) != 0;
    }

    pub fn readBytes(self: *Cursor, len: usize) ![]const u8 {
        if (self.remaining() < len) return error.EndOfStream;
        const start = self.index;
        self.index += len;
        return self.data[start..self.index];
    }

    pub fn readString(self: *Cursor) ![]const u8 {
        const len = try self.readU16();
        const bytes = try self.readBytes(len);
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
        return bytes;
    }

    pub fn readByteArray(self: *Cursor) ![]const u8 {
        const len = try self.readU32();
        return self.readBytes(len);
    }
};

pub const Writer = struct {
    out: []u8,
    index: usize = 0,

    pub fn init(out: []u8) Writer {
        return .{ .out = out };
    }

    pub fn written(self: Writer) []u8 {
        return self.out[0..self.index];
    }

    pub fn remaining(self: Writer) usize {
        return self.out.len - self.index;
    }

    fn reserve(self: *Writer, len: usize) ![]u8 {
        if (self.remaining() < len) return error.NoSpaceLeft;
        const start = self.index;
        self.index += len;
        return self.out[start..self.index];
    }

    pub fn writeU8(self: *Writer, value: u8) !void {
        const bytes = try self.reserve(1);
        bytes[0] = value;
    }

    pub fn writeU16(self: *Writer, value: u16) !void {
        const bytes = try self.reserve(2);
        writeU16BE(bytes, value) catch unreachable;
    }

    pub fn writeU32(self: *Writer, value: u32) !void {
        const bytes = try self.reserve(4);
        writeU32BE(bytes, value) catch unreachable;
    }

    pub fn writeU64(self: *Writer, value: u64) !void {
        const bytes = try self.reserve(8);
        writeU64BE(bytes, value) catch unreachable;
    }

    pub fn writeBool(self: *Writer, value: bool) !void {
        try self.writeU8(if (value) 1 else 0);
    }

    pub fn writeRaw(self: *Writer, bytes: []const u8) !void {
        const dst = try self.reserve(bytes.len);
        @memcpy(dst, bytes);
    }

    pub fn writeString(self: *Writer, bytes: []const u8) !void {
        if (bytes.len > std.math.maxInt(u16)) return error.StringTooLong;
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
        try self.writeU16(@as(u16, @intCast(bytes.len)));
        try self.writeRaw(bytes);
    }

    pub fn writeByteArray(self: *Writer, bytes: []const u8) !void {
        if (bytes.len > std.math.maxInt(u32)) return error.ByteArrayTooLong;
        try self.writeU32(@as(u32, @intCast(bytes.len)));
        try self.writeRaw(bytes);
    }
};

pub fn readU16BE(bytes: []const u8) !u16 {
    if (bytes.len < 2) return error.EndOfStream;
    return (@as(u16, bytes[0]) << 8) | @as(u16, bytes[1]);
}

pub fn readU32BE(bytes: []const u8) !u32 {
    if (bytes.len < 4) return error.EndOfStream;
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

pub fn readU64BE(bytes: []const u8) !u64 {
    if (bytes.len < 8) return error.EndOfStream;
    var out: u64 = 0;
    for (bytes[0..8]) |byte| {
        out = (out << 8) | @as(u64, byte);
    }
    return out;
}

pub fn writeU16BE(out: []u8, value: u16) !void {
    if (out.len < 2) return error.NoSpaceLeft;
    out[0] = @as(u8, @intCast(value >> 8));
    out[1] = @as(u8, @intCast(value & 0xFF));
}

pub fn writeU32BE(out: []u8, value: u32) !void {
    if (out.len < 4) return error.NoSpaceLeft;
    out[0] = @as(u8, @intCast((value >> 24) & 0xFF));
    out[1] = @as(u8, @intCast((value >> 16) & 0xFF));
    out[2] = @as(u8, @intCast((value >> 8) & 0xFF));
    out[3] = @as(u8, @intCast(value & 0xFF));
}

pub fn writeU64BE(out: []u8, value: u64) !void {
    if (out.len < 8) return error.NoSpaceLeft;
    out[0] = @as(u8, @intCast((value >> 56) & 0xFF));
    out[1] = @as(u8, @intCast((value >> 48) & 0xFF));
    out[2] = @as(u8, @intCast((value >> 40) & 0xFF));
    out[3] = @as(u8, @intCast((value >> 32) & 0xFF));
    out[4] = @as(u8, @intCast((value >> 24) & 0xFF));
    out[5] = @as(u8, @intCast((value >> 16) & 0xFF));
    out[6] = @as(u8, @intCast((value >> 8) & 0xFF));
    out[7] = @as(u8, @intCast(value & 0xFF));
}

pub fn encodeUleb128(out: []u8, value: u64) !usize {
    var v = value;
    var i: usize = 0;
    while (true) {
        if (i >= out.len) return error.NoSpaceLeft;
        var byte = @as(u8, @intCast(v & 0x7F));
        v >>= 7;
        if (v != 0) byte |= 0x80;
        out[i] = byte;
        i += 1;
        if (v == 0) return i;
    }
}

pub fn decodeUleb128(cursor: *Cursor) !u64 {
    var result: u64 = 0;
    var shift: usize = 0;
    for (0..10) |_| {
        const byte = try cursor.readU8();
        const low = byte & 0x7F;
        if (shift == 63 and low > 1) return error.VarintOverflow;
        result |= @as(u64, low) << @as(u6, @intCast(shift));
        if ((byte & 0x80) == 0) return result;
        shift += 7;
        if (shift > 63) return error.VarintOverflow;
    }
    return error.VarintOverflow;
}

pub fn zigZagEncode(value: i64) u64 {
    if (value >= 0) return @as(u64, @intCast(value)) << 1;
    return (@as(u64, @intCast(-(value + 1))) << 1) | 1;
}

pub fn zigZagDecode(value: u64) i64 {
    const magnitude = value >> 1;
    if ((value & 1) == 0) return @as(i64, @intCast(magnitude));
    return -(@as(i64, @intCast(magnitude))) - 1;
}

test "fixed width integers are big-endian" {
    var buf: [8]u8 = undefined;
    try writeU16BE(buf[0..2], 0xABCD);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xAB, 0xCD }, buf[0..2]);
    try writeU32BE(buf[0..4], 0x01020304);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4 }, buf[0..4]);
    try writeU64BE(buf[0..8], 0x0102030405060708);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 }, buf[0..8]);
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), try readU64BE(buf[0..8]));
}

test "strings validate utf8 and use u16 length" {
    var buf: [16]u8 = undefined;
    var writer = Writer.init(buf[0..]);
    try writer.writeString("en-IN");

    var cursor = Cursor.init(writer.written());
    try std.testing.expectEqualSlices(u8, "en-IN", try cursor.readString());
    try std.testing.expectEqual(@as(usize, 0), cursor.remaining());
}

test "uleb128 and zigzag roundtrip" {
    var buf: [10]u8 = undefined;
    const values = [_]u64{ 0, 1, 127, 128, 16_384, std.math.maxInt(u64) };
    for (values) |value| {
        const len = try encodeUleb128(buf[0..], value);
        var cursor = Cursor.init(buf[0..len]);
        try std.testing.expectEqual(value, try decodeUleb128(&cursor));
    }

    const signed = [_]i64{ -9, -1, 0, 1, 42, std.math.minInt(i64), std.math.maxInt(i64) };
    for (signed) |value| {
        try std.testing.expectEqual(value, zigZagDecode(zigZagEncode(value)));
    }
}
