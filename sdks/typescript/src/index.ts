export interface ProtocolVersion {
  major: number
  minor: number
}

export const currentProtocol: ProtocolVersion = { major: 1, minor: 0 }
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
  'actionResult'
] as const
export type RuntimePayloadKind = (typeof runtimePayloadKinds)[number]
export type RuntimePayload = Readonly<Record<string, unknown>>

export const sessionCommandKinds = ['start', 'stop', 'inputGate', 'finalize'] as const
export type SessionCommandKind = (typeof sessionCommandKinds)[number]

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
  const metadata: Record<string, string> = {}
  for (const [key, value] of Object.entries(metadataObject)) {
    if (typeof value !== 'string') throw new TypeError('metadata values must be strings')
    metadata[key] = value
  }
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

function validateRuntimePayload(kind: RuntimePayloadKind, payload: Record<string, unknown>): void {
  if (kind === 'transcript') {
    asEnum(payload.kind, transcriptKinds, 'transcript.kind')
    if (typeof payload.text !== 'string') throw new TypeError('transcript.text must be a string')
  } else if (kind === 'audioLevel') {
    const amplitude = payload.amplitude
    if (typeof amplitude !== 'number' || amplitude < 0 || amplitude > 1) {
      throw new TypeError('audioLevel.amplitude must be between 0 and 1')
    }
  } else if (kind === 'sessionStateChanged') {
    asEnum(payload.previous, sessionStates, 'sessionStateChanged.previous')
    asEnum(payload.current, sessionStates, 'sessionStateChanged.current')
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
