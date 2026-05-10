const std = @import("std");
const codec = @import("codec.zig");
const opcodes = @import("opcodes.zig");
const protocol = @import("protocol.zig");

pub const header_len = protocol.header_len_v5;
pub const max_body_len = protocol.max_body_len;

pub const Flags = struct {
    zc_flag: bool = false,
    a11y_present: bool = false,
    spr_delta: bool = false,
    mac_present: bool = false,
    padded: bool = false,

    pub const zc_mask: u8 = 0b1000_0000;
    pub const a11y_mask: u8 = 0b0100_0000;
    pub const spr_mask: u8 = 0b0010_0000;
    pub const mac_mask: u8 = 0b0001_0000;
    pub const padded_mask: u8 = 0b0000_1000;
    pub const reserved_mask: u8 = 0b0000_0111;

    pub fn fromByte(value: u8) !Flags {
        if ((value & reserved_mask) != 0) return error.ReservedFlagSet;
        return .{
            .zc_flag = (value & zc_mask) != 0,
            .a11y_present = (value & a11y_mask) != 0,
            .spr_delta = (value & spr_mask) != 0,
            .mac_present = (value & mac_mask) != 0,
            .padded = (value & padded_mask) != 0,
        };
    }

    pub fn toByte(self: Flags) u8 {
        var out: u8 = 0;
        if (self.zc_flag) out |= zc_mask;
        if (self.a11y_present) out |= a11y_mask;
        if (self.spr_delta) out |= spr_mask;
        if (self.mac_present) out |= mac_mask;
        if (self.padded) out |= padded_mask;
        return out;
    }
};

pub const Header = struct {
    opcode_byte: u8,
    flags: Flags,
    length: u16,

    pub fn decode(bytes: []const u8) !Header {
        if (bytes.len < header_len) return error.IncompleteHeader;
        _ = try opcodes.fromWireByte(bytes[0]);
        return .{
            .opcode_byte = bytes[0],
            .flags = try Flags.fromByte(bytes[1]),
            .length = try codec.readU16BE(bytes[2..4]),
        };
    }

    pub fn opcode(self: Header) !opcodes.Parsed {
        return opcodes.fromWireByte(self.opcode_byte);
    }

    pub fn encode(self: Header, out: []u8) !void {
        if (out.len < header_len) return error.NoSpaceLeft;
        _ = try opcodes.fromWireByte(self.opcode_byte);
        out[0] = self.opcode_byte;
        out[1] = self.flags.toByte();
        try codec.writeU16BE(out[2..4], self.length);
    }
};

pub const DecodedFrame = struct {
    header: Header,
    body: []const u8,
    consumed: usize,

    pub fn opcode(self: DecodedFrame) !opcodes.Parsed {
        return self.header.opcode();
    }
};

pub fn encodedLen(body_len: usize) !usize {
    if (body_len > max_body_len) return error.FrameTooLarge;
    return header_len + body_len;
}

pub fn encodeInto(out: []u8, opcode: opcodes.Parsed, flags: Flags, body: []const u8) ![]u8 {
    const total = try encodedLen(body.len);
    if (out.len < total) return error.NoSpaceLeft;

    const opcode_byte = opcodes.toByte(opcode);
    _ = try opcodes.fromWireByte(opcode_byte);

    const header = Header{
        .opcode_byte = opcode_byte,
        .flags = flags,
        .length = @as(u16, @intCast(body.len)),
    };
    try header.encode(out[0..header_len]);
    @memcpy(out[header_len..total], body);
    return out[0..total];
}

pub fn decodeOne(bytes: []const u8) !DecodedFrame {
    const header = try Header.decode(bytes);
    const total = header_len + @as(usize, header.length);
    if (bytes.len < total) return error.IncompleteFrame;
    return .{
        .header = header,
        .body = bytes[header_len..total],
        .consumed = total,
    };
}

pub fn decodeExact(bytes: []const u8) !DecodedFrame {
    const decoded = try decodeOne(bytes);
    if (decoded.consumed != bytes.len) return error.TrailingBytes;
    return decoded;
}

pub fn validateBodyLengthForSingleFrame(body_len: usize) !void {
    if (body_len > max_body_len) return error.FrameTooLarge;
}

test "frame header is opcode flags u16be length" {
    const body = "abc";
    var buf: [header_len + body.len]u8 = undefined;
    const encoded = try encodeInto(
        buf[0..],
        .{ .standard = .ping },
        .{ .zc_flag = true, .mac_present = true },
        body,
    );

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x06, 0x90, 0x00, 0x03 }, encoded[0..4]);
    const decoded = try decodeExact(encoded);
    try std.testing.expectEqual(@as(u8, 0x06), decoded.header.opcode_byte);
    try std.testing.expect(decoded.header.flags.zc_flag);
    try std.testing.expect(decoded.header.flags.mac_present);
    try std.testing.expectEqualSlices(u8, body, decoded.body);
}

test "reserved flags and reserved opcodes are rejected" {
    try std.testing.expectError(error.ReservedFlagSet, Flags.fromByte(0b0000_0001));
    try std.testing.expectError(error.ReservedOpcode, Header.decode(&[_]u8{ 0xFF, 0, 0, 0 }));
    try std.testing.expectError(error.LocalOpcodeNotTransmitted, Header.decode(&[_]u8{ 0x25, 0, 0, 0 }));
}

test "plugin opcodes are encodable over the wire" {
    var buf: [4]u8 = undefined;
    const encoded = try encodeInto(buf[0..], .{ .plugin = 0xF0 }, .{}, "");
    const decoded = try decodeExact(encoded);
    const opcode = try decoded.opcode();
    switch (opcode) {
        .standard => return error.TestExpectedPluginOpcode,
        .plugin => |value| try std.testing.expectEqual(@as(u8, 0xF0), value),
    }
}
