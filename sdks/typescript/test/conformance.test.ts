import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  audioFrameToJson,
  parseAudioFrame,
  parseRuntimeEvent,
  parseSessionControl,
  parseVoiceSource,
  runtimeEventToJson,
  sessionControlToJson,
  voiceSourceToJson,
  type AudioFrame,
  type RuntimeEvent,
  type SessionControl,
  type VoiceSource
} from '../src/index.ts'

type Message = 'RuntimeEvent' | 'SessionControl' | 'AudioFrame' | 'VoiceSource'
type Parsed = RuntimeEvent | SessionControl | AudioFrame | VoiceSource
interface FixtureSet {
  name: string
  message: Message
  path: string
  lines: number
  expect: 'accept' | 'reject'
  reason?: string
  rejection?: 'parse' | 'order'
  rejectLine?: number
  unknownFields?: string[]
}

const conformanceUrl = new URL('../../../conformance/', import.meta.url)
const manifest = JSON.parse(readFileSync(new URL('manifest.json', conformanceUrl), 'utf8')) as {
  fixtureSets: FixtureSet[]
}

function parse(message: Message, input: unknown): Parsed {
  switch (message) {
    case 'RuntimeEvent': return parseRuntimeEvent(input)
    case 'SessionControl': return parseSessionControl(input)
    case 'AudioFrame': return parseAudioFrame(input)
    case 'VoiceSource': return parseVoiceSource(input)
  }
}

function serialize(message: Message, value: Parsed): Record<string, unknown> {
  switch (message) {
    case 'RuntimeEvent': return runtimeEventToJson(value as RuntimeEvent)
    case 'SessionControl': return sessionControlToJson(value as SessionControl)
    case 'AudioFrame': return audioFrameToJson(value as AudioFrame)
    case 'VoiceSource': return voiceSourceToJson(value as VoiceSource)
  }
}

function orderingKey(message: Message, value: Parsed): bigint | undefined {
  switch (message) {
    case 'RuntimeEvent': return (value as RuntimeEvent).sequence
    case 'SessionControl': return (value as SessionControl).requestSequence
    case 'AudioFrame': return (value as AudioFrame).sequence
    case 'VoiceSource': return undefined
  }
}

function removePath(value: Record<string, unknown>, path: string): void {
  const parts = path.split('/')
  let current: unknown = value
  for (const part of parts.slice(0, -1)) {
    if (typeof current !== 'object' || current === null || Array.isArray(current)) return
    current = (current as Record<string, unknown>)[part]
  }
  if (typeof current === 'object' && current !== null && !Array.isArray(current)) {
    delete (current as Record<string, unknown>)[parts.at(-1) ?? '']
  }
}

test('all manifest conformance sets', () => {
  for (const fixtureSet of manifest.fixtureSets) {
    const lines = readFileSync(new URL(fixtureSet.path, conformanceUrl), 'utf8')
      .split('\n')
      .filter((line) => line.trim() !== '')
    assert.equal(lines.length, fixtureSet.lines, `typescript · ${fixtureSet.name} · count`)
    let previous: bigint | undefined
    const rejectLine = fixtureSet.rejectLine ?? 1
    lines.forEach((line, index) => {
      const lineNumber = index + 1
      const label = `typescript · ${fixtureSet.name} · line ${lineNumber}`
      const input = JSON.parse(line) as Record<string, unknown>
      let parsed: Parsed
      try {
        parsed = parse(fixtureSet.message, input)
      } catch (error) {
        const shouldReject = fixtureSet.expect === 'reject' && fixtureSet.rejection === 'parse' && lineNumber >= rejectLine
        assert.ok(shouldReject, `${label} · ${String(error)}`)
        return
      }
      if (fixtureSet.expect === 'reject' && fixtureSet.rejection === 'parse' && lineNumber >= rejectLine) {
        assert.fail(`${label} · expected ${fixtureSet.reason ?? 'rejection'}`)
      }

      const current = orderingKey(fixtureSet.message, parsed)
      if (current !== undefined) {
        const ordered = previous === undefined || current > previous
        const rejectsOrder = fixtureSet.expect === 'reject' && fixtureSet.rejection === 'order' && lineNumber >= rejectLine
        assert.equal(ordered, !rejectsOrder, `${label} · ${fixtureSet.reason ?? 'ordering'}`)
        if (ordered) previous = current
      }

      const expected = structuredClone(input)
      const actual = structuredClone(serialize(fixtureSet.message, parsed))
      for (const path of fixtureSet.unknownFields ?? []) {
        removePath(expected, path)
        removePath(actual, path)
      }
      assert.deepEqual(actual, expected, `${label} · round-trip`)
    })
  }
})
