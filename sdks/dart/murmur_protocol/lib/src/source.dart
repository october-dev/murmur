enum VoiceSourceTransport {
  bluetoothLowEnergy,
  localAudio,
  network,
  file,
  synthetic,
}

enum VoiceSourceCapability {
  liveAudio,
  storedAudio,
  battery,
  hardwareControl,
  outputAudio,
  backgroundCapture,
  inputMute,
  speakerVerification,
}

/// A source-neutral description of something that can provide voice input.
final class VoiceSource {
  VoiceSource({
    required this.id,
    required this.displayName,
    required this.transport,
    Set<VoiceSourceCapability> capabilities = const {},
    Map<String, String> metadata = const {},
  }) : capabilities = Set.unmodifiable(capabilities),
       metadata = Map.unmodifiable(metadata) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (displayName.trim().isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'must not be empty',
      );
    }
  }

  final String id;
  final String displayName;
  final VoiceSourceTransport transport;
  final Set<VoiceSourceCapability> capabilities;
  final Map<String, String> metadata;

  bool supports(VoiceSourceCapability capability) =>
      capabilities.contains(capability);
}
