import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController
    @EnvironmentObject private var router: AppRouter

    @State private var isImporterPresented = false
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                YagyoBackdrop(progress: player.progress)

                ScrollView {
                    VStack(spacing: 18) {
                        HeaderView(importAction: { isImporterPresented = true })
                        ArtworkStage(track: player.currentTrack, progress: player.progress, isPlaying: player.isPlaying)
                        TransportView()
                        LibrarySection(importAction: { isImporterPresented = true })
                        PlatformNote()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                Task {
                    switch result {
                    case .success(let urls):
                        await library.importAudioFiles(from: urls)
                        if let selectedTrack = library.selectedTrack {
                            player.load(selectedTrack, from: library, autoplay: false)
                        }
                    case .failure(let error):
                        importErrorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Import failed", isPresented: importAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "The selected files could not be imported.")
            }
            .onChange(of: router.pendingAction) { _, action in
                guard action == .continueLastTrack else { return }
                player.playMostRecent(from: library)
                router.pendingAction = nil
            }
        }
    }

    private var importAlertBinding: Binding<Bool> {
        Binding {
            importErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                importErrorMessage = nil
            }
        }
    }
}

private struct HeaderView: View {
    var importAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Text("百鬼夜行")
                        .font(.system(size: 31, weight: .semibold, design: .serif))
                        .tracking(8)
                    Text("音")
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(YagyoColor.geppaku)
                        .frame(width: 25, height: 25)
                        .background(YagyoColor.shu, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .rotationEffect(.degrees(-4))
                }

                Text("Local audio procession")
                    .font(.caption.weight(.semibold))
                    .tracking(3.1)
                    .textCase(.uppercase)
                    .foregroundStyle(YagyoColor.dim)
            }

            Spacer()

            Button(action: importAction) {
                Label("Import", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(YagyoColor.chochin)
            .background(YagyoColor.yoiyami, in: Circle())
            .overlay(Circle().stroke(YagyoColor.chochin.opacity(0.55), lineWidth: 1))
            .accessibilityLabel("Import audio")
        }
        .foregroundStyle(YagyoColor.geppaku)
    }
}

private struct ArtworkStage: View {
    var track: AudioTrack?
    var progress: Double
    var isPlaying: Bool

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Image("DefaultArtwork")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(YagyoColor.line.opacity(0.9), lineWidth: 1)
                    }

                CircularWaveform(progress: progress, isPlaying: isPlaying)
                    .padding(28)
            }

            VStack(spacing: 5) {
                Text(track?.title ?? "No audio in the procession")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(YagyoColor.geppaku)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(track?.originalFilename ?? "Import a track to start")
                    .font(.footnote)
                    .foregroundStyle(YagyoColor.dim)
                    .lineLimit(1)
            }
        }
        .ritualPanel(radius: 32, padding: 12, tint: YagyoColor.kitsunebi.opacity(0.08))
    }
}

private struct TransportView: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                Button {
                    player.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .disabled(!library.hasTracks)

                Button {
                    if player.currentTrack == nil, let selectedTrack = library.selectedTrack {
                        player.load(selectedTrack, from: library, autoplay: true)
                    } else {
                        player.togglePlayPause()
                    }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 72, height: 72)
                        .background(YagyoColor.chochin, in: Circle())
                        .foregroundStyle(YagyoColor.sumi)
                        .shadow(color: YagyoColor.chochin.opacity(player.isPlaying ? 0.52 : 0.18), radius: 18)
                }
                .disabled(!library.hasTracks)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .disabled(!library.hasTracks)
            }
            .font(.title2.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(YagyoColor.geppaku)

            VStack(spacing: 8) {
                Slider(value: progressBinding, in: 0...max(player.duration, 1))
                    .tint(YagyoColor.chochin)
                    .disabled(player.currentTrack == nil)

                HStack {
                    Text(player.elapsedText)
                    Spacer()
                    Text(player.durationText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(YagyoColor.dim)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.1.fill")
                    .foregroundStyle(YagyoColor.dim)
                Slider(value: volumeBinding, in: 0...1)
                    .tint(YagyoColor.kitsunebi)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(YagyoColor.dim)
            }
            .font(.caption)
        }
        .ritualPanel(radius: 24, padding: 16)
    }

    private var progressBinding: Binding<Double> {
        Binding {
            player.elapsedTime
        } set: { value in
            player.seek(to: value)
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding {
            Double(player.volume)
        } set: { value in
            player.volume = Float(value)
        }
    }
}

private struct LibrarySection: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController

    var importAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.headline)
                        .foregroundStyle(YagyoColor.geppaku)
                    Text("Files copied into the app folder")
                        .font(.caption)
                        .foregroundStyle(YagyoColor.dim)
                }
                Spacer()
                Button(action: importAction) {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(YagyoColor.chochin)
                .background(YagyoColor.yoiyami2, in: Circle())
                .accessibilityLabel("Import audio")
            }

            if library.tracks.isEmpty {
                EmptyLibraryView(importAction: importAction)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(library.tracks) { track in
                        TrackRow(track: track)
                    }
                }
            }
        }
        .ritualPanel(radius: 24, padding: 16, tint: YagyoColor.shu.opacity(0.08))
    }
}

private struct TrackRow: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController

    var track: AudioTrack

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id
    }

    var body: some View {
        Button {
            player.load(track, from: library, autoplay: true)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? YagyoColor.chochin : YagyoColor.yoiyami2)
                    Image(systemName: isCurrent && player.isPlaying ? "waveform" : "music.note")
                        .foregroundStyle(isCurrent ? YagyoColor.sumi : YagyoColor.kitsunebi)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YagyoColor.geppaku)
                        .lineLimit(1)
                    Text("\(track.durationText) · \(track.importedDateText)")
                        .font(.caption)
                        .foregroundStyle(YagyoColor.dim)
                }

                Spacer()

                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(isCurrent ? YagyoColor.chochin : YagyoColor.dim)
            }
            .padding(10)
            .background(YagyoColor.sumi.opacity(isCurrent ? 0.54 : 0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCurrent ? YagyoColor.chochin.opacity(0.45) : YagyoColor.line.opacity(0.65), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                player.stopForDeletedTrack(track)
                library.delete(track)
            } label: {
                Label("Delete from app folder", systemImage: "trash")
            }
        }
    }
}

private struct EmptyLibraryView: View {
    var importAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(YagyoColor.chochin)
                .frame(width: 70, height: 70)
                .background(YagyoColor.sumi.opacity(0.48), in: Circle())

            VStack(spacing: 5) {
                Text("The procession is quiet")
                    .font(.headline)
                    .foregroundStyle(YagyoColor.geppaku)
                Text("Choose MP3, M4A, WAV, AIFF, AAC, CAF, or FLAC files. They will be copied into this app.")
                    .font(.footnote)
                    .foregroundStyle(YagyoColor.dim)
                    .multilineTextAlignment(.center)
            }

            Button(action: importAction) {
                Label("Import audio", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(YagyoColor.chochin, in: Capsule())
                    .foregroundStyle(YagyoColor.sumi)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct PlatformNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "music.note.list")
                .foregroundStyle(YagyoColor.kitsunebi)
            Text("Built for iOS 27+. Local files stay inside the app folder; Apple Music catalog features can be layered on later with MusicKit.")
                .font(.caption)
                .foregroundStyle(YagyoColor.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ritualPanel(radius: 18, padding: 12, tint: YagyoColor.kitsunebi.opacity(0.07))
    }
}

#Preview("Empty Library") {
    ContentView()
        .environmentObject(AudioLibraryStore())
        .environmentObject(PlaybackController())
        .environmentObject(AppRouter())
}
