# LNWP v5.0 Zig Implementation Notes

## Source

Generated from:

`/Users/gaurav/Downloads/LNWP-v5.0-Complete-Specification.docx`

An extracted Markdown copy is available at:

`LNWP-v5.0-Complete-Specification.extracted.md`

## Canonical Mappings Used Here

The spec defines the universal encoding rules and many frame fields, but not every frame body has a complete byte layout. This project uses the following mappings so the code is executable and testable:

- `HELLO`: fields are encoded in the exact order of §4.1. Optional fixed-size hashes are encoded as all-zero bytes when absent. Optional strings use empty strings. `plugin_opcodes` uses the spec byte-array encoding (`u32 length + bytes`).
- `EVENT`: `nonce[16]`, `submitted_at_us:u64`, then `payload` as a byte array.
- `ERROR`: `error_code:u16`, then `message` as a spec string.
- `BATCH_PATCH`: `batch_seq:u32`, `patch_count:u8`, then each patch as a byte array. `security.batchPatchMacForEncodedBody` signs `opcode || batch_seq || body_after_batch_seq`, so the sequence number is covered exactly once.
- `VIEWPORT_HINT`: each node set is `u16 count` followed by `u32 node_id[]`; the optional truncated HMAC tag is appended as 8 bytes.
- `FRAGMENT`: body is `original_opcode:u8`, `original_flags:u8`, `original_length:u32`, `fragment_index:u16`, `total_fragments:u16`, then raw chunk bytes.

## Notable Spec Inconsistency

§7.2 says the virtual tree node layout is 28 bytes:

`{id:u32, type_tag:u16, parent_idx:u32, first_child:u32, next_sibling:u32, attr_offset:u32, fingerprint:u64}`

Those listed fields add up to 30 bytes. `src/tree.zig` implements the listed fields exactly as a packed 30-byte node and exposes both `listed_node_wire_size` and `spec_claimed_node_size` so downstream code can make the discrepancy explicit.

## Security Boundary

The project includes HMAC-SHA256, CRC32c, constant-time comparison, snapshot hash helpers, and viewport tags. It does not bundle Kyber-1024, ML-DSA-65, TLS, JWT, Redis, Raft, or QUIC. Those are deliberately provider/runtime integrations because the spec requires validated or platform-specific implementations for production conformance.
