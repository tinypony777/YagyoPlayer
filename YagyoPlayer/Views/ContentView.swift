import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController
    @EnvironmentObject private var router: AppRouter

    @StateObject private var ushimitsu = UshimitsuWatch()

    @State private var isImporterPresented = false
    @State private var importErrorMessage: String?
    @State private var importSummary: ImportSummary?

    var body: some View {
        NavigationStack {
            ZStack {
                YagyoBackdrop(isUshimitsu: ushimitsu.isNight)

                ScrollView {
                    VStack(spacing: 18) {
                        HeaderView(isUshimitsu: ushimitsu.isNight, importAction: { isImporterPresented = true })
                        YagyoParadeView(
                            isPlaying: player.isPlaying,
                            level: player.audioLevel,
                            isUshimitsu: ushimitsu.isNight,
                            onMoonTap: { ushimitsu.toggleForced() }
                        )
                        ArtworkStage(
                            track: player.currentTrack,
                            progress: player.progress,
                            isPlaying: player.isPlaying,
                            level: player.audioLevel
                        )
                        TransportView()
                        LibrarySection(importAction: { isImporterPresented = true })
                        PlaylistSection()
                        PlatformNote()
                        FooterView()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }

                AnnouncementToast(text: ushimitsu.announcement)
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
                        switch library.importState {
                        case .finished(let summary):
                            importSummary = summary
                        case .failed(let message):
                            importErrorMessage = message
                        case .idle, .importing:
                            break
                        }
                        if let selectedTrack = library.selectedTrack {
                            player.load(selectedTrack, from: library, autoplay: false, context: .library)
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
            .alert("取込結果", isPresented: importSummaryBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importSummaryMessage)
            }
            .alert("保存に失敗しました", isPresented: persistenceErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.persistenceErrorMessage ?? "")
            }
            .alert("再生できません", isPresented: playbackErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(player.playbackErrorMessage ?? "")
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

    private var importSummaryBinding: Binding<Bool> {
        Binding {
            importSummary != nil
        } set: { isPresented in
            if !isPresented {
                importSummary = nil
            }
        }
    }

    private var persistenceErrorBinding: Binding<Bool> {
        Binding {
            library.persistenceErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                library.persistenceErrorMessage = nil
            }
        }
    }

    private var playbackErrorBinding: Binding<Bool> {
        Binding {
            player.playbackErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                player.playbackErrorMessage = nil
            }
        }
    }

    private var importSummaryMessage: String {
        guard let summary = importSummary else { return "" }

        var lines: [String] = ["\(summary.imported) 曲を納めました。"]
        if summary.duplicates > 0 {
            lines.append("重複のため見送り: \(summary.duplicates) 件(同じ音源は既に行列にいます)")
        }
        if !summary.failures.isEmpty {
            lines.append("失敗: \(summary.failures.count) 件")
            for failure in summary.failures {
                lines.append("・\(failure.filename) — \(failure.reason)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private struct HeaderView: View {
    var isUshimitsu: Bool
    var importAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Text("百鬼夜行")
                        .font(.system(size: 31, weight: .semibold, design: .serif))
                        .tracking(8)
                        .foregroundStyle(isUshimitsu ? YagyoColor.ushiTitle : YagyoColor.geppaku)
                        .shadow(
                            color: isUshimitsu ? YagyoColor.akaMoon.opacity(0.5) : YagyoColor.chochin.opacity(0.25),
                            radius: 9
                        )
                    Text("音")
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(YagyoColor.geppaku)
                        .frame(width: 25, height: 25)
                        .background(YagyoColor.shu, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .rotationEffect(.degrees(-4))
                }

                Text("Hyakki Yagyō · Local Procession")
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
        .animation(.easeInOut(duration: 1.2), value: isUshimitsu)
    }
}

private struct ArtworkStage: View {
    var track: AudioTrack?
    var progress: Double
    var isPlaying: Bool
    var level: Double

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

                CircularWaveform(progress: progress, isPlaying: isPlaying, level: level)
                    .padding(28)
            }

            VStack(spacing: 5) {
                Text(track?.title ?? "行列はまだ静か")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(YagyoColor.geppaku)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(track?.originalFilename ?? "Import a track to start the procession")
                    .font(.footnote)
                    .foregroundStyle(YagyoColor.dim)
                    .lineLimit(1)
            }
        }
        .ritualPanel(radius: 32, padding: 12, tint: YagyoColor.kitsunebi.opacity(0.08))
        .shadow(color: YagyoColor.chochin.opacity(isPlaying ? 0.1 + level * 0.15 : 0), radius: 24)
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
                        player.load(selectedTrack, from: library, autoplay: true, context: .library)
                    } else {
                        player.togglePlayPause()
                    }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: 72, height: 72)
                        .background(YagyoColor.yoiyami, in: Circle())
                        .foregroundStyle(YagyoColor.chochin)
                        .overlay(Circle().stroke(YagyoColor.chochin, lineWidth: 2))
                        .shadow(
                            color: YagyoColor.chochin.opacity(player.isPlaying ? 0.3 + player.audioLevel * 0.35 : 0.15),
                            radius: 16
                        )
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
                StepProgressBar(
                    progress: player.progress,
                    isEnabled: player.currentTrack != nil
                ) { fraction in
                    player.seek(to: fraction * player.duration)
                }

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
                    Text("行列")
                        .font(.system(.headline, design: .serif))
                        .tracking(4)
                        .foregroundStyle(YagyoColor.geppaku)
                    Text("Library · Files copied into the app folder")
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

    @State private var isDeleteConfirmationPresented = false

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id
    }

    var body: some View {
        let sprite = YokaiGallery.sprite(for: track.id)

        Button {
            player.load(track, from: library, autoplay: true, context: .library)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(YagyoColor.yoiyami2.opacity(isCurrent ? 1 : 0.7))
                    sprite.frames[0].image
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                        .accessibilityHidden(true)
                }
                .frame(width: 46, height: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCurrent ? YagyoColor.chochin.opacity(0.7) : YagyoColor.line, lineWidth: 1)
                }
                .shadow(color: isCurrent && player.isPlaying ? YagyoColor.chochin.opacity(0.4) : .clear, radius: 7)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YagyoColor.geppaku)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(sprite.name)
                            .font(.system(size: 11, design: .serif))
                            .foregroundStyle(isCurrent ? YagyoColor.chochin : YagyoColor.dim)
                        Text("· \(track.durationText) · \(track.importedDateText)")
                            .font(.caption)
                            .foregroundStyle(YagyoColor.dim)
                    }
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
            if !library.playlists.isEmpty {
                let playlistsContainingTrack = Set(
                    library.playlists
                        .filter { $0.contains(track.id) }
                        .map(\.id)
                )
                Menu {
                    ForEach(library.playlists) { playlist in
                        let alreadyInPlaylist = playlistsContainingTrack.contains(playlist.id)
                        Button {
                            library.addTrack(track, to: playlist)
                        } label: {
                            if alreadyInPlaylist {
                                Label(playlist.name, systemImage: "checkmark")
                            } else {
                                Text(playlist.name)
                            }
                        }
                        .disabled(alreadyInPlaylist)
                    }
                } label: {
                    Label("Add to playlist", systemImage: "text.badge.plus")
                }
            }

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete from app folder", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "「\(track.title)」を行列から外しますか?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                player.stopForDeletedTrack(track)
                library.delete(track)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("消えるのはアプリ内にコピーされた音源だけです。取込元のファイルには影響しません。")
        }
    }
}

private struct EmptyLibraryView: View {
    var importAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            YokaiGallery.parade[4].frames[0].image
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("行列はまだ静か")
                    .font(.system(.headline, design: .serif))
                    .tracking(3)
                    .foregroundStyle(YagyoColor.geppaku)
                Text("Choose MP3, M4A, WAV, AIFF, AAC, CAF, or FLAC files. They will be copied into this app.")
                    .font(.footnote)
                    .foregroundStyle(YagyoColor.dim)
                    .multilineTextAlignment(.center)
            }

            Button(action: importAction) {
                HStack(spacing: 5) {
                    Text("納める")
                        .font(.system(size: 14, design: .serif))
                        .tracking(2)
                    Text("import")
                        .font(.system(size: 9))
                        .tracking(1)
                        .foregroundStyle(YagyoColor.dim)
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 11)
                .background(YagyoColor.yoiyami, in: Capsule())
                .overlay(Capsule().stroke(Color(yagyoHex: 0x6a4a20), lineWidth: 1))
                .foregroundStyle(YagyoColor.chochin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import audio")
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
            Text("Built for iOS 26+. Local files stay inside the app folder; Apple Music catalog features can be layered on later with MusicKit.")
                .font(.caption)
                .foregroundStyle(YagyoColor.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ritualPanel(radius: 18, padding: 12, tint: YagyoColor.kitsunebi.opacity(0.07))
    }
}

private struct FooterView: View {
    var body: some View {
        Text("絵巻は右から左へ流れる")
            .font(.system(size: 11, design: .serif))
            .tracking(3)
            .foregroundStyle(YagyoColor.footerInk)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 2)
    }
}

/// Web版のトースト — 丑三つ時の入り・明けを告げる。
private struct AnnouncementToast: View {
    var text: String?

    var body: some View {
        VStack {
            Spacer()
            if let text {
                Text(text)
                    .font(.system(size: 15, design: .serif))
                    .tracking(2)
                    .foregroundStyle(YagyoColor.geppaku)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color(yagyoHex: 0x20233a), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(YagyoColor.line, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 15, y: 8)
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: text)
        .allowsHitTesting(false)
    }
}

#Preview("Empty Library") {
    ContentView()
        .environmentObject(AudioLibraryStore())
        .environmentObject(PlaybackController())
        .environmentObject(AppRouter())
}
