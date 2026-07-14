import SwiftUI

struct PracticeRootView: View {
    enum Workspace: String, CaseIterable, Identifiable {
        case practice
        case setup
        var id: Self { self }
    }

    @ObservedObject var viewModel: MainViewModel
    @State private var workspace: Workspace = .practice

    private var copy: LocalizedCopy { .init(language: viewModel.language) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !viewModel.bleStatus.isConnected && viewModel.wiredSources.isEmpty && workspace == .practice {
                        quickSetupCard
                    }

                    Picker("Workspace", selection: $workspace) {
                        Text(copy.practice).tag(Workspace.practice)
                        Text(copy.setup).tag(Workspace.setup)
                    }
                    .pickerStyle(.segmented)

                    switch workspace {
                    case .practice:
                        PracticeDashboardView(viewModel: viewModel) {
                            workspace = .setup
                        }
                    case .setup:
                        SetupView(viewModel: viewModel)
                    }
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
            .navigationTitle(workspace == .practice ? copy.learnNotes : copy.pianoSetup)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    StatusCapsule(
                        text: viewModel.overallConnectionLabel,
                        connected: viewModel.bleStatus.isConnected || !viewModel.wiredSources.isEmpty
                    )
                }
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
                Button(copy.setup) { workspace = .setup }
                    .buttonStyle(.bordered)
            }
        }
    }
}
