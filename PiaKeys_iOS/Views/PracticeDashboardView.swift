import SwiftUI
import UniformTypeIdentifiers

struct PracticeDashboardView: View {
    @ObservedObject var viewModel: MainViewModel
    let openSetup: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var importingSong = false
    @State private var importingScore = false
    @State private var showingFullKeyboard = false
    @State private var scoreContentHeight: CGFloat = 180

    private var copy: LocalizedCopy { .init(language: viewModel.language) }
    private var activeEvent: MIDINoteEvent? { viewModel.activeNoteEvent }
    private var combinedActiveNotes: Set<Int> { viewModel.heldNoteNumbers.union(viewModel.activeSongNotes) }
    private var displayNote: Int? { viewModel.latestSongNoteNumber ?? activeEvent?.noteNumber }

    var body: some View {
        VStack(spacing: 14) {
            liveMonitorCard

            songPlayerCard

            if let scoreURL = viewModel.selectedSong?.scoreURL {
                scoreCard(url: scoreURL)
            } else {
                songStaffCard
            }

            keyboardCard

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
        .fileImporter(
            isPresented: $importingSong,
            allowedContentTypes: [.midi, UTType(filenameExtension: "mid") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first { viewModel.importSong(from: url) }
            if case let .failure(error) = result { viewModel.showImportError(error.localizedDescription) }
        }
        .fileImporter(
            isPresented: $importingScore,
            allowedContentTypes: [UTType(filenameExtension: "musicxml") ?? .xml, UTType(filenameExtension: "mxl") ?? .zip, .xml],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first { viewModel.importScore(from: url) }
            if case let .failure(error) = result { viewModel.showImportError(error.localizedDescription) }
        }
        .alert(
            "PiaKeys",
            isPresented: Binding(
                get: { viewModel.importMessage != nil },
                set: { if !$0 { viewModel.clearImportMessage() } }
            )
        ) {
            Button("OK") { viewModel.clearImportMessage() }
        } message: {
            Text(viewModel.importMessage ?? "")
        }
        .fullScreenCover(isPresented: $showingFullKeyboard) {
            FullKeyboardView(viewModel: viewModel)
        }
    }

    private var liveMonitorCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    SectionTitle(title: copy.liveMonitor, subtitle: copy.inputSubtitle, symbol: "waveform.path")
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
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(
                        title: copy.songStudio,
                        subtitle: viewModel.selectedSong?.title ?? copy.noNotes,
                        symbol: "play.square.stack"
                    )
                    Spacer()
                    Text(viewModel.songPlaying ? "ON" : "MIDI")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(viewModel.songPlaying ? PiaKeysTheme.gold : PiaKeysTheme.purple)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }

                ProgressView(value: viewModel.selectedSongProgress)
                    .tint(PiaKeysTheme.purple)
                HStack {
                    Text(format(milliseconds: viewModel.songPositionMilliseconds))
                    Spacer()
                    Text(format(milliseconds: viewModel.selectedSong?.durationMilliseconds ?? 0))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    MetricPill(title: "Tempo", value: "\(viewModel.selectedSong?.tempo ?? 0)")
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
            }
        }
    }

    private var songStaffCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: copy.sheetPreview, symbol: "music.quarternote.3")
                    Spacer()
                    Button(copy.importScore) { importingScore = true }
                        .font(.caption)
                }
                SongStaffPreview(
                    song: viewModel.selectedSong,
                    positionMilliseconds: viewModel.songPositionMilliseconds,
                    activeNotes: viewModel.activeSongNotes
                )
            }
        }
    }

    private func scoreCard(url: URL) -> some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: copy.sheetPreview, symbol: "music.note.list")
                    Spacer()
                    Button(copy.importScore) { importingScore = true }
                        .font(.caption)
                }
                MusicXMLScoreView(
                    url: url,
                    positionMilliseconds: viewModel.songPositionMilliseconds,
                    contentHeight: $scoreContentHeight
                )
                    .frame(height: scoreContentHeight)
                    .animation(.easeInOut(duration: 0.2), value: scoreContentHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
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
                    onNotePlayed: viewModel.previewNote
                )
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
                        importingSong = true
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

private struct FullKeyboardView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let rowHeight = max(130, (proxy.size.height - 80) / 2)
                VStack(spacing: 12) {
                    PianoKeyboardView(
                        activeNotes: viewModel.heldNoteNumbers.union(viewModel.activeSongNotes),
                        firstNote: 21,
                        lastNote: 64,
                        height: rowHeight,
                        fitToWidth: true,
                        onNotePlayed: viewModel.previewNote
                    )
                    PianoKeyboardView(
                        activeNotes: viewModel.heldNoteNumbers.union(viewModel.activeSongNotes),
                        firstNote: 65,
                        lastNote: 108,
                        height: rowHeight,
                        fitToWidth: true,
                        onNotePlayed: viewModel.previewNote
                    )
                }
                .padding()
            }
            .navigationTitle("88-key piano")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
