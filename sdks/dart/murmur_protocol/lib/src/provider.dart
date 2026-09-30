import 'runtime.dart';
import 'session.dart';

/// An optional behavior a [VoiceProvider] declares instead of simulating.
///
/// Partial and final transcripts, [ProviderSession.finalize],
/// [ProviderSession.stop], and [ProviderSession.addFrame] backpressure are
/// baseline behavior, not capabilities. An adapter that produces no
/// hypotheses simply emits no [ProviderPartial] events.
enum ProviderCapability {
  /// [ProviderSession.mute] closes the input gate synchronously and flushes the
  /// already accepted tail while the session stays warm.
  immediateMute,

  /// [ProviderSession.unmute] reopens a muted session without reconnecting.
  ///
  /// This capability is valid only together with [immediateMute].
  warmUnmute,

  /// The session may emit [ProviderReadiness] when real audio is live.
  realAudioReadiness,

  /// The session may emit normalized [ProviderAmplitude] levels.
  amplitude,

  /// The session may emit [ProviderRejected], for example when optional
  /// speaker verification rejects a segment.
  rejectedFinals,
}

/// Provider-neutral metadata for one [ProviderSession].
///
/// The request carries no credentials, device identifiers, or capture mode.
/// Providers are mode-neutral, and vendor tuning and credentials belong in the
/// concrete adapter's configuration.
final class ProviderSessionRequest {
  /// Creates a session request for audio in [format].
  ///
  /// A blank [sessionId] throws [ArgumentError].
  ProviderSessionRequest({required this.sessionId, required this.format}) {
    if (sessionId.trim().isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
  }

  /// The caller's identifier for this recognition session.
  ///
  /// It correlates diagnostics and need not equal [AudioFrame.sessionId],
  /// because a connector session may span several recognition sessions.
  final String sessionId;

  /// The format of every frame passed to [ProviderSession.addFrame].
  final AudioFormat format;
}

/// One recognition-side event from a [ProviderSession].
///
/// Delivery order on [ProviderSession.events] is the total order of a session,
/// so events carry no session identifier or sequence number.
sealed class ProviderEvent {
  const ProviderEvent();
}

/// The complete, replaceable hypothesis of the open segment.
///
/// The open segment is the text since the last [ProviderFinal] or
/// [ProviderRejected]. Each partial replaces the previous one; it is not a
/// delta, and adapters accumulate vendor deltas before emitting. An empty
/// [text] clears the displayed hypothesis.
final class ProviderPartial extends ProviderEvent {
  /// Creates a partial hypothesis.
  const ProviderPartial(this.text);

  /// The full hypothesis of the open segment.
  final String text;
}

/// A committed transcript fragment that closes the open segment.
///
/// Finals are append-only, in order, and never revised. An adapter whose vendor
/// rewrites committed text holds that text as a partial until it is stable.
/// [text] is a verbatim fragment that includes any separator it needs, so an
/// utterance is the exact concatenation of its finals.
final class ProviderFinal extends ProviderEvent {
  /// Creates a final fragment.
  ///
  /// An empty [text] throws [ArgumentError]; an operation that recognized
  /// nothing completes with zero finals instead.
  ProviderFinal(this.text) {
    if (text.isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
  }

  /// The verbatim fragment, including any leading separator.
  final String text;
}

/// A committed segment the provider refused.
///
/// It closes and discards the open segment. Rejected text may be displayed but
/// never enters transcript assembly or dispatch. Emitted only with
/// [ProviderCapability.rejectedFinals].
final class ProviderRejected extends ProviderEvent {
  /// Creates a rejected segment.
  ///
  /// An empty [text] throws [ArgumentError].
  ProviderRejected(this.text) {
    if (text.isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
  }

  /// The rejected text, for display only.
  final String text;
}

/// Whether the provider currently receives real audio.
///
/// Emitted only with [ProviderCapability.realAudioReadiness].
final class ProviderReadiness extends ProviderEvent {
  /// Creates a readiness event.
  const ProviderReadiness({required this.live});

  /// Whether real audio is live.
  final bool live;
}

/// A normalized input level.
///
/// Emitted only with [ProviderCapability.amplitude].
final class ProviderAmplitude extends ProviderEvent {
  /// Creates an amplitude event.
  ///
  /// A [value] outside 0 to 1 inclusive, or NaN, throws [ArgumentError].
  ProviderAmplitude(this.value) {
    if (value.isNaN || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value', 'must be between 0 and 1');
    }
  }

  /// The level between 0 and 1 inclusive.
  final double value;
}

/// A terminal failure after [ProviderSession.start] completed.
///
/// It is the last event; the stream is done immediately afterwards. A startup
/// failure is reported only through [ProviderSession.start].
final class ProviderFailure extends ProviderEvent {
  /// Creates a failure event.
  const ProviderFailure(this.error);

  /// The cause, which every pending operation also completes with.
  final VoiceError error;
}

/// A streaming transcription adapter that creates [ProviderSession]s.
///
/// Credentials enter only through the concrete adapter's constructor or factory
/// configuration. No contract type carries a credential, and an adapter must
/// never place credentials, signed URLs, transcript text, audio, or device
/// identifiers in a [VoiceError] message or metadata.
///
/// The provider object may share safe provider-level resources, such as an
/// authenticated client, a model handle, or rate-limit state, across its
/// sessions. Decoder and transcript state never cross sessions.
abstract interface class VoiceProvider {
  /// A stable identifier used for transcript attribution and diagnostics.
  String get id;

  /// The stable, unmodifiable set of optional behaviors this provider
  /// implements.
  Set<ProviderCapability> get capabilities;

  /// Creates an inert session for [request].
  ///
  /// This is synchronous, performs no I/O, and emits nothing, so the caller can
  /// subscribe to [ProviderSession.events] before calling
  /// [ProviderSession.start]. If the adapter cannot decode `request.format`, it
  /// throws a [VoiceError] with code `unsupported_format` that is not
  /// retryable.
  ProviderSession createSession(ProviderSessionRequest request);
}

/// One one-shot recognition session.
///
/// ## Lifecycle
///
/// Create the session, subscribe to [events], await [start], await each
/// [addFrame], then end with [finalize] (graceful) or [stop] (hard cancel).
/// A session never reconnects or restarts; a retry is a new session from
/// [VoiceProvider.createSession], and a failed session is never resumed.
///
/// ## Transcript assembly
///
/// A [ProviderPartial] replaces the open segment's hypothesis. A
/// [ProviderFinal] commits it; finals are never revised, and the utterance is
/// the exact concatenation of its finals. A [ProviderRejected] commits and
/// discards the open segment. Text arrives only on [events]: an operation's
/// finals are added before its future completes, and stream done is
/// authoritative.
///
/// ## Operations by state
///
/// Operations on the open, started session follow the member docs. Otherwise:
///
/// | State | [start] | [addFrame] | [mute] / [unmute] | [finalize] | [stop] |
/// | --- | --- | --- | --- | --- | --- |
/// | not started or start pending | starts, or shares the pending start | [StateError] | [StateError] | [StateError] | cancels |
/// | [finalize] pending | [StateError] | discarded | [StateError] | same future | wins with `cancelled` |
/// | ended by [finalize] | [StateError] | discarded | [StateError] | same future | completes |
/// | ended by [stop] | [StateError] | `cancelled` | `cancelled` | `cancelled` | same future |
/// | ended by failure | [StateError] | that error | that error | that error | completes |
///
/// "Ended by [stop]" and "ended by failure" include a [finalize] that was
/// pending when the session ended: the ending cause decides every outcome.
/// Without its capability, [mute] or [unmute] throws [UnsupportedError] in
/// every state.
///
/// ## Buffering and backpressure
///
/// The caller owns pre-open buffering: it keeps a bounded pre-roll and drains
/// it in order once [start] or [unmute] completes. At most one [addFrame] is
/// outstanding. Each adapter bounds its internal queue, documents that bound
/// and any maximum frame size, and keeps a write pending while the queue is
/// full instead of dropping or growing it. An empty queue always admits one
/// valid frame, and a frame over the documented maximum size is rejected
/// synchronously with [ArgumentError].
///
/// ## Failures
///
/// Documented [VoiceError.code] values are `cancelled`, `unsupported_format`
/// (not retryable), `unauthorized` (not retryable), `rate_limited` (retryable,
/// with an optional decimal-string `metadata['retryAfterMs']`), and
/// `provider_disconnected` (retryable). Other codes are adapter-defined. An
/// unexpected transport close is a [ProviderFailure] with
/// `provider_disconnected`. Finals already emitted stay valid; accepted audio
/// that was not yet decoded is lost.
abstract interface class ProviderSession {
  /// Transcript, readiness, amplitude, and failure events in delivery order.
  ///
  /// The stream is single-subscription, and done means the session is closed.
  /// After [stop] the adapter adds no new events, but events already queued
  /// for a paused listener may still arrive on resume, so consumers must fence
  /// callbacks from a superseded session. Closing never waits for an absent or
  /// paused listener.
  Stream<ProviderEvent> get events;

  /// Opens the session and completes when frames can be accepted.
  ///
  /// Calls made while the first start is pending share its future. Once startup
  /// has settled or the session has ended, calling this throws [StateError].
  /// A startup failure, such as `rate_limited` or `unauthorized`, is reported
  /// only through this future; the adapter releases what it acquired and
  /// closes [events]. If [stop] wins against a pending start, this completes
  /// with a [VoiceError] whose code is `cancelled`.
  Future<void> start();

  /// Offers one frame and completes when the adapter's bounded queue accepts
  /// it.
  ///
  /// Awaiting the future is the backpressure signal. Calling this before
  /// [start] completes, while [unmute] is pending, or while another frame is
  /// outstanding throws [StateError]. A frame over the adapter's documented
  /// maximum size throws [ArgumentError]. An empty queue always accepts a valid
  /// frame, so a write that finds it empty never stays pending. Frames must
  /// match the request format and have strictly increasing
  /// [AudioFrame.sequence]; an adapter may reject a violation with
  /// [ArgumentError]. A frame offered
  /// while muted, while [finalize] is pending, or after a successful
  /// [finalize] is discarded and completes normally. [stop] completes a frame
  /// that was not yet accepted with `cancelled`, and a failure completes it
  /// with that failure's error.
  Future<void> addFrame(AudioFrame frame);

  /// Closes the input gate synchronously and flushes the accepted tail.
  ///
  /// Requires [ProviderCapability.immediateMute]; otherwise this throws
  /// [UnsupportedError]. Audio accepted before the call, including a pending
  /// [addFrame], is decoded and its finals are emitted before the future
  /// completes. The session stays warm. Muting an already muted session
  /// completes immediately.
  ///
  /// At most one of [mute], [unmute], and [finalize] is in flight: repeating
  /// the pending call shares its future, and a different one throws
  /// [StateError].
  Future<void> mute();

  /// Reopens a muted session without reconnecting.
  ///
  /// Requires [ProviderCapability.warmUnmute]; otherwise this throws
  /// [UnsupportedError]. Completes once frames are accepted again. Unmuting an
  /// open session completes immediately. Transitions are serialized as
  /// described on [mute].
  Future<void> unmute();

  /// Gracefully finishes the session.
  ///
  /// The input gate closes synchronously. Audio accepted before the call is
  /// decoded, the remaining finals are emitted, resources are released, and
  /// [events] closes. Zero finals is a valid outcome. Repeated and concurrent
  /// calls return the identical future, which completes with `cancelled` if
  /// [stop] wins or with the failure's error if the provider fails. Calling
  /// this before [start] completes throws [StateError].
  Future<void> finalize();

  /// Cancels recognition and releases resources.
  ///
  /// The input gate closes synchronously, and unaccepted audio and pending
  /// hypotheses are discarded. Every unfinished operation completes with
  /// `cancelled`. Concurrent and repeated calls share one future, which never
  /// completes with an error.
  Future<void> stop();
}
