# Protocol conformance

The JSON Lines fixtures give every Murmur SDK the same observable behavior.
They use the ProtoJSON field and enum names defined in `spec/`, contain only
synthetic data, and must never contain recordings, conversations, credentials,
or real identifiers.

## Manifest and runner contract

`manifest.json` is the only fixture index. `manifestVersion` identifies this
manifest shape; `protocol` identifies the current wire contract. Every member
of `fixtureSets` supplies a unique `name`, an explicit `message`, a path, line
count, and either `expect: accept` or `expect: reject`.

Reject sets also declare a stable `reason`, a `rejection` phase (`parse` or
`order`), and optionally `rejectLine` (one-based, default 1). For parse
rejections every line at or after `rejectLine` must fail parsing. For order
rejections every line must parse, lines before `rejectLine` must strictly
increase, and each line from `rejectLine` onward must fail only that ordering
predicate. Reason values are `missing-payload`, `ambiguous-oneof`,
`missing-session-command`, `ambiguous-session-command`, `invalid-enum`,
`sequence-order`, `invalid-uint64`, `unsupported-protocol-major`,
`invalid-protocol-version`, and `invalid-audio-frame`.

Accept sets may declare slash-separated `unknownFields`. A runner parses each
line, computes its ordering key (`sequence` for RuntimeEvent and AudioFrame,
`requestSequence` for SessionControl, none for VoiceSource), and checks the
expected result. Accepted values are serialized and compared structurally with
the input after every declared unknown path has been removed from both values.
Parse success is asserted separately. Failure messages use
`<sdk> · <set> · line N · <reason or error>` and round-trip failures end in
`· round-trip`.

Unknown additive fields beside a known oneof arm are ignored for a supported
major. A message whose only arm is unknown is rejected because it has no known
arm. Accepted fixtures are canonical: default-valued fields are omitted.
An explicitly present default-valued known field in a checked-in fixture must preserve its presence when round-tripped.

## Lifecycle scenarios

`scenarioSets` freeze the capture-coordinator lifecycle that every SDK must
reproduce. `scenarioManifestVersion` identifies this shape independently of
`manifestVersion`, and the message-per-line `fixtureSets` runners ignore it.
Each scenario is one JSON Lines file of ordered steps. A step is an object with
exactly one key, the step kind, whose value is an object of arguments.

Input steps drive the in-process connector and provider boundary, which
`RuntimeEvent` cannot express. A runner wires a coordinator to a scriptable
connector and provider, applies each input step, and settles asynchronous work
before the next step:

| Step | Arguments | Meaning |
| --- | --- | --- |
| `start` | `mode` (`CAPTURE_MODE_TAP_TO_SPEAK`, `CAPTURE_MODE_HOLD_TO_TALK`, `CAPTURE_MODE_HANDS_FREE`) | Call `start` for the synthetic source |
| `release`, `finalize`, `stop` | none | Call the coordinator API |
| `connect_ok` | none | Complete the pending connect with an idle session whose `start` succeeds |
| `connect_fail` | `error` `{code, message, retryable}` | Fail the pending connect |
| `provider_open_ok` | none | Complete the pending provider open |
| `provider_open_fail` | `error` | Fail the pending provider open |
| `frame` | `seq`, optional `silent` | Emit one 10 ms frame from the newest session, the README sine wave or silence |
| `partial`, `final`, `rejected` | `text` | Deliver a transcript chunk from the newest provider session |
| `readiness` | `live` | Deliver a provider readiness event |
| `amplitude` | `value` in [0, 1] | Deliver a provider amplitude event |
| `provider_closed` | `expected` | Deliver a closed event; when `expected`, also acknowledge a pending finalize |
| `provider_failed` | `error` | Deliver a provider failure event |
| `provider_flushed` | none | Acknowledge the pending warm-gate flush |
| `advanceMs` | `ms` | Advance the scenario clock; the only clock directive |

Every pending connect, open, finalize, or flush must exist when a step
completes or fails it, and a `frame` step must find a listening session.

`emit` steps are the outputs. Each carries one `murmur.v1` RuntimeEvent that
the coordinator must emit next, with no Dart-only fields. A runner fails when
an emitted event differs from the next `emit`, when an event arrives before a
non-`emit` step, or when events remain after the last step. The emit contract
pins the envelope so every SDK matches byte for byte:

- `sequence` is 1-based per session and increments by exactly one per emitted
  event; a superseded session keeps its own counter and a new generation
  starts a new session.
- `monotonicTimeUs` is the scenario clock at emit. The clock starts at 0 and
  moves only on `advanceMs`.
- Session identifiers are `session-1`, `session-2`, and so on, one per
  generation.
- The coordinator writes `live`, `retryable`, and `text` even when they hold
  default values, because consumers read them as booleans and text; `metadata`
  is omitted when empty.
- The first transition of every generation is `SESSION_STATE_IDLE` to
  `SESSION_STATE_STARTING`. No `STOPPED` to `IDLE` event is manufactured.

Each manifest entry names the scenario, its path, `steps` count,
`providerCapabilities` (`partialTranscripts`, `warmGate`, `gracefulFinalize`,
`realAudioReadiness`, `amplitude`, `rejectedFinal`), and the `utterances` the
coordinator must deliver, in order, by the end of the scenario. All scenarios
share `scenarioTimeoutsMs` for the startup, endpoint, finalize, shutdown, and
warm-hold waits. The repository checker validates every `emit` body with the
same rules as the message fixtures, the step vocabulary, and the emit contract.

## Compatibility profile

| Concern | Wire (protobuf / ProtoJSON) | Murmur profile (fixture-enforced) | SDK policy |
| --- | --- | --- | --- |
| uint64 | ProtoJSON parses integer numbers or strings, including exponent forms | Serialize decimal strings; string input is ASCII digits only and at most 2^64-1 | SDKs may additionally accept exact, non-negative JSON integers; in-memory type is language-specific |
| uint32 | JSON integer number | Number must be an integer, not a boolean, from 0 through 2^32-1 | Shared helper and language-specific error type |
| protocol | Version fields are uint32 | Major must equal 1; every non-negative uint32 minor is accepted | Envelope parsers always enforce support |
| oneof | One selected arm | Exactly one known arm is required | Error representation is language-specific |
| unknown fields | Rejected by ProtoJSON parsers by default | Ignored within a supported major | SDKs need not preserve them |
| enums | ProtoJSON accepts names and integers | Validated fields accept known string names only; integers are rejected | Unvalidated opaque bodies remain unchanged |
| bytes | Base64 string | Standard or URL-safe base64 grammar below | SDKs keep the encoded string and need not decode bytes |
| ordering | Application concern | Keys in an accepted set must strictly increase | No sequence-tracking API is required |
| defaults | Usually emitted implicitly by binary encoding | Omit defaults in canonical JSON; VoiceSource omits empty capabilities and metadata | SDKs may always emit required envelope fields |

Validated RuntimeEvent fields are transcript `kind` and `text`, audio-level
`amplitude` in [0, 1], and session-state `previous` and `current`. SessionControl
validates optional input-gate booleans, optional stop reason, and optional start
mode, source, and requested format. AudioFrame validates its format and payload.
VoiceSource requires non-empty identifiers and display names, a known transport,
known capabilities, and string-to-string metadata. Intent, confirmation,
action-result, error, and all other body data remain opaque and are echoed.

Base64 validation counts trailing `=` characters as padding (at most two).
After stripping padding, a length remainder of one modulo four is invalid. If
padding is present it must equal `(4 - remainder) % 4`, and total length must be
divisible by four. The unpadded content must use either the standard alphabet
or the URL-safe alphabet, never a mixture. The empty string is valid.

## Synthetic audio

Both audio fixtures are 16,000 Hz, mono, `AUDIO_ENCODING_PCM_S16LE`, and 10 ms:
160 samples and 320 bytes. The first is a 1 kHz sine wave with sample `n` equal
to `round(8000 * sin(2*pi*1000*n/16000))`, encoded little-endian signed int16.
The second is 320 zero bytes. Recreate the first payload with:

```sh
python3 -c "import base64,math,struct; print(base64.b64encode(b''.join(struct.pack('<h',round(8000*math.sin(2*math.pi*1000*n/16000))) for n in range(160))).decode())"
```

The repository checker decodes fixture base64 and verifies PCM byte length;
SDK parsers validate only the base64 grammar and format metadata.
