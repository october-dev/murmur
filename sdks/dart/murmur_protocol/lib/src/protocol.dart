/// The version of the language-neutral Murmur wire contract.
final class ProtocolVersion {
  const ProtocolVersion({required this.major, required this.minor});

  static const current = ProtocolVersion(major: 1, minor: 0);

  final int major;
  final int minor;

  factory ProtocolVersion.fromJson(Map<String, Object?> json) {
    final major = json['major'];
    final minor = json['minor'];
    if (major is! num || minor is! num) {
      throw const FormatException(
        'protocol.major and protocol.minor are required numbers',
      );
    }
    return ProtocolVersion(major: major.toInt(), minor: minor.toInt());
  }

  Map<String, Object?> toJson() => {'major': major, 'minor': minor};

  bool get isSupported => major == current.major && minor <= current.minor;

  @override
  bool operator ==(Object other) =>
      other is ProtocolVersion && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);
}
