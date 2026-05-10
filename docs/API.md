# LNWP API

Run:

```sh
zig build api --global-cache-dir .zig-global-cache -- --port 8080
```

OpenAPI:

```text
GET /openapi.json
```

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/v1/health` | API health check |
| GET | `/v1/version` | LNWP protocol version metadata |
| GET | `/v1/opcodes` | LNWP v5.0 opcode registry |
| POST | `/v1/frames/decode` | Decode a full hex-encoded LNWP frame |
| POST | `/v1/frames/encode` | Encode a LNWP frame from opcode, flags, and body bytes |
| POST | `/v1/checksums/crc32c` | Compute CRC32c over hex bytes |
| POST | `/v1/security/snapshot-hash` | Compute RESUME_FROM_SNAPSHOT HMAC-SHA256 |
| POST | `/v1/security/batch-mac` | Compute BATCH_PATCH HMAC-SHA256 tag |

## Example

```sh
curl -sS -H 'content-type: application/json' \
  -d '{"hex":"060000080000000000000001"}' \
  http://127.0.0.1:8080/v1/frames/decode
```

Response:

```json
{
  "ok": true,
  "opcode": "ping",
  "opcode_byte": "0x06",
  "flags": 0,
  "length": 8,
  "body_hex": "0000000000000001",
  "consumed": 12
}
```
