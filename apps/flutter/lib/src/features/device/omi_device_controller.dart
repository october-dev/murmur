import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:murmur_app/src/features/device/omi_ble_client.dart';

final omiBleClientProvider = Provider<OmiBleClient>(
  (ref) => ReactiveOmiBleClient(),
);

final omiDeviceControllerProvider = ChangeNotifierProvider<OmiDeviceController>(
  (ref) => OmiDeviceController(ref.watch(omiBleClientProvider)),
);

class OmiDeviceController extends ChangeNotifier {
  OmiDeviceController(this._client) {
    _statusSubscription = _client.statusStream.listen(
      _onBluetoothStatus,
      onError: (Object error) {
        _setError('Could not read Bluetooth status. $error');
      },
    );
  }

  final OmiBleClient _client;
  final Map<String, OmiDevice> _devicesById = {};

  StreamSubscription<OmiBluetoothState>? _statusSubscription;
  StreamSubscription<OmiDevice>? _scanSubscription;
  StreamSubscription<OmiConnectionState>? _connectionSubscription;
  Timer? _scanTimer;

  OmiBluetoothState bluetoothState = OmiBluetoothState.unknown;
  OmiConnectionState connectionState = OmiConnectionState.disconnected;
  OmiDevice? selectedDevice;
  bool isScanning = false;
  String? errorMessage;

  List<OmiDevice> get devices {
    final result = _devicesById.values.toList();
    result.sort((a, b) => b.rssi.compareTo(a.rssi));
    return result;
  }

  bool get canStartScan =>
      !isScanning &&
      connectionState == OmiConnectionState.disconnected &&
      bluetoothState != OmiBluetoothState.poweredOff &&
      bluetoothState != OmiBluetoothState.locationServicesDisabled &&
      bluetoothState != OmiBluetoothState.unsupported;

  Future<void> scan() async {
    if (!canStartScan) return;

    errorMessage = null;
    final hasPermission = await _client.requestPermissions();
    if (!hasPermission) {
      bluetoothState = OmiBluetoothState.unauthorized;
      _setError(
        'Bluetooth access is required to find your Omi. Allow Nearby devices '
        'access in system settings, then try again.',
      );
      return;
    }

    await _stopScan(notify: false);
    _devicesById.clear();
    isScanning = true;
    notifyListeners();

    _scanSubscription = _client.scanForOmi().listen(
      (device) {
        _devicesById[device.id] = device;
        notifyListeners();
      },
      onError: (Object error) {
        _finishScan();
        _setError(_scanErrorMessage(error));
      },
      onDone: _finishScan,
    );

    _scanTimer = Timer(const Duration(seconds: 8), _finishScan);
  }

  Future<void> connect(OmiDevice device) async {
    if (connectionState != OmiConnectionState.disconnected) return;

    errorMessage = null;
    selectedDevice = device;
    connectionState = OmiConnectionState.connecting;
    notifyListeners();

    await _stopScan(notify: false);
    await _connectionSubscription?.cancel();

    if (selectedDevice?.id != device.id ||
        connectionState != OmiConnectionState.connecting) {
      return;
    }

    _connectionSubscription = _client
        .connect(device.id)
        .listen(
          (state) => _onConnectionState(device, state),
          onError: (Object error) {
            if (selectedDevice?.id != device.id) return;
            connectionState = OmiConnectionState.disconnected;
            selectedDevice = null;
            _setError(
              'Could not connect to ${device.displayName}. Keep it nearby and '
              'awake, then try again. $error',
            );
          },
          onDone: () {
            if (selectedDevice?.id != device.id ||
                connectionState == OmiConnectionState.disconnecting) {
              return;
            }
            connectionState = OmiConnectionState.disconnected;
            selectedDevice = null;
            notifyListeners();
          },
        );
  }

  Future<void> disconnect() async {
    if (connectionState == OmiConnectionState.disconnected) return;

    connectionState = OmiConnectionState.disconnecting;
    notifyListeners();

    final subscription = _connectionSubscription;
    _connectionSubscription = null;
    connectionState = OmiConnectionState.disconnected;
    selectedDevice = null;
    notifyListeners();

    await subscription?.cancel();
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  void _onBluetoothStatus(OmiBluetoothState status) {
    bluetoothState = status;
    if (status == OmiBluetoothState.ready &&
        errorMessage?.startsWith('Bluetooth access') == true) {
      errorMessage = null;
    }
    notifyListeners();
  }

  void _onConnectionState(OmiDevice device, OmiConnectionState state) {
    if (selectedDevice?.id != device.id) return;
    connectionState = state;
    if (state == OmiConnectionState.disconnected) selectedDevice = null;
    notifyListeners();
  }

  Future<void> _stopScan({bool notify = true}) async {
    _scanTimer?.cancel();
    _scanTimer = null;

    final subscription = _scanSubscription;
    _scanSubscription = null;
    await subscription?.cancel();

    final changed = isScanning;
    isScanning = false;
    if (changed && notify) notifyListeners();
  }

  void _finishScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    final subscription = _scanSubscription;
    _scanSubscription = null;
    unawaited(subscription?.cancel());
    if (!isScanning) return;
    isScanning = false;
    notifyListeners();
  }

  String _scanErrorMessage(Object error) {
    return switch (bluetoothState) {
      OmiBluetoothState.unauthorized =>
        'Bluetooth access is required to find your Omi. Allow access in '
            'system settings, then try again.',
      OmiBluetoothState.poweredOff =>
        'Bluetooth is off. Turn it on, then scan again.',
      OmiBluetoothState.locationServicesDisabled =>
        'Location services must be on for Bluetooth discovery on this Android '
            'version.',
      _ => 'The Omi scan failed. Please try again. $error',
    };
  }

  void _setError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(_statusSubscription?.cancel());
    unawaited(_scanSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    super.dispose();
  }
}
