use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolVersion {
    pub major: u32,
    pub minor: u32,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
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

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VoiceSource {
    pub source_id: String,
    pub display_name: String,
    pub transport: String,
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
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
        value.parse().map_err(D::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURES: &str = include_str!("../../../../conformance/fixtures/runtime-events.jsonl");

    #[test]
    fn parses_and_preserves_shared_fixtures() {
        let source: Vec<Value> = FIXTURES
            .lines()
            .filter(|line| !line.trim().is_empty())
            .map(|line| serde_json::from_str(line).expect("fixture must be JSON"))
            .collect();
        let events: Vec<RuntimeEvent> = FIXTURES
            .lines()
            .filter(|line| !line.trim().is_empty())
            .map(|line| serde_json::from_str(line).expect("fixture must conform"))
            .collect();

        assert_eq!(events.len(), 7);
        assert_eq!(events[3].sequence, 4);
        assert!(matches!(events[3].payload, RuntimePayload::Transcript(_)));

        let encoded: Vec<Value> = events
            .iter()
            .map(|event| serde_json::to_value(event).expect("event must serialize"))
            .collect();
        assert_eq!(encoded, source);
    }
}
