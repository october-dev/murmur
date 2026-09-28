/// Validation helpers shared by the ProtoJSON payload validators.
///
/// This library is internal to the package and is not exported.
library;

import 'protocol.dart';

/// Returns the value of [field], or [fallback] when the field is absent.
///
/// An explicit `null` is returned as-is so validation rejects it.
Object? fieldOr(Map<String, Object?> body, String field, Object? fallback) =>
    body.containsKey(field) ? body[field] : fallback;

/// Returns [value] when it is one of [names].
String requireEnumName(Object? value, Set<String> names, String field) {
  if (value is! String || !names.contains(value)) {
    throw FormatException('$field must be a known enum name');
  }
  return value;
}

/// Returns [value] when it is a known name other than `*_UNSPECIFIED`.
///
/// Required discriminators use this; optional enums accept `*_UNSPECIFIED`
/// and treat it as absent.
String requireSpecifiedEnumName(
  Object? value,
  Set<String> names,
  String field,
) {
  final name = requireEnumName(value, names, field);
  if (name.endsWith('_UNSPECIFIED')) {
    throw FormatException('$field must not be unspecified');
  }
  return name;
}

/// Whether an optional enum [field] is set; an explicit `*_UNSPECIFIED` name
/// counts as absent.
bool isEnumSet(Map<String, Object?> body, String field) {
  final value = body[field];
  return body.containsKey(field) &&
      !(value is String && value.endsWith('_UNSPECIFIED'));
}

/// Requires an error object exactly when [failed], unless [errorAllowed]
/// permits one in a non-failed state.
void validateOutcome(
  Map<String, Object?> body,
  String name, {
  required bool failed,
  bool errorAllowed = false,
}) {
  if (body.containsKey('error')) {
    requireObject(body['error'], '$name.error');
    if (!failed && !errorAllowed) {
      throw FormatException('$name.error is only allowed when failed');
    }
  } else if (failed) {
    throw FormatException('$name.error is required when failed');
  }
}

/// Requires a finite number from 0 through 1.
void validateUnitInterval(Object? value, String field) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) {
    throw FormatException('$field must be between 0 and 1');
  }
}

/// Requires [completed] not to exceed a known (non-zero) [total].
void validateProgress(BigInt completed, BigInt total, String name) {
  if (total > BigInt.zero && completed > total) {
    throw FormatException('$name progress exceeds its total');
  }
}

/// Returns [value] when it is a JSON array.
List<Object?> requireList(Object? value, String field) {
  if (value is! List<Object?>) {
    throw FormatException('$field must be an array');
  }
  return value;
}
