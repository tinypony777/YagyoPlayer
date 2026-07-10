# Frozen Step 3 DSP Prototype — Current State

## Provenance

This archive was created in the `main` lineage whose starting context was `3937c84df65130e8ea6c829b109a9e42136c8d1c`. Its snapshot content was extracted mechanically from `origin/agent/step3-one-ear` at `f639beed71aea7f24d32cb3ce4a23996000ad8d9`.

The two revisions are lineage context and snapshot source respectively; this document does not imply that the snapshot branch was based on `3937c84`.

## Implemented in the snapshot

- A playback-backend seam around `PlaybackController`, including the temporary legacy `AVAudioPlayer` backend and related controller tests.
- Vendored libebur128 source, module map, upstream `COPYING`, and repository provenance in `ORIGIN.md`.
- A labeled PCM adapter that validates supported channel layouts and maps channel roles for loudness analysis.
- A Swift EBU R128 wrapper and shared analysis result types.
- Unit and linkage tests for the playback seam, PCM adapter, and EBU R128 wrapper, with their fixtures and test support.

## Not included

The frozen GitHub head does not include any of the later proposed or locally attempted components:

- `SilenceDetector`
- `OnsetDetector`
- `PerceptionDSPCore`
- Analysis cache and persistence
- Offline analysis pipeline
- Realtime ring buffer or realtime perception pipeline
- `AVAudioEngine` playback backend

Mac-only commits `41bd00e` and `1abf278` are not present in GitHub and are not included in this snapshot. Accordingly, this archive records only the prototype state visible at `f639bee`; it does not claim to preserve the unpushed Task 4 work.

## Frozen status

The prototype was frozen when Step 3 changed to the Core AI + Music Understanding direction. It remains available solely as historical design and implementation evidence.

No source in this directory is production code, and none is assumed reusable as the future playback-effect chain. Any later reuse requires fresh review against the canonical product direction, the release iOS 27 SDK, realtime audio constraints, licensing, and the bounded Listening Profile design.
