# WWDC26 Music And Audio Notes

These notes capture the platform context used for this build.

## Confirmed Locally

- Xcode: 27.0, build 27A5194q.
- iPhoneOS SDK: 27.0 at `/Applications/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk`.
- MusicKit remains present as `MusicKit.framework`, with SwiftUI companion support in `_MusicKit_SwiftUI.framework`.
- Newer music/audio-adjacent SDK surfaces are present:
  - `NowPlaying.framework`
  - `_NowPlaying_AppIntents.framework`
  - `MusicUnderstanding.framework`
  - `MediaIntents.framework`

## Implementation Decision

The requested app is local-file first, so playback uses `AVAudioPlayer` from AVFoundation instead of MusicKit playback APIs. MusicKit is linked as a forward-compatible dependency, but the initial product does not request Apple Music authorization because importing files from the system picker does not require it.

Now Playing integration uses the stable `MediaPlayer` APIs (`MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`) because they directly support local-file metadata and remote controls. The new iOS 27 `NowPlaying.framework` is noted as a likely future migration path once the app needs a richer system media content model.

`MusicUnderstanding.framework` appears suitable for future analysis features such as loudness, rhythm, pace, key, structure, and instrument activity. This first pass avoids running analysis at import time so file intake stays fast and deterministic.

## Apple References Checked

- MusicKit overview: https://developer.apple.com/documentation/musickit
- AVAudioPlayer: https://developer.apple.com/documentation/avfaudio/avaudioplayer
- SwiftUI file importer: https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)
- UTType audio: https://developer.apple.com/documentation/uniformtypeidentifiers/uttype/audio
