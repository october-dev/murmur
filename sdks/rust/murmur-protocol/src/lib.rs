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
    "providerStatus",
    "inputGateStatus",
    "wakePhrase",
    "batchProgress",
];
const SESSION_ARMS: &[&str] = &[
    "start",
    "stop",
    "inputGate",
    "finalize",
    "speakerVerification",
    "startBatch",
];
const ENGINE_EVENT_ARMS: &[&str] = &[
    "engineStatus",
    "voicePackStatus",
    "microphoneStatus",
    "speechOutput",
    "error",
];
const ENGINE_CONTROL_ARMS: &[&str] = &["voicePack", "speak", "cancelSpeech"];
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
// Required discriminators reject the *_UNSPECIFIED name; optional enums treat
// it as absent.
const ENGINE_LOCALITIES: &[&str] = &[
    "ENGINE_LOCALITY_UNSPECIFIED",
    "ENGINE_LOCALITY_ON_DEVICE",
    "ENGINE_LOCALITY_REMOTE",
];
const ENGINE_PLATFORMS: &[&str] = &[
    "ENGINE_PLATFORM_UNSPECIFIED",
    "ENGINE_PLATFORM_MACOS",
    "ENGINE_PLATFORM_WINDOWS",
    "ENGINE_PLATFORM_LINUX",
    "ENGINE_PLATFORM_IOS",
    "ENGINE_PLATFORM_ANDROID",
];
const ENGINE_READINESS: &[&str] = &[
    "ENGINE_READINESS_UNSPECIFIED",
    "ENGINE_READINESS_NOT_READY",
    "ENGINE_READINESS_PREPARING",
    "ENGINE_READINESS_READY",
    "ENGINE_READINESS_FAILED",
];
const VOICE_PACK_STATES: &[&str] = &[
    "VOICE_PACK_STATE_UNSPECIFIED",
    "VOICE_PACK_STATE_NOT_INSTALLED",
    "VOICE_PACK_STATE_PREPARING",
    "VOICE_PACK_STATE_REPAIRING",
    "VOICE_PACK_STATE_READY",
    "VOICE_PACK_STATE_FAILED",
    "VOICE_PACK_STATE_UNSUPPORTED",
];
const VOICE_PACK_COMPONENT_KINDS: &[&str] = &[
    "VOICE_PACK_COMPONENT_KIND_UNSPECIFIED",
    "VOICE_PACK_COMPONENT_KIND_TRANSCRIPTION",
    "VOICE_PACK_COMPONENT_KIND_VOICE_ACTIVITY",
    "VOICE_PACK_COMPONENT_KIND_SPEECH_OUTPUT",
    "VOICE_PACK_COMPONENT_KIND_WAKE_PHRASE",
    "VOICE_PACK_COMPONENT_KIND_SPEAKER_VERIFICATION",
];
const VOICE_PACK_ACTIONS: &[&str] = &[
    "VOICE_PACK_ACTION_UNSPECIFIED",
    "VOICE_PACK_ACTION_PREPARE",
    "VOICE_PACK_ACTION_RETRY",
    "VOICE_PACK_ACTION_REPAIR",
];
const MICROPHONE_PERMISSIONS: &[&str] = &[
    "MICROPHONE_PERMISSION_UNSPECIFIED",
    "MICROPHONE_PERMISSION_NOT_DETERMINED",
    "MICROPHONE_PERMISSION_GRANTED",
    "MICROPHONE_PERMISSION_DENIED",
    "MICROPHONE_PERMISSION_RESTRICTED",
];
const MICROPHONE_ROUTES: &[&str] = &[
    "MICROPHONE_ROUTE_UNSPECIFIED",
    "MICROPHONE_ROUTE_BUILT_IN",
    "MICROPHONE_ROUTE_WIRED",
    "MICROPHONE_ROUTE_BLUETOOTH",
    "MICROPHONE_ROUTE_USB",
    "MICROPHONE_ROUTE_VIRTUAL",
];
const MICROPHONE_READINESS: &[&str] = &[
    "MICROPHONE_READINESS_UNSPECIFIED",
    "MICROPHONE_READINESS_UNAVAILABLE",
    "MICROPHONE_READINESS_WARMING",
    "MICROPHONE_READINESS_READY",
    "MICROPHONE_READINESS_INTERRUPTED",
];
const MICROPHONE_INTERRUPTIONS: &[&str] = &[
    "MICROPHONE_INTERRUPTION_UNSPECIFIED",
    "MICROPHONE_INTERRUPTION_SYSTEM",
    "MICROPHONE_INTERRUPTION_OTHER_APPLICATION",
    "MICROPHONE_INTERRUPTION_DEVICE_REMOVED",
];
const SPEECH_OUTPUT_STATES: &[&str] = &[
    "SPEECH_OUTPUT_STATE_UNSPECIFIED",
    "SPEECH_OUTPUT_STATE_PREPARING",
    "SPEECH_OUTPUT_STATE_SPEAKING",
    "SPEECH_OUTPUT_STATE_ECHO_CLEARING",
    "SPEECH_OUTPUT_STATE_COMPLETED",
    "SPEECH_OUTPUT_STATE_CANCELLED",
    "SPEECH_OUTPUT_STATE_FAILED",
];
const PROVIDER_STATES: &[&str] = &[
    "PROVIDER_STATE_UNSPECIFIED",
    "PROVIDER_STATE_STARTING",
    "PROVIDER_STATE_ACTIVE",
    "PROVIDER_STATE_FINALIZING",
    "PROVIDER_STATE_FINALIZED",
    "PROVIDER_STATE_CANCELLED",
    "PROVIDER_STATE_FAILED",
];
const INPUT_GATE_CAUSES: &[&str] = &[
    "INPUT_GATE_CAUSE_UNSPECIFIED",
    "INPUT_GATE_CAUSE_HOST",
    "INPUT_GATE_CAUSE_FINALIZATION",
    "INPUT_GATE_CAUSE_SPEECH_OUTPUT",
    "INPUT_GATE_CAUSE_ECHO_CLEARANCE",
    "INPUT_GATE_CAUSE_INTERRUPTION",
];
const WAKE_PHRASE_STAGES: &[&str] = &[
    "WAKE_PHRASE_STAGE_UNSPECIFIED",
    "WAKE_PHRASE_STAGE_DETECTED",
    "WAKE_PHRASE_STAGE_ACTIVATED",
    "WAKE_PHRASE_STAGE_DISMISSED",
];
const SPEAKER_VERIFICATION_MODES: &[&str] = &[
    "SPEAKER_VERIFICATION_MODE_UNSPECIFIED",
    "SPEAKER_VERIFICATION_MODE_DISABLED",
    "SPEAKER_VERIFICATION_MODE_ENFORCED",
    "SPEAKER_VERIFICATION_MODE_BYPASSED",
];
const SPEAKER_VERIFICATION_RESULTS: &[&str] = &[
    "SPEAKER_VERIFICATION_RESULT_UNSPECIFIED",
    "SPEAKER_VERIFICATION_RESULT_ACCEPTED",
    "SPEAKER_VERIFICATION_RESULT_BYPASSED",
    "SPEAKER_VERIFICATION_RESULT_UNCERTAIN",
    "SPEAKER_VERIFICATION_RESULT_REJECTED",
];

/// Speaker-verification results a transcript kind may carry besides an absent
/// or UNSPECIFIED result.
fn speaker_results_for_kind(kind: &str) -> &'static [&'static str] {
    match kind {
        "TRANSCRIPT_KIND_FINAL" => &[
            "SPEAKER_VERIFICATION_RESULT_ACCEPTED",
            "SPEAKER_VERIFICATION_RESULT_BYPASSED",
            "SPEAKER_VERIFICATION_RESULT_UNCERTAIN",
        ],
        "TRANSCRIPT_KIND_REJECTED" => &[
            "SPEAKER_VERIFICATION_RESULT_REJECTED",
            "SPEAKER_VERIFICATION_RESULT_UNCERTAIN",
        ],
        _ => &[],
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolVersion {
    pub major: u32,
    pub minor: u32,
}

pub const CURRENT_PROTOCOL: ProtocolVersion = ProtocolVersion { major: 1, minor: 1 };

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
    ProviderStatus(Map<String, Value>),
    InputGateStatus(Map<String, Value>),
    WakePhrase(Map<String, Value>),
    BatchProgress(Map<String, Value>),
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
        validate_envelope(raw.protocol, &raw.session_id, "sessionId")?;
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
            "providerStatus" => RuntimePayload::ProviderStatus(body),
            "inputGateStatus" => RuntimePayload::InputGateStatus(body),
            "wakePhrase" => RuntimePayload::WakePhrase(body),
            "batchProgress" => RuntimePayload::BatchProgress(body),
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
    SpeakerVerification(Map<String, Value>),
    StartBatch(Map<String, Value>),
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
        validate_envelope(raw.protocol, &raw.session_id, "sessionId")?;
        let (arm, body) = take_exactly_one(&mut raw.remainder, SESSION_ARMS, "session command")?;
        validate_session_body(arm, &body)?;
        let command = match arm {
            "start" => SessionCommand::Start(body),
            "stop" => SessionCommand::Stop(body),
            "inputGate" => SessionCommand::InputGate(body),
            "finalize" => SessionCommand::Finalize(body),
            "speakerVerification" => SessionCommand::SpeakerVerification(body),
            "startBatch" => SessionCommand::StartBatch(body),
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
        validate_envelope(raw.protocol, &raw.session_id, "sessionId")?;
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

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", try_from = "RawEngineEvent")]
pub struct EngineEvent {
    pub protocol: ProtocolVersion,
    pub engine_id: String,
    #[serde(with = "uint64_string")]
    pub sequence: u64,
    #[serde(with = "uint64_string")]
    pub monotonic_time_us: u64,
    #[serde(flatten)]
    pub payload: EnginePayload,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EnginePayload {
    EngineStatus(Map<String, Value>),
    VoicePackStatus(Map<String, Value>),
    MicrophoneStatus(Map<String, Value>),
    SpeechOutput(Map<String, Value>),
    Error(Map<String, Value>),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawEngineEvent {
    protocol: ProtocolVersion,
    engine_id: String,
    #[serde(with = "uint64_string")]
    sequence: u64,
    #[serde(with = "uint64_string")]
    monotonic_time_us: u64,
    #[serde(flatten)]
    remainder: Map<String, Value>,
}

impl TryFrom<RawEngineEvent> for EngineEvent {
    type Error = String;

    fn try_from(mut raw: RawEngineEvent) -> Result<Self, Self::Error> {
        validate_envelope(raw.protocol, &raw.engine_id, "engineId")?;
        let (arm, body) =
            take_exactly_one(&mut raw.remainder, ENGINE_EVENT_ARMS, "engine payload")?;
        validate_engine_payload(arm, &body)?;
        let payload = match arm {
            "engineStatus" => EnginePayload::EngineStatus(body),
            "voicePackStatus" => EnginePayload::VoicePackStatus(body),
            "microphoneStatus" => EnginePayload::MicrophoneStatus(body),
            "speechOutput" => EnginePayload::SpeechOutput(body),
            "error" => EnginePayload::Error(body),
            _ => unreachable!(),
        };
        Ok(Self {
            protocol: raw.protocol,
            engine_id: raw.engine_id,
            sequence: raw.sequence,
            monotonic_time_us: raw.monotonic_time_us,
            payload,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", try_from = "RawEngineControl")]
pub struct EngineControl {
    pub protocol: ProtocolVersion,
    pub engine_id: String,
    #[serde(with = "uint64_string")]
    pub request_sequence: u64,
    #[serde(flatten)]
    pub command: EngineCommand,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EngineCommand {
    VoicePack(Map<String, Value>),
    Speak(Map<String, Value>),
    CancelSpeech(Map<String, Value>),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawEngineControl {
    protocol: ProtocolVersion,
    engine_id: String,
    #[serde(with = "uint64_string")]
    request_sequence: u64,
    #[serde(flatten)]
    remainder: Map<String, Value>,
}

impl TryFrom<RawEngineControl> for EngineControl {
    type Error = String;

    fn try_from(mut raw: RawEngineControl) -> Result<Self, Self::Error> {
        validate_envelope(raw.protocol, &raw.engine_id, "engineId")?;
        let (arm, body) =
            take_exactly_one(&mut raw.remainder, ENGINE_CONTROL_ARMS, "engine command")?;
        validate_engine_command(arm, &body)?;
        let command = match arm {
            "voicePack" => EngineCommand::VoicePack(body),
            "speak" => EngineCommand::Speak(body),
            "cancelSpeech" => EngineCommand::CancelSpeech(body),
            _ => unreachable!(),
        };
        Ok(Self {
            protocol: raw.protocol,
            engine_id: raw.engine_id,
            request_sequence: raw.request_sequence,
            command,
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

fn validate_envelope(
    protocol: ProtocolVersion,
    routing_id: &str,
    field: &str,
) -> Result<(), String> {
    if !is_supported(protocol) {
        return Err(format!("unsupported protocol major {}", protocol.major));
    }
    if routing_id.trim().is_empty() {
        return Err(format!("{field} must be non-empty"));
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

fn required_enum<'a>(
    body: &'a Map<String, Value>,
    field: &str,
    values: &[&str],
) -> Result<&'a str, String> {
    let value = value_enum(body, field)?;
    require_enum(value, values, field)?;
    if value.ends_with("_UNSPECIFIED") {
        return Err(format!("{field} must not be unspecified"));
    }
    Ok(value)
}

fn optional_enum(body: &Map<String, Value>, field: &str, values: &[&str]) -> Result<(), String> {
    if body.contains_key(field) {
        require_enum(value_enum(body, field)?, values, field)?;
    }
    Ok(())
}

/// Whether an optional enum is set; an explicit *_UNSPECIFIED name counts as absent.
fn is_set(body: &Map<String, Value>, field: &str) -> bool {
    body.get(field).is_some_and(|value| {
        !value
            .as_str()
            .is_some_and(|name| name.ends_with("_UNSPECIFIED"))
    })
}

fn non_empty_string<'a>(body: &'a Map<String, Value>, field: &str) -> Result<&'a str, String> {
    body.get(field)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("{field} must be a non-empty string"))
}

fn array_field<'a>(body: &'a Map<String, Value>, field: &str) -> Result<&'a [Value], String> {
    match body.get(field) {
        None => Ok(&[]),
        Some(value) => value
            .as_array()
            .map(Vec::as_slice)
            .ok_or_else(|| format!("{field} must be an array")),
    }
}

fn object_value<'a>(value: &'a Value, field: &str) -> Result<&'a Map<String, Value>, String> {
    value
        .as_object()
        .ok_or_else(|| format!("{field} must be an object"))
}

fn optional_uint32(body: &Map<String, Value>, field: &str) -> Result<u64, String> {
    if body.contains_key(field) {
        uint32_field(body, field)
    } else {
        Ok(0)
    }
}

fn optional_uint64(body: &Map<String, Value>, field: &str) -> Result<u64, String> {
    match body.get(field) {
        None => Ok(0),
        Some(value) => value
            .as_str()
            .filter(|text| !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit()))
            .and_then(|text| text.parse().ok())
            .ok_or_else(|| format!("{field} must be an ASCII uint64 string")),
    }
}

fn validate_unit_interval(body: &Map<String, Value>, field: &str) -> Result<(), String> {
    if let Some(value) = body.get(field) {
        let number = value
            .as_f64()
            .ok_or_else(|| format!("{field} must be a number"))?;
        if !(0.0..=1.0).contains(&number) {
            return Err(format!("{field} must be between 0 and 1"));
        }
    }
    Ok(())
}

fn validate_outcome(
    body: &Map<String, Value>,
    failed: bool,
    error_allowed: bool,
) -> Result<(), String> {
    match body.get("error") {
        Some(error) if !error.is_object() => Err("error must be an object".into()),
        Some(_) if !failed && !error_allowed => Err("error is only allowed when failed".into()),
        None if failed => Err("error is required when failed".into()),
        _ => Ok(()),
    }
}

fn validate_progress(completed: u64, total: u64) -> Result<(), String> {
    if total > 0 && completed > total {
        return Err("progress exceeds its total".into());
    }
    Ok(())
}

fn validate_transcript(body: &Map<String, Value>) -> Result<(), String> {
    let kind = value_enum(body, "kind")?;
    require_enum(kind, TRANSCRIPT_KINDS, "transcript.kind")?;
    if !body.get("text").is_some_and(Value::is_string) {
        return Err("transcript.text must be a string".into());
    }
    optional_enum(body, "speakerVerification", SPEAKER_VERIFICATION_RESULTS)?;
    if is_set(body, "speakerVerification") {
        let result = value_enum(body, "speakerVerification")?;
        if !speaker_results_for_kind(kind).contains(&result) {
            return Err(format!("{kind} cannot carry {result}"));
        }
    }
    let mut previous_start = 0;
    for value in array_field(body, "words")? {
        let word = object_value(value, "transcript.words[]")?;
        if !word.get("text").is_some_and(Value::is_string) {
            return Err("word.text must be a string".into());
        }
        let start = optional_uint32(word, "startOffsetMs")?;
        let end = optional_uint32(word, "endOffsetMs")?;
        if start > end || start < previous_start {
            return Err("words must be ordered and end at or after their start".into());
        }
        validate_unit_interval(word, "confidence")?;
        previous_start = start;
    }
    Ok(())
}

fn validate_runtime_payload(arm: &str, body: &Map<String, Value>) -> Result<(), String> {
    match arm {
        "transcript" => validate_transcript(body)?,
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
        "providerStatus" => {
            let state = required_enum(body, "state", PROVIDER_STATES)?;
            validate_outcome(body, state == "PROVIDER_STATE_FAILED", false)?;
        }
        "inputGateStatus" => {
            let mut causes = Vec::new();
            for cause in array_field(body, "closedBy")? {
                let name = cause.as_str().ok_or("closedBy must contain enum names")?;
                require_enum(name, INPUT_GATE_CAUSES, "closedBy")?;
                if name.ends_with("_UNSPECIFIED") || causes.contains(&name) {
                    return Err("closedBy must contain distinct specified causes".into());
                }
                causes.push(name);
            }
        }
        "wakePhrase" => {
            non_empty_string(body, "phraseId")?;
            required_enum(body, "stage", WAKE_PHRASE_STAGES)?;
            validate_unit_interval(body, "confidence")?;
        }
        "batchProgress" => validate_progress(
            optional_uint32(body, "processedAudioMs")?,
            optional_uint32(body, "totalAudioMs")?,
        )?,
        _ => {}
    }
    Ok(())
}

fn validate_engine_payload(arm: &str, body: &Map<String, Value>) -> Result<(), String> {
    match arm {
        "engineStatus" => {
            let engine = object_value(body.get("engine").unwrap_or(&Value::Null), "engine")?;
            let readiness = required_enum(body, "readiness", ENGINE_READINESS)?;
            if required_enum(engine, "locality", ENGINE_LOCALITIES)? == "ENGINE_LOCALITY_ON_DEVICE"
            {
                required_enum(engine, "platform", ENGINE_PLATFORMS)?;
            } else {
                optional_enum(engine, "platform", ENGINE_PLATFORMS)?;
            }
            for token in array_field(engine, "capabilities")? {
                if !token.as_str().is_some_and(|name| !name.trim().is_empty()) {
                    return Err("capabilities must be non-empty strings".into());
                }
            }
            validate_outcome(
                body,
                readiness == "ENGINE_READINESS_FAILED",
                readiness == "ENGINE_READINESS_NOT_READY",
            )?;
        }
        "voicePackStatus" => {
            non_empty_string(body, "packId")?;
            validate_voice_pack_item(body)?;
            for value in array_field(body, "components")? {
                let component = object_value(value, "component")?;
                non_empty_string(component, "componentId")?;
                required_enum(component, "kind", VOICE_PACK_COMPONENT_KINDS)?;
                validate_voice_pack_item(component)?;
            }
        }
        "microphoneStatus" => {
            non_empty_string(body, "sourceId")?;
            required_enum(body, "permission", MICROPHONE_PERMISSIONS)?;
            let readiness = required_enum(body, "readiness", MICROPHONE_READINESS)?;
            optional_enum(body, "route", MICROPHONE_ROUTES)?;
            optional_enum(body, "interruption", MICROPHONE_INTERRUPTIONS)?;
            if is_set(body, "interruption") != (readiness == "MICROPHONE_READINESS_INTERRUPTED") {
                return Err("interruption is set exactly when interrupted".into());
            }
        }
        "speechOutput" => {
            non_empty_string(body, "outputId")?;
            let state = required_enum(body, "state", SPEECH_OUTPUT_STATES)?;
            validate_outcome(body, state == "SPEECH_OUTPUT_STATE_FAILED", false)?;
        }
        _ => {}
    }
    Ok(())
}

fn validate_voice_pack_item(item: &Map<String, Value>) -> Result<(), String> {
    let state = required_enum(item, "state", VOICE_PACK_STATES)?;
    validate_outcome(item, state == "VOICE_PACK_STATE_FAILED", false)?;
    validate_progress(
        optional_uint64(item, "bytesCompleted")?,
        optional_uint64(item, "bytesTotal")?,
    )
}

fn validate_engine_command(arm: &str, body: &Map<String, Value>) -> Result<(), String> {
    match arm {
        "voicePack" => {
            non_empty_string(body, "packId")?;
            required_enum(body, "action", VOICE_PACK_ACTIONS)?;
        }
        "speak" => {
            non_empty_string(body, "outputId")?;
            non_empty_string(body, "text")?;
            if body.contains_key("fullDuplex") && !body["fullDuplex"].is_boolean() {
                return Err("fullDuplex must be a boolean".into());
            }
            optional_uint32(body, "echoClearanceMs")?;
        }
        _ => {
            non_empty_string(body, "outputId")?;
        }
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
            if body.contains_key("engineId") {
                non_empty_string(body, "engineId")?;
            }
        }
        "speakerVerification" => {
            required_enum(body, "mode", SPEAKER_VERIFICATION_MODES)?;
        }
        "startBatch" => {
            non_empty_string(body, "engineId")?;
            let format = object_value(
                body.get("format").unwrap_or(&Value::Null),
                "startBatch.format",
            )?;
            validate_audio_format(format)?;
            if format["encoding"] == "AUDIO_ENCODING_OPUS"
                && optional_uint32(format, "frameDurationMs")? < 1
            {
                return Err("startBatch.format.frameDurationMs is required for Opus".into());
            }
            optional_uint32(body, "totalAudioMs")?;
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
        Engine(EngineEvent),
        EngineControl(EngineControl),
    }

    impl Parsed {
        fn parse(message: &str, value: Value) -> serde_json::Result<Self> {
            match message {
                "RuntimeEvent" => serde_json::from_value(value).map(Self::Runtime),
                "SessionControl" => serde_json::from_value(value).map(Self::Session),
                "AudioFrame" => serde_json::from_value(value).map(Self::Audio),
                "VoiceSource" => serde_json::from_value(value).map(Self::Source),
                "EngineEvent" => serde_json::from_value(value).map(Self::Engine),
                "EngineControl" => serde_json::from_value(value).map(Self::EngineControl),
                _ => panic!("unknown fixture message {message}"),
            }
        }

        fn ordering_key(&self) -> Option<u64> {
            match self {
                Self::Runtime(value) => Some(value.sequence),
                Self::Session(value) => Some(value.request_sequence),
                Self::Audio(value) => Some(value.sequence),
                Self::Source(_) => None,
                Self::Engine(value) => Some(value.sequence),
                Self::EngineControl(value) => Some(value.request_sequence),
            }
        }

        fn to_value(&self) -> Value {
            match self {
                Self::Runtime(value) => serde_json::to_value(value),
                Self::Session(value) => serde_json::to_value(value),
                Self::Audio(value) => serde_json::to_value(value),
                Self::Source(value) => serde_json::to_value(value),
                Self::Engine(value) => serde_json::to_value(value),
                Self::EngineControl(value) => serde_json::to_value(value),
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
