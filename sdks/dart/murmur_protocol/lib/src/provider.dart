import 'runtime.dart';
import 'session.dart';

/// An optional behavior a [VoiceProvider] declares instead of assuming.
///
/// Each capability has a defined absent behavior in the coordinator:
///
/// - [partialTranscripts] absent: partial text stays empty.
/// - [warmGate] absent: hold-to-talk release finalizes and stops instead of
///   parking the session warm-muted.
/// - [gracefulFinalize] absent: finalization is a hard [ProviderSession.stop].
/// - [realAudioReadiness] absent: capture readiness follows the coordinator's
///   frame predicate instead of provider readiness events.
/// - [amplitude] absent: no audio-level events are published.
/// - [rejectedFinal] absent: the provider never rejects a segment.
enum ProviderCapability {
  partialTranscripts,
  warmGate,
  gracefulFinalize,
  realAudioReadiness,
  amplitude,
  rejectedFinal,
}

/// One recognition-side event from a [ProviderSession].
///
/// Every transcript chunk arrives here. [ProviderSession.finalize] only
/// acknowledges completion; the coordinator assembles the utterance.
sealed class ProviderEvent {
  const ProviderEvent();
}

/// An in-progress hypothesis that later text replaces.
final class ProviderPartial extends ProviderEvent {
  const ProviderPartial(this.text);

  final String text;
}

/// A committed transcript segment.
final class ProviderFinal extends ProviderEvent {
  const ProviderFinal(this.text);

  final String text;
}

/// A committed segment the provider refused, for example on speaker rejection.
///
/// Rejected text may be displayed but never enters an utterance.
final class ProviderRejected extends ProviderEvent {
  const ProviderRejected(this.text);

  final String text;
}

/// Whether the provider currently receives meaningful audio.
final class ProviderReadiness extends ProviderEvent {
  const ProviderReadiness({required this.live});

  final bool live;
}

/// A normalized input level between 0 and 1.
final class ProviderAmplitude extends ProviderEvent {
  ProviderAmplitude(this.value) {
    if (value.isNaN || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value', 'must be between 0 and 1');
    }
  }

  final double value;
}

/// A terminal provider failure.
final class ProviderFailure extends ProviderEvent {
  const ProviderFailure(this.error);

  final VoiceError error;
}

/// The provider session closed.
///
/// [expected] is `true` after [ProviderSession.finalize] or
/// [ProviderSession.stop]; an unexpected close is a disconnect.
final class ProviderClosed extends ProviderEvent {
  const ProviderClosed({required this.expected});

  final bool expected;
}

/// The acknowledgement of a graceful finalization.
final class FinalizationOutcome {
  const FinalizationOutcome({required this.timedOut});

  /// Whether the bounded wait elapsed before the provider acknowledged.
  ///
  /// A timed-out finalization is graceful, not an error: everything already
  /// delivered is kept and the session still stops.
  final bool timedOut;
}

/// One live recognition session.
///
/// The session starts with its input gate open. Every method is safe to call
/// after termination; [stop] is idempotent and [finalize] is single-flight.
abstract interface class ProviderSession {
  /// Delivers one frame.
  ///
  /// Calls are serialized by the caller; awaiting the returned future is the
  /// backpressure signal. Throwing rejects the frame and fails the capture.
  Future<void> addFrame(AudioFrame frame);

  /// Opens or closes the warm input gate without ending the session.
  ///
  /// Closing with [flushAcceptedAudio] lets audio accepted before the close
  /// finish decoding; the returned future completes when that flush is done.
  /// This is distinct from [finalize], which is terminal.
  Future<void> setInputGate({required bool open, bool flushAcceptedAudio});

  /// Partial, final, rejected, readiness, amplitude, failure, and closed
  /// events, in delivery order.
  ///
  /// The stream is single-subscription and completes after termination.
  Stream<ProviderEvent> get events;

  /// Closes the gate, finishes decoding accepted audio, and releases the
  /// session.
  ///
  /// Text arrives on [events]; the returned outcome is an acknowledgement only.
  /// Without [ProviderCapability.gracefulFinalize] this behaves like [stop].
  Future<FinalizationOutcome> finalize();

  /// Cancels decoding and releases resources.
  Future<void> stop();
}

/// A recognition adapter that creates [ProviderSession]s.
abstract interface class VoiceProvider {
  /// Optional behaviors this provider implements.
  Set<ProviderCapability> get capabilities;

  /// Opens a session for audio in [negotiated].
  ///
  /// A failure or timeout throws [VoiceError] after releasing every resource
  /// acquired by this attempt.
  Future<ProviderSession> start(AudioFormat negotiated);
}
