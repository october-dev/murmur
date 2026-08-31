# Murmur connectors

A connector adapts a voice source to the Murmur protocol. Connectors may be
implemented in any language and may run in-process, behind FFI, or as a local or
remote service. Their public behavior is defined by `murmur.v1`, not by a UI
framework.

Each connector should publish a `connector.json` manifest containing:

- connector and implementation versions
- compatible Murmur protocol major version
- source transports and capabilities
- implementation language and SDK
- supported platforms
- code and protocol provenance licenses
- implementation and documentation locations

The initial Omi connector remains inside the Flutter reference app while its
audio path is being completed. Its manifest makes that limitation explicit and
allows a native, Rust, TypeScript, or other implementation to be added later
without changing host applications.

See [docs/connectors/guide.md](../docs/connectors/guide.md) for the full connector
authoring guide, including the lifecycle, capability model, manifest reference,
testing requirements, and privacy documentation.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the connector acceptance rules.
