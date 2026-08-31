# Voice Connector Authoring Guide

A **connector** adapts a specific voice source — a wearable, a phone microphone, a
headset, a desktop agent, a network stream — to Murmur's `murmur.v1` protocol.
Applications consume normalized voice events from connectors without any knowledge
of the underlying transport. Connectors are implemented in any language, may run
in-process, behind FFI, or as a local or remote service, and are defined by their
manifest and the behaviors it claims.

## Relationship to murmur.v1

`murmur.v1` is the versioned public contract. It defines the types of events a
connector emits (audio frames, transcripts, intents, action results) and the types
of commands a consumer can send (start capture, stop capture, interrupt). A
connector is correct when it produces events that conform to `murmur.v1` and reacts
correctly to the commands the runtime sends.

The protocol is the product boundary. SDKs, connectors, apps, and agents are
replaceable implementations; the protocol is not.

## Connector manifest

Every connector ships a `connector.json` rooted in its implementation directory.
The manifest is validated against `spec/connector-manifest.schema.json`. All
fields are required unless marked optional.

### Fields

| Field | Why it matters |
| --- | --- |
| `id` | Unique reverse-DNS identifier. Distinguishes this connector from all others in multi-connector deployments. |
| `name` | Human-readable name shown in UIs and logs. |
| `version` | [SemVer](https://semver.org). Consumers can range-check to avoid regressions. |
| `protocolMajor` | Declares compatibility with `murmur.v1` major version N. Increment only when the protocol breaks. |
| `status` | `experimental` — not yet stable; `supported` — actively maintained; `deprecated` — will be removed. |
| `transports` | Physical or logical transports the connector uses (`bluetooth-le`, `usb`, `wifi`, `websocket`, etc.). |
| `capabilities` | Subset of `["discovery", "connection", "capture", "playback", "control"]` that this connector actually implements. |
| `implementation.language` | Implementation language (dart, rust, typescript, python, etc.). |
| `implementation.sdk` | SDK or library the connector uses internally. |
| `implementation.path` | Path within the repository to the connector's implementation. |
| `platforms` | OS/hardware platforms this connector runs on (`android`, `ios`, `linux`, `macos`, `windows`, `web`). |
| `licenses.implementation` | License of the connector code. |
| `licenses.protocolReference` | License of any upstream protocol documentation or reference implementation adapted into this connector. |
| *(optional) `permissions` | Array of OS-level permissions required (e.g. `["BLUETOOTH_SCAN", "RECORD_AUDIO"]). |
| *(optional) `description` | One-paragraph description of what this connector does. |
| *(optional) `homepage` | Link to the connector's documentation or repository. |

### Minimal manifest

```json
{
  "$schema": "../../spec/connector-manifest.schema.json",
  "id": "com.example.my-connector",
  "name": "My Voice Source",
  "version": "0.1.0",
  "protocolMajor": 1,
  "status": "experimental",
  "transports": ["bluetooth-le"],
  "capabilities": ["discovery", "connection", "capture"],
  "implementation": {
    "language": "dart",
    "sdk": "flutter_reactive_ble",
    "path": "connectors/my-connector"
  },
  "platforms": ["android", "ios"],
  "licenses": {
    "implementation": "Apache-2.0",
    "protocolReference": "MIT"
  }
}
```

## Connector lifecycle

```
┌────────────┐   discover    ┌────────────┐   connect    ┌────────────┐
│  IDLE      │ ────────────► │ DISCOVERED │ ────────────► │ CONNECTING │
└────────────┘               └────────────┘              └────────────┘
                                                                │
                                                    ┌───────────▼──────────┐
                                                    │     CONNECTED        │
                                                    │  capabilities checked│
                                                    │  permissions verified│
                                                    └───────────┬──────────┘
                                                                │  start capture
                                                    ┌───────────▼──────────┐
                                                    │     CAPTURING        │
                                                    │  audio frames flow   │
                                                    └───────────┬──────────┘
                                                                │  stop / error
                                                    ┌───────────▼──────────┐
                                                    │     DISCONNECTING     │
                                                    │  graceful shutdown   │
                                                    └───────────┬──────────┘
                                                                │
                                                    ┌───────────▼──────────┐
                                                    │     IDLE              │
                                                    └───────────────────────┘
```

### 1. Discovery

The connector advertises the voice sources it can reach. A BLE connector scans
for advertising packets; a USB connector enumerates serial numbers; a network
connector queries a broadcast or DNS-SD service. The connector emits
`murmur.v1` source-discovered events for every source it finds. Discovery may
be passive (continuous background scan) or active (triggered by a consumer
request). Sources that disappear emit a source-lost event.

Discovery behavior must be documented, including whether it is persistent or
ephemeral and what triggers a new scan.

### 2. Connection

A consumer selects a discovered source and requests a connection. The connector
allocates any transport state, opens the link, and verifies that the source is
still reachable. If connection fails, the connector emits a connection-error
event with a human-readable code and returns to IDLE. If the connector does not
support a requested capability (e.g., playback), it must reject the connection
request with an error rather than silently degrading.

The connector transitions to the CONNECTED state and exposes its capability set.
Consumers check that required capabilities are present before proceeding.

### 3. Capture session

A consumer starts a capture session. The connector begins emitting audio frames
and any associated metadata. A session has a clean lifecycle: start → frames →
(stop | interrupt | error) → cleanup. Nested or concurrent sessions are not
supported by `murmur.v1`; a connector that receives a start while already
capturing must reject the new request.

### 4. Cleanup

A consumer stops capture or an error occurs. The connector flushes any pending
audio (tail frames), tears down the transport link, releases resources, and
returns to IDLE. A connector that crashes or loses its transport without a
clean shutdown must emit a disconnection event so the runtime can recover.

## Capabilities

A capability is a named behavior that a connector may or may not implement.
`murmur.v1` defines the following capabilities:

| Capability | Meaning |
| --- | --- |
| `discovery` | The connector can enumerate available voice sources. |
| `connection` | The connector can establish and maintain a link to a source. |
| `capture` | The connector can capture and emit audio frames. |
| `playback` | The connector can play audio on the voice source (e.g., voice feedback). |
| `control` | The connector can send control messages to the source (e.g., button events). |

A connector declares the subset it implements in `connector.json`. A
connector that declares `discovery` but not `capture` can enumerate sources but
cannot capture audio. This is intentional: some integrations are read-only
monitors.

A connector must not claim a capability it does not implement. A consumer may
check the manifest and refuse to use a connector that lacks required
capabilities.

## Permissions

A connector that needs OS-level permissions to function (Bluetooth scanning,
microphone access, local network access) must declare them in the manifest
under `permissions`. Permissions are expressed as platform-native strings:
`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `RECORD_AUDIO`, `NEARBY_WIFI_DEVICES`,
etc.

The connector documentation must explain what each permission is used for and
when it is requested (on install, on first use, or on each session).

**Privacy note:** Permissions that access the microphone or capture audio from
a device are privacy-sensitive. The connector author should document what
audio leaves the device, where it goes, and whether it is stored or processed
by a third party.

## Audio formats

Connectors must produce audio frames in the following normalized format unless
the consumer agrees otherwise:

| Parameter | Value |
| --- | --- |
| Encoding | 16-bit signed linear PCM (LE) |
| Sample rate | 16 000 Hz |
| Channels | 1 (mono) |
| Frame size | 512 samples (= 32 ms) or 480 samples (= 30 ms) |

A connector that produces a different format must convert to one of the above
before emitting frames. The connector manifest should note if conversion is
applied and what the source format was.

Audio frames carry a `sourceTimestamp` (see below) and are emitted as
`AudioFrameEvent` messages defined in `spec/proto/murmur/v1/audio.proto`.

## Timestamps

Every audio frame carries two timestamps:

- **`sourceTimestamp`** — the moment the audio was captured at the hardware,
  as a `google.protobuf.Timestamp` (UTC wall-clock). This is the authoritative
  timing for speech recognition and must reflect actual capture order. A
  connector that buffers frames before forwarding must adjust timestamps
  accordingly.

- **` monotonicSequenceNumber`** — a monotonically increasing integer assigned
  by the connector. It is used to detect gaps, duplicates, and reorderings.
  If a frame with sequence N is followed by a frame with sequence N+2, the
  frame with N+1 was dropped.

A connector must not emit frames with identical timestamps from two different
captures; concurrent sessions must be serialized by the connector.

## Backpressure

A consumer that is slow to process frames may apply backpressure. When the
connector's outbound buffer exceeds a configured high-water mark, the connector
must:

1. Stop adding new frames to the buffer (do not drop frames silently).
2. Signal the capture pipeline to pause at the source if possible.
3. If the source cannot pause (e.g., BLE streaming), apply flow control at the
   transport level if the transport supports it; otherwise document that
   backpressure cannot be applied and that frames may be dropped.

The connector emits a `bufferHigh` event when entering the backpressure state
and a `bufferNormal` event when the consumer drains the buffer.

A connector that does not implement backpressure must document this limitation.

## Interruption

A consumer may interrupt an active capture session at any time. The connector
must:

1. Accept the interrupt command without waiting for a transport acknowledgment.
2. Flush any tail frames in its own buffer.
3. Stop the source capture at the hardware level if possible.
4. Transition to the DISCONNECTING state and perform cleanup.
5. Emit a `sessionInterrupted` event before transitioning.

A connector must not block the interrupt command on any I/O. If the connector
is in a state where interrupt is not safe (e.g., mid-flush during a prior
interrupt), it must still acknowledge the new interrupt and process it as soon
as the prior interrupt completes.

## Cleanup

Graceful shutdown means:

- Stopping capture at the hardware level.
- Waiting for any in-flight audio frames to be emitted (bounded by a timeout,
  typically 500 ms).
- Closing the transport link.
- Releasing OS resources (file handles, memory, threads).
- Emitting a `disconnected` event with `graceful: true`.

If graceful cleanup fails within the timeout, the connector must force-close
and emit a `disconnected` event with `graceful: false`. The connector then
transitions to IDLE.

On process termination without graceful cleanup (crash, SIGKILL), the connector
must emit nothing; the runtime detects the missing heartbeats and treats it as a
non-graceful disconnection.

## Testing

### Conformance suite

Every connector must pass the shared `murmur.v1` conformance fixtures. The
fixtures define expected event sequences and timing for discovery, connection,
capture, interruption, and cleanup. A new connector provides fixtures for its
specific transport; the shared fixtures cover the lifecycle that is transport-
agnostic.

Run the conformance suite:

```bash
make check-conformance
```

### Fixtures

A **fixture** is a recorded or synthetic event sequence that validates a
connector's behavior without requiring physical hardware. Fixtures are stored
in `conformance/fixtures/<connector-id>/`.

Recommended fixture types:

| Fixture | Purpose |
| --- | --- |
| `discovery.json` | Source-advertised and source-lost events over a 10-second scan. |
| `connection.yaml` | Connection establishment and capability negotiation. |
| `capture.yaml` | 30 seconds of audio frames with known timestamps and sequence numbers. |
| `interruption.yaml` | Interrupt during mid-capture; verify flush and terminal state. |
| `reconnect.yaml` | Simulated link loss and recovery; verify graceful reconnect. |

Fixtures that contain audio must use synthetic audio (e.g., generated sine
waves) unless the recording has documented consent and a compatible license.
See CONTRIBUTING.md § "Use synthetic audio in tests unless a fixture has clear
consent and licensing."

### Automated tests

A connector implementation should include:

- **Unit tests** for state-machine transitions, timestamp assignment, and
  backpressure logic using mock transports.
- **Integration tests** that run against the conformance fixtures.
- **Property tests** that verify sequence-number monotonicity, timestamp
  ordering, and buffer bounds.

### Physical validation

Fixtures validate the protocol contract. Physical validation proves that the
connector works with real hardware. The connector author must document:

- Physical devices used and their firmware versions.
- Test environment (distance, interference, battery state).
- Pass/fail criteria for each capability.
- Known hardware-specific behaviors or limitations.

Physical validation is required for connectors with status `supported` and
recommended for `experimental`.

## Protocol provenance and license checklist

Before submitting a connector, verify:

- [ ] The upstream protocol (if adapted from a reference implementation or
      specification) is documented with a link to the source.
- [ ] The upstream license is GPL-compatible if the connector is GPL, and
      Apache-2.0/MIT/BSD-compatible if the connector is permissively licensed.
- [ ] Any protocol documentation or reference text adapted into this connector
      is attributed in `licenses.protocolReference` and THIRD_PARTY_NOTICES.md.
- [ ] The `implementation` license covers all code in the connector directory.
- [ ] No third-party binary blobs or closed-source components are included.
- [ ] Any trademarked branding from the upstream source is not used in a way
      that implies endorsement.

For license compatibility questions, open a GitHub Discussion before building
a connector that may have a licensing conflict.

## Privacy implications

A connector author must document, in the connector's README or this guide:

- What audio data leaves the device and over which transport.
- Whether audio is stored, buffered, or logged, and for how long.
- Any third parties that receive audio and their data-handling policies.
- How users can inspect or revoke access.
- Any known privacy-sensitive edge cases (e.g., background capture, shared
  devices, recordings left on storage).

This documentation should be reviewed before marking a connector `supported`.

## Example: minimal connector with synthetic data

Below is **pseudocode** — not a real implementation. It demonstrates the
lifecycle and manifest a connector must implement. The connector discovers
sources from a static list, connects to one, and emits synthetic 16 kHz PCM
audio frames for 30 seconds.

```python
# connectors/example/connector.py  (pseudocode)

import time
import struct
import threading
from murmur.v1 import (
    AudioFrameEvent,
    SourceDiscoveredEvent,
    SourceLostEvent,
    ConnectionEstablishedEvent,
    ConnectionErrorEvent,
    CaptureStartedEvent,
    CaptureStoppedEvent,
    DisconnectedEvent,
    SessionInterruptedEvent,
)

class SyntheticConnector:
    # Matches the manifest:
    manifest_id = "dev.murmur.connector.synthetic"
    manifest_version = "0.1.0"
    protocol_major = 1
    status = "experimental"
    transports = ["synthetic"]
    capabilities = ["discovery", "connection", "capture"]
    platforms = ["linux", "macos", "windows"]
    implementation_language = "python"

    def __init__(self, event_sink):
        self.sink = event_sink  # the murmur runtime event bus
        self.sources = [
            {"id": "src-001", "name": "Synthetic Mic A"},
            {"id": "src-002", "name": "Synthetic Mic B"},
        ]
        self.state = "idle"  # idle, discovered, connecting, connected, capturing, disconnecting

    # ── Discovery ────────────────────────────────────────────────────────────

    def start_discovery(self):
        """Scan for sources and emit SourceDiscoveredEvent for each."""
        assert self.state == "idle", f"Cannot discover from {self.state}"
        for source in self.sources:
            self.sink.put(SourceDiscoveredEvent(
                sourceId=source["id"],
                name=source["name"],
                transport="synthetic",
                capabilities=self.capabilities,
            ))
        self.state = "discovered"

    def stop_discovery(self):
        self.state = "idle"

    # ── Connection ───────────────────────────────────────────────────────────

    def connect(self, source_id):
        assert self.state == "discovered", f"Cannot connect from {self.state}"
        self.state = "connecting"
        source = next((s for s in self.sources if s["id"] == source_id), None)
        if source is None:
            self.sink.put(ConnectionErrorEvent(
                sourceId=source_id,
                code="SOURCE_NOT_FOUND",
                message=f"No source with id {source_id}",
            ))
            self.state = "idle"
            return
        self.active_source = source
        self.state = "connected"
        self.sink.put(ConnectionEstablishedEvent(
            sourceId=source_id,
            capabilities=self.capabilities,
            negotiatedFormat={"encoding": "pcm_s16le", "sampleRate": 16000, "channels": 1},
        ))

    # ── Capture ─────────────────────────────────────────────────────────────

    def start_capture(self):
        assert self.state == "connected", f"Cannot capture from {self.state}"
        self.state = "capturing"
        self.sink.put(CaptureStartedEvent(sourceId=self.active_source["id"]))
        self._capture_thread = threading.Thread(target=self._emit_synthetic_frames)
        self._capture_thread.start()

    def _emit_synthetic_frames(self):
        """Emit 30 seconds of synthetic PCM frames at 16 kHz mono."""
        sample_rate = 16000
        frame_size = 512  # samples
        duration_s = 30
        frame_interval = frame_size / sample_rate  # 32 ms

        total_frames = int(duration_s / frame_interval)
        seq = 0
        start_wall = time.time()

        for i in range(total_frames):
            if self.state != "capturing":
                break  # interrupted

            # Generate a synthetic audio frame (silent PCM).
            pcm = bytes(frame_size * 2)  # 16-bit silence
            emit_at = start_wall + (i * frame_interval)
            sleep_delta = emit_at - time.time()
            if sleep_delta > 0:
                time.sleep(sleep_delta)

            self.sink.put(AudioFrameEvent(
                sourceId=self.active_source["id"],
                # Source timestamp: when this chunk was conceptually captured.
                sourceTimestamp=emit_at,
                # Monotonic sequence number for gap detection.
                monotonicSequenceNumber=seq,
                encoding="pcm_s16le",
                sampleRate=sample_rate,
                channels=1,
                data=pcm,
            ))
            seq += 1

        # All frames emitted; signal natural stop.
        self._do_stop()

    def stop_capture(self):
        """Consumer-initiated stop."""
        assert self.state == "capturing", f"Cannot stop from {self.state}"
        self._do_stop()

    def _do_stop(self):
        self.state = "disconnecting"
        self.sink.put(CaptureStoppedEvent(
            sourceId=self.active_source["id"],
            graceful=True,
        ))
        self._cleanup()

    def interrupt(self):
        """Consumer-initiated interruption during capture."""
        if self.state != "capturing":
            return  # no-op
        self.state = "disconnecting"
        self.sink.put(SessionInterruptedEvent(sourceId=self.active_source["id"]))
        self._cleanup()

    # ── Cleanup ───────────────────────────────────────────────────────────────

    def _cleanup(self):
        if getattr(self, "_capture_thread", None) and self._capture_thread.is_alive():
            self._capture_thread.join(timeout=0.5)
        self.state = "idle"
        self.sink.put(DisconnectedEvent(sourceId=self.active_source["id"], graceful=True))

    # ── Manifest ─────────────────────────────────────────────────────────────

    @staticmethod
    def manifest():
        return {
            "$schema": "../../spec/connector-manifest.schema.json",
            "id": SyntheticConnector.manifest_id,
            "name": "Synthetic",
            "version": SyntheticConnector.manifest_version,
            "protocolMajor": SyntheticConnector.protocol_major,
            "status": SyntheticConnector.status,
            "transports": SyntheticConnector.transports,
            "capabilities": SyntheticConnector.capabilities,
            "implementation": {
                "language": SyntheticConnector.implementation_language,
                "sdk": "murmur_python_sdk",
                "path": "connectors/example",
            },
            "platforms": SyntheticConnector.platforms,
            "licenses": {
                "implementation": "Apache-2.0",
                "protocolReference": "CC0-1.0",
            },
        }
```

This connector:

1. Emits `SourceDiscoveredEvent` for each static source during discovery.
2. Connects on consumer request and emits capability and format negotiation.
3. Emits 30 seconds of synthetic PCM frames with correct `sourceTimestamp` and
   `monotonicSequenceNumber`.
4. Handles consumer-initiated `stop_capture` and `interrupt` cleanly.
5. Returns to IDLE and emits `DisconnectedEvent` on all exit paths.
6. Declares all lifecycle capabilities in its manifest.

## Proposal template

Use the connector proposal issue template at
`.github/ISSUE_TEMPLATE/connector-proposal.md` to propose a new connector.
The template collects the information needed for a maintainer to assess
protocol provenance, license compatibility, platform reach, and privacy
implications before work begins.

---

For questions not covered here, open a [GitHub
Discussion](https://github.com/october-dev/murmur/discussions) or reference
[docs/architecture.md](../architecture.md) and
[docs/voice-runtime.md](../voice-runtime.md).
