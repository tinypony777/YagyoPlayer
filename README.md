# Yagyo Player

Yagyo Player is a SwiftUI audio player for iOS 26 and later. It takes the dark folklore palette of the provided Hyakki Yagyo web app and turns it into a local-first music library.

## What It Does

- Imports audio through the system file picker.
- Copies selected files into the app's Documents/YagyoLibrary folder.
- Persists a small JSON library manifest.
- Lets you organize tracks into playlists (巻物) — create, rename, delete, reorder, and play them; playlists persist in `playlists.json`.
- Helps you trust a growing library with duplicate import feedback, search, playlist-scoped sorting, and editable track metadata.
- Plays local files with AVFoundation.
- Publishes Now Playing metadata and remote play/pause/skip controls through MediaPlayer.
- Exposes small App Shortcuts for opening the player or jumping back to now playing.

## Design — 夜行絵巻

The visual language is ported directly from the Hyakki Yagyo Beat Machine web app:

- **Night parade (夜行絵巻)** — a Canvas hero view where the pixel-art yokai procession (oni, mokugyo, kasa-obake, kappa, kitsunebi, tengu, yuki-onna, biwa-bokuboku) walks right-to-left under a moonlit sky with twinkling stars, drifting fog, and swaying lanterns. While audio plays, 15 Hz `AVAudioPlayer.averagePower` metering is normalized and smoothed into an explainable level band, sustained-low-level proxy (`quietProxy`), and strong-level-rise proxy (`strongRiseProxy`). These are visual proxies, not beat, digital-silence, BPM, or song-structure detection.
- **Ushimitsu mode (丑三つ時)** — tap the moon (or wait until 2 AM) and the night deepens: the sky shifts to a red-tinged palette, the moon turns crimson, and hitotsume-kozo joins the end of the parade.
- **Step-cell seek bar** — the transport progress bar is drawn as 16 sequencer cells; played cells burn 朱 (vermilion), the current cell glows 提灯 (lantern amber).
- **Yokai library icons** — every imported track is assigned a resident yokai sprite, stable across launches. On the Step 4 validation branch, that same resident leads the procession; playback statistics are persisted but do not drive visual progression.

The exact input limits, thresholds, choreography, and Reduce Motion alternatives are published in [docs/CHOREOGRAPHY.md](docs/CHOREOGRAPHY.md). The Step 4 branch is a Karakasa-only 40×48 SNES-grade visual slice. Its current eight-frame candidate is a front-facing red/coral cone with a brown cap and gold band, one eye, smile and tongue, one pale leg, and one geta; the internal `.open` phase name is retained only for compatibility and renders a front-facing reaction. With Xcode 27.0, the generic iOS build succeeded; on an iOS 27 iPhone 17 Pro destination, the focused QA suite passed **11 / 11** with skip 0 and the full suite passed **65 / 65** with skip 0. Semantic AX validation then passed the iPhone 17 Pro state matrix (**4 / 4**) plus Reduce Motion stability (**1 / 1**) and the narrow iPhone 17e default Normal + Karakasa check (**1 / 1**), all with skip 0 and no coordinate taps. Reduce Motion screenshots at `t0` and `t+2 s` are byte-identical, with zero differing canvas-crop bytes. The [current evidence ledger](docs/evidence/step4-karakasa/README.md) records the images and hashes. Contact-sheet/GIF native visual QA is approved; final native visual QA of the Simulator screenshots and user visual approval are still pending. The earlier purple, side-facing/open-umbrella screenshots and older test counts are superseded. This mixed-art Draft PR remains unmerged from `main`; the remaining yokai have not been expanded.

## Design Nav

See [docs/DESIGN_NAV.md](docs/DESIGN_NAV.md) for the Step 4 visual contract, the Karakasa approval gate, design tokens, clearly labeled pre-Step-4 screenshots, and archived proposals.

## Product Direction

See [docs/PRODUCT_DIRECTION.md](docs/PRODUCT_DIRECTION.md) for the product direction (v3, the author's charter) — what this app is and who it is for, the craft at its heart, playback-trust criteria, build order, and the decision rubric used to judge new features.

## WWDC26 / SDK Notes

See [docs/WWDC26-Music-notes.md](docs/WWDC26-Music-notes.md) for the MusicKit, Now Playing, and Music Understanding findings used before implementation.

## Build

```bash
xcodegen generate
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
