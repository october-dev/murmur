export interface ProtocolVersion {
  major: number
  minor: number
}

export const currentProtocol: ProtocolVersion = { major: 1, minor: 1 }
const uint64Max = (1n << 64n) - 1n

export function isSupported(protocol: ProtocolVersion): boolean {
  return protocol.major === currentProtocol.major
}

export const runtimePayloadKinds = [
  'sessionStateChanged',
  'captureReadiness',
  'audioLevel',
  'transcript',
  'error',
  'intentProposal',
  'confirmationRequest',
  'actionResult',
  'providerStatus',
  'inputGateStatus',
  'wakePhrase',
  'batchProgress'
] as const
export type RuntimePayloadKind = (typeof runtimePayloadKinds)[number]
export type RuntimePayload = Readonly<Record<string, unknown>>

export const sessionCommandKinds = [
  'start',
  'stop',
  'inputGate',
  'finalize',
  'speakerVerification',
  'startBatch'
] as const
export type SessionCommandKind = (typeof sessionCommandKinds)[number]

export const enginePayloadKinds = [
  'engineStatus',
  'voicePackStatus',
  'microphoneStatus',
  'speechOutput',
  'error'
] as const
export type EnginePayloadKind = (typeof enginePayloadKinds)[number]

export const engineCommandKinds = ['voicePack', 'speak', 'cancelSpeech'] as const
export type EngineCommandKind = (typeof engineCommandKinds)[number]

export const transcriptKinds = [
  'TRANSCRIPT_KIND_UNSPECIFIED',
  'TRANSCRIPT_KIND_PARTIAL',
  'TRANSCRIPT_KIND_FINAL',
  'TRANSCRIPT_KIND_REJECTED'
] as const
export const sessionStates = [
  'SESSION_STATE_UNSPECIFIED',
  'SESSION_STATE_IDLE',
  'SESSION_STATE_STARTING',
  'SESSION_STATE_LISTENING',
  'SESSION_STATE_WARM_MUTED',
  'SESSION_STATE_FINALIZING',
  'SESSION_STATE_STOPPED',
  'SESSION_STATE_ERROR'
] as const
export const captureModes = [
  'CAPTURE_MODE_UNSPECIFIED',
  'CAPTURE_MODE_TAP_TO_SPEAK',
  'CAPTURE_MODE_HOLD_TO_TALK',
  'CAPTURE_MODE_HANDS_FREE',
  'CAPTURE_MODE_WAKE_PHRASE'
] as const
export const audioEncodings = [
  'AUDIO_ENCODING_PCM_S16LE',
  'AUDIO_ENCODING_PCM_F32LE',
  'AUDIO_ENCODING_OPUS'
] as const
export const voiceSourceTransports = [
  'SOURCE_TRANSPORT_BLUETOOTH_LE',
  'SOURCE_TRANSPORT_LOCAL_AUDIO',
  'SOURCE_TRANSPORT_NETWORK',
  'SOURCE_TRANSPORT_FILE',
  'SOURCE_TRANSPORT_SYNTHETIC'
] as const
export const voiceSourceCapabilities = [
  'SOURCE_CAPABILITY_LIVE_AUDIO',
  'SOURCE_CAPABILITY_STORED_AUDIO',
  'SOURCE_CAPABILITY_BATTERY',
  'SOURCE_CAPABILITY_HARDWARE_CONTROL',
  'SOURCE_CAPABILITY_OUTPUT_AUDIO',
  'SOURCE_CAPABILITY_BACKGROUND_CAPTURE',
  'SOURCE_CAPABILITY_INPUT_MUTE',
  'SOURCE_CAPABILITY_SPEAKER_VERIFICATION'
] as const

// Required discriminators reject the *_UNSPECIFIED name; optional enums treat it
// as absent.
export const engineLocalities = [
  'ENGINE_LOCALITY_UNSPECIFIED',
  'ENGINE_LOCALITY_ON_DEVICE',
  'ENGINE_LOCALITY_REMOTE'
] as const
export const enginePlatforms = [
  'ENGINE_PLATFORM_UNSPECIFIED',
  'ENGINE_PLATFORM_MACOS',
  'ENGINE_PLATFORM_WINDOWS',
  'ENGINE_PLATFORM_LINUX',
  'ENGINE_PLATFORM_IOS',
  'ENGINE_PLATFORM_ANDROID'
] as const
export const engineReadinessStates = [
  'ENGINE_READINESS_UNSPECIFIED',
  'ENGINE_READINESS_NOT_READY',
  'ENGINE_READINESS_PREPARING',
  'ENGINE_READINESS_READY',
  'ENGINE_READINESS_FAILED'
] as const
export const voicePackStates = [
  'VOICE_PACK_STATE_UNSPECIFIED',
  'VOICE_PACK_STATE_NOT_INSTALLED',
  'VOICE_PACK_STATE_PREPARING',
  'VOICE_PACK_STATE_REPAIRING',
  'VOICE_PACK_STATE_READY',
  'VOICE_PACK_STATE_FAILED',
  'VOICE_PACK_STATE_UNSUPPORTED'
] as const
export const voicePackComponentKinds = [
  'VOICE_PACK_COMPONENT_KIND_UNSPECIFIED',
  'VOICE_PACK_COMPONENT_KIND_TRANSCRIPTION',
  'VOICE_PACK_COMPONENT_KIND_VOICE_ACTIVITY',
  'VOICE_PACK_COMPONENT_KIND_SPEECH_OUTPUT',
  'VOICE_PACK_COMPONENT_KIND_WAKE_PHRASE',
  'VOICE_PACK_COMPONENT_KIND_SPEAKER_VERIFICATION'
] as const
export const voicePackActions = [
  'VOICE_PACK_ACTION_UNSPECIFIED',
  'VOICE_PACK_ACTION_PREPARE',
  'VOICE_PACK_ACTION_RETRY',
  'VOICE_PACK_ACTION_REPAIR'
] as const
export const microphonePermissions = [
  'MICROPHONE_PERMISSION_UNSPECIFIED',
  'MICROPHONE_PERMISSION_NOT_DETERMINED',
  'MICROPHONE_PERMISSION_GRANTED',
  'MICROPHONE_PERMISSION_DENIED',
  'MICROPHONE_PERMISSION_RESTRICTED'
] as const
export const microphoneRoutes = [
  'MICROPHONE_ROUTE_UNSPECIFIED',
  'MICROPHONE_ROUTE_BUILT_IN',
  'MICROPHONE_ROUTE_WIRED',
  'MICROPHONE_ROUTE_BLUETOOTH',
  'MICROPHONE_ROUTE_USB',
  'MICROPHONE_ROUTE_VIRTUAL'
] as const
export const microphoneReadinessStates = [
  'MICROPHONE_READINESS_UNSPECIFIED',
  'MICROPHONE_READINESS_UNAVAILABLE',
  'MICROPHONE_READINESS_WARMING',
  'MICROPHONE_READINESS_READY',
  'MICROPHONE_READINESS_INTERRUPTED'
] as const
export const microphoneInterruptions = [
  'MICROPHONE_INTERRUPTION_UNSPECIFIED',
  'MICROPHONE_INTERRUPTION_SYSTEM',
  'MICROPHONE_INTERRUPTION_OTHER_APPLICATION',
  'MICROPHONE_INTERRUPTION_DEVICE_REMOVED'
] as const
export const speechOutputStates = [
  'SPEECH_OUTPUT_STATE_UNSPECIFIED',
  'SPEECH_OUTPUT_STATE_PREPARING',
  'SPEECH_OUTPUT_STATE_SPEAKING',
  'SPEECH_OUTPUT_STATE_ECHO_CLEARING',
  'SPEECH_OUTPUT_STATE_COMPLETED',
  'SPEECH_OUTPUT_STATE_CANCELLED',
  'SPEECH_OUTPUT_STATE_FAILED'
] as const
export const providerStates = [
  'PROVIDER_STATE_UNSPECIFIED',
  'PROVIDER_STATE_STARTING',
  'PROVIDER_STATE_ACTIVE',
  'PROVIDER_STATE_FINALIZING',
  'PROVIDER_STATE_FINALIZED',
  'PROVIDER_STATE_CANCELLED',
  'PROVIDER_STATE_FAILED'
] as const
export const inputGateCauses = [
  'INPUT_GATE_CAUSE_UNSPECIFIED',
  'INPUT_GATE_CAUSE_HOST',
  'INPUT_GATE_CAUSE_FINALIZATION',
  'INPUT_GATE_CAUSE_SPEECH_OUTPUT',
  'INPUT_GATE_CAUSE_ECHO_CLEARANCE',
  'INPUT_GATE_CAUSE_INTERRUPTION'
] as const
export const wakePhraseStages = [
  'WAKE_PHRASE_STAGE_UNSPECIFIED',
  'WAKE_PHRASE_STAGE_DETECTED',
  'WAKE_PHRASE_STAGE_ACTIVATED',
  'WAKE_PHRASE_STAGE_DISMISSED'
] as const
export const speakerVerificationModes = [
  'SPEAKER_VERIFICATION_MODE_UNSPECIFIED',
  'SPEAKER_VERIFICATION_MODE_DISABLED',
  'SPEAKER_VERIFICATION_MODE_ENFORCED',
  'SPEAKER_VERIFICATION_MODE_BYPASSED'
] as const
export const speakerVerificationResults = [
  'SPEAKER_VERIFICATION_RESULT_UNSPECIFIED',
  'SPEAKER_VERIFICATION_RESULT_ACCEPTED',
  'SPEAKER_VERIFICATION_RESULT_BYPASSED',
  'SPEAKER_VERIFICATION_RESULT_UNCERTAIN',
  'SPEAKER_VERIFICATION_RESULT_REJECTED'
] as const
/** Speaker-verification results each transcript kind may carry besides an absent or UNSPECIFIED result. */
export const speakerResultsByKind: Readonly<
  Record<(typeof transcriptKinds)[number], readonly (typeof speakerVerificationResults)[number][]>
> = {
  TRANSCRIPT_KIND_UNSPECIFIED: [],
  TRANSCRIPT_KIND_PARTIAL: [],
  TRANSCRIPT_KIND_FINAL: [
    'SPEAKER_VERIFICATION_RESULT_ACCEPTED',
    'SPEAKER_VERIFICATION_RESULT_BYPASSED',
    'SPEAKER_VERIFICATION_RESULT_UNCERTAIN'
  ],
  TRANSCRIPT_KIND_REJECTED: ['SPEAKER_VERIFICATION_RESULT_REJECTED', 'SPEAKER_VERIFICATION_RESULT_UNCERTAIN']
}

export type VoiceSourceTransport = (typeof voiceSourceTransports)[number]
export type VoiceSourceCapability = (typeof voiceSourceCapabilities)[number]

export interface RuntimeEvent {
  protocol: ProtocolVersion
  sessionId: string
  sequence: bigint
  monotonicTimeUs: bigint
  kind: RuntimePayloadKind
  payload: RuntimePayload
}

export interface SessionControl {
  protocol: ProtocolVersion
  sessionId: string
  requestSequence: bigint
  kind: SessionCommandKind
  body: Readonly<Record<string, unknown>>
}

export interface AudioFrame {
  protocol: ProtocolVersion
  sessionId: string
  sequence: bigint
  monotonicTimeUs: bigint
  format: Readonly<Record<string, unknown>>
  payloadBase64: string
}

export interface EngineEvent {
  protocol: ProtocolVersion
  engineId: string
  sequence: bigint
  monotonicTimeUs: bigint
  kind: EnginePayloadKind
  payload: Readonly<Record<string, unknown>>
}

export interface EngineControl {
  protocol: ProtocolVersion
  engineId: string
  requestSequence: bigint
  kind: EngineCommandKind
  body: Readonly<Record<string, unknown>>
}

export interface VoiceSource {
  sourceId: string
  displayName: string
  transport: VoiceSourceTransport
  capabilities: readonly VoiceSourceCapability[]
  metadata?: Readonly<Record<string, string>>
}

export function parseRuntimeEvent(input: unknown): RuntimeEvent {
  const object = asObject(input, 'runtime event')
  const present = runtimePayloadKinds.filter((field) => Object.hasOwn(object, field))
  if (present.length !== 1) throw new TypeError('runtime event must contain exactly one known payload')
  const kind = present[0]
  const payload = asObject(object[kind], kind)
  validateRuntimePayload(kind, payload)
  return {
    protocol: parseProtocol(object.protocol),
    sessionId: asNonEmptyString(object.sessionId, 'sessionId'),
    sequence: asUint64(object.sequence, 'sequence'),
    monotonicTimeUs: asUint64(object.monotonicTimeUs, 'monotonicTimeUs'),
    kind,
    payload
  }
}

export function parseRuntimeEventJson(source: string): RuntimeEvent {
  return parseRuntimeEvent(JSON.parse(source) as unknown)
}

export function runtimeEventToJson(event: RuntimeEvent): Record<string, unknown> {
  return {
    protocol: event.protocol,
    sessionId: event.sessionId,
    sequence: event.sequence.toString(),
    monotonicTimeUs: event.monotonicTimeUs.toString(),
    [event.kind]: event.payload
  }
}

export function parseSessionControl(input: unknown): SessionControl {
  const object = asObject(input, 'session control')
  const present = sessionCommandKinds.filter((field) => Object.hasOwn(object, field))
  if (present.length !== 1) throw new TypeError('session control must contain exactly one known command')
  const kind = present[0]
  const body = asObject(object[kind], kind)
  validateSessionBody(kind, body)
  return {
    protocol: parseProtocol(object.protocol),
    sessionId: asNonEmptyString(object.sessionId, 'sessionId'),
    requestSequence: asUint64(object.requestSequence, 'requestSequence'),
    kind,
    body
  }
}

export function sessionControlToJson(control: SessionControl): Record<string, unknown> {
  return {
    protocol: control.protocol,
    sessionId: control.sessionId,
    requestSequence: control.requestSequence.toString(),
    [control.kind]: control.body
  }
}

export function parseEngineEvent(input: unknown): EngineEvent {
  const object = asObject(input, 'engine event')
  const present = enginePayloadKinds.filter((field) => Object.hasOwn(object, field))
  if (present.length !== 1) throw new TypeError('engine event must contain exactly one known payload')
  const kind = present[0]
  const payload = asObject(object[kind], kind)
  validateEnginePayload(kind, payload)
  return {
    protocol: parseProtocol(object.protocol),
    engineId: asNonEmptyString(object.engineId, 'engineId'),
    sequence: asUint64(object.sequence, 'sequence'),
    monotonicTimeUs: asUint64(object.monotonicTimeUs, 'monotonicTimeUs'),
    kind,
    payload
  }
}

export function parseEngineEventJson(source: string): EngineEvent {
  return parseEngineEvent(JSON.parse(source) as unknown)
}

export function engineEventToJson(event: EngineEvent): Record<string, unknown> {
  return {
    protocol: event.protocol,
    engineId: event.engineId,
    sequence: event.sequence.toString(),
    monotonicTimeUs: event.monotonicTimeUs.toString(),
    [event.kind]: event.payload
  }
}

export function parseEngineControl(input: unknown): EngineControl {
  const object = asObject(input, 'engine control')
  const present = engineCommandKinds.filter((field) => Object.hasOwn(object, field))
  if (present.length !== 1) throw new TypeError('engine control must contain exactly one known command')
  const kind = present[0]
  const body = asObject(object[kind], kind)
  validateEngineCommand(kind, body)
  return {
    protocol: parseProtocol(object.protocol),
    engineId: asNonEmptyString(object.engineId, 'engineId'),
    requestSequence: asUint64(object.requestSequence, 'requestSequence'),
    kind,
    body
  }
}

export function engineControlToJson(control: EngineControl): Record<string, unknown> {
  return {
    protocol: control.protocol,
    engineId: control.engineId,
    requestSequence: control.requestSequence.toString(),
    [control.kind]: control.body
  }
}

export function parseAudioFrame(input: unknown): AudioFrame {
  const object = asObject(input, 'audio frame')
  const format = asObject(object.format, 'format')
  validateAudioFormat(format)
  const payloadBase64 = object.payload
  if (typeof payloadBase64 !== 'string' || !isBase64(payloadBase64)) {
    throw new TypeError('payload must use valid base64 grammar')
  }
  return {
    protocol: parseProtocol(object.protocol),
    sessionId: asNonEmptyString(object.sessionId, 'sessionId'),
    sequence: asUint64(object.sequence, 'sequence'),
    monotonicTimeUs: asUint64(object.monotonicTimeUs, 'monotonicTimeUs'),
    format,
    payloadBase64
  }
}

export function audioFrameToJson(frame: AudioFrame): Record<string, unknown> {
  return {
    protocol: frame.protocol,
    sessionId: frame.sessionId,
    sequence: frame.sequence.toString(),
    monotonicTimeUs: frame.monotonicTimeUs.toString(),
    format: frame.format,
    payload: frame.payloadBase64
  }
}

export function parseVoiceSource(input: unknown): VoiceSource {
  const object = asObject(input, 'voice source')
  const rawCapabilities = object.capabilities ?? []
  if (!Array.isArray(rawCapabilities)) throw new TypeError('capabilities must be an array')
  const capabilities = rawCapabilities.map((value) =>
    asEnum(value, voiceSourceCapabilities, 'capability')
  )
  const rawMetadata = object.metadata ?? {}
  const metadataObject = asObject(rawMetadata, 'metadata')
  const metadata = Object.fromEntries(
    Object.entries(metadataObject).map(([key, value]) => {
      if (typeof value !== 'string') throw new TypeError('metadata values must be strings')
      return [key, value] as const
    })
  )
  return {
    sourceId: asNonEmptyString(object.sourceId, 'sourceId'),
    displayName: asNonEmptyString(object.displayName, 'displayName'),
    transport: asEnum(object.transport, voiceSourceTransports, 'transport'),
    capabilities,
    metadata
  }
}

export function voiceSourceToJson(source: VoiceSource): Record<string, unknown> {
  const result: Record<string, unknown> = {
    sourceId: source.sourceId,
    displayName: source.displayName,
    transport: source.transport
  }
  if (source.capabilities.length > 0) result.capabilities = source.capabilities
  if (source.metadata !== undefined && Object.keys(source.metadata).length > 0) {
    result.metadata = source.metadata
  }
  return result
}

function parseProtocol(input: unknown): ProtocolVersion {
  const object = asObject(input, 'protocol')
  const protocol = {
    major: asUint32(object.major, 'protocol.major'),
    minor: asUint32(object.minor, 'protocol.minor')
  }
  if (!isSupported(protocol)) throw new TypeError(`unsupported protocol major ${protocol.major}`)
  return protocol
}

function asObject(input: unknown, field: string): Record<string, unknown> {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    throw new TypeError(`${field} must be an object`)
  }
  return input as Record<string, unknown>
}

function asNonEmptyString(input: unknown, field: string): string {
  if (typeof input !== 'string' || input.trim() === '') {
    throw new TypeError(`${field} must be a non-empty string`)
  }
  return input
}

function asUint32(input: unknown, field: string): number {
  if (typeof input !== 'number' || !Number.isInteger(input) || input < 0 || input > 0xffff_ffff) {
    throw new TypeError(`${field} must be a uint32`)
  }
  return input
}

function asUint64(input: unknown, field: string): bigint {
  if (typeof input !== 'string' || !/^[0-9]+$/.test(input)) {
    throw new TypeError(`${field} must be an ASCII uint64 string`)
  }
  const parsed = BigInt(input)
  if (parsed > uint64Max) throw new TypeError(`${field} is outside uint64 range`)
  return parsed
}

function asEnum<const T extends readonly string[]>(input: unknown, values: T, field: string): T[number] {
  if (typeof input !== 'string' || !values.includes(input)) {
    throw new TypeError(`${field} must be a known enum name`)
  }
  return input as T[number]
}

function asRequiredEnum<const T extends readonly string[]>(input: unknown, values: T, field: string): T[number] {
  const value = asEnum(input, values, field)
  if (value.endsWith('_UNSPECIFIED')) throw new TypeError(`${field} must not be unspecified`)
  return value
}

/** A field's value, or `fallback` when the field is absent. An explicit null stays invalid. */
function fieldOr(body: Record<string, unknown>, field: string, fallback: unknown): unknown {
  return Object.hasOwn(body, field) ? body[field] : fallback
}

function asArray(input: unknown, field: string): unknown[] {
  if (!Array.isArray(input)) throw new TypeError(`${field} must be an array`)
  return input
}

/** Whether an optional enum is set; an explicit *_UNSPECIFIED name counts as absent. */
function isSet(body: Record<string, unknown>, field: string): boolean {
  const value = body[field]
  return Object.hasOwn(body, field) && !(typeof value === 'string' && value.endsWith('_UNSPECIFIED'))
}

function validateOutcome(body: Record<string, unknown>, failed: boolean, name: string, errorAllowed = false): void {
  if (Object.hasOwn(body, 'error')) {
    asObject(body.error, `${name}.error`)
    if (!failed && !errorAllowed) throw new TypeError(`${name}.error is only allowed when failed`)
  } else if (failed) {
    throw new TypeError(`${name}.error is required when failed`)
  }
}

function validateUnitInterval(input: unknown, field: string): void {
  if (typeof input !== 'number' || !Number.isFinite(input) || input < 0 || input > 1) {
    throw new TypeError(`${field} must be between 0 and 1`)
  }
}

function validateProgress(completed: bigint | number, total: bigint | number, name: string): void {
  if (total > 0 && completed > total) throw new TypeError(`${name} progress exceeds its total`)
}

function validateTranscript(payload: Record<string, unknown>): void {
  const kind = asEnum(payload.kind, transcriptKinds, 'transcript.kind')
  if (typeof payload.text !== 'string') throw new TypeError('transcript.text must be a string')
  if (Object.hasOwn(payload, 'speakerVerification')) {
    const result = asEnum(payload.speakerVerification, speakerVerificationResults, 'transcript.speakerVerification')
    if (isSet(payload, 'speakerVerification') && !speakerResultsByKind[kind].includes(result)) {
      throw new TypeError(`${kind} cannot carry ${result}`)
    }
  }
  let previousStart = 0
  for (const item of asArray(fieldOr(payload, 'words', []), 'transcript.words')) {
    const word = asObject(item, 'transcript.words[]')
    if (typeof word.text !== 'string') throw new TypeError('word.text must be a string')
    const start = asUint32(fieldOr(word, 'startOffsetMs', 0), 'word.startOffsetMs')
    const end = asUint32(fieldOr(word, 'endOffsetMs', 0), 'word.endOffsetMs')
    if (start > end || start < previousStart) {
      throw new TypeError('words must be ordered and end at or after their start')
    }
    if (Object.hasOwn(word, 'confidence')) validateUnitInterval(word.confidence, 'word.confidence')
    previousStart = start
  }
}

function validateRuntimePayload(kind: RuntimePayloadKind, payload: Record<string, unknown>): void {
  if (kind === 'transcript') {
    validateTranscript(payload)
  } else if (kind === 'audioLevel') {
    const amplitude = payload.amplitude
    if (typeof amplitude !== 'number' || amplitude < 0 || amplitude > 1) {
      throw new TypeError('audioLevel.amplitude must be between 0 and 1')
    }
  } else if (kind === 'sessionStateChanged') {
    asEnum(payload.previous, sessionStates, 'sessionStateChanged.previous')
    asEnum(payload.current, sessionStates, 'sessionStateChanged.current')
  } else if (kind === 'providerStatus') {
    const state = asRequiredEnum(payload.state, providerStates, 'providerStatus.state')
    validateOutcome(payload, state === 'PROVIDER_STATE_FAILED', 'providerStatus')
  } else if (kind === 'inputGateStatus') {
    const causes = asArray(fieldOr(payload, 'closedBy', []), 'inputGateStatus.closedBy').map((cause) =>
      asRequiredEnum(cause, inputGateCauses, 'inputGateStatus.closedBy')
    )
    if (new Set(causes).size !== causes.length) throw new TypeError('inputGateStatus.closedBy must not repeat a cause')
  } else if (kind === 'wakePhrase') {
    asNonEmptyString(payload.phraseId, 'wakePhrase.phraseId')
    asRequiredEnum(payload.stage, wakePhraseStages, 'wakePhrase.stage')
    if (Object.hasOwn(payload, 'confidence')) validateUnitInterval(payload.confidence, 'wakePhrase.confidence')
  } else if (kind === 'batchProgress') {
    validateProgress(
      asUint32(fieldOr(payload, 'processedAudioMs', 0), 'batchProgress.processedAudioMs'),
      asUint32(fieldOr(payload, 'totalAudioMs', 0), 'batchProgress.totalAudioMs'),
      'batchProgress'
    )
  }
}

function validateEnginePayload(kind: EnginePayloadKind, payload: Record<string, unknown>): void {
  if (kind === 'engineStatus') {
    const engine = asObject(payload.engine, 'engineStatus.engine')
    const readiness = asRequiredEnum(payload.readiness, engineReadinessStates, 'engineStatus.readiness')
    const locality = asRequiredEnum(engine.locality, engineLocalities, 'engine.locality')
    if (locality === 'ENGINE_LOCALITY_ON_DEVICE') {
      asRequiredEnum(engine.platform, enginePlatforms, 'engine.platform')
    } else if (Object.hasOwn(engine, 'platform')) {
      asEnum(engine.platform, enginePlatforms, 'engine.platform')
    }
    for (const token of asArray(fieldOr(engine, 'capabilities', []), 'engine.capabilities')) {
      asNonEmptyString(token, 'engine.capabilities[]')
    }
    validateOutcome(
      payload,
      readiness === 'ENGINE_READINESS_FAILED',
      'engineStatus',
      readiness === 'ENGINE_READINESS_NOT_READY'
    )
  } else if (kind === 'voicePackStatus') {
    asNonEmptyString(payload.packId, 'voicePackStatus.packId')
    validateVoicePackItem(payload, 'voicePackStatus')
    for (const item of asArray(fieldOr(payload, 'components', []), 'voicePackStatus.components')) {
      const component = asObject(item, 'voicePackStatus.components[]')
      asNonEmptyString(component.componentId, 'component.componentId')
      asRequiredEnum(component.kind, voicePackComponentKinds, 'component.kind')
      validateVoicePackItem(component, 'component')
    }
  } else if (kind === 'microphoneStatus') {
    asNonEmptyString(payload.sourceId, 'microphoneStatus.sourceId')
    asRequiredEnum(payload.permission, microphonePermissions, 'microphoneStatus.permission')
    const readiness = asRequiredEnum(payload.readiness, microphoneReadinessStates, 'microphoneStatus.readiness')
    if (Object.hasOwn(payload, 'route')) asEnum(payload.route, microphoneRoutes, 'microphoneStatus.route')
    if (Object.hasOwn(payload, 'interruption')) {
      asEnum(payload.interruption, microphoneInterruptions, 'microphoneStatus.interruption')
    }
    if (isSet(payload, 'interruption') !== (readiness === 'MICROPHONE_READINESS_INTERRUPTED')) {
      throw new TypeError('microphoneStatus.interruption is set exactly when interrupted')
    }
  } else if (kind === 'speechOutput') {
    asNonEmptyString(payload.outputId, 'speechOutput.outputId')
    const state = asRequiredEnum(payload.state, speechOutputStates, 'speechOutput.state')
    validateOutcome(payload, state === 'SPEECH_OUTPUT_STATE_FAILED', 'speechOutput')
  }
}

function validateVoicePackItem(item: Record<string, unknown>, name: string): void {
  const state = asRequiredEnum(item.state, voicePackStates, `${name}.state`)
  validateOutcome(item, state === 'VOICE_PACK_STATE_FAILED', name)
  validateProgress(
    asUint64(fieldOr(item, 'bytesCompleted', '0'), `${name}.bytesCompleted`),
    asUint64(fieldOr(item, 'bytesTotal', '0'), `${name}.bytesTotal`),
    name
  )
}

function validateEngineCommand(kind: EngineCommandKind, body: Record<string, unknown>): void {
  if (kind === 'voicePack') {
    asNonEmptyString(body.packId, 'voicePack.packId')
    asRequiredEnum(body.action, voicePackActions, 'voicePack.action')
  } else if (kind === 'speak') {
    asNonEmptyString(body.outputId, 'speak.outputId')
    asNonEmptyString(body.text, 'speak.text')
    if (Object.hasOwn(body, 'fullDuplex') && typeof body.fullDuplex !== 'boolean') {
      throw new TypeError('speak.fullDuplex must be a boolean')
    }
    if (Object.hasOwn(body, 'echoClearanceMs')) asUint32(body.echoClearanceMs, 'speak.echoClearanceMs')
  } else {
    asNonEmptyString(body.outputId, 'cancelSpeech.outputId')
  }
}

function validateAudioFormat(format: Record<string, unknown>): void {
  if (asUint32(format.sampleRateHz, 'sampleRateHz') < 1) throw new TypeError('sampleRateHz must be at least 1')
  if (asUint32(format.channels, 'channels') < 1) throw new TypeError('channels must be at least 1')
  asEnum(format.encoding, audioEncodings, 'encoding')
  if (Object.hasOwn(format, 'frameDurationMs')) asUint32(format.frameDurationMs, 'frameDurationMs')
}

function validateSessionBody(kind: SessionCommandKind, body: Record<string, unknown>): void {
  if (kind === 'inputGate') {
    for (const field of ['open', 'flushAcceptedAudio']) {
      if (Object.hasOwn(body, field) && typeof body[field] !== 'boolean') {
        throw new TypeError(`${field} must be a boolean`)
      }
    }
  } else if (kind === 'stop' && Object.hasOwn(body, 'reason') && typeof body.reason !== 'string') {
    throw new TypeError('stop.reason must be a string')
  } else if (kind === 'start') {
    if (Object.hasOwn(body, 'mode')) asEnum(body.mode, captureModes, 'start.mode')
    if (Object.hasOwn(body, 'source')) parseVoiceSource(body.source)
    if (Object.hasOwn(body, 'requestedFormat')) validateAudioFormat(asObject(body.requestedFormat, 'requestedFormat'))
    if (Object.hasOwn(body, 'engineId')) asNonEmptyString(body.engineId, 'start.engineId')
  } else if (kind === 'speakerVerification') {
    asRequiredEnum(body.mode, speakerVerificationModes, 'speakerVerification.mode')
  } else if (kind === 'startBatch') {
    asNonEmptyString(body.engineId, 'startBatch.engineId')
    const format = asObject(body.format, 'startBatch.format')
    validateAudioFormat(format)
    if (format.encoding === 'AUDIO_ENCODING_OPUS' && ((format.frameDurationMs ?? 0) as number) < 1) {
      throw new TypeError('startBatch.format.frameDurationMs is required for Opus')
    }
    if (Object.hasOwn(body, 'totalAudioMs')) asUint32(body.totalAudioMs, 'startBatch.totalAudioMs')
  }
}

function isBase64(value: string): boolean {
  const match = /=*$/.exec(value)
  const pad = match?.[0].length ?? 0
  if (pad > 2) return false
  const raw = pad === 0 ? value : value.slice(0, -pad)
  if (raw.includes('=') || raw.length % 4 === 1) return false
  if (pad > 0 && (pad !== (4 - (raw.length % 4)) % 4 || value.length % 4 !== 0)) return false
  return /^[A-Za-z0-9+/]*$/.test(raw) || /^[A-Za-z0-9_-]*$/.test(raw)
}
