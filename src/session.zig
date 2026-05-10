const std = @import("std");

pub const State = enum {
    connecting,
    initial_streaming,
    connected,
    brownout_passive,
    sleeping,
    reconnecting,
    syncing,
    fanout_member,
    fanout_suspended,
    credential_refresh_needed,
    disconnected,
};

pub const Event = enum {
    welcome,
    initial_stream_chunk,
    final_initial_chunk,
    initial_chunk_timeout,
    patch,
    batch_patch,
    fle_ratchet,
    brownout_enter,
    brownout_exit,
    sleep,
    wake,
    liveness_fail,
    reconnect_welcome,
    queue_drained,
    fanout_join,
    fanout_leader_election,
    credential_refresh,
    jwt_expiring_error,
};

pub fn transition(from: State, event: Event) !State {
    return switch (from) {
        .connecting => switch (event) {
            .welcome => .connected,
            .initial_stream_chunk => .initial_streaming,
            else => error.InvalidTransition,
        },
        .initial_streaming => switch (event) {
            .final_initial_chunk => .connected,
            .initial_chunk_timeout => .disconnected,
            else => error.InvalidTransition,
        },
        .connected => switch (event) {
            .patch, .batch_patch, .fle_ratchet, .credential_refresh => .connected,
            .brownout_enter => .brownout_passive,
            .sleep => .sleeping,
            .liveness_fail => .reconnecting,
            .fanout_join => .fanout_member,
            .jwt_expiring_error => .credential_refresh_needed,
            else => error.InvalidTransition,
        },
        .brownout_passive => switch (event) {
            .brownout_exit => .connected,
            else => error.InvalidTransition,
        },
        .sleeping => switch (event) {
            .wake => .connected,
            else => error.InvalidTransition,
        },
        .reconnecting => switch (event) {
            .reconnect_welcome => .syncing,
            else => error.InvalidTransition,
        },
        .syncing => switch (event) {
            .queue_drained => .connected,
            else => error.InvalidTransition,
        },
        .fanout_member => switch (event) {
            .fanout_leader_election => .fanout_suspended,
            .patch, .batch_patch => .fanout_member,
            else => error.InvalidTransition,
        },
        .fanout_suspended => switch (event) {
            .welcome => .fanout_member,
            else => error.InvalidTransition,
        },
        .credential_refresh_needed => switch (event) {
            .credential_refresh => .connected,
            else => error.InvalidTransition,
        },
        .disconnected => switch (event) {
            .reconnect_welcome => .syncing,
            else => error.InvalidTransition,
        },
    };
}

test "core session lifecycle follows spec table" {
    try std.testing.expectEqual(State.connected, try transition(.connecting, .welcome));
    try std.testing.expectEqual(State.initial_streaming, try transition(.connecting, .initial_stream_chunk));
    try std.testing.expectEqual(State.connected, try transition(.initial_streaming, .final_initial_chunk));
    try std.testing.expectEqual(State.reconnecting, try transition(.connected, .liveness_fail));
    try std.testing.expectEqual(State.syncing, try transition(.reconnecting, .reconnect_welcome));
    try std.testing.expectEqual(State.connected, try transition(.syncing, .queue_drained));
    try std.testing.expectError(error.InvalidTransition, transition(.connected, .queue_drained));
}
