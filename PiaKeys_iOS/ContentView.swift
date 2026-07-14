import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        TabView {
            PracticeRootView(viewModel: viewModel)
                .tabItem { Label(LocalizedCopy(language: viewModel.language).practice, systemImage: "pianokeys") }

            MetronomeView(viewModel: viewModel)
                .tabItem { Label(LocalizedCopy(language: viewModel.language).metronome, systemImage: "metronome") }
        }
        .tint(PiaKeysTheme.purple)
        .preferredColorScheme(viewModel.appearance.colorScheme)
    }
}

#Preview {
    ContentView()
}
