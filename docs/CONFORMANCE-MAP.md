# Conformance Map

This project is structured around the LNWP v5.0 conformance suites listed in §12.2.

| Suite Area | Covered By | Notes |
| --- | --- | --- |
| TS-01 HELLO/WELCOME | `messages.Hello`, `protocol.negotiateVersion` | HELLO has a canonical binary mapping documented in `IMPLEMENTATION-NOTES.md`. WELCOME fields are not fully specified in the DOCX, so this project leaves it to application code. |
| TS-02 PATCH seq | `messages.Ack`, `session.transition` | PATCH body is opaque because the spec states "ops array" but does not define the op bytecode. |
| TS-03 EVENT | `messages.Event` | Encodes nonce, submitted timestamp, and opaque payload. |
| TS-04 PING/PONG | `messages.Ping`, `frame` | Same body for both opcodes. |
| TS-05 RESYNC | `opcodes`, `session` | Opcode/state support; application resync policy remains external. |
| TS-06 FRAGMENT | `fragment`, `frame` | Uses the project canonical fragment body layout. |
| TS-07 BACKPRESSURE | `opcodes`, `errors` | Opcode/error registry support. Rate policy is runtime-specific. |
| TS-36 Integrity MAC | `security.batchPatchMacForEncodedBody` | HMAC-SHA256 mode implemented. ML-DSA mode is provider integration. |
| TS-37 Session multiplex | `protocol.broadcast_logical_session_id`, `opcodes` | Multiplex attach payloads are not fully specified in the DOCX. |
| TS-40 Data residency | `messages.Hello`, `opcodes`, `errors` | Enforcement storage/relay policy remains runtime-specific. |
| TS-42 CRC/SIMD equivalence | `crc32c` | Scalar CRC32c check value included. SIMD dispatch is future runtime optimization. |
| TS-43 Viewport pruning | `messages.encodeViewportHintBody`, `security.viewportHintTag` | Node-set encoding and truncated HMAC tag implemented. |
| TS-44 Delta encoding | `codec.zigZagEncode`, `codec.encodeUleb128` | Constant-length sensitive-field padding is schema-layer work. |
| TS-45 Resume from snapshot | `messages.ResumeFromSnapshot`, `security.snapshotHash` | HMAC-SHA256 snapshot hash implemented. |

Production ENTERPRISE conformance additionally depends on validated PQC/ML-DSA providers, transport runtimes, JWT/mTLS verification, Raft/Redis state, and observability systems.
