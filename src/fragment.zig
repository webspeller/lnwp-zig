const std = @import("std");
const codec = @import("codec.zig");
const frame = @import("frame.zig");
const opcodes = @import("opcodes.zig");

pub const body_header_len: usize = 10;
pub const max_chunk_len: usize = frame.max_body_len - body_header_len;

pub const Fragment = struct {
    original_opcode: u8,
    original_flags: frame.Flags,
    original_length: u32,
    fragment_index: u16,
    total_fragments: u16,
    chunk: []const u8,
};

pub fn fragmentCount(body_len: usize) !u16 {
    if (body_len <= frame.max_body_len) return 1;
    const count = (body_len + max_chunk_len - 1) / max_chunk_len;
    if (count > std.math.maxInt(u16)) return error.FrameTooLarge;
    return @as(u16, @intCast(count));
}

pub fn encodeBody(out: []u8, frag: Fragment) ![]u8 {
    if (frag.total_fragments == 0) return error.MalformedFrame;
    if (frag.fragment_index >= frag.total_fragments) return error.MalformedFrame;
    if (frag.chunk.len > max_chunk_len) return error.FrameTooLarge;

    _ = try opcodes.fromWireByte(frag.original_opcode);
    var writer = codec.Writer.init(out);
    try writer.writeU8(frag.original_opcode);
    try writer.writeU8(frag.original_flags.toByte());
    try writer.writeU32(frag.original_length);
    try writer.writeU16(frag.fragment_index);
    try writer.writeU16(frag.total_fragments);
    try writer.writeRaw(frag.chunk);
    return writer.written();
}

pub fn decodeBody(body: []const u8) !Fragment {
    var cursor = codec.Cursor.init(body);
    const original_opcode = try cursor.readU8();
    _ = try opcodes.fromWireByte(original_opcode);
    const original_flags = try frame.Flags.fromByte(try cursor.readU8());
    const original_length = try cursor.readU32();
    const fragment_index = try cursor.readU16();
    const total_fragments = try cursor.readU16();
    const chunk = try cursor.readBytes(cursor.remaining());
    if (total_fragments == 0) return error.MalformedFrame;
    if (fragment_index >= total_fragments) return error.MalformedFrame;
    return .{
        .original_opcode = original_opcode,
        .original_flags = original_flags,
        .original_length = original_length,
        .fragment_index = fragment_index,
        .total_fragments = total_fragments,
        .chunk = chunk,
    };
}

test "fragment body carries indexes and original frame metadata" {
    var buf: [64]u8 = undefined;
    const encoded = try encodeBody(buf[0..], .{
        .original_opcode = @as(u8, @intFromEnum(opcodes.Opcode.patch)),
        .original_flags = .{ .mac_present = true },
        .original_length = 70_000,
        .fragment_index = 1,
        .total_fragments = 2,
        .chunk = "part",
    });

    const decoded = try decodeBody(encoded);
    try std.testing.expectEqual(@as(u8, 0x03), decoded.original_opcode);
    try std.testing.expect(decoded.original_flags.mac_present);
    try std.testing.expectEqual(@as(u32, 70_000), decoded.original_length);
    try std.testing.expectEqual(@as(u16, 1), decoded.fragment_index);
    try std.testing.expectEqualSlices(u8, "part", decoded.chunk);
}
