import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        TabView {
            MIDIMonitorRootView(viewModel: viewModel)
                .tabItem { Label(LocalizedCopy(language: viewModel.language).midiMonitor, systemImage: "pianokeys") }

            MetronomeView(viewModel: viewModel)
                .tabItem { Label(LocalizedCopy(language: viewModel.language).metronome, systemImage: "metronome") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { viewModel.suspendPlayback() }
        }
        .background { PiaKeysBackground() }
        .tint(PiaKeysTheme.purple)
        .preferredColorScheme(viewModel.appearance.colorScheme)
    }
}

#Preview {
    ContentView()
}
