import SwiftUI
import UIKit

struct MIDIWorkspaceView: View {
    enum Layout {
        case monitor
        case songStudio
    }

    @ObservedObject var viewModel: MainViewModel
    let layout: Layout
    let openSetup: () -> Void
    let openSongStudio: () -> Void
    let requestSongImport: () -> Void
    let requestScoreImport: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingFullKeyboard = false
    @State private var compactKeyboardFirstNote = Self.defaultCompactKeyboardFirstNote
    @State private var scoreContentHeight: CGFloat = 180
    @State private var sheetDetail: SheetDetail?

    private static let compactKeyboardMinimumNote = 21
    private static let compactKeyboardMaximumNote = 108
    private static let compactKeyboardSpan = 24
    private static let compactKeyboardEdgePadding = 4
    private static let defaultCompactKeyboardFirstNote = 48

    private var copy: LocalizedCopy { .init(language: viewModel.language) }
    private var activeEvent: MIDINoteEvent? { viewModel.activeNoteEvent }
    private var combinedActiveNotes: Set<Int> { viewModel.heldNoteNumbers.union(viewModel.activeSongNotes) }
    private var displayNote: Int? { viewModel.latestSongNoteNumber ?? activeEvent?.noteNumber }

    init(
        viewModel: MainViewModel,
        layout: Layout = .monitor,
        openSetup: @escaping () -> Void,
        openSongStudio: @escaping () -> Void = {},
        requestSongImport: @escaping () -> Void = {},
        requestScoreImport: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.layout = layout
        self.openSetup = openSetup
        self.openSongStudio = openSongStudio
        self.requestSongImport = requestSongImport
        self.requestScoreImport = requestScoreImport
    }

    var body: some View {
        VStack(spacing: 14) {
            switch layout {
            case .monitor:
                liveMonitorCard
                keyboardCard
                HStack(spacing: 10) {
                    Button {
                        openSongStudio()
                    } label: {
                        Label(copy.songStudio, systemImage: "play.square.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        openSetup()
                    } label: {
                        Label(copy.setup, systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PiaKeysTheme.purple)
                    .foregroundStyle(.white)
                }
            case .songStudio:
                songPlayerCard

                if let scoreURL = viewModel.selectedSong?.scoreURL {
                    scoreCard(url: scoreURL)
                } else {
                    songStaffCard
                }

                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 14) {
                        libraryCard
                        outputCard
                    }
                } else {
                    libraryCard
                    outputCard
                }
            }
        }
        .background {
            LandscapeKeyboardPresenter(
                isPresented: $showingFullKeyboard,
                viewModel: viewModel
            )
            .frame(width: 0, height: 0)
        }
        .sheet(item: $sheetDetail) { detail in
            PlaybackPositionView(position: viewModel.playbackPosition) { milliseconds in
                SheetMusicDetailView(
                    detail: detail,
                    positionMilliseconds: milliseconds,
                    copy: copy
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var liveMonitorCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    SectionTitle(title: copy.liveMonitor, subtitle: copy.liveMonitorSubtitle, symbol: "waveform.path")
                    Spacer()
                    VStack(spacing: 0) {
                        Text(activeEvent?.noteName ?? "—")
                            .font(.title2.weight(.bold))
                        Text(activeEvent.map { copy.solfegeName(for: $0.noteNumber) } ?? "—")
                            .font(.subheadline)
                    }
                    .foregroundStyle(PiaKeysTheme.purple)
                    .frame(width: 78, height: 78)
                    .background(PiaKeysTheme.purple.opacity(0.12), in: Circle())
                    .overlay { Circle().stroke(PiaKeysTheme.purple.opacity(0.7), lineWidth: 2) }
                }

                HStack(spacing: 8) {
                    MetricPill(
                        title: copy.source,
                        value: copy.sourceName(viewModel.activeNoteEvent?.source ?? (viewModel.visibleWiredSources.isEmpty ? nil : .wired))
                    )
                    MetricPill(title: copy.velocity, value: "\(activeEvent?.velocity ?? 0)")
                    MetricPill(title: copy.event, value: copy.eventName(activeEvent?.type))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.recentNotes).font(.caption).foregroundStyle(.secondary)
                    Group {
                        if recentNoteEvents.isEmpty {
                            Text(copy.noNotes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(recentNoteEvents) { event in
                                        VStack(spacing: 2) {
                                            Text(event.noteName).font(.subheadline.weight(.semibold))
                                            Text("#\(event.noteNumber)").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            colorScheme == .dark
                                                ? PiaKeysTheme.darkInsetSurface
                                                : PiaKeysTheme.paleBlue.opacity(0.8),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(PiaKeysTheme.gold.opacity(0.65)) }
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                    .frame(height: 48, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var recentNoteEvents: [MIDINoteEvent] {
        Array(viewModel.noteEvents.filter { $0.type == .noteOn }.prefix(6))
    }

    private var songPlayerCard: some View {
        let duration = viewModel.selectedSongDurationMilliseconds
        return PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(
                        title: copy.songStudio,
                        subtitle: viewModel.selectedSong?.title ?? copy.noNotes,
                        symbol: "play.square.stack"
                    )
                    Spacer()
                    Text(viewModel.songPlaying ? copy.playing : copy.midiReady)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(viewModel.songPlaying ? PiaKeysTheme.gold : PiaKeysTheme.purple)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(uiColor: .systemBackground), in: Capsule())
                }

                PlaybackPositionView(position: viewModel.playbackPosition) { milliseconds in
                    VStack(spacing: 14) {
                        Slider(
                            value: Binding(
                                get: { Double(milliseconds) },
                                set: { viewModel.seekSong(to: Int64($0.rounded())) }
                            ),
                            in: 0...Double(max(1, duration))
                        )
                        .tint(PiaKeysTheme.gold)
                        HStack {
                            Text(format(milliseconds: milliseconds))
                            Spacer()
                            Text(format(milliseconds: duration))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    MetricPill(title: copy.tempo, value: "\(viewModel.selectedSong?.tempo ?? 0)")
                    MetricPill(title: copy.timeSignature, value: viewModel.selectedSong?.timeSignature ?? "—")
                    MetricPill(title: copy.chord, value: ChordRecognizer.recognize(combinedActiveNotes)?.symbol ?? "—")
                }

                HStack {
                    Button {
                        viewModel.toggleSongPlayback()
                    } label: {
                        Label(viewModel.songPlaying ? copy.pause : copy.play, systemImage: viewModel.songPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(copy.reset) { viewModel.resetSong() }
                        .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Text(copy.speed).font(.caption.weight(.semibold))
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { speed in
                        Button("\(speed, specifier: "%.2g")×") {
                            viewModel.playbackSpeed = speed
                        }
                        .buttonStyle(.bordered)
                        .tint(viewModel.playbackSpeed == speed ? PiaKeysTheme.purple : .secondary)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(minWidth: 40)
                    }
                }

                HStack(spacing: 8) {
                    Toggle(copy.loop, isOn: $viewModel.loopEnabled)
                        .font(.caption)
                    Button(copy.loopStart) {
                        viewModel.loopStartMilliseconds = viewModel.songPositionMilliseconds
                    }
                    .buttonStyle(.bordered)
                    Button(copy.loopEnd) {
                        viewModel.loopEndMilliseconds = viewModel.songPositionMilliseconds
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Picker(copy.hands, selection: $viewModel.playbackHand) {
                        ForEach(PracticeHandSelection.allCases) { hand in
                            Text(handLabel(hand)).tag(hand)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle(copy.countIn, isOn: $viewModel.countInEnabled)
                        .font(.caption)
                }

                if viewModel.countInEnabled {
                    Picker(
                        copy.countInBars,
                        selection: Binding(
                            get: { viewModel.countInBars },
                            set: { viewModel.countInBars = $0 }
                        )
                    ) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(copy.countInBars)
                }

                if viewModel.practiceCountingIn {
                    Label(
                        String(format: copy.countInBeat, viewModel.practiceCountInBeat + 1),
                        systemImage: "metronome"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PiaKeysTheme.gold)
                }
            }
        }
    }

    private func handLabel(_ hand: PracticeHandSelection) -> String {
        switch hand {
        case .both: copy.bothHands
        case .left: copy.leftHand
        case .right: copy.rightHand
        }
    }

    private var songStaffCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: copy.sheetPreview, symbol: "music.quarternote.3")
                    Spacer()
                    Button(copy.importScore) { requestScoreImport() }
                        .font(.caption)
                }
                Button { sheetDetail = .generated(viewModel.selectedSong) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        PlaybackPositionView(position: viewModel.playbackPosition) { milliseconds in
                            SongStaffPreview(
                                song: viewModel.selectedSong,
                                positionMilliseconds: milliseconds,
                                activeNotes: viewModel.activeSongNotes,
                                language: viewModel.language
                            )
                        }
                        openSheetHint
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copy.openSheet)
            }
        }
    }

    private func scoreCard(url: URL) -> some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: copy.sheetPreview, symbol: "music.note.list")
                    Spacer()
                    Button(copy.importScore) { requestScoreImport() }
                        .font(.caption)
                }
                Button { sheetDetail = .musicXML(url) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        PlaybackPositionView(position: viewModel.playbackPosition) { milliseconds in
                            MusicXMLScoreView(
                                url: url,
                                positionMilliseconds: milliseconds,
                                contentHeight: $scoreContentHeight,
                                language: viewModel.language
                            )
                            .allowsHitTesting(false)
                        }
                        openSheetHint
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copy.openSheet)
                    .frame(height: scoreContentHeight)
                    .animation(.easeInOut(duration: 0.2), value: scoreContentHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var openSheetHint: some View {
        Label(copy.openSheet, systemImage: "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(PiaKeysTheme.purple)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(uiColor: .systemBackground), in: Capsule())
            .padding(10)
    }

    private var keyboardCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: copy.keyboard, symbol: "pianokeys")
                    Spacer()
                    if let displayNote {
                        Text("\(displayNote.noteName) / \(copy.solfegeName(for: displayNote))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PiaKeysTheme.purple)
                    }
                }

                Group {
                    if let chord = ChordRecognizer.recognize(combinedActiveNotes) {
                        Label(chord.symbol, systemImage: "music.note")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PiaKeysTheme.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text(copy.noChord)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(height: 24, alignment: .leading)

                Button {
                    showingFullKeyboard = true
                } label: {
                    Label(copy.fullKeyboard, systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)

                PianoKeyboardView(
                    activeNotes: combinedActiveNotes,
                    firstNote: compactKeyboardFirstNote,
                    lastNote: compactKeyboardLastNote,
                    height: 128,
                    fitToWidth: true,
                    language: copy.language,
                    onNoteOn: viewModel.beginPreviewNote,
                    onNoteOff: viewModel.endPreviewNote
                )
                .equatable()
                .animation(.easeInOut(duration: 0.24), value: compactKeyboardFirstNote)
            }
        }
        .onAppear {
            updateCompactKeyboardWindow(for: compactKeyboardNotes)
        }
        .onChange(of: combinedActiveNotes) { _, _ in
            updateCompactKeyboardWindow(for: compactKeyboardNotes)
        }
        .onChange(of: displayNote) { _, _ in
            updateCompactKeyboardWindow(for: compactKeyboardNotes)
        }
    }

    private var compactKeyboardNotes: Set<Int> {
        var notes = combinedActiveNotes
        if let displayNote { notes.insert(displayNote) }
        return notes
    }

    private var compactKeyboardLastNote: Int {
        min(
            Self.compactKeyboardMaximumNote,
            compactKeyboardFirstNote + Self.compactKeyboardSpan
        )
    }

    private func updateCompactKeyboardWindow(for activeNotes: Set<Int>) {
        guard let minimumNote = activeNotes.min(), let maximumNote = activeNotes.max() else { return }

        let lowerEdge = compactKeyboardFirstNote + Self.compactKeyboardEdgePadding
        let upperEdge = compactKeyboardLastNote - Self.compactKeyboardEdgePadding
        guard minimumNote < lowerEdge || maximumNote > upperEdge else { return }

        let centerNote = (minimumNote + maximumNote) / 2
        let unalignedStart = centerNote - Self.compactKeyboardSpan / 2
        let alignedStart = unalignedStart - positiveRemainder(unalignedStart, modulus: 12)
        let maximumStart = Self.compactKeyboardMaximumNote - Self.compactKeyboardSpan
        let nextStart = min(
            max(Self.compactKeyboardMinimumNote, alignedStart),
            maximumStart
        )

        guard nextStart != compactKeyboardFirstNote else { return }
        withAnimation(.easeInOut(duration: 0.24)) {
            compactKeyboardFirstNote = nextStart
        }
    }

    private func positiveRemainder(_ value: Int, modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private var libraryCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: copy.library, symbol: "books.vertical")
                    Spacer()
                    Button {
                        requestSongImport()
                    } label: {
                        Label(copy.importMIDI, systemImage: "square.and.arrow.down")
                    }
                    .font(.caption)
                }

                ForEach(viewModel.songs) { song in
                    Button {
                        viewModel.selectSong(song.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.subheadline.weight(.semibold))
                                Text(song.composer).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if song.id == viewModel.selectedSongID {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(PiaKeysTheme.purple)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if song.id != PracticeSong.demo.id {
                            Button(role: .destructive) {
                                viewModel.deleteSong(song.id)
                            } label: {
                                Label(copy.deleteSong, systemImage: "trash")
                            }
                        }
                    }
                    if song.id != viewModel.songs.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var outputCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: copy.outputRoute, symbol: "arrow.triangle.branch")
                Picker(copy.outputRoute, selection: $viewModel.songOutputRoute) {
                    ForEach(SongOutputRoute.allCases) { route in
                        Text(copy.outputRouteName(route)).tag(route)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if viewModel.songOutputRoute == .wired && !viewModel.canSendWiredMIDI {
                    unavailableOutputButton(copy.noWiredMIDIOutput)
                }
                if viewModel.songOutputRoute == .ble && !viewModel.canSendBLEMIDI {
                    unavailableOutputButton(copy.bluetoothOutputNotReady)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func unavailableOutputButton(_ message: String) -> some View {
        Button {
            viewModel.songOutputRoute = .appOnly
            openSetup()
        } label: {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
        }
        .buttonStyle(.bordered)
    }

    private func format(milliseconds: Int64) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// Confines the 30 Hz observation to content that actually displays time.
private struct PlaybackPositionView<Content: View>: View {
    @ObservedObject var position: PlaybackPosition
    @ViewBuilder let content: (Int64) -> Content

    var body: some View {
        content(position.milliseconds)
    }
}

private enum SheetDetail: Identifiable {
    case generated(PracticeSong?)
    case musicXML(URL)

    var id: String {
        switch self {
        case .generated: "generated"
        case let .musicXML(url): "musicxml:\(url.path)"
        }
    }
}

private struct SheetMusicDetailView: View {
    let detail: SheetDetail
    let positionMilliseconds: Int64
    let copy: LocalizedCopy

    @Environment(\.dismiss) private var dismiss
    @State private var scoreContentHeight: CGFloat = 520
    @State private var scorePage = 1
    @State private var scorePageCount = 1

    var body: some View {
        NavigationStack {
            Group {
                switch detail {
                case let .generated(song):
                    VStack(spacing: 10) {
                        if let song {
                            GeneratedSongScoreView(
                                song: song,
                                positionMilliseconds: positionMilliseconds,
                                height: 420,
                                showsAllPages: false,
                                page: scorePage,
                                language: copy.language,
                                onPageCount: updatePageCount,
                                onPageChange: updatePage
                            )
                            .padding(.horizontal)
                            pageControls
                        } else {
                            ContentUnavailableView(copy.noSheetMusic, systemImage: "music.note.list")
                        }
                    }
                case let .musicXML(url):
                    VStack(spacing: 10) {
                        MusicXMLScoreView(
                            url: url,
                            positionMilliseconds: positionMilliseconds,
                            contentHeight: $scoreContentHeight,
                            heightRange: 360...620,
                            showsAllPages: false,
                            page: scorePage,
                            language: copy.language,
                            onPageCount: updatePageCount,
                            onPageChange: updatePage
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: min(620, max(360, scoreContentHeight)))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding()
                        pageControls
                    }
                }
            }
            .navigationTitle(copy.sheetMusic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.close) { dismiss() }
                }
            }
        }
    }

    private var pageControls: some View {
        Group {
            if scorePageCount > 1 {
                HStack(spacing: 18) {
                    Button {
                        scorePage = max(1, scorePage - 1)
                    } label: {
                        Label(copy.previousPage, systemImage: "chevron.left")
                    }
                    .disabled(scorePage <= 1)

                    Text("\(scorePage) / \(scorePageCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        scorePage = min(scorePageCount, scorePage + 1)
                    } label: {
                        Label(copy.nextPage, systemImage: "chevron.right")
                    }
                    .disabled(scorePage >= scorePageCount)
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 8)
            }
        }
    }

    private func updatePageCount(_ count: Int) {
        scorePageCount = max(1, count)
        scorePage = min(max(1, scorePage), scorePageCount)
    }

    private func updatePage(_ page: Int) {
        // The WebView can report the active page before its render-status
        // message updates scorePageCount. Keep that page until the count is
        // known; updatePageCount performs the final bounds check.
        scorePage = max(1, page)
    }
}

private struct FullKeyboardView: View {
    @ObservedObject var viewModel: MainViewModel
    let onDone: () -> Void

    @State private var scrollProgress: CGFloat = 0
    @State private var scrollTargetNote = 48
    @State private var scrollRequestID = 0
    @State private var scrollAnimationDuration = 0.12

    private static let firstNote = 21
    private static let lastNote = 108
    private static let whiteKeyWidth: CGFloat = 52

    private var copy: LocalizedCopy { .init(language: viewModel.language) }
    private var notes: [Int] { Array(Self.firstNote...Self.lastNote) }
    private var whiteNotes: [Int] { notes.filter { !$0.isBlackPianoKey } }

    var body: some View {
        GeometryReader { proxy in
            let keyboardWidth = max(1, proxy.size.width - 32)
            let controlsHeight: CGFloat = 44
            let overviewHeight: CGFloat = 48
            let verticalSpacing: CGFloat = 6
            let verticalInset: CGFloat = 6
            let reservedHeight = controlsHeight + overviewHeight + 2 * (verticalSpacing + verticalInset)
            let keyboardHeight = max(96, proxy.size.height - reservedHeight)
            let viewportFraction = min(
                1,
                keyboardWidth / (CGFloat(whiteNotes.count) * Self.whiteKeyWidth)
            )
            let visibleRange = visibleNoteRange(viewportWidth: keyboardWidth)
            let rangeLabel = "\(visibleRange.lowerBound.noteName) – \(visibleRange.upperBound.noteName)"

            VStack(spacing: verticalSpacing) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.fullPiano)
                            .font(.headline)
                            .lineLimit(1)
                        Text(rangeLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        moveViewport(byOctaves: -1, viewportWidth: keyboardWidth)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: controlsHeight, height: controlsHeight)
                            .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copy.lowerOctave)

                    Button {
                        moveViewport(byOctaves: 1, viewportWidth: keyboardWidth)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .frame(width: controlsHeight, height: controlsHeight)
                            .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copy.higherOctave)

                    Button(copy.close, action: onDone)
                        .buttonStyle(.borderedProminent)
                        .tint(PiaKeysTheme.purple)
                        .frame(height: controlsHeight)
                }

                PianoKeyboardView(
                    activeNotes: viewModel.heldNoteNumbers.union(viewModel.activeSongNotes),
                    firstNote: Self.firstNote,
                    lastNote: Self.lastNote,
                    height: keyboardHeight,
                    language: copy.language,
                    naturalKeyWidth: Self.whiteKeyWidth,
                    scrollToNote: scrollTargetNote,
                    scrollRequestID: scrollRequestID,
                    scrollAnimationDuration: scrollAnimationDuration,
                    onScrollProgress: { progress in
                        if abs(progress - scrollProgress) > 0.001 {
                            scrollProgress = progress
                        }
                    },
                    onNoteOn: viewModel.beginPreviewNote,
                    onNoteOff: viewModel.endPreviewNote
                )
                .equatable()

                HStack(spacing: 7) {
                    Text(Self.firstNote.noteName)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    PianoKeyboardOverviewView(
                        activeNotes: viewModel.heldNoteNumbers.union(viewModel.activeSongNotes),
                        progress: scrollProgress,
                        viewportFraction: viewportFraction,
                        rangeLabel: rangeLabel,
                        language: copy.language,
                        onSeek: { progress in seek(to: progress, viewportWidth: keyboardWidth) },
                        onAdjust: { octaves in moveViewport(byOctaves: octaves, viewportWidth: keyboardWidth) }
                    )

                    Text(Self.lastNote.noteName)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(height: overviewHeight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, verticalInset)
        }
        .ignoresSafeArea(.container, edges: .vertical)
        .background { PiaKeysBackground() }
    }

    private func maximumFirstWhiteIndex(viewportWidth: CGFloat) -> Int {
        let visibleWhiteCount = max(1, Int(floor(viewportWidth / Self.whiteKeyWidth)))
        return max(0, whiteNotes.count - visibleWhiteCount)
    }

    private func currentFirstWhiteIndex(viewportWidth: CGFloat) -> Int {
        let maximumIndex = maximumFirstWhiteIndex(viewportWidth: viewportWidth)
        return min(max(Int((scrollProgress * CGFloat(maximumIndex)).rounded()), 0), maximumIndex)
    }

    private func visibleNoteRange(viewportWidth: CGFloat) -> ClosedRange<Int> {
        let maximumIndex = maximumFirstWhiteIndex(viewportWidth: viewportWidth)
        let firstIndex = min(max(Int((scrollProgress * CGFloat(maximumIndex)).rounded()), 0), maximumIndex)
        let visibleWhiteCount = max(1, Int(ceil(viewportWidth / Self.whiteKeyWidth)))
        let lastIndex = min(whiteNotes.count - 1, firstIndex + visibleWhiteCount - 1)
        return whiteNotes[firstIndex]...whiteNotes[lastIndex]
    }

    private func moveViewport(byOctaves octaves: Int, viewportWidth: CGFloat) {
        let maximumIndex = maximumFirstWhiteIndex(viewportWidth: viewportWidth)
        let nextIndex = min(
            max(currentFirstWhiteIndex(viewportWidth: viewportWidth) + (octaves * 7), 0),
            maximumIndex
        )
        requestScroll(toWhiteIndex: nextIndex, animationDuration: 0.22)
    }

    private func seek(to progress: CGFloat, viewportWidth: CGFloat) {
        let maximumIndex = maximumFirstWhiteIndex(viewportWidth: viewportWidth)
        let nextIndex = min(max(Int((progress * CGFloat(maximumIndex)).rounded()), 0), maximumIndex)
        requestScroll(toWhiteIndex: nextIndex, animationDuration: 0.08)
    }

    private func requestScroll(toWhiteIndex index: Int, animationDuration: Double) {
        let targetNote = whiteNotes[min(max(index, 0), whiteNotes.count - 1)]
        guard targetNote != scrollTargetNote else { return }
        scrollAnimationDuration = animationDuration
        scrollTargetNote = targetNote
        scrollRequestID &+= 1
    }
}

private struct LandscapeKeyboardPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let viewModel: MainViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> PresentationAnchorViewController {
        let controller = PresentationAnchorViewController()
        context.coordinator.presenter = controller
        controller.onReady = { [weak coordinator = context.coordinator] in
            coordinator?.updatePresentation()
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: PresentationAnchorViewController,
        context: Context
    ) {
        context.coordinator.presenter = uiViewController
        context.coordinator.isPresented = $isPresented
        context.coordinator.updatePresentation()
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isPresented: Binding<Bool>
        let viewModel: MainViewModel
        weak var presenter: UIViewController?
        weak var keyboard: LandscapeKeyboardHostingController?
        private var isPresenting = false
        private var isDismissing = false
        private var portraitResetWorkItem: DispatchWorkItem?

        init(isPresented: Binding<Bool>, viewModel: MainViewModel) {
            self.isPresented = isPresented
            self.viewModel = viewModel
        }

        func updatePresentation() {
            keyboard?.overrideUserInterfaceStyle = keyboardInterfaceStyle

            if isPresented.wrappedValue {
                guard !isDismissing else { return }
                presentKeyboardIfNeeded()
            } else if presenter?.presentedViewController is LandscapeKeyboardHostingController,
                      !isDismissing {
                dismissKeyboard()
            }
        }

        private func presentKeyboardIfNeeded() {
            guard !isPresenting,
                  !isDismissing,
                  keyboard == nil,
                  let presenter,
                  presenter.viewIfLoaded?.window != nil,
                  presenter.presentedViewController == nil else { return }

            portraitResetWorkItem?.cancel()
            portraitResetWorkItem = nil
            let scene = presenter.view.window?.windowScene

            // UIKit evaluates the app-level mask while creating this controller.
            // Set it before presenting so a second open cannot combine a
            // landscape-only controller with the previous portrait mask.
            InterfaceOrientationController.prepare(.landscape, in: scene)
            isPresenting = true
            let keyboard = LandscapeKeyboardHostingController(
                rootView: FullKeyboardView(viewModel: viewModel) { [weak self] in
                    self?.dismissKeyboard()
                }
            )
            // This controller is outside ContentView's SwiftUI environment, so
            // mirror the app-level appearance through UIKit's trait collection.
            keyboard.overrideUserInterfaceStyle = keyboardInterfaceStyle
            self.keyboard = keyboard
            keyboard.modalPresentationStyle = .fullScreen
            presenter.present(keyboard, animated: true) { [weak self, weak keyboard] in
                guard let self else { return }
                self.isPresenting = false
                keyboard?.presentationController?.delegate = self
                InterfaceOrientationController.request(
                    .landscape,
                    in: keyboard?.view.window?.windowScene ?? scene
                )
            }
        }

        private func dismissKeyboard() {
            guard !isDismissing else { return }
            guard let presenter,
                  let keyboard = self.keyboard ?? presenter.presentedViewController as? LandscapeKeyboardHostingController else {
                isPresented.wrappedValue = false
                schedulePortraitReset(in: presenter?.view.window?.windowScene)
                return
            }
            self.keyboard = keyboard
            isDismissing = true
            isPresented.wrappedValue = false
            let scene = keyboard.view.window?.windowScene ?? presenter.view.window?.windowScene
            keyboard.dismiss(animated: true) { [weak self, weak keyboard] in
                self?.finishDismissal(of: keyboard, in: scene)
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            // Full-screen keyboard dismissal is initiated by Done. Ignore a
            // late delegate callback from an older presentation so it cannot
            // mutate the binding for a newly opened keyboard.
            guard isDismissing else { return }
            isPresented.wrappedValue = false
            let scene = presenter?.view.window?.windowScene
            finishDismissal(of: keyboard, in: scene)
        }

        private func finishDismissal(
            of keyboard: LandscapeKeyboardHostingController?,
            in scene: UIWindowScene?
        ) {
            guard isDismissing else { return }
            if let keyboard, let trackedKeyboard = self.keyboard, keyboard !== trackedKeyboard {
                return
            }
            self.keyboard = nil
            isPresenting = false
            isDismissing = false
            schedulePortraitReset(in: scene)
        }

        private func schedulePortraitReset(in scene: UIWindowScene?) {
            portraitResetWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      !self.isPresented.wrappedValue,
                      !self.isPresenting,
                      !self.isDismissing else { return }
                InterfaceOrientationController.request(.portrait, in: scene)
            }
            portraitResetWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        private var keyboardInterfaceStyle: UIUserInterfaceStyle {
            switch viewModel.appearance {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
        }
    }
}

private final class PresentationAnchorViewController: UIViewController {
    var onReady: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onReady?()
    }
}

private final class LandscapeKeyboardHostingController: UIHostingController<FullKeyboardView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        InterfaceOrientationController.request(.landscape, in: view.window?.windowScene)
    }
}
