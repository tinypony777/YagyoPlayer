# WWDC26 Music And Audio Notes

These notes distinguish the app's current production baseline from the provisional iOS 27 intelligence direction.

## Current Production And CI Baseline

- Xcode 26.3 is the CI-selected toolchain on GitHub Actions `macos-15`.
- iOS 26 simulator runtimes are used for the build-and-test workflow.
- MusicKit remains present as `MusicKit.framework`, with SwiftUI companion support in `_MusicKit_SwiftUI.framework`.
- Current playback does not depend on Music Understanding or Core AI.

## Current Implementation Decision

The requested app is local-file first, so playback uses `AVAudioPlayer` from AVFoundation instead of MusicKit playback APIs. MusicKit is linked as a forward-compatible dependency, but the initial product does not request Apple Music authorization because importing files from the system picker does not require it.

Now Playing integration uses the stable `MediaPlayer` APIs (`MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`) because they directly support local-file metadata and remote controls. The newer `NowPlaying.framework` is noted as a likely future migration path once the app needs a richer system media content model.

No music-intelligence analysis runs during import or playback in the current iOS 26 app. File intake therefore remains independent of the iOS 27 proposal.

## iOS 27 Beta Direction — Phase 0 Active

Apple's Music Understanding and Core AI documentation describe iOS 27 beta APIs. On 2026-07-14 the user explicitly resumed Step 3, so Music Understanding is now under an availability-gated capability spike. It is not a playback dependency or stable release contract yet.

- Music Understanding is the Apple-defined musical-analysis source. The Xcode 27 beta spike compiles and analyzes a local `AVURLAsset`; the release SDK must still reconfirm input boundaries, device availability, and on-device behavior before release.
- Core AI is the proposed on-device ranking layer for a developer-supplied model. It may rank only YagyoPlayer's allow-listed DSP recipe IDs; it does not author an executable effects graph.
- The feature remains optional and local-first. Unsupported devices, unavailable models, invalid results, or failed validation return to unchanged `Original` playback.
- Listening Profile processing and parade-reaction analysis are separate contracts. Music Understanding may inform either where the release API fits, but selected playback DSP is not treated as the parade's analysis engine.

The app target now contains a weak-linked adapter and app-owned result model, but import, UI, cache, playback, and render callbacks do not invoke it yet. API names, packaging, supported formats, and performance assumptions must still be revalidated against Apple's iOS 27 release SDK.

## Apple References Checked

- MusicKit overview: https://developer.apple.com/documentation/musickit
- AVAudioPlayer: https://developer.apple.com/documentation/avfaudio/avaudioplayer
- Music Understanding (iOS 27 beta): https://developer.apple.com/documentation/musicunderstanding
- Core AI (iOS 27 beta): https://developer.apple.com/documentation/coreai
- SwiftUI file importer: https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)
- UTType audio: https://developer.apple.com/documentation/uniformtypeidentifiers/uttype/audio
