# Extracted from LNWP-v5.0-Complete-Specification.docx

LNWP

Live Native Wire Protocol

v5.0 — Complete Protocol Specification

FIRST MAJOR RELEASE  ·  Normative  ·  Production Ready  ·  Supersedes ALL Prior Versions


| Attribute | Value |
| --- | --- |
| Release | v5.0 — First major version since v4.0 |
| Status | Normative — Production Ready |
| Supersedes | ALL prior versions, completely. v5.0 is a full rewrite — not additive. |
| Wire Compatibility | v4.x clients are wire-compatible via §3.1 version negotiation. v5.0 DOES add 3 breaking changes (§0.3). |
| Architecture | 14 unified chapters replacing 300 additive sections. No version annotations. Single source of truth. |
| Performance Targets | p50 < 4 ms · p99 < 10 ms · parse < 80 ns · diff < 0.4 µs · encode < 1 µs · 0 memcpy |
| Energy | < 0.1%/hr background · < 0.9%/hr active · < 8 W/M server sessions |
| Security | 31 STRIDE threats · 53 conformance suites · HMAC per-batch · ML-DSA-65 quantum-safe · 0 open CVEs |

Sub-10ms live UI. Zero-copy from kernel to render. Quantum-resistant. Energy-efficient by spec. Formally audited.

## §0 — About This Document

### §0.1 Purpose

This document is the complete, authoritative specification of the Live Native Wire Protocol (LNWP) v5.0. It supersedes all prior versions (v3.5 through v4.5) in their entirety. Every normative requirement, every wire format, every security property, and every operational procedure is defined here. No external document is required to implement LNWP v5.0.

v5.0 is the first complete rewrite of LNWP. Versions v3.5–v4.5 were structured as additive patches, accumulating 300 sections across 10 releases. v5.0 consolidates this material into 14 logical chapters, eliminates all version-annotation scaffolding, tightens every requirement, and adds the improvements described in §0.3.

### §0.2 Conformance Tiers


| Tier | Name | Binary Size | Target Platform | Key Constraints |
| --- | --- | --- | --- | --- |
| NANO | IoT Minimal | < 40 KB | Microcontrollers (ESP32, STM32) | PATCH/EVENT/PING only; no PQC; no ADC; no ratchet; no fan-out |
| BASE | Embedded Full | < 85 KB | Embedded displays, set-top boxes | Full session lifecycle; ADC; BATCH_PATCH; no SPR; PQC optional |
| FULL | Mobile/Desktop | < 220 KB | iOS, Android, macOS, Windows, Linux browser | All features; PQC REQUIRED; ratchet REQUIRED; WebTransport REQUIRED |
| ENTERPRISE | Server | Unlimited | Server instances, proxies, gateways | All features + fan-out leader election; DPDK optional; ML-DSA REQUIRED |

### §0.3 Breaking Changes from v4.x


| Breaking Changes — v4.x → v5.0 |
| --- |
| BREAK-1: Frame header compacted. v4.x: u8 opcode + u8 flags + u24 length = 5 bytes. v5.0: u8 opcode + u8 flags + u16 length = 4 bytes. Max frame body: 65,535 bytes (was 16 MB). Frames exceeding 65,535 bytes MUST use FRAGMENT (§2.3). Wire-incompatible with v4.x without negotiation.<br>BREAK-2: PQC REQUIRED for FULL and ENTERPRISE tiers. v4.x required PQC only for L3+. v5.0: any FULL or ENTERPRISE implementation without Kyber-1024 is non-conformant.<br>BREAK-3: snapshot_hash in RESUME_FROM_SNAPSHOT is HMAC-SHA256 (32 bytes). v4.4 used xxHash3 (8 bytes). v4.5 already fixed this; v5.0 makes the HMAC format the only accepted format.<br>MIGRATION: v4.x clients negotiate v4.x protocol via §3.1 version field in HELLO. A v5.0 server serves v4.x clients in compatibility mode (5-byte header, old snapshot_hash). Compatibility mode is OPTIONAL for server implementations. |

## §1 — Architecture & Core Guarantees

### §1.1 Design Principles

LNWP is a binary, server-driven, live-state protocol for native UI. The server holds the authoritative component tree. Clients render whatever the server sends. The six non-negotiable design principles are:


| Principle | Guarantee | Mechanism |
| --- | --- | --- |
| Zero-Copy End-to-End | No application-level memcpy from kernel receive buffer to render | io_uring ZC recv §8.1; arena-packed tree §8.4; sendfile snapshot §8.5 |
| Sub-10ms p99 | Event-to-patch delivery < 10 ms p99 under nominal load | DPDK-optional kernel bypass; lock-free ring buffers §6.1; speculative pre-computation §6.4 |
| Quantum-Resistant | All key establishment and batch integrity are quantum-safe at FULL+ tier | Kyber-1024 §7.2; ML-DSA-65 §7.4; HKDF-SHA3-256 ratchet §7.3 |
| Energy-Measurable | Battery drain and server watts are normative SLOs, not aspirations | DRX alignment §8.2; viewport pruning §8.3; power profiles §8.6; §11.4 energy gates |
| Formally Audited | All 31 STRIDE threats identified, mitigated, and conformance-tested | §7.9 threat model; TS-46–TS-53 adversarial test vectors §12.2 |
| Horizontally Unbounded | No per-instance session ceiling; cluster scales to any size | Stateless diff + Redis/DragonflyDB state §9.1; fan-out §9.3; federation §9.7 |

### §1.2 Reliability Stack


| Layer | Name | Mechanism | Failure Handled |
| --- | --- | --- | --- |
| L6 | Application | Optimistic updates + rollback | Bad server state |
| L5 | Session | RESUME + seq checksum + inflight replay | Server restart |
| L4 | Reconnect | Exponential backoff + circuit breaker | Network loss |
| L3 | Liveness | RTT-aware PING/PONG + CQ-Signal | Silent TCP drop |
| L2 | Transport | ACCC + ADC + 8-level FPQ | Congestion, buffer overflow |
| L1 | Priority | 8-level FPQ; P0 bypass lane | Liveness starvation |
| L0 | Isolation | SCIP quarantine + eviction | Head-of-line blocking |
| L−1 | I/O Integrity | ZC mapped buffers + CRC32c (SIMD) | DMA bit errors, kernel corruption |
| L−2 | Ratchet Sec. | Double-Ratchet KDF per N patches | FLE session secret extraction |
| L−3 | Fan-Out Cons. | SESSION_FANOUT seq alignment | Device patch divergence |
| L−4 | Config Cons. | RUNTIME_CONFIG versioned ACK + Raft dissemination | Config skew across instances |
| L−5 | Patch Integ. | Session HMAC MAC over BATCH_PATCH runs | Proxy PATCH injection |

### §1.3 Performance Targets — v5.0


| Metric | v4.5 Target | v5.0 Target | Mechanism |
| --- | --- | --- | --- |
| Patch latency p50 | < 12 ms | < 4 ms | Speculative pre-computation §6.4 + lock-free state §6.1 |
| Patch latency p99 | < 80 ms | < 10 ms | DPDK/io_uring-sqpoll §3.5; viewport pruning §8.3 |
| Event round-trip p99 | < 150 ms | < 20 ms | QUIC-native §3.2; zero-copy parse §8.1 |
| Frame parse p99 | < 100 ns | < 80 ns | SIMD CRC32c §8.6; 4-byte header §2.1 |
| Diff p99 (200-node, 4 core) | < 0.5 µs | < 0.4 µs | Lock-free deque §6.2; NUMA binding §8.7 |
| Patch encode p99 | < 2 µs | < 1 µs | Arena-packed tree §8.4; zero-copy encode §8.1 |
| Session availability | 99.95% | 99.99% | Raft-hardened fan-out §9.3; cluster BROWNOUT CB §9.4 |
| Background battery drain | < 0.1%/hr | < 0.1%/hr | SESSION_SLEEP §8.2; DRX alignment §8.2 |
| Server W/M active sessions | < 8 W/M | < 6 W/M | Viewport pruning §8.3; adaptive compression §6.5 |

## §2 — Wire Format

### §2.1 Frame Header (4 bytes)


| Byte(s) | Field | Type | Description |
| --- | --- | --- | --- |
| 0 | opcode | u8 | Frame type; see §2.2 opcode registry |
| 1 | flags | u8 | Bit 7: zc_flag (zero-copy buffer). Bit 6: a11y_present. Bit 5: spr_delta. Bit 4: mac_present/integrity_mode. Bit 3: padded. Bits 2–0: reserved (MUST be 0) |
| 2–3 | length | u16 big-endian | Body length in bytes (0–65,535). Frames > 65,535 bytes MUST use FRAGMENT (opcode 0x08) |


| §2.1 Frame Header |
| --- |
| The 4-byte header is a breaking change from v4.x (5-byte). A v4.x client connecting to a v5.0 server negotiates the old header format via proto_version in HELLO. A v5.0 server in compatibility mode uses 5-byte headers for v4.x clients.<br>CRC32c (for ZC frames, §8.1) is appended AFTER the body, not in the header. It is part of the frame body region when zc_flag=1.<br>Numeric encoding throughout: all multi-byte integers are big-endian on the wire except where noted (varints use little-endian base-128). |

### §2.2 Opcode Registry


| Opcode | Frame | Direction | FPQ Priority | Description |
| --- | --- | --- | --- | --- |
| 0x01 | HELLO | C→S | — | Session initiation; carries auth, capabilities, locale, residency_zone |
| 0x02 | WELCOME | S→C | — | Session accepted; carries schema, session_mac_key, PQC material |
| 0x03 | PATCH | S→C | P1 | Single-tree state update; body: ops array |
| 0x04 | ACK | C→S | P1 | PATCH acknowledgement with last_applied_seq |
| 0x05 | EVENT | C→S | P2 | Client interaction; carries payload, nonce, submitted_at |
| 0x06 | PING | Both | P0 | Liveness probe; carries timestamp_us for RTT measurement |
| 0x07 | PONG | Both | P0 | Liveness response; echoes PING timestamp_us |
| 0x08 | FRAGMENT | Both | — | Fragment of a frame > 65,535 bytes; carries fragment_index, total_fragments |
| 0x09 | RESYNC | C→S | P0 | Client requests full state resync after detected desync |
| 0x0A | ERROR | Both | P0 | Error notification; carries error_code (§2.3), message |
| 0x0B | RESUME | C→S | — | Session resume after disconnect; carries session_id, last_seq |
| 0x0C | MIGRATE | S→C | P0 | Rolling-deploy server migration; carries target_url, migrate_token |
| 0x0D | DRAIN | S→C | P0 | Server is draining; client should prepare for MIGRATE |
| 0x0E | BACKPRESSURE | S→C | P0 | Flow control: server is applying session rate reduction |
| 0x0F | SLOWDOWN | S→C | P0 | Stronger backpressure; client MUST reduce EVENT rate |
| 0x10 | BATCH_PATCH | S→C | P1 | Multiple patches in one frame; mac_tag appended if mac_present |
| 0x11 | ADC_DICT_UPDATE | S→C | P3 | New zstd dictionary for this session |
| 0x12 | PRIORITY_SIGNAL | C→S | P1 | SCIP self-report: client signals its own processing capacity |
| 0x13 | GRPC_FRAME | Both | P2 | gRPC bridge payload §6.6 |
| 0x14 | INITIAL_STREAM_CHUNK | S→C | P1 | Chunked initial state delivery §6.7; carries chunk_index, priority_band |
| 0x15 | SESSION_FANOUT | S→C | P1 | Fan-out group management: JOIN/LEAVE/FANOUT_PATCH §9.3 |
| 0x16 | RUNTIME_CONFIG | S→C | P1 | Live operational parameter update; versioned §9.5 |
| 0x17 | POWER_PROFILE | S→C | P3 | Battery-adaptive profile switch: NORMAL/POWER_SAVE/ULTRA_LOW §8.6 |
| 0x18 | VIEWPORT_HINT | C→S | P3 | Visible/near/medium node sets for diff pruning §8.3 |
| 0x19 | SESSION_SLEEP | C→S | P1 | Client entering background; suppress non-P0 patches for N ms §8.2 |
| 0x1A | LOCALE_HINT | Both | P3 | Locale/timezone/direction change §9.9 |
| 0x1B | TRANSPORT_MIGRATE | S→C | P1 | Zero-downtime transport switch §3.4 |
| 0x1C | CLIENT_TELEMETRY | C→S | P5 | Device health metrics: battery, RSSI, decode/render latency §10.3 |
| 0x1D | BUSINESS_EVENT | C→S | P5 | Application analytics payload; opaque; DP-eligible §10.4 |
| 0x1E | CREDENTIAL_REFRESH | C→S | P1 | Mid-session JWT rotation §7.6 |
| 0x1F | HELLO_REBIND | C→S | P1 | JWT channel binding refresh on TLS resumption §7.5 |
| 0x20 | RESUME_FROM_SNAPSHOT | C→S | — | Resume with snapshot delta instead of full initial stream §6.8 |
| 0x21 | BROWNOUT | S→C | P0 | Server brownout entry/exit notification §9.4 |
| 0x22 | FLE_RATCHET | S→C | P1 | FLE double-ratchet key advance §7.3 |
| 0x23 | SESSION_MULTIPLEX | Both | P1 | N logical sessions over 1 connection §9.2 |
| 0x24 | RESIDENCY_HINT | C→S | P1 | Session data zone binding §9.8 |
| 0x25 | GC_PAUSE_HINT | Local | — | Host GC notification to liblnwp §8.8 (not transmitted over wire; IPC only) |
| 0x26 | COMPONENT_HOT_RELOAD | S→C | P2 | Dev-mode component code update §12.3 |
| 0x27 | SCHEMA_ROLLBACK | S→C | P1 | Schema revert to prior version §9.6 |
| 0xF0–0xFE | PLUGIN_* | Both | varies | Experimental vendor opcodes §12.5; registered in plugin registry |
| 0xFF | RESERVED | — | — | MUST NOT be sent; receiving returns ERROR 4000 |

### §2.3 Error Code Registry


| Range | Category | Key Codes |
| --- | --- | --- |
| 1000–1999 | Transport errors | 1001 VERSION_MISMATCH · 1002 FRAME_TOO_LARGE · 1003 INVALID_OPCODE · 1004 MALFORMED_FRAME · 1005 CRC_MISMATCH |
| 2000–2999 | Auth errors | 2001 AUTH_FAILED · 2002 JWT_EXPIRED · 2003 CHANNEL_BINDING_REQUIRED · 2004 AUTH_RATE_LIMITED · 2005 CREDENTIAL_REFRESH_REQUIRED |
| 3000–3999 | Session errors | 3001 SERVER_OVERLOADED · 3002 SESSION_NOT_FOUND · 3003 SEQ_GAP · 3004 SCHEMA_VERSION_MISMATCH · 3005 RATCHET_DESYNCED · 3006 ADC_DICT_CORRUPT · 3007 GRPC_CB_OPEN · 3008 RATE_LIMITED · 3009 SCHEMA_CAS_CONFLICT · 3010 FANOUT_LIMIT · 3011 BROWNOUT_ACTIVE · 3012 QOS_EXCEEDED · 3013 SYNCING_TIMEOUT · 3014 ROLLBACK_PENDING · 3015 DEBUG_DENIED · 3016 CDP_UNSUPPORTED · 3017 WT_DOWNGRADE · 3018 CLUSTER_BROWNOUT · 3019 CONFIG_REJECTED · 3020 LOCALE_UNSUPPORTED · 3021 FANOUT_LEADER_CONFLICT · 3022 INTEGRITY_MAC_FAILED · 3023 MULTIPLEX_LIMIT · 3024 RESIDENCY_VIOLATION · 3025 CONFLICT_UNRESOLVABLE · 3026 PLUGIN_REJECTED · 3027 ENCODING_UNSUPPORTED · 3028 INITIAL_STREAM_INTERRUPTED |
| 4000–4999 | Protocol errors | 4000 RESERVED_OPCODE · 4001 CAPABILITY_MISMATCH · 4002 SNAPSHOT_HASH_INVALID · 4003 VIEWPORT_HMAC_INVALID · 4004 IPC_AUTH_FAILED |

### §2.4 Encoding Details


| Encoding Element | Specification |
| --- | --- |
| Integers | All fixed-width integers: big-endian. Variable-length integers: unsigned LEB128 (base-128, little-endian continuation bit) |
| Strings | UTF-8; length-prefixed with u16 (max 65,535 bytes). MUST be valid UTF-8; invalid UTF-8 returns ERROR 1004 |
| Byte arrays | u32 length prefix followed by raw bytes. Length 0 is valid (empty array) |
| Node IDs | u32 wire; maps to session-keyed SipHash-1-3 permuted arena index. Arena index never appears on wire |
| Timestamps | u64 microseconds since Unix epoch; UTC. Clients SHOULD use system monotonic clock corrected to wall time |
| Booleans | u8; 0=false, 1=true; values 2–255 MUST be treated as true for forward compatibility |
| Varint deltas | Zigzag-encoded signed LEB128 for DELTA_ENCODING fields §8.9; zigzag: (n << 1) XOR (n >> 63) |
| Alternative | CBOR (encoding=1) or MessagePack (encoding=2) negotiated in HELLO; field mapping identical to binary; NANO/BASE tiers: binary only |

## §3 — Transport Bindings

### §3.1 Version Negotiation

The client sends proto_version (u16) in HELLO: 0x0500 for v5.0, 0x0401 for v4.1, etc. The server responds with the highest version it supports that is ≤ the client's version. The negotiated version governs frame header width, feature availability, and conformance tier mapping.

### §3.2 Transport Priority Order


| Priority | Transport | Requirement | Notes |
| --- | --- | --- | --- |
| 1st | QUIC-native (HTTP/3) | FULL+ENTERPRISE | Direct QUIC streams; no WebSocket wrapper. Port 443 UDP. ALPN: lnwp/5 |
| 2nd | WebTransport (RFC 9297) | FULL+ENTERPRISE | Browser clients; QUIC datagrams for PING; reliable streams for PATCH/EVENT |
| 3rd | QUIC via WebSocket upgrade | FULL | Legacy path; QUIC negotiated inside WS upgrade for environments blocking UDP 443 |
| 4th | HTTP/2 + SSE | FULL | Push PATCH via SSE; EVENT via XHR or fetch. Server-sent events for duplex-ish |
| 5th | HTTP/1.1 + SSE + polling | BASE+ | Maximum compatibility; higher latency; no QUIC benefits |


| §3.2 Transport Selection |
| --- |
| QUIC-native (1st priority) is the breaking difference from v4.x where QUIC was tunnelled inside WebSocket. v5.0 uses QUIC streams directly when available. The ALPN token "lnwp/5" distinguishes v5.0 from v4.x ("lnwp/4").<br>NANO and BASE tiers: HTTP/1.1+SSE only. WebTransport and QUIC-native are FULL+ only. This bounds embedded TLS stack requirements for constrained devices.<br>Transport selection is determined during HELLO. The client lists supported transports in preference order; the server selects the highest-priority mutually supported transport. |

### §3.3 Session Multiplexing (FULL+)

Up to 256 logical LNWP sessions share one underlying connection via SESSION_MULTIPLEX (opcode 0x23). Each logical session has independent FPQ priority, backpressure, SCIP scoring, and ratchet state. The broadcast logical_session_id (0xFFFFFFFF) is reserved for connection-level coalesced PING and MUST NOT be used for regular sessions (server returns ERROR 3023 on ATTACH attempt).

### §3.4 Zero-Downtime Transport Migration

TRANSPORT_MIGRATE (0x1B) pre-connects the client to a new transport endpoint before tearing down the old connection. Protocol: (1) Server sends 0x1B with target_url and migrate_token (128-bit CSPRNG, 30-second TTL); (2) Client connects to target_url and sends HELLO with migrate_token; (3) Server issues WELCOME with same session_id and ratchet epoch; (4) Client ACKs on new transport; (5) Old transport closed. PATCHes buffered during migration window; drained via BATCH_PATCH after WELCOME.

### §3.5 Kernel-Bypass Mode (ENTERPRISE, optional)

On Linux servers with DPDK or AF_XDP support, LNWP can bypass the kernel network stack entirely. This reduces packet processing latency from ~10 µs to ~1 µs. Kernel-bypass is opt-in, operator-configured, and requires dedicated NIC RSS queues. When active, lnwp.io.kernel_bypass_enabled=1 metric is set. The protocol is identical; only the I/O path changes. Fallback to standard io_uring path is automatic on bypass failure.

## §4 — Session Lifecycle

### §4.1 HELLO Frame Fields


| Field | Type | Required | Description |
| --- | --- | --- | --- |
| proto_version | u16 | MUST | Protocol version: 0x0500 for v5.0 |
| session_id | u64 | MUST for RESUME; 0 for new session | Existing session to resume; 0 = new |
| jwt | string | MUST | Signed JWT for authentication |
| jwt_binding_hash | bytes[32] | MUST for FULL+ | HMAC-SHA256(tls_session_hash, jwt_jti); channel binding §7.5 |
| schema_version | u32 | MUST | Client's current schema version; 0 if unknown |
| app_version | string | SHOULD | SemVer app version; used for schema compatibility §9.6 |
| capabilities | u64 bitfield | MUST | Bit flags: bit0=zc_capable, bit1=batch_capable, bit2=fanout_capable, bit3=integrity_capable, bit4=streaming_capable, bit5=multiplex_capable, bit6=telemetry_capable, bit7=viewport_capable, bit8=ml_dsa_capable, bit9=rebind_capable, bit10=config_reload_capable, bit11=hot_reload_capable, bit12=security_critical_aware |
| cdp_tier | u2 | MUST | 0=FULL/ENTERPRISE, 1=BASE, 2=NANO |
| locale | string | SHOULD | BCP 47 locale tag, e.g. "en-IN" |
| residency_zone | string | SHOULD if regulated | IANA region for data residency enforcement §9.8 |
| encoding | u8 | MAY | 0=binary (default), 1=CBOR, 2=MessagePack |
| snapshot_seq | u32 | MAY | For RESUME_FROM_SNAPSHOT §6.8; client's last snapshot seq |
| snapshot_hash | bytes[32] | MAY (with snapshot_seq) | HMAC-SHA256(session_mac_key, snapshot_seq \|\| tree_root_fingerprint) §6.8 |
| plugin_opcodes | u8[] | MAY | Experimental plugin opcodes this client will emit |

### §4.2 Session State Machine


| From | Event | Guard | To | Side Effects |
| --- | --- | --- | --- | --- |
| — | connect() | url valid | CONNECTING | Open transport; send HELLO |
| CONNECTING | WELCOME | version compatible | CONNECTED | Init PQC; seed ratchet; init arena tree; render first tree |
| CONNECTING | INITIAL_STREAM_CHUNK | streaming_capable=1 | INITIAL_STREAMING | Render above-fold chunk immediately; defer EVENTs |
| INITIAL_STREAMING | final chunk | all chunks received | CONNECTED | Flush buffered EVENTs |
| INITIAL_STREAMING | chunk timeout | > chunk_timeout_ms | DISCONNECTED | ERROR 3028; RESYNC |
| CONNECTED | PATCH | seq == next_seq | CONNECTED | ZC parse; apply to arena; update last_seq |
| CONNECTED | BATCH_PATCH | mac valid if mac_present | CONNECTED | Verify HMAC; apply N patches; single ACK |
| CONNECTED | FLE_RATCHET | epoch == next_epoch | CONNECTED | Advance ratchet; zero old key |
| CONNECTED | BROWNOUT | any | BROWNOUT_PASSIVE | Serve cached patches; pause EVENTs |
| BROWNOUT_PASSIVE | BROWNOUT exit | ttl elapsed | CONNECTED | Flush buffered EVENTs; RESYNC if needed |
| CONNECTED | SESSION_SLEEP | client-initiated | SLEEPING | Server accumulates delta; no non-P0 patches |
| SLEEPING | SESSION_SLEEP wake | sleep_ms=0 | CONNECTED | Server delivers one BATCH_PATCH with accumulated delta |
| CONNECTED | liveness_fail() | 3 PINGs missed | RECONNECTING | Start reconnect with exponential backoff |
| RECONNECTING | WELCOME | session valid | SYNCING | Drain via BATCH_PATCH §6.8 |
| SYNCING | queue drained | all ACKed | CONNECTED | Notify UI: back online |
| CONNECTED | FANOUT JOIN | fanout_capable=1 | FANOUT_MEMBER | Join group; receive shared PATCH stream |
| FANOUT_MEMBER | FANOUT leader election | Raft election | FANOUT_SUSPENDED | Queue EVENTs; await new leader WELCOME |
| CONNECTED | CREDENTIAL_REFRESH | new JWT valid | CONNECTED | Update session auth; ratchet continues |
| CONNECTED | ERROR 2005 | JWT expiring | CREDENTIAL_REFRESH_NEEDED | Must send CREDENTIAL_REFRESH within grace_ms |

## §5 — Real-Time Delivery Engine

### §5.1 Lock-Free Session Ring Buffer

Session state (last_seq, backpressure window, SCIP score, ratchet epoch) is stored in a fixed-size, cache-line-aligned ring buffer per session. The ring uses a Michael-Scott two-lock-free queue variant with a single producer (the diff worker) and single consumer (the send worker). No mutex; only compare-and-swap (CAS) operations. This eliminates lock contention at the hot path and reduces per-patch CPU by ~15% at high session counts.

### §5.2 Multi-Core Diff Engine

Virtual tree subtrees at depth ≥ 2 with ≥ 16 nodes are parallelised using a Chase-Lev lock-free work-stealing deque (not a spinlock-based deque). Each worker thread is NUMA-bound and allocates from a NUMA-local arena. The dispatch thread handles the root and depth-1 nodes. Subtrees that share no parent are independent and can be diffed in any order. DIFF_SHARD_HINT in HELLO declares pre-computed subtree boundaries.


| Config Parameter | Default | Description |
| --- | --- | --- |
| worker_count | NumCPU − 1 | Diff worker pool size; 1 = serial fallback |
| min_subtree_nodes | 16 | Minimum nodes for a subtree to be dispatched to worker pool |
| hedge_threshold_us | p95 × 1.5 | After this latency, re-dispatch the diff unit to a second worker (§5.3) |
| max_hedge_fraction | 0.05 | Max fraction of concurrent diffs that can be hedged |

### §5.3 Hedged Diff Dispatch

When a diff unit exceeds hedge_threshold_us (rolling 60-second p95 × 1.5), it is dispatched to a second worker concurrently. The first result to complete is used; the other is cancelled via a cancel flag checked at each diff step boundary. This reduces tail latency 40–60% at high core counts without increasing average CPU.

### §5.4 Speculative Pre-Computation

During the transit time of a client EVENT (network RTT ÷ 2), the server can speculatively begin computing the diff of the most likely next state using SPR confidence scores. If confidence > 0.65, the speculative diff begins. When the EVENT arrives: (a) full hit (confidence > 0.85): 0-RTT PATCH delivery; (b) partial hit (0.65–0.85): PATCH_DELTA_SPR sent (diff between speculative and authoritative tree); (c) miss: discard and compute normal diff. The speculative path is transparent to the application SDK.

### §5.5 Adaptive Frame Coalescing

The adaptive tick algorithm controls how long the diff engine waits to coalesce patches before transmitting. Tick window adjusts in the range [tick_min_ms, tick_max_ms] based on three signals: event inter-arrival time EWMA, ACCC congestion window utilisation, and client render_queue_depth from CLIENT_TELEMETRY. The ceiling is additionally bounded by drx_cycle_ms − 5 ms for DRX alignment. BATCH_PATCH packs up to 255 patches per frame, reducing per-patch framing overhead to near zero.

### §5.6 Adaptive Compression

ADC compression level is auto-selected per session based on measured CPU utilisation and compression ratio. Level selection algorithm: if lnwp.qos.tenant_cpu_utilisation > 85% for 10 s → level 1; restore to level 3 at < 60%. ADC dictionaries are trained incrementally via Vitter reservoir sampling (k=1000) + ZDICT_finalizeDictionary every 100 new patches (2 ms CPU vs 200 ms for full retrain). Full retrain occurs once per 24 hours during a low-traffic window. Cross-session corpus seeded per (tenant_id, schema_version_id) to prevent cross-tenant training data leakage.

### §5.7 gRPC Bridge

GRPC_FRAME (0x13) tunnels gRPC protocol buffers through LNWP to native clients. Circuit breaker: CLOSED → OPEN → HALF_OPEN. State transitions: CLOSED → OPEN on 5 consecutive errors or > 50% error rate in 10 s; OPEN → HALF_OPEN after 30 s; HALF_OPEN → CLOSED on successful probe. SSRF guard: gRPC upstreams MUST be in an operator-maintained allowlist; RFC-1918 addresses blocked.

### §5.8 Initial State Streaming

INITIAL_STREAM_CHUNK (0x14) delivers the initial component tree progressively in 4 priority bands: band 0 (above-fold) arrives first and is rendered immediately; bands 1–3 (near/medium/deferred) follow. Clients in INITIAL_STREAMING state queue EVENTs and defer sending until the final chunk arrives. On brief reconnect (< 120 s), RESUME_FROM_SNAPSHOT (0x20) delivers only the delta from the client's last snapshot — typically 2–15 KB instead of the full tree. snapshot_hash MUST be HMAC-SHA256(session_mac_key, snapshot_seq || tree_root_fingerprint).

## §6 — Security

### §6.1 Transport Security


| Requirement | Specification |
| --- | --- |
| TLS version | TLS 1.3 minimum. TLS 1.2 MUST NOT be used in production. Plaintext MUST NOT be used. |
| mTLS | RECOMMENDED for all FULL+ deployments. REQUIRED for FedRAMP High and HIPAA. Certificate profile: SPIFFE SVID (X.509 with URI SAN spiffe://{trust_domain}/lnwp/session/{session_id}). Key: P-256 ECDSA or Ed25519. Lifetime: ≤ 24 hours. Revocation: OCSP stapling; hard-fail if unavailable. Trust anchor pin: SHA3-256 of SPIFFE CA certificate, delivered in WELCOME, pinned on first connect. |
| JWT channel binding | jwt_binding_hash = HMAC-SHA256(tls_exporter_value, jwt_jti). REQUIRED for FULL+ (ERROR 2003 if absent). Refreshed on TLS resumption via HELLO_REBIND (0x1F). |

### §6.2 Post-Quantum Key Establishment

FULL and ENTERPRISE tiers MUST perform a PQC hybrid KEM on every session. Hybrid KEM: X25519 (classical) + CRYSTALS-Kyber-1024 (post-quantum). Both shared secrets are combined via HKDF-SHA3-256 to produce the session root key. The root key seeds both the FLE session secret and the FLE ratchet root key. WELCOME signing uses ML-DSA-65 (NIST FIPS 204). Kyber-1024 public key is rotated every 24 hours or 10M frames. Per-tenant Kyber key pairs for T0/T1 tenants (dedicated HSM partitions).


| §6.2 PQC Requirements |
| --- |
| Implementations MUST use a NIST-validated Kyber-1024 library. Constant-time execution REQUIRED for Kyber decapsulation. Valgrind ct-grind verification MUST be in the §11.3 Stage 6 gate.<br>The 12-month grandfather period for legacy non-PQC FULL deployments expired with v4.1. v5.0 makes no exceptions: non-PQC FULL implementations are non-conformant.<br>Key Transparency (KT): TOFU pinning required. On first connection, client stores SHA3-256 of server Kyber public key in platform keychain. Mismatch on subsequent connects: ERROR 4003 and session refused. KT log submission optional; recommended for T0/T1 tenants. |

### §6.3 Field-Level Encryption (FLE)


| Tier | Label | Encryption | Who Can Read |
| --- | --- | --- | --- |
| T1 | Public | None; transmitted as plaintext | Any party (server, client, transit) |
| T2 | Internal | None; server-side access control enforced | Authenticated sessions with appropriate tenant scope |
| T3 | Sensitive | ChaCha20-Poly1305 with double-ratchet MK (§6.4) | Only the specific client session. Server sees ciphertext only. |

### §6.4 FLE Double-Ratchet Forward Secrecy

The FLE ratchet advances the message key (MK) every ratchet_interval_patches (default 1000) or ratchet_interval_s (default 300 s). Key hierarchy: Root Key (RK) from PQC KEM output → Chain Key (CK) via HKDF-SHA3-256 with epoch counter → Message Key (MK) for ChaCha20-Poly1305. After ACK, previous MK is zeroed via @volatileStore (Zig) or memory_barrier + explicit zero (C). Overlap window ≤ 2×RTT. Ratchet epoch persisted to platform storage (48-byte record: epoch+CK+session_id+CRC32c) — soft reboots resume at correct epoch without re-handshake. Blast radius of key extraction: ≤ 1000 patches.

### §6.5 Batch Integrity MAC

Every BATCH_PATCH includes a mac_tag when mac_present flag is set. Two modes: mode 1 = HMAC-SHA256 (session_mac_key, opcode || batch_seq || body); 32 bytes; < 50 µs verification. Mode 2 = ML-DSA-65 signature; 3293 bytes; < 2 ms verification. Mode 3 = both (transition period). The session_mac_key is derived from the PQC KEM output and advances with the ratchet. MAC verification MUST be constant-time. ERROR 3022 on failure; session terminated immediately.

### §6.6 Security-Critical Node Annotation

Schema nodes annotated security_critical=true are diffed and patched on every tick regardless of VIEWPORT_HINT, SESSION_SLEEP, or power profile. These are nodes whose stale state would mislead the user about authentication, authorization, payment status, or fraud detection. VIEWPORT_HINT frames MUST be HMAC-signed (8-byte truncated HMAC-SHA256) to prevent forgery. Server rejects unsigned VIEWPORT_HINTs from sessions with integrity_capable=1 (ERROR 4003).

### §6.7 Privacy & Differential Privacy

CLIENT_TELEMETRY aggregates have Laplace noise (ε=1.0) applied before storage. Fields: decode/render latency p99, memory pressure, battery_state (bucketed to 3 values), cpu_throttled. Raw CLIENT_TELEMETRY frames are never stored. Retention: 7 days for latency aggregates; 24 hours for device state. GDPR Recital 26: telemetry with ε=1.0 noise classified as non-personal data. POWER_PROFILE frame delivery jittered 0–200 ms (uniform random) to prevent behavioral fingerprinting. BATCH_PATCH on SESSION_SLEEP wake padded to 5 size buckets (≤1KB, 1–4KB, 4–16KB, 16–64KB, ≥64KB) to prevent state-volatility inference from packet sizes. viewport_data_sensitive=true schema flag: visible_node_ids excluded from §10.2 operational logs.

### §6.8 STRIDE Threat Model — 31 Entries


| ID | Category | Threat Summary | Primary Mitigation |
| --- | --- | --- | --- |
| T-01 | Spoofing | Unauthenticated HELLO | JWT verification before WELCOME; channel binding §6.1 |
| T-02 | Tampering | PATCH injection via proxy | Session HMAC MAC §6.5; TLS 1.3 |
| T-03 | Repudiation | Client denies EVENT submission | WORM audit log with HMAC chain §10.2 |
| T-04 | Info Disclose | T3 attribute interception | ChaCha20-Poly1305 FLE §6.3 |
| T-05 | DoS | EVENT flood exhausts thread pool | Per-session + per-tenant rate limiting |
| T-06 | Elevation | Cross-tenant Redis key access | Tenant-namespaced key prefix + HMAC §9.6 |
| T-07 | Spoofing | JWT replay on new TLS connection | jwt_binding_hash channel binding §6.1 |
| T-08 | Info Disclose | Captured TLS session key replay | PQC hybrid KEM; forward secrecy §6.2 |
| T-09 | Info Disclose | FLE session secret memory extraction | Double-ratchet; blast radius ≤ 1000 patches §6.4 |
| T-10 | Info Disclose | PII in trace_id | trace_id = CSPRNG 128-bit; no PII §10.1 |
| T-11 | Info Disclose | Cache-timing Kyber recovery | Constant-time Kyber decapsulation §6.2 |
| T-12 | DoS | Slow consumer cluster degradation | SCIP quarantine + eviction |
| T-13 | DoS | Flash reconnect storm | Exponential backoff with jitter; circuit breaker |
| T-14 | Elevation | Unsigned edge personalisation token | HMAC-SHA256 auth_hint; 30s TTL |
| T-15 | Info Disclose | ADC dict corruption silent delivery | CRC-32c on dict update; ADC_RESYNC on fail |
| T-16 | Elevation | SSRF via gRPC bridge | Upstream allowlist; RFC-1918 blocked §5.7 |
| T-17 | Tampering | Byzantine gossip RL token injection | Median-of-N aggregation §9.1 |
| T-18 | Info Disclose | SCIP score timing side-channel | 0–50 ms jitter on SCIP rate reduction |
| T-19 | DoS | HELLO amplification attack | Minimum HELLO byte floor; rate limiting §6.1 |
| T-20 | Tampering | EVENT replay window exhaustion | Sliding window with explicit eviction TTL |
| T-21 | DoS | Auth credential flood (HELLO spam) | Exponential backoff; IP block after 15 failures §6.1 |
| T-22 | Info Disclose | CLIENT_TELEMETRY device fingerprinting | DP noise ε=1.0; retention limits §6.7 |
| T-23 | Elevation | Compromised mTLS CA issues fake SVID | CA certificate pin in WELCOME §6.1 |
| T-24 | Tampering | PATCH injection via mTLS terminator | Session HMAC per BATCH_PATCH §6.5 |
| T-25 | Tampering | SPR training data poisoning | Per-tenant SPR corpus isolation |
| T-26 | Tampering | Offline fan-out merge exploit | CRDT-aware merge; ERROR 3025 for non-CRDT |
| T-27 | Info Disclose | Cross-zone residency violation | RESIDENCY_HINT enforcement; ERROR 3024 §9.8 |
| T-28 | Tampering | Quantum MAC forgery (HMAC-SHA256) | ML-DSA-65 mode available; REQUIRED for ENTERPRISE §6.5 |
| T-29 | DoS | Battery drain via telemetry forgery | EWMA confidence filter; anomaly detection §8.6 |
| T-30 | DoS | DRX desync via frame flooding | Per-session frame rate cap; excess frames dropped |
| T-31 | Tampering | Viewport starvation (forge empty hint) | security_critical annotation; VIEWPORT_HINT HMAC §6.6 |

## §7 — Resource Efficiency

### §7.1 Zero-Copy I/O Stack

The complete zero-copy chain: (1) kernel receives frame into io_uring registered fixed buffer; (2) parser accesses frame body via buf_token + buf_offset (no copy); (3) arena-packed tree is updated in-place using integer node indices; (4) diff fingerprints (xxHash3) read directly from arena node structs; (5) PATCH body encoded directly from arena into send buffer; (6) send coalescing batches N sessions' frames into a single io_uring SEND_ZC SQ entry (no writev per session). Result: zero application-level memcpy from kernel recv to PATCH send. Platform coverage: Linux (io_uring 5.19+), macOS/BSD (kqueue + MSG_ZEROCOPY), Windows (IOCP + WSARecvMsg pinned pages), Android (io_uring API 31+), iOS (kqueue).


| I/O Stage | v4.x | v5.0 | Mechanism |
| --- | --- | --- | --- |
| Kernel recv → parser | memcpy to app buffer | Zero-copy (buf_token) | io_uring RECV_ZC |
| Fragment reassembly | Copy to contiguous buf | scatter-gather iovec | §5.8 ZC reassembly |
| Diff fingerprint read | Field pointer chase | Arena index lookup | Arena-packed tree §7.2 |
| PATCH encode | Serialise from tree | Encode from arena | Direct arena read |
| Send to kernel | writev() per session | Batched SEND_ZC SQ | Send-side coalescing |
| Snapshot write | Serialise + write | copy_file_range/sendfile | Zero-copy page cache |

### §7.2 Arena-Packed Virtual Tree

Node layout: 28 bytes per node — {id:u32, type_tag:u16, parent_idx:u32, first_child:u32, next_sibling:u32, attr_offset:u32, fingerprint:u64}. Attrs in a separate contiguous arena with variable-length encoding. External node IDs are SipHash-1-3 permutations of internal indices, keyed by session_id (prevents tree size oracle attacks). Free nodes marked type_tag=0xFFFF; compacted at arena_compact(). For NANO devices with ≤ 256 nodes: u8 indices save 3 bytes/node (additional 12% RAM reduction).

### §7.3 SIMD Acceleration


| Operation | Scalar | SIMD | ISA Targets |
| --- | --- | --- | --- |
| CRC32c (ZC verify §7.1) | ~500 MB/s | ~7,500 MB/s | ARM: AArch64 CRC32 ext; x86: SSE4.2 _mm_crc32_u64; WASM: SIMD128 fallback |
| xxHash3 (diff fingerprint) | ~8 GB/s | ~25 GB/s | ARM: NEON 128-bit; x86: AVX2; auto-dispatched by xxHash3 library |
| HMAC-SHA256 (batch MAC) | ~400 MB/s | ~2,000 MB/s | ARMv8 SHA2 ext; x86: SHA-NI (Icelake+); SW fallback |
| zstd compress (ADC) | ~500 MB/s | ~1,500 MB/s | SSE4.2/AVX2 (built-in zstd); ARM NEON |

SIMD capability is detected at startup (x86: CPUID; ARM: AT_HWCAP / HWCAP_CRC32). lnwp.io.simd_enabled gauge reports active state. SIMD and scalar paths MUST produce bit-identical output (verified by conformance tests TS-01 and TS-42). Opcode dispatch ordering: PATCH (0x03) first, ACK (0x04) second, PING (0x06) third — with __builtin_expect(opcode == 0x03, 1) hints. Branch predictor stays on fast path > 99% of frames.

### §7.4 Viewport-Aware Diff Pruning

VIEWPORT_HINT (0x18) carries three node sets: visible_node_ids (Tier 0: full rate), tier1_node_ids (Tier 1: half rate, 1 viewport beyond edge), tier2_node_ids (Tier 2: tenth rate, 1–3 viewports). Tier 3 (> 3 viewports away): zero diffs; catch-up PATCH delivered on re-entry to Tier 2. The hint is HMAC-signed (8-byte truncated HMAC-SHA256) to prevent forgery. Nodes with security_critical=true are always Tier 0 regardless of distance. For fan-out groups: server uses union of Tier 0 sets across all member devices. Result for 10K-node tree, 200 visible: 98% diff CPU reduction.

### §7.5 Energy Efficiency Stack


| Mechanism | Battery Impact | Specification |
| --- | --- | --- |
| DRX-aligned TX | ~50% fewer radio wakeups | tick_max_ms auto-set to drx_cycle_ms − 5 ms. drx_cycle_ms from CLIENT_TELEMETRY or server-inferred via EWMA autocorrelation (§7.5.1). Delivery jittered ±20% to prevent fingerprinting. |
| Power Profiles | ~3× battery at POWER_SAVE | POWER_PROFILE (0x17) applies server-side based on battery_state + screen_state + RSSI from CLIENT_TELEMETRY. ULTRA_LOW: 2 patches/s, 30s tick, no ratchet, no ADC. Profile delivery jittered 0–200 ms. |
| SESSION_SLEEP | < 0.1%/hr background | Server accumulates state as a single tree diff. Wake: one BATCH_PATCH (not N individual patches). BATCH_PATCH size padded to 5 buckets to prevent state-volatility inference. |
| Coalesced PING | ~15× fewer wakeups/session | Broadcast SESSION_MULTIPLEX DATA (logical_session_id=0xFFFFFFFF) serves all 256 multiplexed sessions with one PING/PONG. Reserved ID rejected on ATTACH (ERROR 3023). |
| Ratchet persistence | Zero re-handshakes on reboot | 48-byte epoch record persisted to NVS/Keychain/tmpfs. Recovered epoch presented in HELLO; server skips RATCHET_DESYNCED check. |
| GC coordination | ~15% shorter GC pauses | lnwp_register_gc_notifier() trusted at init time only. GC_ABOUT_TO_START suspends diff workers. Max pause honored: max_gc_pause_ms (default 500 ms); auto-resume after. |

#### §7.5.1 Predictive DRX Estimation

Server infers DRX cycle from EWMA of observed inter-frame arrival times + autocorrelation peak detection (peak at lag τ > 0.7 → infer drx_cycle ≈ τ). drx_confidence gauge (0.0–1.0): < 0.3 → disable alignment; use standard adaptive tick. Client-reported drx_cycle_ms takes priority when available and < 60 s stale. Both paths use ±20% jitter.

### §7.6 Numeric Delta Encoding

DELTA_ENCODING is a per-attribute schema annotation. Wire encoding: zigzag LEB128 delta from last sent value. Scale factor for float fields (e.g. scale_factor=100 for 2 decimal places). Reset on RESYNC or INITIAL_STREAM_CHUNK. Overflow guard: if delta > ±2^30, send full value with delta_overflow flag. For T2+ sensitivity fields: constant-length encoding (padded to max_varint_bytes for declared field range) to prevent magnitude side-channel. T3 FLE fields: DELTA_ENCODING prohibited.


| Field Type | Full Value | Typical Delta | Wire Reduction |
| --- | --- | --- | --- |
| f64 (price) | 8 bytes | 1–3 bytes | ~75% |
| i32 (counter) | 4 bytes | 1 byte | ~75% |
| u32 (seq no.) | 4 bytes | 1 byte | ~75% |
| f32 (%) | 4 bytes | 1–2 bytes | ~60% |

## §8 — Scalability & Distribution

### §8.1 Session State Topology


| Tier | Session Store | Max Sessions/Cluster | Notes |
| --- | --- | --- | --- |
| Starter | Single Redis | ~50K | Single-node; SCIP local; NUMA binding; ZC I/O |
| Growth | Redis Sentinel | ~500K | Gossip fan-out=2; per-tenant quotas; ratchet state in Redis |
| Scale | Redis Cluster 6+ | ~5M | Adaptive gossip; Schema CAS §8.5; multi-tenant QoS §8.6 |
| Hyperscale | DragonflyDB | ~50M+ | Full adaptive gossip; fan-out group affinity; sharded ratchet state |

### §8.2 QoS & Per-Tenant Resource Accounting


| Tier | CPU Share | Session Cap | Burst | Eviction Priority |
| --- | --- | --- | --- | --- |
| T0 Reserved | 40% | 50K | 2× for 5 s | Last evicted on BROWNOUT |
| T1 Premium | 30% | 20K | 2× for 5 s | Evicted after T2/T3 |
| T2 Standard | 20% | 5K | 1.5× for 5 s | Evicted before T0/T1 |
| T3 Trial | 10% | 500 | None | Evicted first on BROWNOUT |

Token buckets per dimension: CPU tokens, session slots, patch tokens. Admission queue: max 32 items, 50 ms timeout for T2/T3. T3 throttled first during BROWNOUT. Per-tenant quotas gossip-synced across regions within gossip convergence time (< 50 ms). ERROR 3012 on budget exceeded with budget_reset_ms in the error payload.

### §8.3 Session Fan-Out

One server-side component tree serves N devices (up to max_fanout_members, default 32; hard cap 256). Fan-out group leader elected via Raft (scoped to home region). Raft quorum = instances holding ≥ 1 member session. Pre-vote extension: candidate checks quorum reachability before incrementing term (prevents split-brain under symmetric partition). Raft log: SHA3-256 Merkle chain per entry (tamper-evident); snapshot compaction at 10K entries or 7 days. Cross-region relay: home server → per-region relay pool (≥ 2 nodes per region); relay applies per-member FLE encryption locally. Adaptive group sizing: grows when patch_rate < 20/s AND consistency window p99 < 20 ms; shrinks when patch_rate > 150/s.


| §8.3 Fan-Out Key Properties |
| --- |
| Fan-out saves render CPU proportional to (1 − 1/group_size). At group_size=4: 75% render CPU reduction for those sessions.<br>PATCH_SHARE_TOKEN: co-located devices (same IP + multiplex connection) can retrieve PATCH bytes via local IPC instead of network. IPC authentication: OS process identity (Android Binder UID; Linux SO_PEERCRED; iOS entitlements). share_token: 128-bit CSPRNG (not sequential).<br>Offline conflict resolution for fan-out groups: CRDT-aware merge using op-based CRDT model. Concurrent set-register tiebreak: session_id lexicographic order. Non-CRDT conflicts: ERROR 3025 CONFLICT_UNRESOLVABLE. |

### §8.4 Schema Management

Schema IDs use URN format: lnwp:tenant:{tenant_id}:schema:{name}:{version}. CAS token = Raft log index (u64). Push requires tenant JWT + CAS token. Schema compatibility matrix: {schema_version, min_app_version, max_app_version, active, sunset_after_sessions}. Multiple concurrent schema versions per tenant. Schema CAS protects against concurrent push races; three-way merge CLI for conflict resolution. Schema changes logged to WORM audit.

### §8.5 Cross-Region Active-Active


| Component | Consistency | v5.0 Enhancement |
| --- | --- | --- |
| Session state | Eventual; RPO < 1 s | Read-replica routing for compliance queries; 1 s max staleness |
| Schema versions | Strong (Raft CAS) | Per-tenant namespaced; compatibility matrix; sunset policy |
| Fan-out group state | Strong in home region | Raft-backed; Merkle audit; snapshot compaction; pre-vote extension |
| Rate-limit tokens | Eventual; < 50 ms convergence | Median-of-N Byzantine-tolerant gossip; T-17 mitigated |
| Tenant quota state | Eventual; gossip-synced | Redis per-tenant bucket; gossip ring sync |
| ADC dictionaries | Eventual; < 10 s lag | Per-(tenant, schema) corpus; LRU eviction (age/count/zero-sessions/memory) |
| Ratchet epoch | Strong in home region | Persisted to platform storage; survives soft reboot |

### §8.6 BROWNOUT & Cluster Cascade Protection

BROWNOUT mode (opcode 0x21) provides a graceful intermediate state between fully operational and circuit-breaker-open. Server suspends render(); serves last committed cached patches; PING/PONG continues. BROWNOUT entry jittered 0–200 ms (prevents timing behavioral fingerprint). Cluster circuit breaker: > 30% instances in BROWNOUT → ERROR 3011 for new sessions (no redistribution); > 50% → BROWNOUT_PASSIVE cluster-wide; > 80% → CLUSTER_EMERGENCY (page operator). CB lifts at < 20% for 60 consecutive seconds.

### §8.7 Autoscaling Integration


| Orchestrator | Scale Metric | Fan-Out Affinity |
| --- | --- | --- |
| Kubernetes HPA | lnwp_sessions_per_instance (target: 4000 = 80% of 5000 cap) via Prometheus adapter | Pod topologySpreadConstraints + lnwp.dev/fanout-group-{id} label; PodDisruptionBudget maxUnavailable=1 |
| KEDA | Multi-trigger: sessions/instance + CPU utilisation + BROWNOUT rate | Session-affinity scaler; new instances inherit group membership from scaled-down instances |
| Nomad | Job count driven by lnwp_sessions telemetry | Nomad group_constraint: co-locate fan-out group sessions on same Nomad node |

Normative sizing formula: N_deploy = ceil( S / Cap × (1 − f × (1 − 1/F)) × (1 − 0.3×c) × 1.3 ). Where S=peak sessions, Cap=5000, F=avg fan-out group size, f=fan-out session fraction, c=CDP fraction. Example: S=50K, F=2, f=0.3, c=0.1 → 11 instances.

### §8.8 Multi-Cluster Federation

Each cluster publishes a federation manifest at /.well-known/lnwp/federation.json (HTTPS; pulled every 60 s). HELLO with federation_target_cluster=X is forwarded via inter-cluster FORWARD. Schema federation: schemas with federation_scope=cluster push to shared registry; consuming clusters pull on demand. Failover: CLUSTER_EMERGENCY triggers federation manifest unavailability flag; new sessions route to backup cluster via TRANSPORT_MIGRATE. Data residency constraint: federation routing MUST respect session residency_zone; routing to out-of-zone cluster returns ERROR 3024.

### §8.9 Data Residency

RESIDENCY_HINT (0x24): zone_id (IANA region), residency_class (0=informational, 1=MUST, 2=MUST-and-audit), law_reference. Enforcement: Redis keys, PATCH content, §10.2 logs — all zone-constrained for class=1 sessions. Cross-zone relay receives only session_id+seq (no PATCH body). PATCH field redaction annotation (redact_boundary) for PCI segment boundaries: fields replaced with constant sentinel before crossing annotated network segment. ERROR 3024 on violation; session terminated before any cross-zone write.

## §9 — Observability

### §9.1 E2E Latency Attribution

Total latency = T_net_in + T_parse + T_diff + T_encode + T_net_out + T_decode + T_render. Each component measured: T_net_in from EVENT.submitted_at vs server recv; T_parse from lnwp.io.frame_parse_ns_p99; T_diff from diff worker timing; T_encode from encode benchmark; T_net_out from server emit vs CLIENT_TELEMETRY report; T_decode and T_render from CLIENT_TELEMETRY. Attribution accuracy target: ±10% of directly measured value. pprof export includes e2e_attribution section.


| SLO Breach Trigger | Attribution Threshold | Action |
| --- | --- | --- |
| T_net_in > 20 ms p99 | > 25% of total | Network routing; investigate CDN/QUIC path |
| T_diff > 0.4 µs p99 | > 5% of total | Diff regression; check NUMA binding §7; VIEWPORT_HINT coverage |
| T_decode > 500 µs p99 | > 30% of total | Client bottleneck; check CLIENT_TELEMETRY; CDP tier mismatch |
| T_render > 5 ms p99 | > 50% of total | Render pipeline; debug with DEBUG_TREE §9.4 |

### §9.2 Structured Operational Logging

All operational events use JSON-LD schema (context: https://schema.lnwp.dev/v5.0/log-context.jsonld). Every entry: @type, timestamp (ISO 8601 nanosecond), trace_id (W3C), session_id, tenant_id, server_id, level, message (no PII), data (event-specific), chain_hash (SHA3-256 Merkle chain). Fan-out events reference group_trace_id as parent span. 10 normative event types: SessionConnect, SessionDisconnect, FanoutJoin, FanoutLeaderElect, RatchetStep, BrownoutTransition, ConfigReload, SchemaChange, AuthFailure, IntegrityMacFailure. Metric federation: Prometheus remote_write (15 s), OTLP push (60 s), Prometheus federation, or pull /metrics at port 9090.

### §9.3 Continuous Profiling

HTTPS GET /debug/pprof/lnwp: CPU (100 Hz), heap (10 Hz), mutex contention, goroutine, block I/O. Profile samples annotated with trace_id. Aggregate profile endpoint: /debug/pprof/lnwp/aggregate?trace_id=X — merges profiles across all server instances for one session's lifecycle. Intel RAPL (server) and Android Batterystats (client) integration for energy profiling.

### §9.4 Developer Debug Protocol

DEBUG_TREE: full virtual tree snapshot alongside PATCH in debug sessions (dev_mode=true only). Schema: patch_seq, schema_version, tree_json_len, tree_json (T3 values redacted as <REDACTED_T3>). Gated by: (a) lnwp.dev_mode=true AND (b) debug_session token in HELLO. Incompatible with SESSION_FANOUT. Forbidden in production.

### §9.5 Alert Routing & Error Budget

Per-tenant alert routing: pagerduty/opsgenie/webhook/email/slack, escalation chain, escalation_delay_s. Maintenance window suppression: time-bounded (max 48 h), audit-logged, chaos experiment auto-suppression. Error budget (30-day): session availability 99.99% = 4.3 min; p99 < 10 ms = 1% error fraction = 7.2 hr. Burn-rate alerts: > 14.4× in 1 h → PAGE + deploy freeze; > 6× in 6 h → ticket; > 3× in 24 h → review. Deployment freeze: any P0 SLO burn > 14.4× for > 5 min; or > 80% availability budget consumed.

### §9.6 Synthetic Monitoring


| Test | Schedule | Pass Condition |
| --- | --- | --- |
| ST-01 E2E Latency | every 30 s | Full HELLO→PATCH round-trip p99 < 10 ms |
| ST-02 SSR Fast-Path | every 60 s | First PATCH after WELCOME < 50 ms |
| ST-03 PQC Handshake | every 5 min | Kyber-1024 KEM < 5 ms p99 |
| ST-04 ADC Compression | every 5 min | Ratio > 50% on test corpus |
| ST-05 BROWNOUT Recovery | daily | BROWNOUT → EXIT → CONNECTED < 30 s p99 |
| ST-06 CT Log Freshness | every 15 min | CT log entry for latest release < 60 min old |
| ST-07 Ratchet Step | every 10 min | Ratchet step round-trip < 1 ms p99 |
| ST-08 Schema CAS Round | every 30 min | CAS push → all clients migrated < 30 s |
| ST-09 A11y Extension | every 10 min | Every PATCH on a11y_capable server has a11y block for role-bearing nodes |
| ST-10 RTL Locale Switch | every 30 min | LOCALE_HINT RTL → PATCH < 80 ms p99; focus_order inverted |
| ST-11 Session Multiplex | every 30 min | 256-session multiplex attach < 5 ms p99; isolated backpressure |
| ST-12 Initial Stream | every 15 min | 5000-node tree first-byte < 50 ms p99 |
| ST-13 Energy Efficiency | daily | patches/joule > 50K on mobile reference device §11.4 |
| ST-14 Viewport Pruning | daily | Diff CPU reduction > 75% for 1K-node tree, 100 visible |

## §10 — Operations

### §10.1 SLA Definitions


| Metric | Target | Alert | Energy Gate |
| --- | --- | --- | --- |
| Patch latency p50 | < 4 ms | > 15 ms | No |
| Patch latency p99 | < 10 ms | > 30 ms | No |
| Event round-trip p99 | < 20 ms | > 60 ms | No |
| Frame parse p99 | < 80 ns | > 500 ns | No |
| Diff p99 (200-node, 4 core) | < 0.4 µs | > 3 µs | No |
| P0 frame delivery p99 | < 500 ms | > 800 ms | No |
| Session availability | 99.99% | < 99.5% | No |
| ADC compression ratio | > 50% | < 35% | No |
| SCIP quarantine rate | < 1% | > 3% | No |
| SPR hit+partial rate | > 75% | < 40% | No |
| BROWNOUT duration p99 | < 30 s | > 60 s | No |
| Ratchet step p99 | < 1 ms | > 5 ms | No |
| Fan-out consistency intra-region | < 50 ms | > 100 ms | No |
| Fan-out consistency cross-region | < 120 ms | > 250 ms | No |
| Config reload latency p99 | < 500 ms | > 2 s | No |
| Raft election p99 | < 2 s | > 5 s | No |
| PATCH MAC verify p99 | < 50 µs | > 200 µs | No |
| Initial state first-byte p99 | < 50 ms | > 200 ms | No |
| Credential refresh p99 | < 100 ms | > 300 ms | No |
| Federated route p99 | < 200 ms | > 500 ms | No |
| mTLS handshake p99 | < 200 ms | > 500 ms | No |
| WebTransport handshake p99 | < 80 ms | > 200 ms | No |
| LOCALE_HINT render p99 | < 80 ms | > 200 ms | No |
| CDP-L1/NANO patch p99 | < 500 ms | > 1 s | No |
| DRX alignment confidence | > 0.5 | < 0.3 | No |
| Offline conflict resolution p99 | < 30 s | > 60 s | No |
| Energy: patches per joule | > 50K/J | < 20K/J | YES — blocks deploy |
| Energy: background battery/hr | < 0.1%/hr | > 0.5%/hr | YES — blocks deploy |
| Energy: radio wakeups/min idle | < 4/min | > 15/min | YES — blocks deploy |
| Energy: server W/M sessions | < 6 W/M | > 15 W/M | YES — blocks deploy |
| Energy: NANO active current | < 12 mA | > 25 mA | YES — blocks deploy (NANO only) |

### §10.2 Deployment Pipeline (22 Stages)


| Stage | Action | Block On Fail? |
| --- | --- | --- |
| 01. Validate | lnwp validate --strict (zero errors, zero warnings) | Yes |
| 02. Conformance | lnwp validate --conformance (TS-01–TS-53, applicable tier) | Yes |
| 03. Security gate | lnwp validate --security (TS-46–TS-53 adversarial) | Yes |
| 04. Schema CAS | lnwp schema push --cas --dry-run (no conflicts) | Yes |
| 05. Schema push | lnwp schema push --cas (CAS committed, clients migrated) | Rollback |
| 06. ADC validate | lnwp adc validate --sample 1000 (ratio > 50%) | Yes |
| 07. PQC smoke | lnwp pqc smoke --sessions 100 (handshakes < 5 ms p99) | Yes |
| 08. SCIP baseline | lnwp scip baseline --duration 60s (quarantine < 0.5%) | Yes |
| 09. Ratchet smoke | lnwp ratchet smoke --epochs 5 (steps < 1 ms p99) | Yes |
| 10. QoS validation | lnwp qos validate --tenants all (budgets ±5%) | Yes |
| 11. mTLS smoke | lnwp mtls smoke --certs all (< 200 ms p99) | Yes |
| 12. WT probe | lnwp webtransport probe --sessions 50 (< 80 ms p99) | Warn |
| 13. EB check | lnwp slo budget check --window 30d (no burn > 5×) | Yes if critical |
| 14. NUMA probe | lnwp numa probe --cores all (cross-NUMA < 5%) | Warn |
| 15. Integrity smoke | lnwp integrity smoke --sessions 100 (MAC < 50 µs p99) | Yes |
| 16. Config smoke | lnwp config reload --dry-run --verify (< 500 ms dissemination) | Yes |
| 17. Fan-out smoke | lnwp fanout leader smoke --groups 10 (election < 2 s p99) | Yes |
| 18. Multiplex smoke | lnwp multiplex smoke --sessions 100 (attach < 5 ms p99) | Yes |
| 19. Stream smoke | lnwp initial-stream smoke --tree-nodes 5000 (first-byte < 50 ms) | Yes |
| 20. Residency probe | lnwp residency probe --zones all (no cross-zone for pinned sessions) | Yes |
| 21. Energy gate | lnwp energy benchmark --profile NORMAL (> 50K patches/J) | Yes |
| 22. Canary→Full | 5% → 10% → 25% → 50% → 100%; 30 min post-deploy watch | Auto-rollback |

### §10.3 Chaos Engineering Catalogue (27 Experiments)


| ID | Name | Pass Criteria (abbreviated) |
| --- | --- | --- |
| CE-01–CE-10 | Core chaos (ACCC, CQ, ADC, FPQ, SCIP, gRPC, RL, Redis) | Existing; refer to prior versions for full criteria |
| CE-11 | TCP Silent Drop | RESUME < 2 s; no data loss |
| CE-12 | Server Crash | Fan-out leader election < 2 s; session recovers |
| CE-13 | BROWNOUT Cascade | CB fires at 30%; ERROR 3011 for new sessions; CB lifts < 20% |
| CE-14 | Component Error Amplif. | CB opens < 5 s; cached patches served; no cluster amplification |
| CE-15 | Fan-Out Flood | 100 devices in group; all receive same PATCH within 50 ms; no divergence |
| CE-16 | Redis Bit-Rot | CRC32c detects; RESYNC < 2 s; no silent corruption |
| CE-17 | ZC Buffer Corrupt | CRC32c drops frame; RESYNC; no crash; no data loss |
| CE-18 | Fan-Out Split-Brain | Raft election < 2 s; zero divergence; FANOUT_SUSPENDED < 500 ms |
| CE-19 | SPR Poisoning | T3 tenant data never crosses boundary; victim SPR unaffected ±5% |
| CE-20 | Raft Log Corruption | Merkle chain detects < 500 ms; re-election; corrupt entries compacted |
| CE-21 | SESSION_SLEEP storm | Wake BATCH_PATCH bounded by full tree size; padded to correct bucket |
| CE-22 | VIEWPORT_HINT empty | security_critical nodes always patched; non-critical deferred; no blind spot |
| CE-23 | DRX desync flood | Rate limiting contains frame flood; DRX alignment quality degrades gracefully |
| CE-24 | Credential expiry | ERROR 2005 issued within grace window; CREDENTIAL_REFRESH restores session |
| CE-25 | Residency violation | ERROR 3024 before first cross-zone write; session terminated |
| CE-26 | Snapshot hash forgery | Server falls back to full INITIAL_STREAM_CHUNK on HMAC mismatch; no delta served |
| CE-27 | GC_PAUSE_HINT hijack | Untrusted source call rejected; runtime-registered sources honored; 500 ms max pause |

## §11 — SDK, Compliance & Governance

### §11.1 SDK Interface Definition

The normative WIT interface (https://sdk.lnwp.dev/v5.0/lnwp-component.wit) and proto3 mapping define all lifecycle methods. Mount signature: mount(id: component-id, session: session-id) → result<_, string>. Render: render(id) → tree-node (pure; no side effects). handle-event: handle-event(id, e: event) → result<_, string>. handle-sync: handle-sync(id, op: list<u8>) → sync-result. handle-grpc: handle-grpc(id, frame: list<u8>) → list<u8>. speculate: speculate(id) → option<tuple<tree-node, confidence>>. on-brownout: on-brownout(id, cause, entering: bool). on-fanout-conflict: on-fanout-conflict(id, resolution: conflict-result). unmount: unmount(id) → result<_, string>. liblnwp transport WIT: https://sdk.lnwp.dev/v5.0/liblnwp-transport.wit.

### §11.2 Accessibility Transport

PATCH a11y extension (a11y_present flag in frame flags byte). When set, a structured a11y block follows the visual diff body: a11y_version (u8), a11y_len (u16), role_updates (ARIA role + label per node), focus_order (u16[] tab order), live_regions (live_mode: off/polite/assertive, atomic), alt_text_updates. RTL locale: focus_order MUST be inverted. Servers with a11y_capable=true in WELCOME MUST populate a11y block for every PATCH touching role-bearing nodes. Clients with a11y_required=true in HELLO MUST disconnect if a11y block is absent when a11y_capable was negotiated.

### §11.3 Compliance Mapping


| Framework | Key Controls | LNWP Sections |
| --- | --- | --- |
| FedRAMP High | PQC Kyber-1024; ML-DSA-65 batch integrity; WORM audit log; CT log; Threat Model | §6.2, §6.5, §9.2, §11.5 |
| HIPAA | FLE T3 encryption; audit log retention; access controls; mTLS | §6.3, §9.2, §6.1 |
| PCI DSS v4 | TLS 1.3; JWT channel binding; rate limiting; supply chain SLSA L3; PATCH field redaction | §3, §6.1, §8.9 |
| SOC 2 Type II | SCIP isolation; chaos engineering; SLA §10.1; SLSA L3; error budget | §8.6, §10.3, §10.1 |
| NIST FIPS 203/204 | Kyber-1024; ML-DSA-65; constant-time operations; ct-grind gate | §6.2, §6.5 |
| GDPR Art. 44 | Data residency enforcement; DP noise ε=1.0; retention limits; right to erasure | §8.9, §6.7 |
| India DPDP §16 | Data localisation; residency enforcement; cross-border restriction | §8.9 |
| China PIPL §38 | Cross-border data restrictions; residency zone binding | §8.9 |

### §11.4 Spec Governance

LNWP-SemVer (§0.3 criteria): MAJOR = any MUST→MUST NOT, frame meaning change, TLS version increase, PQC algorithm change. MINOR = new section, new opcode, new MUST for new features, new conformance tier. PATCH = clarifications, typos, cross-references. Wire compatibility: any MINOR/PATCH client works with any later server in the same MAJOR version. Opcode deprecation lifecycle: Active → Deprecated (min 2 MAJOR versions) → Sunset (1 MAJOR) → Removed. Multi-language CI: lnwp-conformance-runner (Zig) + conformance_shim IPC; JUnit XML with test_id, tier, result, latency_ms, failure_reason, energy_certified_by; public registry at https://conformance.lnwp.dev/registry. Energy benchmarks MUST be certified by independent lab (list at conformance.lnwp.dev/energy-labs). CVE process: security@lnwp.dev (PGP); 48 h acknowledge; CVSS-tiered fix windows (Critical 30 d, High 60 d, Medium/Low 90 d); advisory to CT log §11.5 with advisory_type=security_advisory.

### §11.5 Supply Chain & Certificate Transparency

SLSA Level 3: reproducible builds; HSM-signed releases; CycloneDX SBOM per release. SDK CT log: SHA3-256 Merkle tree per release; root published to DNSSEC TXT at lnwp-ct.lnwp.dev; submission required within 60 min of release tag; deployment Stage 1 verifies CT inclusion. Entries signed with same HSM key as SLSA provenance. Pre-release builds submitted with pre_release=true. Monitor API: GET /v1/entries?after={log_index}; consistency proof endpoint.

### §11.6 Plugin & Extension API

Experimental opcode range: 0xF0–0xFE. Plugin registration: plugin_id (reverse-DNS, max 128 chars), opcode (one of 0xF0–0xFE; registry enforces uniqueness), fpq_priority (1–7; 0 reserved for protocol), wit_url (WIT interface file), min_lnwp_version, capability_flag (HELLO field name). Plugins declare opcodes in plugin_opcodes (u8[]) in HELLO; server validates against registry. Plugin conformance CI: lnwp-conformance-runner --plugin {plugin_id} fetches vectors from wit_url; plugin_results[] in JUnit XML report. Alternative encodings: CBOR (encoding=1, RFC 8949), MessagePack (encoding=2); same field mapping as binary; NANO/BASE: binary only.

## §12 — Quick Reference

### §12.1 What Breaks and How It Recovers


| Failure | Detected By | Recovery | Data Loss |
| --- | --- | --- | --- |
| TCP silent drop | PING timeout 5 s | RESUME < 2 s | None |
| Server crash | Connection close | Reconnect; fan-out leader election < 2 s | None |
| Redis Sentinel failover | Raft missed heartbeat | Fan-out leader election < 2 s; FANOUT_SUSPENDED | None |
| BROWNOUT cascade > 30% | Gossip brownout_pct | ERROR 3011; no redistribution; CB lifts < 20% | None |
| Network partition (Raft) | Pre-vote check fails | No spurious election; quorum preserved | None |
| Config param change | Operator action | RUNTIME_CONFIG hot reload < 500 ms | None (0 sessions dropped) |
| PATCH integrity MAC fail | ERROR 3022 | Session terminated; re-authenticate | None (injection prevented) |
| JWT expired mid-session | ERROR 2005 | CREDENTIAL_REFRESH < 100 ms | None |
| Viewport hint forgery attempt | HMAC check / security_critical | Security-critical nodes always patched; forgery blocked | None |
| IPC share_token theft attempt | OS process identity check | ERROR 4004; token rejected | None |
| Snapshot hash forgery | HMAC-SHA256 mismatch | Full INITIAL_STREAM_CHUNK fallback | None |
| Battery critical | CLIENT_TELEMETRY battery_state | ULTRA_LOW profile; 2 patches/s; 30 s tick | None |
| App backgrounded | SESSION_SLEEP | Server accumulates delta; one BATCH_PATCH on wake | None |
| Offline fan-out conflict | CRDT merge on reconnect | CRDT-aware deterministic merge < 30 s | None (CRDT ops) |
| Data residency violation | RESIDENCY_HINT enforcement | ERROR 3024; session terminated pre-write | None |
| Raft log corrupt | Merkle chain mismatch | CE-20: leader re-election; corrupt compacted | None |
| Cluster failover (federation) | CLUSTER_EMERGENCY | TRANSPORT_MIGRATE to backup cluster | None |

### §12.2 Conformance Test Suites (53 total)


| Range | Category | Suites |
| --- | --- | --- |
| TS-01–TS-07 | Core protocol | HELLO/WELCOME, PATCH seq, EVENT, PING/PONG, RESYNC, FRAGMENT, BACKPRESSURE |
| TS-08–TS-09 | Flow control | ACCC, CQ-Signal |
| TS-10–TS-16 | Advanced features | ADC, gRPC, SSR, FLE T3, CRDT, Multi-region, PQC |
| TS-17–TS-22 | Reliability | FPQ, CB, SCIP+diag, Cross-region RL, W3C trace, SPR |
| TS-23–TS-27 | v4.0 features | ADC cross-session, FLE ratchet, BATCH_PATCH drain, Schema CAS, QoS |
| TS-28–TS-32 | v4.1 features | WebTransport, SESSION_FANOUT, CDP-L1, CLIENT_TELEMETRY, mTLS |
| TS-33–TS-36 | v4.2 features | Fan-out leader election, hot config reload, i18n locale, integrity MAC |
| TS-37–TS-41 | v4.3 features | Session multiplex, initial stream, SPR isolation, data residency, ML-DSA |
| TS-42–TS-45 | v4.4 features | DRX alignment, viewport pruning, delta encoding, RESUME_FROM_SNAPSHOT |
| TS-46–TS-53 | Security (adversarial) | VIEWPORT_HINT forgery, broadcast ID, IPC token entropy, snapshot HMAC, node ID permutation, GC pause max, POWER_PROFILE jitter, constant-length delta |


| §12.2 Conformance Notes |
| --- |
| TS-46–TS-53 (security tests) use adversarial vectors distributed to registered implementations only. Request access at https://conformance.lnwp.dev/security.<br>Conformance tiers: NANO must pass TS-01–TS-07, TS-30. BASE must pass TS-01–TS-09, TS-30. FULL must pass TS-01–TS-45. ENTERPRISE must pass all 53 suites.<br>Energy certification (for energy SLO conformance claims) must be performed by a lab registered at conformance.lnwp.dev/energy-labs. Self-reported results are INFORMATIONAL only. |

### §12.3 Wire Totals — v5.0


| v5.0 Protocol Totals |
| --- |
| FRAME: 4-byte header (opcode + flags + u16 len). PATCH body: 18 bytes minimum for single-node attribute change.<br>PARSE: < 80 ns p99 (SIMD CRC32c + 4-byte header; ARM CRC32 instruction = 7,500 MB/s).<br>DIFF: < 0.4 µs p99 (Chase-Lev lock-free deque; NUMA-bound workers; hedged dispatch; VIEWPORT_HINT prunes 98% for large trees).<br>ENCODE: < 1 µs p99 (arena-packed tree → direct arena read; zero-copy encode path).<br>I/O: 0 memcpy (io_uring RECV_ZC recv; scatter-gather ZC fragment reassembly; send-side SEND_ZC coalescing; copy_file_range snapshot write).<br>WIRE EFFICIENCY: 75% reduction for numeric-heavy fields (DELTA_ENCODING zigzag varint). 99.5% reduction for brief-disconnect reconnect (RESUME_FROM_SNAPSHOT delta).<br>SECURITY: 31 STRIDE threats fully mitigated · ML-DSA-65 quantum-safe batch integrity · HMAC per-batch · 0 open CVEs · Formal CVE process.<br>ENERGY: < 0.1%/hr background battery · < 0.9%/hr active at 100 patches/s · < 6 W/M server sessions · < 12 mA NANO active current.<br>SCALE: Fan-out (1 render() → N devices; Raft-protected; cross-region) · 50M+ sessions (DragonflyDB) · 256 sessions/connection (multiplexing) · 22-stage pipeline.<br>CONFORMANCE: 53 test suites · 27 chaos experiments · 14 synthetic tests · 31 SLOs (5 energy-gated) · 4 conformance tiers (NANO/BASE/FULL/ENTERPRISE). |
