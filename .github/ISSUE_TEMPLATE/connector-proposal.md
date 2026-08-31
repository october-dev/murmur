<!--- ⚠️ This is the connector proposal template. Do not remove the YAML frontmatter. --->
---
name: Voice Connector Proposal
about: Propose a new voice source connector for Murmur
title: "[Connector] "
labels: ["connector", "proposal"]
assignees: ""
---

## Voice source

**What is the voice source?** Describe the device, platform, or service this
connector adapts (e.g., "Omi BLE wearable", "macOS system microphone", "USB
conference phone", "RTSP audio stream").

**What is the upstream project or protocol?** Link to any public specification,
reference firmware, SDK documentation, or open-source implementation this
connector is based on. If there is no public specification, describe the
reverse-engineering or observation process used.

## Platform and implementation

**Target platforms** — Which operating systems and architectures does this
connector run on? (e.g., Android, iOS, Linux, macOS, Windows, Web, or
cross-platform)

**Implementation language** — Which language would this connector be written in?
(e.g., Dart, Rust, TypeScript, Python, C++)

**Implementation path** — Where within the repository would this connector live?
(e.g., `connectors/omi`, `connectors/my-device`)

## Capabilities

Check the capabilities this connector will implement:

- [ ] **discovery** — Enumerate available voice sources
- [ ] **connection** — Establish and maintain a transport link
- [ ] **capture** — Emit audio frames to the runtime
- [ ] **playback** — Play audio on the voice source (optional)
- [ ] **control** — Send control messages to the source (optional)

**Any capabilities intentionally not supported?** (e.g., "This connector
does not support playback because the hardware has no speaker")

## Protocol and license

**Upstream protocol license** — What license does the upstream protocol or
reference implementation use? (e.g., MIT, Apache-2.0, BSD-3, proprietary)

**Implementation license** — What license will the connector code use?
(Confirm it is compatible with Apache-2.0)

**Provenance checklist:**

- [ ] Upstream protocol is documented with a public specification or
      documented reverse-engineering.
- [ ] Upstream license is identified and confirmed compatible.
- [ ] No binary blobs or closed-source components are required.
- [ ] Any adapted code or protocol text is attributed in the manifest's
      `licenses.protocolReference` field and in THIRD_PARTY_NOTICES.md.

## Hardware access and permissions

List the OS-level permissions required:

| Permission | Platform | When requested | Justification |
| --- | --- | --- | --- |
| (e.g. BLUETOOTH_SCAN) | Android | On first scan | Required to discover BLE voice sources |
| (e.g. Bluetooth) | iOS | On first scan | Required to discover nearby BLE devices |
| (e.g. RECORD_AUDIO) | All | On first capture | Required to access the microphone stream |
| | | | |

**Will audio leave the device?** If yes, describe what is sent, to where, and
by what path (e.g., "Audio is streamed over BLE to the host device; no audio
is stored by the connector").

**Known privacy implications:** (e.g., "This connector streams raw PCM to a
third-party transcription provider over HTTPS; see the provider's privacy
policy at <URL>")

## Audio format

| Parameter | Value |
| --- | --- |
| Source encoding | (e.g., Opus, SBC, raw PCM) |
| Source sample rate | (e.g., 8000, 16000, 44100 Hz) |
| Source channels | (e.g., 1 mono, 2 stereo) |
| Normalized output encoding | (e.g., PCM S16LE, always) |
| Normalized output sample rate | (e.g., 16000 Hz, always) |
| Normalized output channels | (e.g., 1 mono, always) |

Does the connector convert audio? If so, describe the conversion pipeline.
If not, confirm the native format already matches the normalized format.

## Lifecycle behaviors

**Discovery model:** Is discovery persistent (always scanning in background) or
ephemeral (scan only when the consumer requests it)?

**Reconnect behavior:** Does the connector automatically reconnect if the
transport link is lost? Describe the retry policy (e.g., exponential backoff,
max retries, permanent failure).

**Interruption handling:** Describe how the connector responds to an interrupt
command during active capture.

**Cleanup on unexpected disconnect:** Describe what happens if the transport
link is lost without a clean disconnect (e.g., does the connector emit
`DisconnectedEvent(graceful=false)`?).

## Testing plan

**Fixtures** — Will this connector provide conformance fixtures for the shared
test suite? (Required for `supported` status; recommended for `experimental`)

- [ ] `discovery.json` — Source discovery sequence
- [ ] `connection.yaml` — Connection establishment and capability negotiation
- [ ] `capture.yaml` — Audio frame sequence with timestamps and sequence numbers
- [ ] `interruption.yaml` — Interrupt mid-capture
- [ ] `reconnect.yaml` — Link loss and recovery

**Hardware validation** — List the physical devices and firmware versions this
connector has been tested against. (Required for `supported`; recommended for
`experimental`)

| Device | Firmware version | Platform | Result |
| --- | --- | --- | --- |
| | | | |

**Automated tests** — Describe the unit, integration, or property tests the
connector implementation will include.

## Status and roadmap

What is the proposed initial status for this connector?

- [ ] **experimental** — Functioning but not yet stable; API may change.
- [ ] **supported** — Actively maintained; suitable for general use.

If **experimental**, what milestones remain before it could be promoted to
**supported**?

## Related links

- Upstream protocol or specification:
- Reference implementation:
- Existing issues or prior art:
- Maintainer discussion (if any):
