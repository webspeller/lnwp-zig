const std = @import("std");
const lnwp = @import("lnwp");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    if (args.len < 2) {
        try usage(stdout);
        return;
    }

    if (std.mem.eql(u8, args[1], "opcodes")) {
        try printOpcodes(stdout);
    } else if (std.mem.eql(u8, args[1], "decode-hex")) {
        if (args.len < 3) return error.MissingHexFrame;
        try decodeHexFrame(stdout, allocator, args[2]);
    } else {
        try usage(stdout);
        return error.UnknownCommand;
    }
}

fn usage(writer: anytype) !void {
    try writer.writeAll(
        \\lnwp-inspect commands:
        \\  opcodes
        \\  decode-hex <hex-frame>
        \\
    );
}

fn printOpcodes(writer: anytype) !void {
    inline for (@typeInfo(lnwp.opcodes.Opcode).@"enum".fields) |field| {
        const opcode: lnwp.opcodes.Opcode = @enumFromInt(field.value);
        try writer.print("0x{X:0>2} {s} {s} {s}\n", .{
            field.value,
            field.name,
            @tagName(lnwp.opcodes.direction(opcode)),
            @tagName(lnwp.opcodes.priority(opcode)),
        });
    }
    try writer.writeAll("0xF0-0xFE plugin both varies\n");
}

fn decodeHexFrame(writer: anytype, allocator: std.mem.Allocator, hex: []const u8) !void {
    const bytes = try lnwp.hex.decodeAlloc(allocator, hex);
    defer allocator.free(bytes);

    const decoded = try lnwp.frame.decodeExact(bytes);
    const opcode = try decoded.opcode();
    try writer.print("opcode=0x{X:0>2} ({s}) flags=0x{X:0>2} length={d}\n", .{
        decoded.header.opcode_byte,
        lnwp.opcodes.tagName(opcode),
        decoded.header.flags.toByte(),
        decoded.header.length,
    });
}
