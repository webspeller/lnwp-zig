# Contributing

Thanks for helping improve LNWP Zig.

## Development

```sh
zig build test --global-cache-dir .zig-global-cache
zig build --global-cache-dir .zig-global-cache
zig build api --global-cache-dir .zig-global-cache -- --port 8080
```

Please keep protocol changes tied to the extracted specification or a documented extension note.

## Pull Requests

- Keep patches focused.
- Add tests for protocol wire changes.
- Update `docs/openapi.json` and `clients/typescript/src/index.ts` when API endpoints change.
- Run `zig fmt` before submitting.

## Security

Do not include real JWTs, session keys, tenant IDs, production traces, or private protocol vectors in issues or pull requests.
