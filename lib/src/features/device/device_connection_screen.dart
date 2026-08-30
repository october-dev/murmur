import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murmur/src/features/device/omi_ble_client.dart';
import 'package:murmur/src/features/device/omi_device_controller.dart';

class DeviceConnectionScreen extends ConsumerWidget {
  const DeviceConnectionScreen({super.key});

  static const _ink = Color(0xFF161713);
  static const _muted = Color(0xFF74766F);
  static const _line = Color(0xFFE8E7E0);
  static const _accent = Color(0xFF5A5BE7);
  static const _success = Color(0xFF16845B);
  static const _background = Color(0xFFFDFCF8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(omiDeviceControllerProvider);
    final devices = controller.devices;
    final device =
        controller.selectedDevice ?? (devices.isEmpty ? null : devices.first);
    final action = _primaryAction(controller, device);
    final copy = _connectionCopy(controller, device);

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  sliver: SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      children: [
                        _Header(bluetoothState: controller.bluetoothState),
                        if (controller.errorMessage case final message?) ...[
                          const SizedBox(height: 18),
                          _ErrorMessage(
                            message: message,
                            onDismiss: controller.clearError,
                          ),
                        ],
                        const Spacer(),
                        Text(
                          copy.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.1,
                          ),
                        ),
                        const SizedBox(height: 9),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 330),
                          child: Text(
                            copy.subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        _OmiImageButton(
                          onPressed: action.callback,
                          actionLabel: action.label,
                          isBusy:
                              controller.isScanning ||
                              controller.connectionState ==
                                  OmiConnectionState.connecting,
                          isConnected:
                              controller.connectionState ==
                              OmiConnectionState.connected,
                          hasDevice: device != null,
                        ),
                        const SizedBox(height: 24),
                        _ActionHint(
                          label: action.label,
                          isEnabled: action.callback != null,
                          isConnected:
                              controller.connectionState ==
                              OmiConnectionState.connected,
                        ),
                        const SizedBox(height: 14),
                        _SecondaryAction(
                          controller: controller,
                          hasDevice: device != null,
                        ),
                        const Spacer(),
                        const _PrivacyLine(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static _PrimaryAction _primaryAction(
    OmiDeviceController controller,
    OmiDevice? device,
  ) {
    if (controller.connectionState == OmiConnectionState.connected) {
      return const _PrimaryAction(label: 'Omi connected');
    }
    if (controller.connectionState == OmiConnectionState.connecting) {
      return const _PrimaryAction(label: 'Connecting…');
    }
    if (controller.connectionState == OmiConnectionState.disconnecting) {
      return const _PrimaryAction(label: 'Disconnecting…');
    }
    if (controller.isScanning) {
      return const _PrimaryAction(label: 'Searching nearby…');
    }
    if (device != null) {
      return _PrimaryAction(
        label: 'Tap wearable to connect',
        callback: () => controller.connect(device),
      );
    }
    if (controller.canStartScan) {
      return _PrimaryAction(
        label: controller.bluetoothState == OmiBluetoothState.unauthorized
            ? 'Tap wearable to allow access'
            : 'Tap wearable to scan',
        callback: controller.scan,
      );
    }
    return const _PrimaryAction(label: 'Bluetooth unavailable');
  }

  static _ConnectionCopy _connectionCopy(
    OmiDeviceController controller,
    OmiDevice? device,
  ) {
    if (controller.connectionState == OmiConnectionState.connected) {
      return _ConnectionCopy(
        title: 'Connected',
        subtitle: '${device?.displayName ?? 'Omi'} is ready for Murmur.',
      );
    }
    if (controller.connectionState == OmiConnectionState.connecting) {
      return _ConnectionCopy(
        title: 'Connecting…',
        subtitle:
            'Keep ${device?.displayName ?? 'your Omi'} close to this phone.',
      );
    }
    if (controller.connectionState == OmiConnectionState.disconnecting) {
      return const _ConnectionCopy(
        title: 'Disconnecting…',
        subtitle: 'Closing the Bluetooth connection.',
      );
    }
    if (controller.isScanning) {
      return const _ConnectionCopy(
        title: 'Looking for Omi',
        subtitle: 'Keep your wearable awake and close to this phone.',
      );
    }
    if (device != null) {
      final count = controller.devices.length;
      return _ConnectionCopy(
        title: count == 1 ? 'Omi found' : '$count Omi devices found',
        subtitle: '${device.displayName} · ${_signalLabel(device.rssi)} signal',
      );
    }

    return switch (controller.bluetoothState) {
      OmiBluetoothState.poweredOff => const _ConnectionCopy(
        title: 'Turn on Bluetooth',
        subtitle: 'Murmur needs Bluetooth to find your wearable.',
      ),
      OmiBluetoothState.unsupported => const _ConnectionCopy(
        title: 'Bluetooth unavailable',
        subtitle: 'This phone does not support Bluetooth Low Energy.',
      ),
      OmiBluetoothState.locationServicesDisabled => const _ConnectionCopy(
        title: 'Turn on location',
        subtitle:
            'This Android version requires location for nearby discovery.',
      ),
      OmiBluetoothState.unauthorized => const _ConnectionCopy(
        title: 'Connect your Omi',
        subtitle: 'Tap the wearable and allow Bluetooth access when asked.',
      ),
      OmiBluetoothState.unknown => const _ConnectionCopy(
        title: 'Connect your Omi',
        subtitle: 'Checking Bluetooth on this phone…',
      ),
      OmiBluetoothState.ready => const _ConnectionCopy(
        title: 'Connect your Omi',
        subtitle: 'Keep it nearby, then tap the wearable to start.',
      ),
    };
  }

  static String _signalLabel(int rssi) {
    if (rssi >= -60) return 'strong';
    if (rssi >= -75) return 'good';
    return 'weak';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.bluetoothState});

  final OmiBluetoothState bluetoothState;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'murmur',
            style: TextStyle(
              color: DeviceConnectionScreen._ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.1,
            ),
          ),
        ),
        _BluetoothStatus(state: bluetoothState),
      ],
    );
  }
}

class _BluetoothStatus extends StatelessWidget {
  const _BluetoothStatus({required this.state});

  final OmiBluetoothState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      OmiBluetoothState.ready => ('Ready', DeviceConnectionScreen._success),
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
      OmiBluetoothState.unknown => ('Checking', DeviceConnectionScreen._muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: DeviceConnectionScreen._line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: DeviceConnectionScreen._ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OmiImageButton extends StatelessWidget {
  const _OmiImageButton({
    required this.onPressed,
    required this.actionLabel,
    required this.isBusy,
    required this.isConnected,
    required this.hasDevice,
  });

  final VoidCallback? onPressed;
  final String actionLabel;
  final bool isBusy;
  final bool isConnected;
  final bool hasDevice;

  @override
  Widget build(BuildContext context) {
    final ringColor = isConnected
        ? DeviceConnectionScreen._success
        : hasDevice
        ? DeviceConnectionScreen._accent
        : DeviceConnectionScreen._line;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: actionLabel,
      child: Tooltip(
        message: actionLabel,
        child: SizedBox.square(
          dimension: 252,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isBusy)
                const Positioned.fill(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: DeviceConnectionScreen._accent,
                    backgroundColor: DeviceConnectionScreen._line,
                  ),
                )
              else
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor, width: 2),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: const Color(0xFFF0EFEA),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('omi-action'),
                    customBorder: const CircleBorder(),
                    onTap: onPressed,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Image.asset(
                        'assets/images/omi-wearable.webp',
                        fit: BoxFit.contain,
                        semanticLabel: 'Omi wearable',
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: 24,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? DeviceConnectionScreen._success
                        : hasDevice
                        ? DeviceConnectionScreen._accent
                        : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isConnected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionHint extends StatelessWidget {
  const _ActionHint({
    required this.label,
    required this.isEnabled,
    required this.isConnected,
  });

  final String label;
  final bool isEnabled;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEnabled) ...[
          const Icon(
            Icons.touch_app_outlined,
            size: 16,
            color: DeviceConnectionScreen._muted,
          ),
          const SizedBox(width: 6),
        ] else if (isConnected) ...[
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: DeviceConnectionScreen._success,
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            color: isConnected
                ? DeviceConnectionScreen._success
                : DeviceConnectionScreen._muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.controller, required this.hasDevice});

  final OmiDeviceController controller;
  final bool hasDevice;

  @override
  Widget build(BuildContext context) {
    if (controller.connectionState == OmiConnectionState.connected) {
      return TextButton(
        onPressed: controller.disconnect,
        child: const Text('Disconnect'),
      );
    }
    if (hasDevice &&
        controller.connectionState == OmiConnectionState.disconnected &&
        !controller.isScanning) {
      return TextButton.icon(
        onPressed: controller.canStartScan ? controller.scan : null,
        icon: const Icon(Icons.refresh_rounded, size: 17),
        label: const Text('Scan again'),
      );
    }
    return const SizedBox(height: 48);
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1EC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFFA44122),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF7D311A),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 17),
          ),
        ],
      ),
    );
  }
}

class _PrivacyLine extends StatelessWidget {
  const _PrivacyLine();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: DeviceConnectionScreen._muted,
        ),
        SizedBox(width: 6),
        Text(
          'Bluetooth only · audio remains off',
          style: TextStyle(color: DeviceConnectionScreen._muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _PrimaryAction {
  const _PrimaryAction({required this.label, this.callback});

  final String label;
  final VoidCallback? callback;
}

class _ConnectionCopy {
  const _ConnectionCopy({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}
