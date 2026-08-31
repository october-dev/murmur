# Murmur agents

Agents let an approved intent reach a paired computer, server, or automation
host. They consume the same language-neutral protocol as apps and SDKs, so an
agent can be written in Rust, TypeScript, Python, Dart, or another language.

No executable agent ships yet. Before implementation, the protocol must define
pairing, authentication, revocation, replay protection, typed allowlisted
tools, confirmation, expiry, idempotency, cancellation, and audit behavior.
Raw transcript text and generated shell strings are never executable commands.

Track that design in GitHub issues #12 and #20.
