const std = @import("std");

pub const free_type_tag: u16 = 0xFFFF;
pub const listed_node_wire_size: usize = 30;
pub const spec_claimed_node_size: usize = 28;

pub const Node = packed struct {
    id: u32,
    type_tag: u16,
    parent_idx: u32,
    first_child: u32,
    next_sibling: u32,
    attr_offset: u32,
    fingerprint: u64,

    pub fn free() Node {
        return .{
            .id = 0,
            .type_tag = free_type_tag,
            .parent_idx = 0,
            .first_child = 0,
            .next_sibling = 0,
            .attr_offset = 0,
            .fingerprint = 0,
        };
    }

    pub fn isFree(self: Node) bool {
        return self.type_tag == free_type_tag;
    }
};

pub const Arena = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    attrs: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Arena {
        return .{
            .allocator = allocator,
            .nodes = .empty,
            .attrs = .empty,
        };
    }

    pub fn deinit(self: *Arena) void {
        self.nodes.deinit(self.allocator);
        self.attrs.deinit(self.allocator);
    }

    pub fn addAttrs(self: *Arena, bytes: []const u8) !u32 {
        const offset = self.attrs.items.len;
        if (offset > std.math.maxInt(u32)) return error.ArenaTooLarge;
        try self.attrs.appendSlice(self.allocator, bytes);
        return @as(u32, @intCast(offset));
    }

    pub fn addNode(self: *Arena, node: Node) !u32 {
        const index = self.nodes.items.len;
        if (index > std.math.maxInt(u32)) return error.ArenaTooLarge;
        try self.nodes.append(self.allocator, node);
        return @as(u32, @intCast(index));
    }

    pub fn markFree(self: *Arena, index: u32) !void {
        const idx = @as(usize, index);
        if (idx >= self.nodes.items.len) return error.NodeNotFound;
        self.nodes.items[idx] = Node.free();
    }
};

test "listed arena node fields occupy 30 bytes, despite spec note claiming 28" {
    try std.testing.expectEqual(@as(usize, listed_node_wire_size), @divExact(@bitSizeOf(Node), 8));
    try std.testing.expectEqual(@as(usize, 30), listed_node_wire_size);
}

test "arena stores nodes and attrs" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();

    const attr_offset = try arena.addAttrs("role=button");
    const index = try arena.addNode(.{
        .id = 1,
        .type_tag = 2,
        .parent_idx = 0,
        .first_child = 0,
        .next_sibling = 0,
        .attr_offset = attr_offset,
        .fingerprint = 0xABCD,
    });
    try std.testing.expectEqual(@as(u32, 0), index);
    try arena.markFree(index);
    try std.testing.expect(arena.nodes.items[@as(usize, index)].isFree());
}
