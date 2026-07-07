# Yagyo Player

Yagyo Player is a SwiftUI audio player for iOS 27 and later. It takes the dark folklore palette of the provided Hyakki Yagyo web app and turns it into a local-first music library.

## What It Does

- Imports audio through the system file picker.
- Copies selected files into the app's Documents/YagyoLibrary folder.
- Persists a small JSON library manifest.
- Plays local files with AVFoundation.
- Publishes Now Playing metadata and remote play/pause/skip controls through MediaPlayer.
- Exposes small App Shortcuts for opening the player or jumping back to now playing.

## WWDC26 / SDK Notes

See [docs/WWDC26-Music-notes.md](docs/WWDC26-Music-notes.md) for the MusicKit, Now Playing, and Music Understanding findings used before implementation.

## Build

```bash
xcodegen generate
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
