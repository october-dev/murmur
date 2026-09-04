use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;

const RUNTIME_ARMS: &[&str] = &[
    "sessionStateChanged",
    "captureReadiness",
    "audioLevel",
    "transcript",
    "error",
    "intentProposal",
    "confirmationRequest",
    "actionResult",
];
const SESSION_ARMS: &[&str] = &["start", "stop", "inputGate", "finalize"];
const TRANSCRIPT_KINDS: &[&str] = &[
    "TRANSCRIPT_KIND_UNSPECIFIED",
    "TRANSCRIPT_KIND_PARTIAL",
    "TRANSCRIPT_KIND_FINAL",
    "TRANSCRIPT_KIND_REJECTED",
];
const SESSION_STATES: &[&str] = &[
    "SESSION_STATE_UNSPECIFIED",
    "SESSION_STATE_IDLE",
    "SESSION_STATE_STARTING",
    "SESSION_STATE_LISTENING",
    "SESSION_STATE_WARM_MUTED",
    "SESSION_STATE_FINALIZING",
    "SESSION_STATE_STOPPED",
    "SESSION_STATE_ERROR",
];
const CAPTURE_MODES: &[&str] = &[
    "CAPTURE_MODE_UNSPECIFIED",
    "CAPTURE_MODE_TAP_TO_SPEAK",
    "CAPTURE_MODE_HOLD_TO_TALK",
    "CAPTURE_MODE_HANDS_FREE",
    "CAPTURE_MODE_WAKE_PHRASE",
];
const AUDIO_ENCODINGS: &[&str] = &[
    "AUDIO_ENCODING_PCM_S16LE",
    "AUDIO_ENCODING_PCM_F32LE",
    "AUDIO_ENCODING_OPUS",
];
const SOURCE_TRANSPORTS: &[&str] = &[
    "SOURCE_TRANSPORT_BLUETOOTH_LE",
    "SOURCE_TRANSPORT_LOCAL_AUDIO",
    "SOURCE_TRANSPORT_NETWORK",
    "SOURCE_TRANSPORT_FILE",
    "SOURCE_TRANSPORT_SYNTHETIC",
];
const SOURCE_CAPABILITIES: &[&str] = &[
    "SOURCE_CAPABILITY_LIVE_AUDIO",
    "SOURCE_CAPABILITY_STORED_AUDIO",
    "SOURCE_CAPABILITY_BATTERY",
    "SOURCE_CAPABILITY_HARDWARE_CONTROL",
    "SOURCE_CAPABILITY_OUTPUT_AUDIO",
    "SOURCE_CAPABILITY_BACKGROUND_CAPTURE",
    "SOURCE_CAPABILITY_INPUT_MUTE",
    "SOURCE_CAPABILITY_SPEAKER_VERIFICATION",
];

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolVersion {
    pub major: u32,
    pub minor: u32,
}

pub const CURRENT_PROTOCOL: ProtocolVersion = ProtocolVersion { major: 1, minor: 0 };

pub fn is_supported(protocol: ProtocolVersion) -> bool {
    protocol.major == CURRENT_PROTOCOL.major
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", try_from = "RawRuntimeEvent")]
pub struct RuntimeEvent {
    pub protocol: ProtocolVersion,
    pub session_id: String,
    #[serde(with = "uint64_string")]
    pub sequence: u64,
    #[serde(with = "uint64_string")]
    pub monotonic_time_us: u64,
    #[serde(flatten)]
    pub payload: RuntimePayload,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RuntimePayload {
    SessionStateChanged(Map<String, Value>),
    CaptureReadiness(Map<String, Value>),
    AudioLevel(Map<String, Value>),
    Transcript(Map<String, Value>),
    Error(Map<String, Value>),
    IntentProposal(Map<String, Value>),
    ConfirmationRequest(Map<String, Value>),
    ActionResult(Map<String, Value>),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawRuntimeEvent {
    protocol: ProtocolVersion,
    session_id: String,
    #[serde(with = "uint64_string")]
    sequence: u64,
    #[serde(with = "uint64_string")]
    monotonic_time_us: u64,
    #[serde(flatten)]
    remainder: Map<String, Value>,
}

impl TryFrom<RawRuntimeEvent> for RuntimeEvent {
    type Error = String;

    fn try_from(mut raw: RawRuntimeEvent) -> Result<Self, Self::Error> {
        validate_envelope(raw.protocol, &raw.session_id)?;
        let (arm, body) = take_exactly_one(&mut raw.remainder, RUNTIME_ARMS, "runtime payload")?;
        validate_runtime_payload(arm, &body)?;
        let payload = match arm {
            "sessionStateChanged" => RuntimePayload::SessionStateChanged(body),
            "captureReadiness" => RuntimePayload::CaptureReadiness(body),
            "audioLevel" => RuntimePayload::AudioLevel(body),
            "transcript" => RuntimePayload::Transcript(body),
            "error" => RuntimePayload::Error(body),
            "intentProposal" => RuntimePayload::IntentProposal(body),
            "confirmationRequest" => RuntimePayload::ConfirmationRequest(body),
            "actionResult" => RuntimePayload::ActionResult(body),
            _ => unreachable!(),
        };
        Ok(Self {
            protocol: raw.protocol,
            session_id: raw.session_id,
            sequence: raw.sequence,
            monotonic_time_us: raw.monotonic_time_us,
            payload,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", try_from = "RawSessionControl")]
pub struct SessionControl {
    pub protocol: ProtocolVersion,
    pub session_id: String,
    #[serde(with = "uint64_string")]
    pub request_sequence: u64,
    #[serde(flatten)]
    pub command: SessionCommand,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SessionCommand {
    Start(Map<String, Value>),
    Stop(Map<String, Value>),
    InputGate(Map<String, Value>),
    Finalize(Map<String, Value>),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawSessionControl {
    protocol: ProtocolVersion,
    session_id: String,
    #[serde(with = "uint64_string")]
    request_sequence: u64,
    #[serde(flatten)]
    remainder: Map<String, Value>,
}

impl TryFrom<RawSessionControl> for SessionControl {
    type Error = String;

    fn try_from(mut raw: RawSessionControl) -> Result<Self, Self::Error> {
        validate_envelope(raw.protocol, &raw.session_id)?;
        let (arm, body) = take_exactly_one(&mut raw.remainder, SESSION_ARMS, "session command")?;
        validate_session_body(arm, &body)?;
        let command = match arm {
            "start" => SessionCommand::Start(body),
            "stop" => SessionCommand::Stop(body),
            "inputGate" => SessionCommand::InputGate(body),
            "finalize" => SessionCommand::Finalize(body),
            _ => unreachable!(),
        };
        Ok(Self {
            protocol: raw.protocol,
            session_id: raw.session_id,
            request_sequence: raw.request_sequence,
            command,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", try_from = "RawAudioFrame")]
pub struct AudioFrame {
    pub protocol: ProtocolVersion,
    pub session_id: String,
    #[serde(with = "uint64_string")]
    pub sequence: u64,
    #[serde(with = "uint64_string")]
    pub monotonic_time_us: u64,
    pub format: Map<String, Value>,
    #[serde(rename = "payload")]
    pub payload_base64: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawAudioFrame {
    protocol: ProtocolVersion,
    session_id: String,
    #[serde(with = "uint64_string")]
    sequence: u64,
    #[serde(with = "uint64_string")]
    monotonic_time_us: u64,
    format: Map<String, Value>,
    #[serde(rename = "payload")]
    payload_base64: String,
}

impl TryFrom<RawAudioFrame> for AudioFrame {
    type Error = String;

    fn try_from(raw: RawAudioFrame) -> Result<Self, Self::Error> {
        validate_envelope(raw.protocol, &raw.session_id)?;
        validate_audio_format(&raw.format)?;
        if !valid_base64(&raw.payload_base64) {
            return Err("payload must use valid base64 grammar".into());
        }
        Ok(Self {
            protocol: raw.protocol,
            session_id: raw.session_id,
            sequence: raw.sequence,
            monotonic_time_us: raw.monotonic_time_us,
            format: raw.format,
            payload_base64: raw.payload_base64,
        })
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", try_from = "RawVoiceSource")]
pub struct VoiceSource {
    pub source_id: String,
    pub display_name: String,
    pub transport: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub capabilities: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub metadata: BTreeMap<String, String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawVoiceSource {
    source_id: String,
    display_name: String,
    transport: String,
    #[serde(default)]
    capabilities: Vec<String>,
    #[serde(default)]
    metadata: BTreeMap<String, String>,
}

impl TryFrom<RawVoiceSource> for VoiceSource {
    type Error = String;

    fn try_from(raw: RawVoiceSource) -> Result<Self, Self::Error> {
        if raw.source_id.trim().is_empty() || raw.display_name.trim().is_empty() {
            return Err("sourceId and displayName must be non-empty".into());
        }
        require_enum(&raw.transport, SOURCE_TRANSPORTS, "transport")?;
        for capability in &raw.capabilities {
            require_enum(capability, SOURCE_CAPABILITIES, "capability")?;
        }
        Ok(Self {
            source_id: raw.source_id,
            display_name: raw.display_name,
            transport: raw.transport,
            capabilities: raw.capabilities,
            metadata: raw.metadata,
        })
    }
}

fn validate_envelope(protocol: ProtocolVersion, session_id: &str) -> Result<(), String> {
    if !is_supported(protocol) {
        return Err(format!("unsupported protocol major {}", protocol.major));
    }
    if session_id.trim().is_empty() {
        return Err("sessionId must be non-empty".into());
    }
    Ok(())
}

fn take_exactly_one(
    remainder: &mut Map<String, Value>,
    arms: &'static [&'static str],
    name: &str,
) -> Result<(&'static str, Map<String, Value>), String> {
    let present: Vec<&str> = arms
        .iter()
        .copied()
        .filter(|arm| remainder.contains_key(*arm))
        .collect();
    if present.len() != 1 {
        return Err(format!("{name} must contain exactly one known arm"));
    }
    let arm = present[0];
    let value = remainder.remove(arm).expect("present arm must exist");
    let body = value
        .as_object()
        .cloned()
        .ok_or_else(|| format!("{arm} must be an object"))?;
    Ok((arm, body))
}

fn require_enum(value: &str, values: &[&str], field: &str) -> Result<(), String> {
    if values.contains(&value) {
        Ok(())
    } else {
        Err(format!("{field} must be a known enum name"))
    }
}

fn value_enum<'a>(body: &'a Map<String, Value>, field: &str) -> Result<&'a str, String> {
    body.get(field)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("{field} must be an enum name"))
}

fn validate_runtime_payload(arm: &str, body: &Map<String, Value>) -> Result<(), String> {
    match arm {
        "transcript" => {
            require_enum(value_enum(body, "kind")?, TRANSCRIPT_KINDS, "transcript.kind")?;
            if !body.get("text").is_some_and(Value::is_string) {
                return Err("transcript.text must be a string".into());
            }
        }
        "audioLevel" => {
            let amplitude = body
                .get("amplitude")
                .and_then(Value::as_f64)
                .ok_or("audioLevel.amplitude must be a number")?;
            if !(0.0..=1.0).contains(&amplitude) {
                return Err("audioLevel.amplitude must be between 0 and 1".into());
            }
        }
        "sessionStateChanged" => {
            require_enum(value_enum(body, "previous")?, SESSION_STATES, "previous")?;
            require_enum(value_enum(body, "current")?, SESSION_STATES, "current")?;
        }
        _ => {}
    }
    Ok(())
}

fn validate_session_body(arm: &str, body: &Map<String, Value>) -> Result<(), String> {
    match arm {
        "inputGate" => {
            for field in ["open", "flushAcceptedAudio"] {
                if body.contains_key(field) && !body[field].is_boolean() {
                    return Err(format!("{field} must be a boolean"));
                }
            }
        }
        "stop" => {
            if body.contains_key("reason") && !body["reason"].is_string() {
                return Err("stop.reason must be a string".into());
            }
        }
        "start" => {
            if body.contains_key("mode") {
                require_enum(value_enum(body, "mode")?, CAPTURE_MODES, "start.mode")?;
            }
            if let Some(source) = body.get("source") {
                serde_json::from_value::<VoiceSource>(source.clone()).map_err(|error| error.to_string())?;
            }
            if let Some(format) = body.get("requestedFormat") {
                validate_audio_format(
                    format
                        .as_object()
                        .ok_or("start.requestedFormat must be an object")?,
                )?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn uint32_field(format: &Map<String, Value>, field: &str) -> Result<u64, String> {
    format
        .get(field)
        .and_then(Value::as_u64)
        .filter(|value| *value <= u32::MAX as u64)
        .ok_or_else(|| format!("{field} must be a uint32"))
}

fn validate_audio_format(format: &Map<String, Value>) -> Result<(), String> {
    if uint32_field(format, "sampleRateHz")? < 1 {
        return Err("sampleRateHz must be at least 1".into());
    }
    if uint32_field(format, "channels")? < 1 {
        return Err("channels must be at least 1".into());
    }
    require_enum(value_enum(format, "encoding")?, AUDIO_ENCODINGS, "encoding")?;
    if format.contains_key("frameDurationMs") {
        uint32_field(format, "frameDurationMs")?;
    }
    Ok(())
}

fn valid_base64(value: &str) -> bool {
    let pad = value.len() - value.trim_end_matches('=').len();
    if pad > 2 {
        return false;
    }
    let raw = &value[..value.len() - pad];
    if raw.contains('=') || raw.len() % 4 == 1 {
        return false;
    }
    if pad > 0 && (pad != (4 - raw.len() % 4) % 4 || value.len() % 4 != 0) {
        return false;
    }
    let standard = raw
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'/'));
    let url_safe = raw
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'));
    standard || url_safe
}

mod uint64_string {
    use serde::{de::Error, Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &u64, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&value.to_string())
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<u64, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err(D::Error::custom("uint64 must contain ASCII digits only"));
        }
        value.parse().map_err(D::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, path::PathBuf};

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Manifest {
        fixture_sets: Vec<FixtureSet>,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct FixtureSet {
        name: String,
        message: String,
        path: String,
        lines: usize,
        expect: String,
        reason: Option<String>,
        rejection: Option<String>,
        reject_line: Option<usize>,
        #[serde(default)]
        unknown_fields: Vec<String>,
    }

    enum Parsed {
        Runtime(RuntimeEvent),
        Session(SessionControl),
        Audio(AudioFrame),
        Source(VoiceSource),
    }

    impl Parsed {
        fn parse(message: &str, value: Value) -> serde_json::Result<Self> {
            match message {
                "RuntimeEvent" => serde_json::from_value(value).map(Self::Runtime),
                "SessionControl" => serde_json::from_value(value).map(Self::Session),
                "AudioFrame" => serde_json::from_value(value).map(Self::Audio),
                "VoiceSource" => serde_json::from_value(value).map(Self::Source),
                _ => panic!("unknown fixture message {message}"),
            }
        }

        fn ordering_key(&self) -> Option<u64> {
            match self {
                Self::Runtime(value) => Some(value.sequence),
                Self::Session(value) => Some(value.request_sequence),
                Self::Audio(value) => Some(value.sequence),
                Self::Source(_) => None,
            }
        }

        fn to_value(&self) -> Value {
            match self {
                Self::Runtime(value) => serde_json::to_value(value),
                Self::Session(value) => serde_json::to_value(value),
                Self::Audio(value) => serde_json::to_value(value),
                Self::Source(value) => serde_json::to_value(value),
            }
            .expect("parsed fixture must serialize")
        }
    }

    fn remove_path(value: &mut Value, path: &str) {
        let mut parts = path.split('/').peekable();
        let mut current = value;
        while let Some(part) = parts.next() {
            if parts.peek().is_none() {
                if let Some(object) = current.as_object_mut() {
                    object.remove(part);
                }
                return;
            }
            match current.as_object_mut().and_then(|object| object.get_mut(part)) {
                Some(next) => current = next,
                None => return,
            }
        }
    }

    #[test]
    fn passes_every_manifest_conformance_set() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
        let conformance = root.join("conformance");
        let manifest: Manifest = serde_json::from_str(
            &fs::read_to_string(conformance.join("manifest.json")).expect("manifest must be readable"),
        )
        .expect("manifest must be valid");
        for fixture_set in manifest.fixture_sets {
            let source = fs::read_to_string(conformance.join(&fixture_set.path)).expect("fixture must be readable");
            let lines: Vec<&str> = source.lines().filter(|line| !line.trim().is_empty()).collect();
            assert_eq!(
                lines.len(),
                fixture_set.lines,
                "rust · {} · count",
                fixture_set.name
            );
            let mut previous = None;
            let reject_line = fixture_set.reject_line.unwrap_or(1);
            for (index, line) in lines.iter().enumerate() {
                let line_number = index + 1;
                let label = format!("rust · {} · line {line_number}", fixture_set.name);
                let input: Value = serde_json::from_str(line).expect("fixture line must be JSON");
                let parsed = match Parsed::parse(&fixture_set.message, input.clone()) {
                    Ok(value) => value,
                    Err(error) => {
                        let should_reject = fixture_set.expect == "reject"
                            && fixture_set.rejection.as_deref() == Some("parse")
                            && line_number >= reject_line;
                        assert!(should_reject, "{label} · {error}");
                        continue;
                    }
                };
                if fixture_set.expect == "reject"
                    && fixture_set.rejection.as_deref() == Some("parse")
                    && line_number >= reject_line
                {
                    panic!(
                        "{label} · expected {}",
                        fixture_set.reason.as_deref().unwrap_or("rejection")
                    );
                }
                if let Some(current) = parsed.ordering_key() {
                    let ordered = previous.map_or(true, |value| current > value);
                    let rejects_order = fixture_set.expect == "reject"
                        && fixture_set.rejection.as_deref() == Some("order")
                        && line_number >= reject_line;
                    assert_eq!(ordered, !rejects_order, "{label} · ordering");
                    if ordered {
                        previous = Some(current);
                    }
                }
                let mut expected = input;
                let mut actual = parsed.to_value();
                for path in &fixture_set.unknown_fields {
                    remove_path(&mut expected, path);
                    remove_path(&mut actual, path);
                }
                assert_eq!(actual, expected, "{label} · round-trip");
            }
        }
    }
}
