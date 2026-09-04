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
