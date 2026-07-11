# LNWP Zig

This is a self-contained Zig implementation project for the LNWP v5.0 protocol described in `LNWP-v5.0-Complete-Specification.docx`.

Why does it exist? Because I wanted to connect any mobile frontend (whether it is native apps, flutter, react native or cordova/capacitor/PWAs etc) with any backend logic without worrying about the compliance. This is an attempt to be compliant to almost all the global compliance. It includes the DB encryption layer (DB will be installed by the user) too while being very small in size and top-notch in functionality.

The repository focuses on the parts of the specification that are concrete at the wire and SDK boundary:

- 4-byte v5 frame header, flag validation, plugin opcode range, and reserved opcode handling
- Full opcode and error-code registries from the specification
- Big-endian fixed integers, UTF-8 strings, byte arrays, unsigned LEB128, and zigzag deltas
- HELLO, ACK, EVENT, PING/PONG, ERROR, RESUME, RESUME_FROM_SNAPSHOT, BATCH_PATCH, VIEWPORT_HINT, and FRAGMENT helpers
- HMAC-SHA256 batch integrity helpers, snapshot hashes, viewport truncated HMAC tags, and CRC32c
- Transport selection, session lifecycle transitions, and arena-packed virtual tree primitives
- REST API endpoints for frontend/backend access, with OpenAPI and JavaScript/TypeScript clients
- Unit tests that map to the core conformance areas in TS-01 through TS-07 plus selected security utilities

## Layouttra

```text
src/
  lnwp.zig        Public module barrel
  protocol.zig    Versions, tiers, capabilities, protocol constants
  opcodes.zig     Opcode registry, directions, FPQ priorities
  errors.zig      LNWP error code registry
  codec.zig       Binary encoding primitives
  frame.zig       Frame header and frame encode/decode
  messages.zig    Typed body helpers
  security.zig    HMAC/tag/hash utilities
  crc32c.zig      CRC32c Castagnoli checksum
  fragment.zig    Large-frame fragment body helpers
  transport.zig   Transport priority selection
  session.zig     Session state machine transitions
  tree.zig        Arena-packed node model
  api_server.zig  REST API server
clients/
  javascript/      Browser/Node fetch client
  typescript/      Typed client package source
docs/
  openapi.json     REST API specification
```

## Build

Install Zig, then run:

```sh
zig build test
zig build run -- opcodes
zig build run -- decode-hex 06000000
```

Validated locally with Zig 0.16.0. In this sandbox, use a project-local global cache:

```sh
zig build test --global-cache-dir .zig-global-cache
zig build --global-cache-dir .zig-global-cache
```

## API Server

Run the local API server:

```sh
zig build api --global-cache-dir .zig-global-cache -- --port 8080
```

Core endpoints:

```text
GET  /v1/health
GET  /v1/version
GET  /v1/opcodes
POST /v1/frames/decode
POST /v1/frames/encode
POST /v1/checksums/crc32c
POST /v1/security/snapshot-hash
POST /v1/security/batch-mac
GET  /openapi.json
```

Example:

```sh
curl -sS -H 'content-type: application/json' \
  -d '{"hex":"060000080000000000000001"}' \
  http://127.0.0.1:8080/v1/frames/decode
```

Frontend/browser access is available through `clients/javascript/lnwp-client.js`. A typed package skeleton is in `clients/typescript`.

## Spec Notes

The DOCX fully specifies the v5 frame header and encoding primitives, but some frame bodies are described by field names rather than by a byte-for-byte body map. For those, this project defines a conservative canonical binary mapping in `docs/IMPLEMENTATION-NOTES.md` and keeps those choices isolated in `src/messages.zig` and `src/fragment.zig`.

See `docs/CONFORMANCE-MAP.md` for how the modules map to the TS-01 through TS-53 suite areas.

Production FULL and ENTERPRISE conformance still requires a NIST-validated Kyber-1024 / ML-DSA-65 provider, TLS/QUIC transport integration, JWT validation, and deployment/runtime systems such as Redis/Raft/observability. This library provides the protocol core and extension points for those pieces.
