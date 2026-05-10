const std = @import("std");
const lnwp = @import("lnwp");

const max_body_len: usize = 1024 * 1024;
const openapi_json = @embedFile("openapi.json");

const DecodeFrameRequest = struct {
    hex: []const u8,
};

const EncodeFrameRequest = struct {
    opcode: []const u8,
    flags: ?u8 = null,
    body_hex: ?[]const u8 = null,
};

const HexRequest = struct {
    hex: []const u8,
};

const SnapshotHashRequest = struct {
    key_hex: []const u8,
    snapshot_seq: u32,
    tree_root_fingerprint_hex: []const u8,
};

const BatchMacRequest = struct {
    key_hex: []const u8,
    batch_seq: u32,
    payload_hex: []const u8,
};

const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    body: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var host: []const u8 = "127.0.0.1";
    var port: u16 = 8080;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--host")) {
            i += 1;
            if (i >= args.len) return error.MissingHost;
            host = args[i];
        } else if (std.mem.eql(u8, args[i], "--port")) {
            i += 1;
            if (i >= args.len) return error.MissingPort;
            port = try std.fmt.parseInt(u16, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--help")) {
            var stdout_buffer: [1024]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.writeAll("usage: lnwp-api [--host 127.0.0.1] [--port 8080]\n");
            try stdout.flush();
            return;
        } else {
            return error.UnknownArgument;
        }
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var address = try std.Io.net.IpAddress.parse(host, port);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    try stdout.print("lnwp-api listening on http://{s}:{d}\n", .{ host, port });
    try stdout.flush();

    while (true) {
        var stream = try server.accept(io);
        defer stream.close(io);
        handleConnection(io, allocator, stream) catch {};
    }
}

fn handleConnection(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream) !void {
    var read_buffer: [8192]u8 = undefined;
    var reader_state = stream.reader(io, &read_buffer);
    const reader = &reader_state.interface;

    var write_buffer: [8192]u8 = undefined;
    var writer_state = stream.writer(io, &write_buffer);
    const writer = &writer_state.interface;

    const request = parseRequest(reader) catch |err| {
        try sendError(writer, "400 Bad Request", @errorName(err));
        return;
    };

    if (std.mem.eql(u8, request.method, "OPTIONS")) {
        try sendEmpty(writer, "204 No Content");
        return;
    }

    route(allocator, writer, request) catch |err| {
        try sendError(writer, "400 Bad Request", @errorName(err));
    };
}

fn parseRequest(reader: *std.Io.Reader) !HttpRequest {
    const raw_request_line = (try reader.takeDelimiter('\n')) orelse return error.MalformedRequestLine;
    const request_line = trimLine(raw_request_line);

    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return error.MalformedRequestLine;
    const target = parts.next() orelse return error.MalformedRequestLine;
    _ = parts.next() orelse return error.MalformedRequestLine;

    var content_length: usize = 0;
    while (true) {
        const raw_line = (try reader.takeDelimiter('\n')) orelse return error.MalformedHeaders;
        const line = trimLine(raw_line);
        if (line.len == 0) break;

        if (std.mem.indexOfScalar(u8, line, ':')) |colon| {
            const name = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                content_length = try std.fmt.parseInt(usize, value, 10);
                if (content_length > max_body_len) return error.BodyTooLarge;
            }
        }
    }

    const body = if (content_length == 0) "" else try reader.take(content_length);
    const path = if (std.mem.indexOfScalar(u8, target, '?')) |q| target[0..q] else target;
    return .{ .method = method, .path = path, .body = body };
}

fn route(allocator: std.mem.Allocator, writer: *std.Io.Writer, request: HttpRequest) !void {
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/")) {
        try sendHtml(writer, "200 OK", index_html);
    } else if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/openapi.json")) {
        try sendJson(writer, "200 OK", openapi_json);
    } else if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/v1/health")) {
        try sendJson(writer, "200 OK", "{\"ok\":true,\"service\":\"lnwp-api\",\"version\":\"0.1.0\"}");
    } else if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/v1/version")) {
        try sendJson(writer, "200 OK", "{\"protocol\":\"LNWP\",\"version\":\"5.0\",\"wire_version\":\"0x0500\",\"max_body_len\":65535}");
    } else if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/v1/opcodes")) {
        try handleOpcodes(allocator, writer);
    } else if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/v1/frames/decode")) {
        try handleDecodeFrame(allocator, writer, request.body);
    } else if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/v1/frames/encode")) {
        try handleEncodeFrame(allocator, writer, request.body);
    } else if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/v1/checksums/crc32c")) {
        try handleCrc32c(allocator, writer, request.body);
    } else if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/v1/security/snapshot-hash")) {
        try handleSnapshotHash(allocator, writer, request.body);
    } else if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/v1/security/batch-mac")) {
        try handleBatchMac(allocator, writer, request.body);
    } else {
        try sendError(writer, "404 Not Found", "not_found");
    }
}

fn handleOpcodes(allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const w = &out.writer;

    try w.writeAll("{\"opcodes\":[");
    var first = true;
    inline for (@typeInfo(lnwp.opcodes.Opcode).@"enum".fields) |field| {
        const opcode: lnwp.opcodes.Opcode = @enumFromInt(field.value);
        if (!first) try w.writeByte(',');
        first = false;
        try w.print(
            "{{\"byte\":\"0x{X:0>2}\",\"value\":{d},\"name\":\"{s}\",\"direction\":\"{s}\",\"priority\":\"{s}\"}}",
            .{
                field.value,
                field.value,
                field.name,
                @tagName(lnwp.opcodes.direction(opcode)),
                @tagName(lnwp.opcodes.priority(opcode)),
            },
        );
    }
    try w.writeAll("],\"plugin_range\":\"0xF0-0xFE\"}");
    try sendJson(writer, "200 OK", out.written());
}

fn handleDecodeFrame(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(DecodeFrameRequest, allocator, body, .{});
    defer parsed.deinit();

    const bytes = try lnwp.hex.decodeAlloc(allocator, parsed.value.hex);
    defer allocator.free(bytes);
    const decoded = try lnwp.frame.decodeExact(bytes);
    const opcode = try decoded.opcode();

    const body_hex = try lnwp.hex.encodeAlloc(allocator, decoded.body);
    defer allocator.free(body_hex);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try out.writer.print(
        "{{\"ok\":true,\"opcode\":\"{s}\",\"opcode_byte\":\"0x{X:0>2}\",\"flags\":{d},\"length\":{d},\"body_hex\":\"{s}\",\"consumed\":{d}}}",
        .{
            lnwp.opcodes.tagName(opcode),
            decoded.header.opcode_byte,
            decoded.header.flags.toByte(),
            decoded.header.length,
            body_hex,
            decoded.consumed,
        },
    );
    try sendJson(writer, "200 OK", out.written());
}

fn handleEncodeFrame(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(EncodeFrameRequest, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const parsed_opcode = try parseOpcode(parsed.value.opcode);
    const parsed_flags = try lnwp.frame.Flags.fromByte(parsed.value.flags orelse 0);
    const body_hex = parsed.value.body_hex orelse "";
    const body_bytes = try lnwp.hex.decodeAlloc(allocator, body_hex);
    defer allocator.free(body_bytes);

    const encoded_len = try lnwp.frame.encodedLen(body_bytes.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded);
    const frame_bytes = try lnwp.frame.encodeInto(encoded, parsed_opcode, parsed_flags, body_bytes);
    const frame_hex = try lnwp.hex.encodeAlloc(allocator, frame_bytes);
    defer allocator.free(frame_hex);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try out.writer.print(
        "{{\"ok\":true,\"hex\":\"{s}\",\"length\":{d},\"opcode_byte\":\"0x{X:0>2}\"}}",
        .{ frame_hex, frame_bytes.len, lnwp.opcodes.toByte(parsed_opcode) },
    );
    try sendJson(writer, "200 OK", out.written());
}

fn handleCrc32c(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(HexRequest, allocator, body, .{});
    defer parsed.deinit();

    const bytes = try lnwp.hex.decodeAlloc(allocator, parsed.value.hex);
    defer allocator.free(bytes);
    const checksum = lnwp.crc32c.checksum(bytes);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try out.writer.print("{{\"ok\":true,\"crc32c\":\"0x{X:0>8}\",\"value\":{d}}}", .{ checksum, checksum });
    try sendJson(writer, "200 OK", out.written());
}

fn handleSnapshotHash(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(SnapshotHashRequest, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const key = try lnwp.hex.decodeAlloc(allocator, parsed.value.key_hex);
    defer allocator.free(key);
    const fingerprint_bytes = try lnwp.hex.decodeAlloc(allocator, parsed.value.tree_root_fingerprint_hex);
    defer allocator.free(fingerprint_bytes);
    if (fingerprint_bytes.len != 8) return error.InvalidFingerprintLength;
    const fingerprint = try lnwp.codec.readU64BE(fingerprint_bytes);
    const hash = lnwp.security.snapshotHash(key, parsed.value.snapshot_seq, fingerprint);
    const hash_hex = try lnwp.hex.encodeAlloc(allocator, hash[0..]);
    defer allocator.free(hash_hex);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try out.writer.print("{{\"ok\":true,\"snapshot_hash\":\"{s}\"}}", .{hash_hex});
    try sendJson(writer, "200 OK", out.written());
}

fn handleBatchMac(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(BatchMacRequest, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const key = try lnwp.hex.decodeAlloc(allocator, parsed.value.key_hex);
    defer allocator.free(key);
    const payload = try lnwp.hex.decodeAlloc(allocator, parsed.value.payload_hex);
    defer allocator.free(payload);
    const tag = lnwp.security.batchPatchMacHmacSha256(key, parsed.value.batch_seq, payload);
    const tag_hex = try lnwp.hex.encodeAlloc(allocator, tag[0..]);
    defer allocator.free(tag_hex);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try out.writer.print("{{\"ok\":true,\"mac_tag\":\"{s}\",\"mode\":\"hmac-sha256\"}}", .{tag_hex});
    try sendJson(writer, "200 OK", out.written());
}

fn parseOpcode(text: []const u8) !lnwp.opcodes.Parsed {
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
        const value = try std.fmt.parseInt(u8, text[2..], 16);
        return lnwp.opcodes.fromWireByte(value);
    }

    inline for (@typeInfo(lnwp.opcodes.Opcode).@"enum".fields) |field| {
        if (std.mem.eql(u8, text, field.name)) {
            return .{ .standard = @enumFromInt(field.value) };
        }
    }
    return error.InvalidOpcode;
}

fn trimLine(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
}

fn sendJson(writer: *std.Io.Writer, status: []const u8, body: []const u8) !void {
    try sendBody(writer, status, "application/json; charset=utf-8", body);
}

fn sendHtml(writer: *std.Io.Writer, status: []const u8, body: []const u8) !void {
    try sendBody(writer, status, "text/html; charset=utf-8", body);
}

fn sendError(writer: *std.Io.Writer, status: []const u8, message: []const u8) !void {
    var buffer: [256]u8 = undefined;
    const body = try std.fmt.bufPrint(&buffer, "{{\"ok\":false,\"error\":\"{s}\"}}", .{message});
    try sendJson(writer, status, body);
}

fn sendEmpty(writer: *std.Io.Writer, status: []const u8) !void {
    try writer.print(
        "HTTP/1.1 {s}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        .{status},
    );
    try writer.flush();
}

fn sendBody(writer: *std.Io.Writer, status: []const u8, content_type: []const u8, body: []const u8) !void {
    try writer.print(
        "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n{s}",
        .{ status, content_type, body.len, body },
    );
    try writer.flush();
}

const index_html =
    \\<!doctype html>
    \\<html lang="en">
    \\<head><meta charset="utf-8"><title>LNWP API</title></head>
    \\<body>
    \\<h1>LNWP API</h1>
    \\<p>OpenAPI: <a href="/openapi.json">/openapi.json</a></p>
    \\<ul>
    \\<li>GET /v1/health</li>
    \\<li>GET /v1/version</li>
    \\<li>GET /v1/opcodes</li>
    \\<li>POST /v1/frames/decode {"hex":"060000080000000000000001"}</li>
    \\<li>POST /v1/frames/encode {"opcode":"ping","flags":0,"body_hex":"0000000000000001"}</li>
    \\</ul>
    \\</body>
    \\</html>
;
