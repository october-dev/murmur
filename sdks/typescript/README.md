# @october-dev/murmur-protocol

TypeScript models and conformance helpers for the versioned `murmur.v1` voice
protocol. This package is framework-neutral and is shared by Node, Electron,
Expo, React Native, web, and server integrations.

```ts
import { parseRuntimeEventJson } from '@october-dev/murmur-protocol'

const event = parseRuntimeEventJson(message)
```

The package source and build metadata are ready for npm. It remains unpublished
while the initial public protocol is reviewed against the shared conformance
fixtures.
