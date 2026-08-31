# Murmur protocol specification

The files under `proto/murmur/v1` are Murmur's language-neutral source of
truth. Applications, connectors, providers, SDKs, sidecars, and remote agents
exchange these concepts without depending on Flutter or Dart.

The first stable namespace is `murmur.v1`. Backward-compatible fields may be
added within v1. Removing fields, changing field meanings, reusing field
numbers, or changing enum values requires a new protocol namespace.

## Encoding

- Protocol Buffers are canonical for binary and generated SDK use.
- ProtoJSON is canonical for JSON transports and conformance fixtures.
- Audio payloads use protobuf `bytes`; ProtoJSON represents them as base64.
- Event order uses a session-scoped `sequence`, not wall-clock time.
- `monotonic_time_us` measures elapsed time on the producing host and must not
  be compared across machines or sessions.

The protocol does not prescribe an in-process API or transport. It can cross a
WebSocket, gRPC stream, local socket, stdio sidecar, FFI boundary, or remain
inside one process.

## Validate

With `protoc` installed, run:

```bash
make check-protocol
```

The command compiles every schema into a temporary descriptor set without
writing generated code into the repository.
