export interface ProtocolVersion {
  major: number
  minor: number
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

export interface RuntimeEvent {
  protocol: ProtocolVersion
  sessionId: string
  sequence: bigint
  monotonicTimeUs: bigint
  kind: RuntimePayloadKind
  payload: RuntimePayload
}

export const voiceSourceTransports = [
  'SOURCE_TRANSPORT_BLUETOOTH_LE',
  'SOURCE_TRANSPORT_LOCAL_AUDIO',
  'SOURCE_TRANSPORT_NETWORK',
  'SOURCE_TRANSPORT_FILE',
  'SOURCE_TRANSPORT_SYNTHETIC'
] as const

export type VoiceSourceTransport = (typeof voiceSourceTransports)[number]

export interface VoiceSource {
  sourceId: string
  displayName: string
  transport: VoiceSourceTransport
  capabilities: readonly string[]
  metadata?: Readonly<Record<string, string>>
}

export function parseRuntimeEvent(input: unknown): RuntimeEvent {
  const object = asObject(input, 'runtime event')
  const protocolObject = asObject(object.protocol, 'protocol')
  const protocol: ProtocolVersion = {
    major: asNonNegativeInteger(protocolObject.major, 'protocol.major'),
    minor: asNonNegativeInteger(protocolObject.minor, 'protocol.minor')
  }
  const sessionId = asNonEmptyString(object.sessionId, 'sessionId')
  const sequence = asUint64(object.sequence, 'sequence')
  const monotonicTimeUs = asUint64(object.monotonicTimeUs, 'monotonicTimeUs')
  const present = runtimePayloadKinds.filter((field) => Object.hasOwn(object, field))
  if (present.length !== 1) {
    throw new TypeError('runtime event must contain exactly one known payload')
  }
  const kind = present[0]
  const payload = asObject(object[kind], kind)
  validatePayload(kind, payload)
  return { protocol, sessionId, sequence, monotonicTimeUs, kind, payload }
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

function asNonNegativeInteger(input: unknown, field: string): number {
  if (typeof input !== 'number' || !Number.isSafeInteger(input) || input < 0) {
    throw new TypeError(`${field} must be a non-negative integer`)
  }
  return input
}

function asUint64(input: unknown, field: string): bigint {
  if (typeof input !== 'string' || !/^\d+$/.test(input)) {
    throw new TypeError(`${field} must be a uint64 string`)
  }
  return BigInt(input)
}

function validatePayload(kind: RuntimePayloadKind, payload: Record<string, unknown>): void {
  if (kind === 'transcript') {
    asNonEmptyString(payload.kind, 'transcript.kind')
    if (typeof payload.text !== 'string') throw new TypeError('transcript.text must be a string')
  }
  if (kind === 'audioLevel') {
    const amplitude = payload.amplitude
    if (typeof amplitude !== 'number' || amplitude < 0 || amplitude > 1) {
      throw new TypeError('audioLevel.amplitude must be between 0 and 1')
    }
  }
}
