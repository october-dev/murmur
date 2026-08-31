# Murmur SDKs

SDKs are adapters around the versioned protocol in `spec/`; none of them owns
the protocol. The Dart SDK is the first implementation used by the Flutter
reference app. TypeScript, Python, and Rust packages provide equivalent event
and source surfaces for desktop apps, servers, agents, research tools, and
native sidecars.

An SDK must pass the shared fixtures in `conformance/` before it can claim
compatibility. Generated protobuf bindings may be added inside an SDK, but
generated implementation details must not leak into connector or application
APIs.

| SDK | Intended environments | State |
| --- | --- | --- |
| Dart | Flutter and pure-Dart applications | Source and event model implemented |
| TypeScript | Node, Electron, React Native, and web | Event model implemented |
| Python | Research, automation, and AI services | Event model implemented |
| Rust | Native runtimes, sidecars, servers, and embedded hosts | Event model implemented |

The SDKs intentionally start small. Audio processing, BLE access, databases,
and model providers belong in separate packages built on these contracts.
