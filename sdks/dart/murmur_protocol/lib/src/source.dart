import 'protocol.dart';

enum VoiceSourceTransport {
  bluetoothLowEnergy('SOURCE_TRANSPORT_BLUETOOTH_LE'),
  localAudio('SOURCE_TRANSPORT_LOCAL_AUDIO'),
  network('SOURCE_TRANSPORT_NETWORK'),
  file('SOURCE_TRANSPORT_FILE'),
  synthetic('SOURCE_TRANSPORT_SYNTHETIC');

  const VoiceSourceTransport(this.protoJsonName);

  final String protoJsonName;
}

enum VoiceSourceCapability {
  liveAudio('SOURCE_CAPABILITY_LIVE_AUDIO'),
  storedAudio('SOURCE_CAPABILITY_STORED_AUDIO'),
  battery('SOURCE_CAPABILITY_BATTERY'),
  hardwareControl('SOURCE_CAPABILITY_HARDWARE_CONTROL'),
  outputAudio('SOURCE_CAPABILITY_OUTPUT_AUDIO'),
  backgroundCapture('SOURCE_CAPABILITY_BACKGROUND_CAPTURE'),
  inputMute('SOURCE_CAPABILITY_INPUT_MUTE'),
  speakerVerification('SOURCE_CAPABILITY_SPEAKER_VERIFICATION');

  const VoiceSourceCapability(this.protoJsonName);

  final String protoJsonName;
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

  factory VoiceSource.fromJson(Map<String, Object?> json) {
    final rawCapabilities = json['capabilities'] ?? const <Object?>[];
    final rawMetadata = json['metadata'] ?? const <String, Object?>{};
    if (rawCapabilities is! List<Object?>) {
      throw const FormatException('capabilities must be an array');
    }
    final metadataObject = requireObject(rawMetadata, 'metadata');
    final metadata = <String, String>{};
    for (final entry in metadataObject.entries) {
      final value = entry.value;
      if (value is! String) {
        throw const FormatException('metadata values must be strings');
      }
      metadata[entry.key] = value;
    }
    return VoiceSource(
      id: requireNonEmptyString(json['sourceId'], 'sourceId'),
      displayName: requireNonEmptyString(json['displayName'], 'displayName'),
      transport: _transportFromWire(json['transport']),
      capabilities: rawCapabilities.map(_capabilityFromWire).toSet(),
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() {
    final result = <String, Object?>{
      'sourceId': id,
      'displayName': displayName,
      'transport': transport.protoJsonName,
    };
    if (capabilities.isNotEmpty) {
      result['capabilities'] = capabilities
          .map((capability) => capability.protoJsonName)
          .toList();
    }
    if (metadata.isNotEmpty) result['metadata'] = metadata;
    return result;
  }

  bool supports(VoiceSourceCapability capability) =>
      capabilities.contains(capability);
}

VoiceSourceTransport _transportFromWire(Object? value) {
  for (final transport in VoiceSourceTransport.values) {
    if (transport.protoJsonName == value) return transport;
  }
  throw const FormatException('transport must be a known enum name');
}

VoiceSourceCapability _capabilityFromWire(Object? value) {
  for (final capability in VoiceSourceCapability.values) {
    if (capability.protoJsonName == value) return capability;
  }
  throw const FormatException('capability must be a known enum name');
}
