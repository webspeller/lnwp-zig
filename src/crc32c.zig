const std = @import("std");

const polynomial_reversed: u32 = 0x82F6_3B78;

pub fn checksum(bytes: []const u8) u32 {
    var crc: u32 = 0xFFFF_FFFF;
    for (bytes) |byte| {
        crc ^= @as(u32, byte);
        for (0..8) |_| {
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ polynomial_reversed;
            } else {
                crc >>= 1;
            }
        }
    }
    return ~crc;
}

pub fn verify(bytes: []const u8, expected: u32) bool {
    return checksum(bytes) == expected;
}

test "crc32c check value" {
    try std.testing.expectEqual(@as(u32, 0xE306_9283), checksum("123456789"));
}
