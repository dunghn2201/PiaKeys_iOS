import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        TabView {
            PracticeRootView(viewModel: viewModel)
                .tabItem { Label(LocalizedCopy(language: viewModel.language).practice, systemImage: "pianokeys") }

            MetronomeView(viewModel: viewModel)
                .tabItem { Label(LocalizedCopy(language: viewModel.language).metronome, systemImage: "metronome") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { viewModel.suspendPlayback() }
        }
        .tint(PiaKeysTheme.purple)
        .preferredColorScheme(viewModel.appearance.colorScheme)
    }
}

#Preview {
    ContentView()
}
