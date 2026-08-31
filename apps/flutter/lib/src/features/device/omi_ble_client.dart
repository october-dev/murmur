import 'dart:io';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:murmur_protocol/murmur_protocol.dart';
import 'package:permission_handler/permission_handler.dart';

const omiServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';

enum OmiBluetoothState {
  unknown,
  unsupported,
  unauthorized,
  poweredOff,
  locationServicesDisabled,
  ready,
}

enum OmiConnectionState { disconnected, connecting, connected, disconnecting }

class OmiDevice {
  const OmiDevice({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;
  final int rssi;

  VoiceSource get source => VoiceSource(
    id: id,
    displayName: name.trim().isEmpty ? 'Omi' : name.trim(),
    transport: VoiceSourceTransport.bluetoothLowEnergy,
    capabilities: const {VoiceSourceCapability.liveAudio},
    metadata: const {'connector': 'omi'},
  );

  String get displayName => source.displayName;
}

abstract class OmiBleClient {
  Stream<OmiBluetoothState> get statusStream;

  Future<bool> requestPermissions();

  Stream<OmiDevice> scanForOmi();

  Stream<OmiConnectionState> connect(String deviceId);
}

class ReactiveOmiBleClient implements OmiBleClient {
  ReactiveOmiBleClient({reactive.FlutterReactiveBle? ble})
    : _ble = ble ?? reactive.FlutterReactiveBle();

  final reactive.FlutterReactiveBle _ble;
  static final reactive.Uuid _serviceId = reactive.Uuid.parse(omiServiceUuid);

  @override
  Stream<OmiBluetoothState> get statusStream =>
      _ble.statusStream.map(_mapBluetoothState).distinct();

  @override
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    // Location is only used by Android 11 and earlier for BLE discovery. Its
    // manifest entry is capped at API 30, so newer Android versions only show
    // the Nearby devices prompt for scan/connect.
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    return (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
        (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
  }

  @override
  Stream<OmiDevice> scanForOmi() {
    return _ble
        .scanForDevices(
          withServices: [_serviceId],
          scanMode: reactive.ScanMode.lowLatency,
        )
        .where(
          (device) => device.serviceUuids.any(
            (uuid) => uuid.toString().toLowerCase() == omiServiceUuid,
          ),
        )
        .map(
          (device) =>
              OmiDevice(id: device.id, name: device.name, rssi: device.rssi),
        );
  }

  @override
  Stream<OmiConnectionState> connect(String deviceId) {
    return _ble
        .connectToDevice(
          id: deviceId,
          servicesWithCharacteristicsToDiscover: {_serviceId: const []},
          connectionTimeout: const Duration(seconds: 12),
        )
        .map((update) => _mapConnectionState(update.connectionState))
        .distinct();
  }

  static OmiBluetoothState _mapBluetoothState(reactive.BleStatus status) {
    return switch (status) {
      reactive.BleStatus.unknown => OmiBluetoothState.unknown,
      reactive.BleStatus.unsupported => OmiBluetoothState.unsupported,
      reactive.BleStatus.unauthorized => OmiBluetoothState.unauthorized,
      reactive.BleStatus.poweredOff => OmiBluetoothState.poweredOff,
      reactive.BleStatus.locationServicesDisabled =>
        OmiBluetoothState.locationServicesDisabled,
      reactive.BleStatus.ready => OmiBluetoothState.ready,
    };
  }

  static OmiConnectionState _mapConnectionState(
    reactive.DeviceConnectionState state,
  ) {
    return switch (state) {
      reactive.DeviceConnectionState.disconnected =>
        OmiConnectionState.disconnected,
      reactive.DeviceConnectionState.connecting =>
        OmiConnectionState.connecting,
      reactive.DeviceConnectionState.connected => OmiConnectionState.connected,
      reactive.DeviceConnectionState.disconnecting =>
        OmiConnectionState.disconnecting,
    };
  }
}
