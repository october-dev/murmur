import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murmur/src/app.dart';
import 'package:murmur/src/features/device/omi_ble_client.dart';
import 'package:murmur/src/features/device/omi_device_controller.dart';

void main() {
  testWidgets('shows the Omi connection screen', (tester) async {
    final client = FakeOmiBleClient();
    addTearDown(client.dispose);

    await tester.pumpWidget(_testApp(client));
    await tester.pump();

    expect(find.text('murmur'), findsOneWidget);
    expect(find.text('Bluetooth ready'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Scan for Omi'), findsOneWidget);
    expect(find.text('No Omi found yet'), findsOneWidget);
  });

  testWidgets('discovers, connects, and disconnects an Omi', (tester) async {
    final client = FakeOmiBleClient();
    addTearDown(client.dispose);

    await tester.pumpWidget(_testApp(client));
    await tester.pump();

    await tester.tap(find.text('Scan for Omi'));
    await tester.pump();
    expect(find.text('Searching for Omi…'), findsOneWidget);

    client.discover(
      const OmiDevice(id: 'omi-1', name: 'Omi DevKit', rssi: -48),
    );
    await tester.pump();
    client.finishScan();
    await tester.pump();

    expect(find.text('Omi DevKit'), findsOneWidget);
    expect(find.text('Strong signal · -48 dBm'), findsOneWidget);

    final connectButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Connect'),
    );
    expect(connectButton.onPressed, isNotNull);
    connectButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(client.connectCalls, 1);
    expect(find.text('Connecting…'), findsWidgets);

    client.updateConnection(OmiConnectionState.connected);
    await tester.pump();

    expect(find.text('Connected'), findsWidgets);
    expect(find.text('Disconnect'), findsOneWidget);

    final disconnectButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Disconnect'),
    );
    expect(disconnectButton.onPressed, isNotNull);
    disconnectButton.onPressed!();
    client.finishConnection();
    await tester.pumpAndSettle();

    expect(find.text('Not connected'), findsOneWidget);
  });
}

Widget _testApp(FakeOmiBleClient client) {
  return ProviderScope(
    overrides: [omiBleClientProvider.overrideWithValue(client)],
    child: const MurmurApp(),
  );
}

class FakeOmiBleClient implements OmiBleClient {
  final _statusController = StreamController<OmiBluetoothState>.broadcast(
    sync: true,
  );
  final _scanController = StreamController<OmiDevice>.broadcast(sync: true);
  final _connectionController =
      StreamController<OmiConnectionState>.broadcast(sync: true);
  int connectCalls = 0;

  @override
  Stream<OmiBluetoothState> get statusStream async* {
    yield OmiBluetoothState.ready;
    yield* _statusController.stream;
  }

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Stream<OmiDevice> scanForOmi() => _scanController.stream;

  @override
  Stream<OmiConnectionState> connect(String deviceId) {
    connectCalls += 1;
    return _connectionController.stream;
  }

  void discover(OmiDevice device) => _scanController.add(device);

  void finishScan() => unawaited(_scanController.close());

  void updateConnection(OmiConnectionState state) {
    _connectionController.add(state);
  }

  void finishConnection() => unawaited(_connectionController.close());

  Future<void> dispose() async {
    await _statusController.close();
    if (!_scanController.isClosed) await _scanController.close();
    if (!_connectionController.isClosed) await _connectionController.close();
  }
}
