/// The version of the language-neutral Murmur wire contract.
final class ProtocolVersion {
  const ProtocolVersion({required this.major, required this.minor});

  static const current = ProtocolVersion(major: 1, minor: 0);

  final int major;
  final int minor;

  factory ProtocolVersion.fromJson(Map<String, Object?> json) {
    final version = ProtocolVersion(
      major: parseUint32(json['major'], 'protocol.major'),
      minor: parseUint32(json['minor'], 'protocol.minor'),
    );
    if (!version.isSupported) {
      throw FormatException('unsupported protocol major ${version.major}');
    }
    return version;
  }

  Map<String, Object?> toJson() => {'major': major, 'minor': minor};

  bool get isSupported => major == current.major;

  @override
  bool operator ==(Object other) =>
      other is ProtocolVersion && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);
}

const _uint32Max = 0xffffffff;
final _asciiUint = RegExp(r'^[0-9]+$');
final _standardBase64 = RegExp(r'^[A-Za-z0-9+/]*$');
final _urlSafeBase64 = RegExp(r'^[A-Za-z0-9_-]*$');
final _uint64Max = BigInt.parse('18446744073709551615');

int parseUint32(Object? value, String field) {
  if (value is! int || value < 0 || value > _uint32Max) {
    throw FormatException('$field must be a uint32');
  }
  return value;
}

BigInt parseUint64(Object? value, String field) {
  final BigInt? parsed;
  if (value is int && value >= 0) {
    parsed = BigInt.from(value);
  } else if (value is String && _asciiUint.hasMatch(value)) {
    parsed = BigInt.tryParse(value);
  } else {
    parsed = null;
  }
  if (parsed == null || parsed > _uint64Max) {
    throw FormatException('$field must be an ASCII uint64 within range');
  }
  return parsed;
}

Map<String, Object?> requireObject(Object? value, String field) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

String requireNonEmptyString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

bool isValidBase64(String value) {
  var pad = 0;
  for (
    var index = value.length - 1;
    index >= 0 && value[index] == '=';
    index--
  ) {
    pad++;
  }
  if (pad > 2) return false;
  final raw = pad == 0 ? value : value.substring(0, value.length - pad);
  if (raw.contains('=') || raw.length % 4 == 1) return false;
  if (pad > 0 && (pad != (4 - raw.length % 4) % 4 || value.length % 4 != 0)) {
    return false;
  }
  return _standardBase64.hasMatch(raw) || _urlSafeBase64.hasMatch(raw);
}
