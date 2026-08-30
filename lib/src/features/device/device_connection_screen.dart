import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murmur/src/features/device/omi_ble_client.dart';
import 'package:murmur/src/features/device/omi_device_controller.dart';

class DeviceConnectionScreen extends ConsumerWidget {
  const DeviceConnectionScreen({super.key});

  static const _ink = Color(0xFF171713);
  static const _muted = Color(0xFF6E716A);
  static const _surface = Color(0xFFF4F3ED);
  static const _accent = Color(0xFF5B5CE2);
  static const _success = Color(0xFF16845B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(omiDeviceControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFCFBF7),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  sliver: SliverList.list(
                    children: [
                      _Header(bluetoothState: controller.bluetoothState),
                      const SizedBox(height: 32),
                      _ConnectionCard(controller: controller),
                      if (controller.errorMessage case final message?) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(
                          message: message,
                          onDismiss: controller.clearError,
                        ),
                      ],
                      const SizedBox(height: 28),
                      _ScanHeader(controller: controller),
                      const SizedBox(height: 12),
                      _DeviceList(controller: controller),
                      const SizedBox(height: 28),
                      const _PrivacyNote(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.bluetoothState});

  final OmiBluetoothState bluetoothState;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'murmur',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: DeviceConnectionScreen._ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your wearable. Your models. Your memory.',
                style: TextStyle(
                  color: DeviceConnectionScreen._muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        _BluetoothBadge(state: bluetoothState),
      ],
    );
  }
}

class _BluetoothBadge extends StatelessWidget {
  const _BluetoothBadge({required this.state});

  final OmiBluetoothState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      OmiBluetoothState.ready => (
        'Bluetooth ready',
        DeviceConnectionScreen._success,
      ),
      OmiBluetoothState.poweredOff => ('Bluetooth off', Colors.orange.shade800),
      OmiBluetoothState.unauthorized => (
        'Access needed',
        Colors.orange.shade800,
      ),
      OmiBluetoothState.unsupported => ('Unsupported', Colors.red.shade700),
      OmiBluetoothState.locationServicesDisabled => (
        'Location off',
        Colors.orange.shade800,
      ),
      OmiBluetoothState.unknown => ('Checking Bluetooth', Colors.blueGrey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_rounded, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.controller});

  final OmiDeviceController controller;

  @override
  Widget build(BuildContext context) {
    final isConnected =
        controller.connectionState == OmiConnectionState.connected;
    final isConnecting =
        controller.connectionState == OmiConnectionState.connecting;
    final isDisconnecting =
        controller.connectionState == OmiConnectionState.disconnecting;
    final device = controller.selectedDevice;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isConnected
            ? const Color(0xFFEAF7F0)
            : DeviceConnectionScreen._surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isConnected
              ? const Color(0xFFB9E1CC)
              : const Color(0xFFE4E2D8),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isConnected
                  ? DeviceConnectionScreen._success
                  : DeviceConnectionScreen._ink,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              isConnected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.graphic_eq_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected
                      ? 'Connected'
                      : isConnecting
                      ? 'Connecting…'
                      : isDisconnecting
                      ? 'Disconnecting…'
                      : 'Not connected',
                  style: const TextStyle(
                    color: DeviceConnectionScreen._ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  device?.displayName ??
                      'Find your nearby Omi to begin pairing.',
                  style: const TextStyle(
                    color: DeviceConnectionScreen._muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (isConnected || isDisconnecting) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: isDisconnecting ? null : controller.disconnect,
              child: Text(isDisconnecting ? 'Waiting' : 'Disconnect'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF0EA),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFA44122),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Color(0xFF7D311A), height: 1.4),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanHeader extends StatelessWidget {
  const _ScanHeader({required this.controller});

  final OmiDeviceController controller;

  @override
  Widget build(BuildContext context) {
    final requiresAccess =
        controller.bluetoothState == OmiBluetoothState.unauthorized;
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nearby devices',
                style: TextStyle(
                  color: DeviceConnectionScreen._ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Only Omi wearables are shown.',
                style: TextStyle(color: DeviceConnectionScreen._muted),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: controller.canStartScan ? controller.scan : null,
          icon: controller.isScanning
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  requiresAccess
                      ? Icons.lock_open_rounded
                      : Icons.radar_rounded,
                  size: 18,
                ),
          label: Text(
            controller.isScanning
                ? 'Scanning'
                : requiresAccess
                ? 'Grant access'
                : 'Scan for Omi',
          ),
        ),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.controller});

  final OmiDeviceController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.devices;
    if (devices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8E6DE)),
        ),
        child: Column(
          children: [
            Icon(
              controller.isScanning
                  ? Icons.bluetooth_searching_rounded
                  : Icons.bluetooth_rounded,
              color: DeviceConnectionScreen._muted,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              controller.isScanning ? 'Searching for Omi…' : 'No Omi found yet',
              style: const TextStyle(
                color: DeviceConnectionScreen._ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              controller.isScanning
                  ? 'Keep your wearable awake and close to this phone.'
                  : 'Wake your Omi, keep it nearby, then start a scan.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DeviceConnectionScreen._muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final device in devices) ...[
          _DeviceTile(device: device, controller: controller),
          if (device != devices.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.controller});

  final OmiDevice device;
  final OmiDeviceController controller;

  @override
  Widget build(BuildContext context) {
    final isSelected = controller.selectedDevice?.id == device.id;
    final isConnecting =
        isSelected &&
        controller.connectionState == OmiConnectionState.connecting;
    final isConnected =
        isSelected &&
        controller.connectionState == OmiConnectionState.connected;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF9DD6B8)
              : const Color(0xFFE8E6DE),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFEFEEFF),
            child: Icon(
              Icons.mic_none_rounded,
              color: DeviceConnectionScreen._accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  style: const TextStyle(
                    color: DeviceConnectionScreen._ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_signalLabel(device.rssi)} · ${device.rssi} dBm',
                  style: const TextStyle(
                    color: DeviceConnectionScreen._muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed:
                controller.connectionState == OmiConnectionState.disconnected
                ? () => controller.connect(device)
                : null,
            child: Text(
              isConnecting
                  ? 'Connecting…'
                  : isConnected
                  ? 'Connected'
                  : 'Connect',
            ),
          ),
        ],
      ),
    );
  }

  static String _signalLabel(int rssi) {
    if (rssi >= -60) return 'Strong signal';
    if (rssi >= -75) return 'Good signal';
    return 'Weak signal';
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 18,
          color: DeviceConnectionScreen._muted,
        ),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'This milestone only establishes the Bluetooth connection. Murmur '
            'does not record or upload audio yet.',
            style: TextStyle(
              color: DeviceConnectionScreen._muted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
