import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @StateObject private var ushimitsu: UshimitsuWatch

    @State private var selectedTab: YagyoTab
    @State private var isImporterPresented = false
    @State private var isFixedEQAuditionPresented = false
    @State private var importErrorMessage: String?
    @State private var importSummary: ImportSummary?
    private let initiallyExpandedPlaylistID: Playlist.ID?

    init(
        initialTab: YagyoTab = .yagyo,
        startsInUshimitsu: Bool = false,
        initiallyExpandedPlaylistID: Playlist.ID? = nil
    ) {
        _selectedTab = State(initialValue: initialTab)
        _ushimitsu = StateObject(
            wrappedValue: UshimitsuWatch(initiallyForced: startsInUshimitsu)
        )
        self.initiallyExpandedPlaylistID = initiallyExpandedPlaylistID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TabView(selection: $selectedTab) {
                    ForEach(YagyoTab.allCases, id: \.self) { tab in
                        tabPage(for: tab)
                            .tabItem { Label(tab.title, systemImage: tab.icon) }
                            .tag(tab)
                    }
                }
                .tint(YagyoPrintColor.vermillionInk)
                .toolbarBackground(YagyoPrintColor.paperRaised, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.light, for: .tabBar)
                .background(YagyoPrintColor.canvas.ignoresSafeArea())

                AnnouncementToast(text: ushimitsu.announcement)
                    .padding(.bottom, 60)
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
                        guard !urls.isEmpty else { return }
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
            .sheet(isPresented: $isFixedEQAuditionPresented) {
                FixedEQAuditionView()
                    .environmentObject(library)
                    .environmentObject(player)
            }
            .onChange(of: router.pendingAction) { _, action in
                guard let action else { return }
                if action == .continueLastTrack {
                    player.playMostRecent(from: library)
                }
                selectedTab = YagyoTab.destination(for: action)
                router.pendingAction = nil
            }
        }
        .preferredColorScheme(.light)
    }

    /// 間取り(§4.2): 夜行=アプリの顔、行列=Library、巻物=Playlists。
    /// 取込導線は行列タブへ移すが、初回起動(空ライブラリで夜行に着地)の
    /// ためヘッダの取込ボタンも残す。
    @ViewBuilder
    private func tabPage(for tab: YagyoTab) -> some View {
        ZStack {
            YagyoBackdrop(isUshimitsu: ushimitsu.isNight)

            switch tab {
            case .yagyo:
                // 通常文字サイズは絵巻・丸紋・再生操作が同時に見える1画面を守る。
                // Accessibilityカテゴリだけは内容を切らず、縦スクロールへ退避する。
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        yagyoContent
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                            .padding(.bottom, 24)
                    }
                } else {
                    yagyoContent
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                }
            case .gyoretsu:
                ScrollView {
                    VStack(spacing: 18) {
                        LibrarySection(importAction: { isImporterPresented = true })
                        PlatformNote()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            case .makimono:
                ScrollView {
                    VStack(spacing: 18) {
                        PlaylistSection(initiallyExpandedPlaylistID: initiallyExpandedPlaylistID)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if tab.showsMiniAkari, let track = latestCurrentTrack {
                MiniAkariBar(
                    title: track.title,
                    isPlaying: player.isPlaying,
                    onToggle: { player.togglePlayPause() },
                    onOpenYagyo: { selectedTab = .yagyo }
                )
            }
        }
    }

    private var yagyoContent: some View {
        VStack(spacing: 12) {
            HeaderView(
                isUshimitsu: ushimitsu.isNight,
                showsFixedEQAudition: player.supportsFixedEQAudition,
                auditionAction: { isFixedEQAuditionPresented = true },
                importAction: { isImporterPresented = true }
            )
            ReactiveVisualStage(
                signals: player.paradeSignals,
                track: latestCurrentTrack,
                progress: player.progress,
                isUshimitsu: ushimitsu.isNight,
                isCompact: true,
                onMoonTap: { ushimitsu.toggleForced() }
            )
            TransportView()
            FooterView()
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

    private var latestCurrentTrack: AudioTrack? {
        guard let currentTrack = player.currentTrack else { return nil }
        return library.tracks.first { $0.id == currentTrack.id } ?? currentTrack
    }
}

private struct HeaderView: View {
    var isUshimitsu: Bool
    var showsFixedEQAudition: Bool
    var auditionAction: () -> Void
    var importAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text("百鬼夜行")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .tracking(6)
                        .foregroundStyle(isUshimitsu ? YagyoPrintColor.vermillionInk : YagyoPrintColor.ink)
                    Text("音")
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(YagyoPrintColor.paperRaised)
                        .frame(width: 27, height: 27)
                        .background(YagyoPrintColor.vermillion, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .rotationEffect(.degrees(-4))

                    if isUshimitsu {
                        Text("丑三つ")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(YagyoPrintColor.paperRaised)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(YagyoPrintColor.vermillionInk, in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text("Hyakki Yagyō · Local Procession")
                    .font(.caption.weight(.semibold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            HStack(spacing: 8) {
                if showsFixedEQAudition {
                    RetroIconButton(
                        systemImage: "ear",
                        accessibilityLabel: "一本の耳を開く",
                        accent: YagyoPrintColor.vermillionInk,
                        shape: .seal,
                        action: auditionAction
                    )
                }

                Button(action: importAction) {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(YagyoPrintColor.ink)
                .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(YagyoPrintColor.ink, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .inset(by: 4)
                        .stroke(YagyoPrintColor.paperMuted, lineWidth: 1)
                }
                .accessibilityLabel("Import audio")
            }
        }
        .modernRetroPanel(tone: .paper, radius: 12, padding: 12)
        .animation(.easeInOut(duration: 1.2), value: isUshimitsu)
    }
}

private struct ReactiveVisualStage: View {
    @ObservedObject var signals: ParadeSignalCoordinator
    var track: AudioTrack?
    var progress: Double
    var isUshimitsu: Bool
    var isCompact: Bool = false
    var onMoonTap: () -> Void

    var body: some View {
        let snapshot = signals.snapshot
        let residentID = track.map { YokaiResidency.spriteID(for: $0.id) }

        YagyoParadeView(
            signal: snapshot,
            residentSpriteID: residentID,
            isUshimitsu: isUshimitsu,
            onMoonTap: onMoonTap
        )
        ArtworkStage(
            track: track,
            progress: progress,
            waveformLevel: snapshot.waveformLevel,
            activity: snapshot.activity,
            waveformLevelBand: snapshot.waveformLevelBand,
            isCompact: isCompact
        )
    }
}

private struct ArtworkStage: View {
    var track: AudioTrack?
    var progress: Double
    var waveformLevel: Double
    var activity: ParadeSignalSnapshot.Activity
    var waveformLevelBand: ParadeSignalSnapshot.LevelBand
    /// 夜行タブの1画面レイアウト用。波形の四角を残り高さへ縮め、
    /// 曲札を1行へ畳んで、スクロールなしで再生操作まで見えるようにする。
    var isCompact: Bool = false

    var body: some View {
        VStack(spacing: isCompact ? 10 : 16) {
            CircularWaveform(
                progress: progress,
                level: waveformLevel,
                activity: activity,
                levelBand: waveformLevelBand
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(minHeight: 140, maxHeight: isCompact ? .infinity : 360)
            .frame(maxWidth: .infinity)

            if isCompact {
                HStack(spacing: 8) {
                    Text(track?.title ?? "行列はまだ静か")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YagyoPrintColor.ink)
                        .lineLimit(1)
                    if let artist = track?.artist, !artist.isEmpty {
                        Text("· \(artist)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(YagyoPrintColor.teal)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(YagyoPrintColor.ink, lineWidth: 1)
                }
            } else {
                VStack(spacing: 5) {
                    Text(track?.title ?? "行列はまだ静か")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(YagyoPrintColor.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let artist = track?.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(YagyoPrintColor.teal)
                            .lineLimit(1)
                    }

                    Text(track?.originalFilename ?? "Import a track to start the procession")
                        .font(.footnote)
                        .foregroundStyle(YagyoPrintColor.inkMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(YagyoPrintColor.ink, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TransportView: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Button {
                    player.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .frame(width: 48, height: 48)
                        .background(YagyoPrintColor.paperRaised, in: Circle())
                        .overlay(Circle().stroke(YagyoPrintColor.ink, lineWidth: 1))
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
                        .frame(width: 64, height: 64)
                        .background(YagyoPrintColor.persimmon, in: Circle())
                        .foregroundStyle(YagyoPrintColor.ink)
                        .overlay {
                            Circle().stroke(YagyoPrintColor.ink, lineWidth: 1.5)
                            Circle()
                                .inset(by: 5)
                                .stroke(YagyoPrintColor.paperRaised, lineWidth: 1)
                        }
                }
                .disabled(!library.hasTracks)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 48, height: 48)
                        .background(YagyoPrintColor.paperRaised, in: Circle())
                        .overlay(Circle().stroke(YagyoPrintColor.ink, lineWidth: 1))
                }
                .disabled(!library.hasTracks)
            }
            .font(.title2.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(YagyoPrintColor.ink)
            .opacity(library.hasTracks ? 1 : 0.45)

            VStack(spacing: 4) {
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
                .foregroundStyle(YagyoPrintColor.inkMuted)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.1.fill")
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                TomoshibiSlider(value: volumeBinding)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(YagyoPrintColor.inkMuted)
            }
            .font(.caption)
        }
        .modernRetroPanel(tone: .paper, radius: 12, padding: 10)
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

    @State private var searchText = ""
    @State private var sort = LibrarySort.newest
    @State private var selectedPlaylistID: Playlist.ID?
    @State private var editingTrack: AudioTrack?
    @State private var tobariTrack: AudioTrack?

    var body: some View {
        let visibleTracks = library.filteredTracks(searchText: searchText, sort: sort, playlistID: selectedPlaylistID)
        let duplicateTrackGroups = library.duplicateTrackGroups

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("行列")
                        .font(.system(.headline, design: .serif))
                        .tracking(4)
                        .foregroundStyle(YagyoPrintColor.ink)
                    Text("Library · Files copied into the app folder")
                        .font(.caption)
                        .foregroundStyle(YagyoPrintColor.inkMuted)
                }
                Spacer()
                Button(action: importAction) {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(YagyoPrintColor.ink)
                .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(YagyoPrintColor.ink, lineWidth: 1)
                }
                .accessibilityLabel("Import audio")
            }

            libraryFeedback(duplicateTrackGroups: duplicateTrackGroups)
            libraryControls(visibleCount: visibleTracks.count)

            if library.tracks.isEmpty {
                EmptyLibraryView(importAction: importAction)
            } else if visibleTracks.isEmpty {
                EmptyFilteredLibraryView(clearFilters: clearFilters)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleTracks) { track in
                        TrackRow(
                            track: track,
                            playbackContext: playbackContext,
                            editAction: { editingTrack = track },
                            tobariAction: { tobariTrack = track }
                        )
                    }
                }
            }
        }
        .modernRetroPanel(tone: .paper, radius: 12, padding: 16)
        .sheet(item: $editingTrack) { track in
            TrackMetadataEditor(track: track)
        }
        .sheet(item: $tobariTrack) { track in
            TobariView(track: track)
        }
        .onChange(of: selectedPlaylistID) { _, playlistID in
            if playlistID == nil, sort == .playlistOrder {
                sort = .newest
            }
        }
        .onChange(of: library.playlists.map(\.id)) { _, playlistIDs in
            guard let selectedPlaylistID, !playlistIDs.contains(selectedPlaylistID) else { return }
            self.selectedPlaylistID = nil
            if sort == .playlistOrder {
                sort = .newest
            }
        }
    }

    @ViewBuilder
    private func libraryFeedback(duplicateTrackGroups: [DuplicateTrackGroup]) -> some View {
        switch library.importState {
        case .importing(let count):
            LibraryStatusBanner(
                icon: "square.and.arrow.down",
                title: "取込中",
                message: "\(count) 件の音源を行列へ納めています。",
                accent: YagyoPrintColor.teal
            )
        case .finished(let summary) where summary.hasIssues:
            LibraryStatusBanner(
                icon: "exclamationmark.octagon",
                title: "取込結果を確認",
                message: importFeedbackMessage(summary),
                accent: YagyoPrintColor.vermillionInk
            )
        case .failed(let message):
            LibraryStatusBanner(
                icon: "exclamationmark.triangle.fill",
                title: "ライブラリを読み込めません",
                message: message,
                accent: YagyoPrintColor.vermillionInk
            )
        case .idle, .finished:
            EmptyView()
        }

        if !duplicateTrackGroups.isEmpty {
            LibraryStatusBanner(
                icon: "doc.on.doc.fill",
                title: "重複候補があります",
                message: duplicateFeedbackMessage(duplicateTrackGroups),
                accent: YagyoPrintColor.vermillionInk
            )
        }

        if library.tracks.count >= 24 {
            LibraryStatusBanner(
                icon: "magnifyingglass",
                title: "長い行列を整理できます",
                message: "検索、巻物スコープ、追加日・タイトル・長さ・巻物順の並び替えで探せます。",
                accent: YagyoPrintColor.brass
            )
        }
    }

    private func libraryControls(visibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                TextField("Search title, artist, file, notes", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .foregroundStyle(YagyoPrintColor.ink)
                    .tint(YagyoPrintColor.vermillionInk)
            }
            .font(.footnote)
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(YagyoPrintColor.ink, lineWidth: 1)
            }

            // menuスタイルのPickerはラベルが折り返すと枠外へあふれて下の行に重なる
            // (実機で確認)。fixedSizeで1行の固有幅を確保し、収まらない幅では2段組へ。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    scopePicker
                    sortPicker
                    Spacer(minLength: 8)
                    trackCountText(visibleCount: visibleCount)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        scopePicker
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 10) {
                        sortPicker
                        Spacer(minLength: 0)
                    }
                    trackCountText(visibleCount: visibleCount)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(YagyoPrintColor.vermillionInk)
        }
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $selectedPlaylistID) {
            Text("行列すべて").tag(Playlist.ID?.none)
            ForEach(library.playlists) { playlist in
                Text(playlist.name).tag(Optional(playlist.id))
            }
        }
        .pickerStyle(.menu)
        .lineLimit(1)
        .fixedSize()
        .frame(minHeight: 44)
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sort) {
            ForEach(availableSorts) { sort in
                Text(sort.rawValue).tag(sort)
            }
        }
        .pickerStyle(.menu)
        .lineLimit(1)
        .fixedSize()
        .frame(minHeight: 44)
    }

    private func trackCountText(visibleCount: Int) -> some View {
        Text("\(visibleCount) / \(library.tracks.count) 曲")
            .font(.caption.monospacedDigit())
            .foregroundStyle(YagyoPrintColor.inkMuted)
            .lineLimit(1)
            .fixedSize()
    }

    private var availableSorts: [LibrarySort] {
        if selectedPlaylistID == nil {
            return LibrarySort.allCases.filter { $0 != .playlistOrder }
        }
        return LibrarySort.allCases
    }

    private var playbackContext: PlaybackContext {
        guard let selectedPlaylistID else { return .library }
        return .playlist(selectedPlaylistID)
    }

    private func clearFilters() {
        searchText = ""
        selectedPlaylistID = nil
        sort = .newest
    }

    private func importFeedbackMessage(_ summary: ImportSummary) -> String {
        var parts: [String] = []
        if summary.duplicates > 0 {
            parts.append("重複見送り \(summary.duplicates) 件")
        }
        if !summary.failures.isEmpty {
            parts.append("失敗 \(summary.failures.count) 件")
        }
        return parts.joined(separator: " · ")
    }

    private func duplicateFeedbackMessage(_ groups: [DuplicateTrackGroup]) -> String {
        let visibleGroups = groups.prefix(3).map { group in
            group.tracks
                .map { "\($0.title) (\($0.originalFilename))" }
                .joined(separator: " / ")
        }
        var message = "同じ SHA-256 の音源が \(groups.count) 組あります: \(visibleGroups.joined(separator: " · "))"
        if groups.count > visibleGroups.count {
            message += " 他 \(groups.count - visibleGroups.count) 組"
        }
        return message
    }
}

private struct LibraryStatusBanner: View {
    var icon: String
    var title: String
    var message: String
    var accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.ink)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent, lineWidth: 1)
        }
    }
}

private struct TrackRow: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController

    var track: AudioTrack
    var playbackContext: PlaybackContext = .library
    var editAction: () -> Void
    var tobariAction: () -> Void

    @State private var isDeleteConfirmationPresented = false

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id
    }

    var body: some View {
        let sprite = YokaiGallery.sprite(for: track.id)

        Button {
            if isCurrent {
                // いま流れている曲は頭出しし直さず、再生/一時停止を切り替える
                // (行のアイコンがpause表示のときの期待どおりの挙動)。
                // 次曲/前曲の文脈だけは見えているスコープへ合わせる。
                player.adoptContext(playbackContext, from: library)
                player.togglePlayPause()
            } else {
                player.load(track, from: library, autoplay: true, context: playbackContext)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isCurrent ? YagyoPrintColor.paper : YagyoPrintColor.paperRaised)
                    sprite.thumbnail.image
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                        .accessibilityHidden(true)
                }
                .frame(width: 46, height: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isCurrent ? YagyoPrintColor.vermillionInk : YagyoPrintColor.paperMuted, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCurrent ? YagyoPrintColor.vermillionInk : YagyoPrintColor.ink)
                        .lineLimit(1)

                    if let artist = track.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(YagyoPrintColor.teal)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Text(sprite.name)
                            .font(.system(size: 11, design: .serif))
                            .foregroundStyle(isCurrent ? YagyoPrintColor.vermillionInk : YagyoPrintColor.inkMuted)
                        Text("· \(track.durationText) · \(track.importedDateText)")
                            .font(.caption)
                            .foregroundStyle(YagyoPrintColor.inkMuted)
                        if track.notes != nil {
                            Image(systemName: "note.text")
                                .font(.caption2)
                                .foregroundStyle(YagyoPrintColor.inkMuted)
                        }
                        if track.artworkFilename != nil {
                            Image(systemName: "photo")
                                .font(.caption2)
                                .foregroundStyle(YagyoPrintColor.inkMuted)
                        }
                    }
                }

                Spacer()

                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(isCurrent ? YagyoPrintColor.vermillionInk : YagyoPrintColor.inkMuted)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 8)
            .frame(minHeight: 64)
            .background(isCurrent ? YagyoPrintColor.paperRaised : YagyoPrintColor.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isCurrent ? YagyoPrintColor.vermillionInk : YagyoPrintColor.paperMuted, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: editAction) {
                Label("Edit metadata", systemImage: "pencil")
            }

            Button(action: tobariAction) {
                Label("狐火の帳で検聴", systemImage: "flame")
            }

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

private struct TrackMetadataEditor: View {
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var track: AudioTrack

    @State private var title: String
    @State private var artist: String
    @State private var artworkFilename: String
    @State private var notes: String

    init(track: AudioTrack) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist ?? "")
        _artworkFilename = State(initialValue: track.artworkFilename ?? "")
        _notes = State(initialValue: track.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("音源の札") {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Artwork filename or reference", text: $artworkFilename)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section("Stored copy") {
                    Text(track.storedFilename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("札を直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let didSave = library.updateMetadata(
                            for: track.id,
                            title: title,
                            artist: artist,
                            artworkFilename: artworkFilename,
                            notes: notes
                        )
                        if didSave,
                           let updatedTrack = library.tracks.first(where: { $0.id == track.id }) {
                            player.refreshCurrentTrackMetadata(updatedTrack)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct EmptyLibraryView: View {
    var importAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            (YokaiGallery.sprite(withID: "kitsune") ?? YokaiGallery.parade[0]).thumbnail.image
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("行列はまだ静か")
                    .font(.system(.headline, design: .serif))
                    .tracking(3)
                    .foregroundStyle(YagyoPrintColor.ink)
                Text("Choose MP3, M4A, WAV, AIFF, AAC, CAF, or FLAC files. They will be copied into this app.")
                    .font(.footnote)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
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
                        .foregroundStyle(YagyoPrintColor.ink)
                }
                .padding(.horizontal, 17)
                .frame(minHeight: 44)
                .background(YagyoPrintColor.persimmon, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(YagyoPrintColor.ink, lineWidth: 1))
                .foregroundStyle(YagyoPrintColor.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import audio")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct EmptyFilteredLibraryView: View {
    var clearFilters: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(YagyoPrintColor.inkMuted)
            Text("該当する音源が見つかりません")
                .font(.system(.subheadline, design: .serif))
                .tracking(2)
                .foregroundStyle(YagyoPrintColor.ink)
            Text("検索語、巻物スコープ、並び替えを変えて探せます。")
                .font(.footnote)
                .foregroundStyle(YagyoPrintColor.inkMuted)
                .multilineTextAlignment(.center)
            Button("条件を戻す", action: clearFilters)
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(YagyoPrintColor.vermillionInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(YagyoPrintColor.vermillionInk, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct PlatformNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "music.note.list")
                .foregroundStyle(YagyoPrintColor.ink)
            Text("Built for iOS 26+. Local files stay inside the app folder; Apple Music catalog features can be layered on later with MusicKit.")
                .font(.caption)
                .foregroundStyle(YagyoPrintColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modernRetroPanel(tone: .paper, radius: 12, padding: 12)
    }
}

private struct FooterView: View {
    var body: some View {
        Text("絵巻は右から左へ流れる")
            .font(.system(size: 11, design: .serif))
            .tracking(3)
            .foregroundStyle(YagyoPrintColor.inkMuted)
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
                    .foregroundStyle(YagyoPrintColor.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(YagyoPrintColor.vermillionInk, lineWidth: 1)
                    }
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: text)
        .allowsHitTesting(false)
    }
}

/// 間取り — 夜行の3タブ。仕様§4.2の承認構成(推奨案: 3タブ+ミニ灯り)。
enum YagyoTab: String, CaseIterable {
    case yagyo
    case gyoretsu
    case makimono

    var title: String {
        switch self {
        case .yagyo: "夜行"
        case .gyoretsu: "行列"
        case .makimono: "巻物"
        }
    }

    var icon: String {
        switch self {
        case .yagyo: "house"
        case .gyoretsu: "list.bullet"
        case .makimono: "scroll"
        }
    }

    /// ミニ灯り(現在曲の小さなバー)を出すタブ。夜行は本体の操作面があるので出さない。
    var showsMiniAkari: Bool {
        self != .yagyo
    }

    /// URLショートカットの行き先。libraryは行列、再生系は夜行へ。
    static func destination(for action: AppRouter.PendingAction) -> YagyoTab {
        switch action {
        case .showLibrary: .gyoretsu
        case .showNowPlaying, .continueLastTrack: .yagyo
        }
    }
}

/// ミニ灯り — 行列/巻物タブの下部に、現在曲がある間だけ灯る小さなバー。
/// タップで夜行タブへ。再生/一時停止は同一曲toggleの原則を守る。
/// 意匠は灯芯と同じ「罫と丸紋」の文法(フラット塗り+丸紋、glowなし)。
struct MiniAkariBar: View {
    var title: String
    var isPlaying: Bool
    var onToggle: () -> Void
    var onOpenYagyo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(YagyoPrintColor.persimmon)
                .overlay(Circle().stroke(YagyoPrintColor.ink, lineWidth: 1.5))
                .overlay(
                    Circle()
                        .fill(YagyoPrintColor.vermillion)
                        .frame(width: 4, height: 4)
                        .opacity(isPlaying ? 1 : 0)
                )
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(YagyoPrintColor.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(YagyoPrintColor.paper, in: Circle())
                    .overlay(Circle().stroke(YagyoPrintColor.vermillionInk, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(YagyoPrintColor.vermillionInk)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(YagyoPrintColor.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(YagyoPrintColor.ink, lineWidth: 1)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .inset(by: 4)
                .stroke(YagyoPrintColor.paperMuted, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenYagyo)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ミニ灯り: \(title)。タップで夜行へ")
        .accessibilityAction(named: "夜行を開く") { onOpenYagyo() }
    }
}

#Preview("Empty Library") {
    ContentView()
        .environmentObject(AudioLibraryStore())
        .environmentObject(PlaybackController())
        .environmentObject(AppRouter())
}
