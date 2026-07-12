import SwiftUI

/// 巻物（プレイリスト）管理セクション — 取り込んだ曲をアプリ内で自由に整理する。
struct PlaylistSection: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController

    @State private var isCreatePresented = false
    @State private var newPlaylistName = ""
    @State private var playlistToRename: Playlist?
    @State private var renameText = ""
    @State private var expandedPlaylistID: Playlist.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if library.playlists.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(library.playlists) { playlist in
                        PlaylistRow(
                            playlist: playlist,
                            isExpanded: expandedPlaylistID == playlist.id,
                            toggleExpanded: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedPlaylistID = expandedPlaylistID == playlist.id ? nil : playlist.id
                                }
                            },
                            renameAction: {
                                renameText = playlist.name
                                playlistToRename = playlist
                            }
                        )
                    }
                }
            }
        }
        .ritualPanel(radius: 24, padding: 16, tint: YagyoColor.kitsunebi.opacity(0.08))
        .alert("新しい巻物", isPresented: $isCreatePresented) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") {
                library.createPlaylist(named: newPlaylistName)
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
        } message: {
            Text("Name the new playlist.")
        }
        .alert("巻物の名を改める", isPresented: renameAlertBinding) {
            TextField("Playlist name", text: $renameText)
            Button("Rename") {
                if let playlist = playlistToRename {
                    library.renamePlaylist(playlist, to: renameText)
                }
                playlistToRename = nil
            }
            Button("Cancel", role: .cancel) {
                playlistToRename = nil
            }
        } message: {
            Text("Enter a new name for the playlist.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("巻物")
                    .font(.system(.headline, design: .serif))
                    .tracking(4)
                    .foregroundStyle(YagyoColor.geppaku)
                Text("Playlists · Organize tracks your way")
                    .font(.caption)
                    .foregroundStyle(YagyoColor.dim)
            }
            Spacer()
            Button {
                isCreatePresented = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(YagyoColor.chochin)
            .background(YagyoColor.yoiyami2, in: Circle())
            .accessibilityLabel("Create playlist")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("巻物はまだ白紙")
                .font(.system(.subheadline, design: .serif))
                .tracking(2)
                .foregroundStyle(YagyoColor.geppaku)
            Text("Create a playlist, then add tracks from the library via long press.")
                .font(.footnote)
                .foregroundStyle(YagyoColor.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding {
            playlistToRename != nil
        } set: { isPresented in
            if !isPresented {
                playlistToRename = nil
            }
        }
    }
}

private struct PlaylistRow: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController

    var playlist: Playlist
    var isExpanded: Bool
    var toggleExpanded: () -> Void
    var renameAction: () -> Void

    private var isActive: Bool {
        library.activePlaylistID == playlist.id
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggleExpanded) {
                HStack(spacing: 12) {
                    Image(systemName: "scroll")
                        .font(.title3)
                        .foregroundStyle(isActive ? YagyoColor.chochin : YagyoColor.dim)
                        .frame(width: 36, height: 36)
                        .background(YagyoColor.yoiyami2.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(YagyoColor.geppaku)
                            .lineLimit(1)
                        Text("\(playlist.trackCount) track\(playlist.trackCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(isActive ? YagyoColor.chochin : YagyoColor.dim)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(YagyoColor.dim)
                }
                .padding(10)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    playFromStart()
                } label: {
                    Label("Play playlist", systemImage: "play.fill")
                }
                .disabled(library.tracks(in: playlist).isEmpty)

                Button(action: renameAction) {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    library.deletePlaylist(playlist)
                } label: {
                    Label("Delete playlist", systemImage: "trash")
                }
            }

            if isExpanded {
                expandedContent
            }
        }
        .background(YagyoColor.sumi.opacity(isActive ? 0.54 : 0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActive ? YagyoColor.chochin.opacity(0.45) : YagyoColor.line.opacity(0.65), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        let playlistTracks = library.tracks(in: playlist)

        VStack(spacing: 6) {
            if playlistTracks.isEmpty {
                Text("Long press a library track to add it here.")
                    .font(.caption)
                    .foregroundStyle(YagyoColor.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(playlistTracks.enumerated()), id: \.element.id) { index, track in
                    PlaylistTrackRow(
                        playlist: playlist,
                        track: track,
                        position: index,
                        count: playlistTracks.count
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func playFromStart() {
        guard let first = library.tracks(in: playlist).first else { return }
        player.load(first, from: library, autoplay: true, context: .playlist(playlist.id))
    }
}

private struct PlaylistTrackRow: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController

    var playlist: Playlist
    var track: AudioTrack
    var position: Int
    var count: Int

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id && library.activePlaylistID == playlist.id
    }

    var body: some View {
        Button {
            if player.currentTrack?.id == track.id {
                // いま流れている曲は頭出しし直さない。この行がpause表示なら止め、
                // 文脈違い(行列や別の巻物で再生中)ならこの巻物へ文脈だけ移す。
                let wasShowingPause = isCurrent && player.isPlaying
                player.adoptContext(.playlist(playlist.id), from: library)
                if wasShowingPause {
                    player.pause()
                } else if !player.isPlaying {
                    player.play()
                }
            } else {
                player.load(track, from: library, autoplay: true, context: .playlist(playlist.id))
            }
        } label: {
            HStack(spacing: 10) {
                Text("\(position + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(YagyoColor.dim)
                    .frame(width: 20, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isCurrent ? YagyoColor.chochin : YagyoColor.geppaku)
                        .lineLimit(1)
                    Text(track.durationText)
                        .font(.caption2)
                        .foregroundStyle(YagyoColor.dim)
                }

                Spacer()

                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle")
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? YagyoColor.chochin : YagyoColor.dim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(YagyoColor.yoiyami.opacity(isCurrent ? 0.85 : 0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                library.moveTrack(track, in: playlist, by: -1)
            } label: {
                Label("Move up", systemImage: "arrow.up")
            }
            .disabled(position == 0)

            Button {
                library.moveTrack(track, in: playlist, by: 1)
            } label: {
                Label("Move down", systemImage: "arrow.down")
            }
            .disabled(position == count - 1)

            Button(role: .destructive) {
                library.removeTrack(track, from: playlist)
            } label: {
                Label("Remove from playlist", systemImage: "minus.circle")
            }
        }
    }
}
