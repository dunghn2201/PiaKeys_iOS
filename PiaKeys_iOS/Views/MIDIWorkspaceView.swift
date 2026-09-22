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
    @State private var showingFullKeyboard = false
    @State private var scoreContentHeight: CGFloat = 180
    @State private var sheetDetail: SheetDetail?

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
                    .buttonStyle(.bordered)
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
                        Text(activeEvent?.solfegeName ?? "—")
                            .font(.subheadline)
                    }
                    .foregroundStyle(PiaKeysTheme.purple)
                    .frame(width: 78, height: 78)
                    .background(PiaKeysTheme.purple.opacity(0.12), in: Circle())
                    .overlay { Circle().stroke(PiaKeysTheme.purple.opacity(0.7), lineWidth: 2) }
                }

                HStack(spacing: 8) {
                    MetricPill(title: copy.source, value: viewModel.inputSourceLabel)
                    MetricPill(title: copy.velocity, value: "\(activeEvent?.velocity ?? 0)")
                    MetricPill(title: copy.event, value: activeEvent?.type.rawValue ?? "—")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.recentNotes).font(.caption).foregroundStyle(.secondary)
                    if recentNoteEvents.isEmpty {
                        Text(copy.noNotes).font(.subheadline).foregroundStyle(.secondary)
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
                                    .background(PiaKeysTheme.paleBlue.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(PiaKeysTheme.gold.opacity(0.65)) }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
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
                                activeNotes: viewModel.activeSongNotes
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
                                contentHeight: $scoreContentHeight
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
                        Text("\(displayNote.noteName) / \(displayNote.solfegeName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PiaKeysTheme.purple)
                    }
                }

                if let chord = ChordRecognizer.recognize(combinedActiveNotes) {
                    Label(chord.symbol, systemImage: "music.note")
                        .font(.headline)
                        .foregroundStyle(PiaKeysTheme.gold)
                } else {
                    Text(copy.noChord).font(.caption).foregroundStyle(.secondary)
                }

                Button {
                    showingFullKeyboard = true
                } label: {
                    Label(copy.fullKeyboard, systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)

                Toggle(copy.fullKeyboardHint, isOn: $viewModel.showFullKeyboard)
                    .font(.subheadline)

                PianoKeyboardView(
                    activeNotes: combinedActiveNotes,
                    height: viewModel.showFullKeyboard ? 112 : 175,
                    fitToWidth: viewModel.showFullKeyboard,
                    onNoteOn: viewModel.beginPreviewNote,
                    onNoteOff: viewModel.endPreviewNote
                )
                .equatable()
            }
        }
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
                        Text(route.rawValue).tag(route)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if viewModel.songOutputRoute == .wired && !viewModel.canSendWiredMIDI {
                    unavailableOutputButton("No wired MIDI output")
                }
                if viewModel.songOutputRoute == .ble && !viewModel.canSendBLEMIDI {
                    unavailableOutputButton("Bluetooth MIDI output is not ready")
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
                                onPageCount: updatePageCount,
                                onPageChange: updatePage
                            )
                            .padding(.horizontal)
                            pageControls
                        } else {
                            ContentUnavailableView("No sheet music", systemImage: "music.note.list")
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

    var body: some View {
        GeometryReader { proxy in
            let rowHeight = max(130, (proxy.size.height - 76) / 2)
            VStack(spacing: 12) {
                HStack {
                    Text("88-key piano")
                        .font(.headline)
                    Spacer()
                    Button("Done", action: onDone)
                        .buttonStyle(.bordered)
                }

                PianoKeyboardView(
                    activeNotes: viewModel.heldNoteNumbers.union(viewModel.activeSongNotes),
                    firstNote: 21,
                    lastNote: 64,
                    height: rowHeight,
                    fitToWidth: true,
                    onNoteOn: viewModel.beginPreviewNote,
                    onNoteOff: viewModel.endPreviewNote
                )
                .equatable()
                PianoKeyboardView(
                    activeNotes: viewModel.heldNoteNumbers.union(viewModel.activeSongNotes),
                    firstNote: 65,
                    lastNote: 108,
                    height: rowHeight,
                    fitToWidth: true,
                    onNoteOn: viewModel.beginPreviewNote,
                    onNoteOff: viewModel.endPreviewNote
                )
                .equatable()
            }
            .padding()
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
