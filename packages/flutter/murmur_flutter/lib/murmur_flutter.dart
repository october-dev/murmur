import 'package:flutter/services.dart';

export 'package:murmur_protocol/murmur_protocol.dart';

final class MurmurNativeCapabilities {
  const MurmurNativeCapabilities({
    required this.microphone,
    required this.bluetoothLowEnergy,
  });

  factory MurmurNativeCapabilities.fromMap(Map<Object?, Object?> value) {
    return MurmurNativeCapabilities(
      microphone: value['microphone'] == true,
      bluetoothLowEnergy: value['bluetoothLowEnergy'] == true,
    );
  }

  final bool microphone;
  final bool bluetoothLowEnergy;
}

abstract final class MurmurFlutter {
  static const _channel = MethodChannel('dev.october.murmur/flutter');

  static Future<MurmurNativeCapabilities> getCapabilities() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
    );
    return MurmurNativeCapabilities.fromMap(value ?? const {});
  }

  static Future<bool> requestPermissions() async {
    return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
  }
}
