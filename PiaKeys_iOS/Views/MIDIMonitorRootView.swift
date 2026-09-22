import SwiftUI
import UniformTypeIdentifiers

struct MIDIMonitorRootView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showingSongStudio = false
    @State private var showingSetup = false
    @State private var importingSong = false
    @State private var importingScore = false

    private var copy: LocalizedCopy { .init(language: viewModel.language) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !viewModel.bleStatus.isConnected && viewModel.wiredSources.isEmpty {
                        quickSetupCard
                    }
                    MIDIWorkspaceView(
                        viewModel: viewModel,
                        layout: .monitor,
                        openSetup: { showingSetup = true },
                        openSongStudio: { showingSongStudio = true }
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background {
                LinearGradient(
                    colors: [Color(uiColor: .systemBackground), PiaKeysTheme.paleBlue.opacity(0.32), Color(uiColor: .systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle(copy.midiMonitor)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    StatusCapsule(
                        text: viewModel.overallConnectionLabel,
                        connected: viewModel.hasExternalMIDIConnection
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSetup = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(copy.setup)
                }
            }
            .sheet(isPresented: $showingSongStudio) {
                NavigationStack {
                    ScrollView {
                        MIDIWorkspaceView(
                            viewModel: viewModel,
                            layout: .songStudio,
                            openSetup: {
                                showingSongStudio = false
                                showingSetup = true
                            },
                            openSongStudio: {},
                            requestSongImport: { importingSong = true },
                            requestScoreImport: { importingScore = true }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .navigationTitle(copy.songStudio)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(copy.close) { showingSongStudio = false }
                        }
                    }
                }
                .fileImporter(
                    isPresented: $importingSong,
                    allowedContentTypes: [.midi, UTType(filenameExtension: "mid") ?? .data],
                    allowsMultipleSelection: false
                ) { result in
                    if case let .success(urls) = result, let url = urls.first {
                        viewModel.importSong(from: url)
                    }
                    if case let .failure(error) = result {
                        viewModel.showImportError(error.localizedDescription)
                    }
                }
                .fileImporter(
                    isPresented: $importingScore,
                    allowedContentTypes: [
                        UTType(filenameExtension: "musicxml") ?? .xml,
                        UTType(filenameExtension: "mxl") ?? .zip,
                        .xml
                    ],
                    allowsMultipleSelection: false
                ) { result in
                    if case let .success(urls) = result, let url = urls.first {
                        viewModel.importScore(from: url)
                    }
                    if case let .failure(error) = result {
                        viewModel.showImportError(error.localizedDescription)
                    }
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
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingSetup) {
                NavigationStack {
                    ScrollView {
                        SetupView(viewModel: viewModel)
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                    .navigationTitle(copy.setup)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(copy.close) { showingSetup = false }
                        }
                    }
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var quickSetupCard: some View {
        PiaKeysCard {
            HStack(spacing: 12) {
                Image(systemName: "pianokeys")
                    .font(.title2)
                    .foregroundStyle(PiaKeysTheme.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.pianoSetup).font(.headline)
                    Text(copy.inputSubtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(copy.setup) { showingSetup = true }
                    .buttonStyle(.bordered)
            }
        }
    }
}
