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

    init(initiallyExpandedPlaylistID: Playlist.ID? = nil) {
        _expandedPlaylistID = State(initialValue: initiallyExpandedPlaylistID)
    }

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
        .modernRetroPanel(tone: .paper, radius: 12, padding: 16)
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
        WoodblockSectionHeader(
            title: "巻物",
            overline: "BOUND VOLUMES",
            detail: "Playlists · Arrange tracks in your order",
            accent: YagyoPrintColor.vermillionInk
        ) {
            Button {
                isCreatePresented = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(YagyoPrintColor.vermillionInk)
            .background(YagyoPrintColor.paperRaised, in: WoodblockFrameShape(cut: 8))
            .overlay {
                WoodblockFrameShape(cut: 8)
                    .stroke(YagyoPrintColor.vermillionInk, lineWidth: 1.5)
            }
            .accessibilityLabel("Create playlist")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("巻物はまだ白紙")
                .font(.system(.subheadline, design: .serif))
                .tracking(2)
                .foregroundStyle(YagyoPrintColor.ink)
            Text("Create a playlist, then add tracks from the library via long press.")
                .font(.footnote)
                .foregroundStyle(YagyoPrintColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            RetroDivider(color: YagyoPrintColor.paperMuted)
        }
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
                        .foregroundStyle(isActive ? YagyoPrintColor.vermillionInk : YagyoPrintColor.inkMuted)
                        .frame(width: 44, height: 44)
                        .background(YagyoPrintColor.persimmon.opacity(0.18), in: WoodblockFrameShape(cut: 7))
                        .overlay {
                            WoodblockFrameShape(cut: 7)
                                .stroke(
                                    isActive ? YagyoPrintColor.vermillionInk : YagyoPrintColor.indigoMuted,
                                    lineWidth: 1
                                )
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isActive ? YagyoPrintColor.vermillionInk : YagyoPrintColor.ink)
                            .lineLimit(1)
                        Text("\(playlist.trackCount) track\(playlist.trackCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(YagyoPrintColor.inkMuted)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(YagyoPrintColor.inkMuted)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 6)
                .frame(minHeight: 64)
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
        .background(isActive ? YagyoPrintColor.paperRaised : YagyoPrintColor.paper, in: WoodblockFrameShape(cut: 8))
        .overlay {
            WoodblockFrameShape(cut: 8)
                .stroke(
                    isActive ? YagyoPrintColor.vermillionInk : YagyoPrintColor.indigoMuted,
                    lineWidth: 1
                )
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        let playlistTracks = library.tracks(in: playlist)

        VStack(spacing: 6) {
            if playlistTracks.isEmpty {
                Text("Long press a library track to add it here.")
                    .font(.caption)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
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
        .padding(.top, 2)
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
                Text(positionLabel)
                    .font(.system(.caption, design: .serif).weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                    .frame(width: 20, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isCurrent ? YagyoPrintColor.vermillionInk : YagyoPrintColor.ink)
                        .lineLimit(1)
                    Text(track.durationText)
                        .font(.caption2)
                        .foregroundStyle(YagyoPrintColor.inkMuted)
                }

                Spacer()

                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle")
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? YagyoPrintColor.vermillionInk : YagyoPrintColor.inkMuted)
                    .frame(width: 36, height: 36)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .background(isCurrent ? YagyoPrintColor.paperRaised : YagyoPrintColor.paper, in: WoodblockFrameShape(cut: 7))
            .overlay {
                WoodblockFrameShape(cut: 7)
                    .stroke(isCurrent ? YagyoPrintColor.vermillionInk : YagyoPrintColor.paperMuted, lineWidth: 1)
            }
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

    private var positionLabel: String {
        let marks = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        return marks.indices.contains(position) ? marks[position] : "\(position + 1)"
    }
}
