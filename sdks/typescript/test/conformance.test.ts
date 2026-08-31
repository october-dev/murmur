import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { parseRuntimeEventJson, runtimeEventToJson } from '../src/index.ts'

const fixtureUrl = new URL('../../../conformance/fixtures/runtime-events.jsonl', import.meta.url)
const lines = readFileSync(fixtureUrl, 'utf8').trim().split('\n')

test('parses and preserves all shared runtime fixtures', () => {
  const events = lines.map(parseRuntimeEventJson)
  assert.equal(events.length, 7)
  assert.deepEqual(
    events.map((event) => event.sequence),
    [1n, 2n, 3n, 4n, 5n, 6n, 7n]
  )
  assert.equal(events[3]?.kind, 'transcript')
  assert.equal(events[3]?.payload.text, 'synthetic hello')

  events.forEach((event, index) => {
    assert.deepEqual(runtimeEventToJson(event), JSON.parse(lines[index] ?? ''))
  })
})

test('rejects unknown and ambiguous payloads', () => {
  const base = {
    protocol: { major: 1, minor: 0 },
    sessionId: 'test',
    sequence: '1',
    monotonicTimeUs: '1'
  }
  assert.throws(() => parseRuntimeEventJson(JSON.stringify({ ...base, unknownEvent: {} })))
  assert.throws(() =>
    parseRuntimeEventJson(
      JSON.stringify({ ...base, captureReadiness: { live: true }, audioLevel: { amplitude: 0.5 } })
    )
  )
})
