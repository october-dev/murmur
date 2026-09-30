# Engine and model licensing

`manifest.json` is the single, default-deny inventory of native engine
dependencies, model weights, voices, tokenizers, phonemizers, and test fixtures
that Murmur may package or download. `tool/check_licensing.py` enforces it, and
runs through `make check-licensing` locally and in CI.

## Scope and disclaimer

This is an engineering compliance record, not legal advice. It records what the
pinned upstream sources state and what Murmur's policy requires. The legal
review recorded per entry is the only approval.

Murmur currently bundles and downloads no engine, model, voice, tokenizer, or
phonemizer, and has no model downloader or release packaging. A `user-download`
classification does not imply that a downloader exists. **Anything not listed
in the manifest is unapproved.**

Out of scope: pub and npm application dependencies, and the existing Omi,
Omarchy, and Expo notices in `THIRD_PARTY_NOTICES.md`.

## Status against #33

| Criterion | Status |
| --- | --- |
| Inventory by exact version and source | Met by the manifest. It lists the FluidAudio (#42) and sherpa-onnx (#26) candidates with their configured native closure, the model, tokenizer, G2P, and voice components #42 needs, and the test fixtures. |
| Record license and terms | Met by `license`, `upstream`, `terms`, and `review.notes`. |
| Separate bundled from downloaded artifacts | Met by `distribution`. |
| Machine-readable manifest with hashes or revisions | Met: every non-fixture entry has a 40-hex `revision`, byte-hashed `downloads`, or both. |
| Notices | Met for the current distribution, which contains no engine or model material. The checker requires a notice heading before any `bundle` entry can be approved. In-package copies arrive with the first packaged artifact (#21). |
| Terms before automated downloads | Met fail-closed for the current distribution, because no automated download exists. The manifest records each artifact's required presentation, and the checker refuses an approved download without terms and hashes. |
| Block unsupported or ambiguous artifacts | Met fail-closed for the current distribution. Nothing is approved, ambiguous entries must be `blocked`, and any tracked model, binary, or audio file must be registered. |
| Update procedure | Below. |
| Synthetic fixture provenance | Met by the two `fixture` entries. |
| Qualified legal review | **Outstanding external gate.** Every non-fixture entry is `pending`. #33 closes only after qualified reviewers record their outcome per entry. |

**Criteria 6 and 7 re-open when a new path is added.** A pull request that adds
a downloader (#16) or a packaging path (#21, #42, #26) re-opens both criteria
for that path, and must add the matching cross-check in the same pull request.
The checks expected later are:

- `Package.resolved`, CMake, and model-URL cross-checks against this manifest
  (#42, #26, #16). The sherpa-onnx check must also assert the configuration's
  options, including `SHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=OFF`
  (so no unrecorded ONNX Runtime from the build machine can be linked) and the
  dynamic runtime linkage (`SHERPA_ONNX_LINK_LIBSTDCPP_STATICALLY=OFF`,
  `SHERPA_ONNX_USE_STATIC_CRT=OFF`, with no `CMAKE_MSVC_RUNTIME_LIBRARY`
  override). It must also inspect the linked artifacts for statically embedded
  runtimes.
- a download UI that enforces `terms.download.presentation` (#16)
- package-contents and in-package notice checks (#21).

## Manifest contract

`manifestVersion` is `1`. `artifacts` is a non-empty list. Unknown fields and
duplicate JSON keys are rejected.

### Artifact entries

| Field | Contract |
| --- | --- |
| `id` | Unique lowercase kebab-case, with dots allowed between alphanumerics (`parakeet-tdt-0.6b-v3-coreml`). |
| `kind` | `engine` or `native-library` (code kinds), or `model`, `voice`, `tokenizer`, or `phonemizer` (content kinds). |
| `name`, `version` | Non-empty. `name` is also the notice heading an approved bundle needs. |
| `source` | `https://` repository or model page. A commit in a `source` URL (for example `/tree/<commit>/path`) must equal `revision`. |
| `vcs` | Optional. The github.com, gitlab.com, or huggingface.co repository that `revision` belongs to, when `source` is a package page such as crates.io. It is the explicit, reviewed record of a source/evidence host difference. |
| `revision` | 40-hex git or Hugging Face commit, or `null`. |
| `downloads` | Every fetched file or archive: `{ "url", "sha256", "size", "platform"? }`. The URL is `https://`, `sha256` is 64 hex characters of the actual bytes (for Hugging Face, the LFS object hash, not the pointer hash), and `size` is a positive integer. There is one element per platform where the bytes differ, and each `url` and `platform` pair is unique. A Hugging Face URL is bound to its own entry: it must use the canonical host and start with `https://huggingface.co/<source repository>/resolve/<entry revision>/`, so the fetched bytes come from the reviewed repository and revision. Other hosts, ports, and `.`/`..` segments are rejected. |
| `paths` | Exact repository-relative tracked files, for committed binaries. Each path belongs to one entry and must be tracked. |
| `configuration` | Required and non-empty for an `engine`, and `null` for every other kind. |
| `requires` | Component ids that must exist. The graph must be acyclic, and nothing may require an `engine` or a `fixture`. |
| `usedBy` | Non-owning labels (issues, engine ids). They play no part in approval. |
| `license` | `{ "code", "content", "name", "evidence" }`. See below. |
| `upstream` | Derived-from hops: `{ "name", "source", "vcs"?, "revision"?, "license", "licenseName"?, "evidence" }`. `licenseName` is the exact name of a custom (`other` or `LicenseRef-*`) license. |
| `terms` | `redistribution`, `commercialUse`, and `modification` are each `allowed`, `prohibited`, or `unknown`. `attribution` is a string. `download` is `{ "access", "presentation" }`. `termsUrl` is the current user-facing `https://` link, or `null`. |
| `distribution` | `bundle`, `user-download`, or `blocked`. |
| `review` | `date` (`YYYY-MM-DD`), `notes` (engineering findings, download facts, block reasons), and `legal`: `{ "status", "reference", "date", "fingerprint"? }`. |

A pin is required: every non-fixture entry has a `revision`, a non-empty
`downloads`, or both.

**License fields.** Code kinds must identify `license.code`, and content kinds
must identify `license.content`. Identified means neither `null` nor
`NOASSERTION`. The other field may also be recorded. This stops a vocabulary
from inheriting a surrounding code license. An upstream artifact that ships
code and data under different terms is split into a code entry and a content
entry.

**Evidence.** `license.evidence` and every `upstream[].evidence` must be a file
on github.com, gitlab.com, or huggingface.co, in the reviewed repository, at the
reviewed commit:

- for `license.evidence`, the entry's `vcs` (or else its `source`) repository at
  its `revision`
- for a hop, the hop's `vcs` (or else its `source`) repository at the hop's
  `revision`, which is required whenever the hop cites evidence.

The URL must name one file: a `blob` or `raw` path on github.com or gitlab.com,
or a `blob`, `resolve`, or `raw` path on huggingface.co, with a non-empty path
after the commit. The following are all rejected:

- directory views (`tree`) and pathless `blob`/`resolve` URLs
- evidence from another repository or another commit
- `blob/main`, tags, and bare repository pages
- other hosts or ports
- `.` or `..` segments.

`terms.termsUrl` is exempt because it is the link shown to users.

**Dependency direction.** An engine requires the native code and
engine-vendored data that its configuration compiles or links. A model requires
its own tokenizer, G2P or phonemizer data, and voices. A model never requires an
engine: compatibility is recorded in `usedBy`.

**Download terms.** `access` is `public`, `gated` (an account or accepted terms
at the host), or `unknown`. `presentation` is what must be shown before the
first network request: `none`, `link`, `acknowledgement`, or `unknown`. `none`
is valid only for `bundle`, and `user-download` requires `link` or
`acknowledgement`.

**Legal review.** `status` is `pending`, `approved`, or `rejected`. `approved`
and `rejected` require a non-empty `reference` and `date`. The repository stores
only the non-privileged reference and date, never counsel's advice.

**Reviewed fingerprint.** An `approved` entry must record
`review.legal.fingerprint`: the SHA-256 of the canonical JSON (sorted keys, no
whitespace) of every entry field except `usedBy` and `review`. That covers
identity, pins, downloads, paths, configuration, `requires`, license, upstream,
terms, and distribution. Print it with
`python3 tool/check_licensing.py --fingerprint <id>`. Any later change to those
fields fails the check until a fresh review records a new fingerprint, so a
bump cannot keep an old approval. Changes to a required entry invalidate that
entry's own approval, which in turn blocks every entry that requires it.

### Fixture entries

Fixture entries have only `id`, `kind: fixture`, `name`, `paths`,
`synthetic: true`, a non-empty `method`, and `review.notes`. The tracked files
under `conformance/fixtures/` must equal the union of fixture `paths`, with no
path listed twice.

Fixtures have no remote source, revision, license, or terms. They are
Murmur-authored, live in this repository under its Apache-2.0 license, and
their exact `paths` and `method` *are* their source and provenance.
`conformance/manifest.json` remains the only fixture index. The checker cannot
prove that content is synthetic, so that stays a review step.

### Tracked-file scan

The checker fails if any tracked file matching one of the patterns below is not
listed exactly in some entry's `paths`. Matching ignores case, so `Model.ONNX`
and `Voice.WAV` are scanned too:

- models: `.onnx`, `.ort`, `.mlmodel`, `.safetensors`, `.gguf`, `.pt`, `.pth`,
  `.tflite`, and `.bin` files, plus anything inside an `.mlpackage/` or
  `.mlmodelc/` directory
- native binaries: `.so`, `.dylib`, `.a`, and `.dll` files, plus anything inside
  an `.xcframework/` directory
- audio: `.wav`, `.flac`, `.mp3`, `.ogg`, `.opus`, and `.m4a` files.

Resolve a false positive with an entry or a reviewed change to this list, never
with a blanket exclude.

## Policy

- **Three classes.** `bundle` may ship inside a Murmur package. `user-download`
  must be fetched by the user's device. `blocked` may do neither. The
  classification is an engineering decision. Release is enabled only by an
  `approved` legal review.
- **Ambiguity forces `blocked`.** An entry must be `blocked` if any of the
  following hold:
  - any permission, `terms.download.access`, or `terms.download.presentation`
    is `unknown`
  - its kind's license field is missing or `NOASSERTION`
  - `license.evidence` is missing
  - a custom license (`other` or `LicenseRef-*`) lacks an exact `license.name`
    or evidence
  - an upstream hop lacks an identified license or evidence, or has a custom
    license without an exact `licenseName`
  - its legal review is `rejected`.

  Custom terms are not missing terms: once the name and evidence are captured,
  the normal rules apply. A `blocked` entry is never `approved`, and a completed
  negative review stays in the history as `rejected` and `blocked`.
- **Approval** requires all of the following:
  - a legal reference and date, and the fingerprint of the fields reviewed
  - every answer known
  - `commercialUse: allowed`
  - a recorded `attribution`
  - every `requires` entry approved.

  In addition, a `bundle` needs `redistribution: allowed` and a `##` heading in
  `THIRD_PARTY_NOTICES.md` containing its `name`. A bundled model, voice,
  tokenizer, or phonemizer also needs non-empty, byte-hashed `downloads`, so
  approval binds to the exact bytes shipped. A `user-download` needs a
  `termsUrl` and non-empty, byte-hashed `downloads`. A download is not a
  loophole.
- **Commercial use.** Requiring `commercialUse: allowed` is a conservative
  project policy, not a legal inference from a license: Murmur does not present
  a use-restricted artifact as generally supported. The legal reviewer remains
  the authority on the recorded terms.
- **The most restrictive hop decides.** An SDK's license is not the license of
  the weights, tokenizers, phonemizers, voices, or binaries it fetches, and no
  part of a pack inherits an archive's or engine's license by assumption. Packs
  are split per component wherever provenance or terms differ.
- **One configuration per engine entry.** `requires` is complete for exactly
  that configuration. Another build variant, such as sherpa-onnx with TTS or
  FluidAudio without NemoTextProcessing, needs its own reviewed engine entry.
  The current configurations are provisional until #42 and #26 confirm them.
- **Vendored code.** An engine's `upstream` lists every project whose code its
  configured sources copy, adapt, or port, each with its own license and
  evidence. The most restrictive hop decides, so an unlicensed or unpinnable
  snippet blocks the engine.
- **Runtime boundary.** Each engine configuration names its C, C++, and
  language runtime linkage. The current configurations link these runtimes
  dynamically from the target operating system and do not package them:
  - glibc, libstdc++, and libgcc_s on Linux
  - the MSVC `/MD` runtime on Windows, where the Visual C++ Redistributable is
    a system prerequisite
  - libSystem, libc++, and the Swift runtime on macOS.

  Static runtime linkage, or shipping a runtime app-locally, needs its own
  reviewed entry.
- **Modification.** Murmur modifies no third-party artifact. A Murmur-made
  derivative is its own entry with its own review.

## Download rule

This rule binds #16 and every engine adapter:

- fetch only `approved` entries, and only from their `downloads[].url`
- verify `sha256` and `size` before activating anything
- before the first network request, show `terms.termsUrl` and
  `terms.attribution`, and require an explicit accept when `presentation` is
  `acknowledgement`
- a cancelled prompt makes no request
- never download silently on first use.

FluidAudio v0.17.4's own model downloader fetches Hugging Face `main` for every
repository except `speaker-diarization-coreml`. #42 must therefore fetch from
this manifest's pinned files instead of relying on FluidAudio's default.

## Current findings

These were verified on 2026-09-28 against the pinned commits. The manifest is
the per-field record, and every non-fixture entry is `legal.status: pending`.

**Bundle candidates:**

- FluidAudio engine: `fluidaudio`, `nemo-text-processing`, `fastcluster`,
  `vbx`, `japanese-g2p`
- NemoTextProcessing's statically linked closure: 30 `rust-crate-*` entries,
  plus `rust-std`, `rust-compiler-builtins`, and seven more `rust-crate-*`
  entries that the standard library links. The closure comes from
  `cargo tree --locked -e normal,no-proc-macro --features ffi,fst-engine` over
  the seven Apple targets that build-xcframework.sh builds. It was checked
  against the v0.3.1 release binary, whose panic locations name only crate
  versions in that closure and rustc 1.98.1 (`48a229ce`). Each crate is pinned
  by its crates.io archive hash (equal to the `Cargo.lock` checksum) and its
  VCS commit.
- sherpa-onnx's dependencies: `kaldi-native-fbank`, `kaldi-decoder`,
  `kaldifst`, `openfst`, `eigen`, `simple-sentencepiece`, `nlohmann-json`
- `silero-vad-coreml` (MIT, small). It still needs per-file `downloads` before
  approval.

`fluidaudio` also records, as upstream hops, the projects whose code its
library ports: FunASR, NeMo, misaki, ZipVoice, Chatterbox, StyleTTS2, and
mobius, all MIT or Apache-2.0.

**User-download candidates:**

- `parakeet-tdt-0.6b-v3-coreml` and `parakeet-tdt-0.6b-v3-vocab` (CC-BY-4.0,
  attribution to NVIDIA)
- `kokoro-82m-coreml-ane`, `kokoro-82m-ane-vocab`, and `kokoro-voice-af-heart`
  (Apache-2.0).

Each still needs per-file `downloads` before approval.

**Blocked:**

- `luxtts-en-us-g2p-lexicon`: FluidAudio bundles this espeak-ng-harvested
  lexicon into every build, with no stated license. **FluidAudio cannot be
  approved until it is resolved.**
- `kokoro-english-lexicon`: Misaki does not document the dictionaries its
  English gold and silver lexicons were compiled from, so its repository
  license cannot be inherited by the data.
- `kokoro-english-g2p`: the BART G2P weights have an undocumented source and
  license. The English Kokoro model cannot be approved until both English G2P
  entries are resolved.
- `parakeet-realtime-eou-120m-coreml` and `parakeet-realtime-eou-120m-vocab`:
  the exact NVIDIA Open Model License text is not captured. #42 streaming must
  wait for its review or use TDT v3 chunking.
- `pyannote-segmentation-legacy-coreml` and `wespeaker-v2-legacy-coreml`: the
  two files FluidAudio's speaker-embedding path loads. The repository's NOTICE
  explicitly excludes them from its CC-BY-4.0 scope, and neither records a
  source checkpoint, author, or license.
- `kokoro-spanish-french-g2p`: espeak-ng-generated pronunciations with no stated
  data license, outside the English configuration.
- `sherpa-onnx`: its compiled sources copy code from Kaldi, k2, icefall, CATT
  (all Apache-2.0) and cpp-base64 (zlib-style notice). They also copy the
  Buckwalter transliteration table, whose repository has no license, and a
  StackOverflow trim snippet with no pinnable source or recorded license. Those
  two need a qualified review, or an upstream replacement, before the engine
  can be classified as a bundle again.
- `onnxruntime`: a third-party rebuild with no declared license or reproducible
  provenance. **sherpa-onnx cannot be approved until it is resolved.** The
  sherpa-onnx configuration sets
  `SHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=OFF`. Otherwise
  sherpa-onnx links any ONNX Runtime it finds on the build machine without a
  hash check, bypassing the pinned archives.
- `espeak-ng` and `piper-phonemize`: GPL-3.0 TTS dependencies, unreachable from
  the recognition-only configuration.

## Update procedure

A version-only or URL-only bump cannot pass the checker. For every new or
changed artifact:

1. Resolve the release or tag to a 40-hex commit.
2. Name the engine configuration, enumerate its complete `requires`, and check
   for cycles.
3. Trace every upstream hop (base model, conversion, training data, vendored
   code) to its license.
4. Cite commit-pinned evidence for the entry and every hop.
5. Record `downloads` for every fetched file: URL, byte SHA-256, size, and
   platform.
6. Set `terms.download.access` and `presentation`.
7. Update `THIRD_PARTY_NOTICES.md` and the findings above.
8. Record the legal outcome, reference, and date, or leave it `pending`. An
   approval also records the fingerprint that
   `python3 tool/check_licensing.py --fingerprint <id>` prints for the reviewed
   entry.
9. Run `make check-licensing`.

A pull request that adds a downloader or packaging path adds its licensing
cross-check in the same pull request.

## Questions for counsel

- CC-BY-4.0 attribution in apps and on-device downloads (Parakeet, pyannote)
- the NVIDIA Open Model License and the scoped CC-BY-4.0 notice on the
  diarization mirror, including the ungated mirror of a gated upstream
- the status of data generated or harvested from GPL-3.0 espeak-ng
- GPL-3.0 phonemizer linking, should a TTS variant ever be proposed
- ONNX Runtime rebuild provenance and its embedded third-party notices
- the sources behind Misaki's English lexicons and the Kokoro BART G2P
- the provenance of the legacy pyannote segmentation and WeSpeaker Core ML files
- the unlicensed Buckwalter table and the StackOverflow snippet compiled into
  sherpa-onnx, and whether ported algorithms create derivative-work obligations
  for FluidAudio's upstream projects
- commercial use across all of the above.
