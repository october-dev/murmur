import 'session.dart';
import 'source.dart';

/// The lifecycle state of an in-process voice session.
enum SessionState {
  /// Connected and ready to start capture.
  idle,

  /// Acquiring and negotiating capture resources.
  starting,

  /// Producing audio frames.
  listening,

  /// Finishing audio already accepted by the session.
  finalizing,

  /// Capture has ended and resources have been released.
  stopped,

  /// Capture ended because of a runtime failure.
  error,
}

/// A typed in-process runtime failure.
final class VoiceError implements Exception {
  /// Creates a voice runtime failure.
  VoiceError({
    required this.code,
    required this.message,
    required this.retryable,
    Map<String, String> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata);

  /// A stable machine-readable failure code.
  final String code;

  /// A human-readable message that is safe to display.
  final String message;

  /// Whether retrying the failed operation may succeed.
  final bool retryable;

  /// Additional non-sensitive machine-readable details.
  final Map<String, String> metadata;

  @override
  String toString() => 'VoiceError($code): $message';
}

/// Discovers voice sources and creates idle sessions for them.
abstract interface class VoiceConnector {
  /// Discovers sources until the single-subscription stream is cancelled.
  ///
  /// Cancelling the subscription must stop the active scan and release its
  /// resources.
  Stream<VoiceSource> discoverSources();

  /// Connects to [source] and returns an idle session that is not capturing.
  ///
  /// A failure or timeout throws [VoiceError]. Before completing with an error,
  /// the connector must release every resource acquired by this attempt.
  Future<VoiceSession> connect(VoiceSource source);
}

/// One mode-neutral voice capture connection.
///
/// Every getter remains readable after the session terminates.
abstract interface class VoiceSession {
  /// The identifier used by frames and events from this session.
  String get sessionId;

  /// The source connected to this session.
  VoiceSource get source;

  /// The negotiated format, or `null` until [start] negotiates one.
  ///
  /// The last negotiated format remains readable after termination.
  AudioFormat? get format;

  /// The current lifecycle snapshot.
  SessionState get state;

  /// Broadcast lifecycle transitions with no replay.
  ///
  /// Consumers should subscribe first and then read [state], tolerating one
  /// duplicate. The snapshot may be newer than an asynchronously delivered
  /// transition. This stream must never delay cleanup when unlistened or paused.
  Stream<SessionState> get stateChanges;

  /// The terminal failure, or `null` when the session has not failed.
  ///
  /// An implementation must set this before emitting [SessionState.error].
  VoiceError? get error;

  /// Audio frames produced while the session is listening.
  ///
  /// The stream is single-subscription and completes after termination.
  /// Implementations must bound all pending frames, including events queued by
  /// their stream controller, and document which frames are dropped when the
  /// consumer is absent or paused. Stream drainage must never delay cleanup.
  Stream<AudioFrame> get frames;

  /// Starts capture and negotiates [format].
  ///
  /// [requestedFormat] is a preference; the negotiated result is exposed by
  /// [format]. Calling this after termination throws [StateError]. If [stop] or
  /// [close] wins against a pending start, this completes with a [VoiceError]
  /// whose code is `cancelled`, and late acquisitions are released.
  Future<void> start({AudioFormat? requestedFormat});

  /// Stops capture and releases resources.
  ///
  /// Concurrent and repeated calls share one cleanup operation. [reason] is
  /// optional diagnostic context and must not contain speech or credentials.
  /// Stopping is terminal; another capture requires a newly connected session.
  Future<void> stop({String? reason});

  /// Stops capture and releases resources.
  ///
  /// Concurrent and repeated calls to [stop] and [close] share one cleanup
  /// operation and await the same outcome.
  Future<void> close();
}
