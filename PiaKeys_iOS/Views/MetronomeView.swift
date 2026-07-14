import SwiftUI

struct MetronomeView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var copy: LocalizedCopy { .init(language: viewModel.language) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            controlCard
                            soundCard
                        }
                        VStack(spacing: 14) {
                            timeSignatureCard
                            accentCard
                            audioCard
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        controlCard
                        timeSignatureCard
                        accentCard
                        soundCard
                        audioCard
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .background {
                LinearGradient(
                    colors: [Color(uiColor: .systemBackground), PiaKeysTheme.paleBlue.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle(copy.practiceTiming)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    StatusCapsule(text: viewModel.overallConnectionLabel, connected: viewModel.bleStatus.isConnected || !viewModel.wiredSources.isEmpty)
                }
            }
        }
    }

    private var controlCard: some View {
        PiaKeysCard {
            VStack(spacing: 18) {
                SectionTitle(title: copy.metronome, symbol: "metronome")
                    .frame(maxWidth: .infinity, alignment: .leading)
                PendulumView(
                    tempo: viewModel.tempo,
                    running: viewModel.metronomeRunning,
                    beat: viewModel.metronomeBeat,
                    beatCount: Int(viewModel.timeSignature.split(separator: "/").first ?? "4") ?? 4,
                    visualPulse: viewModel.visualPulse
                )
                .frame(height: 300)

                HStack {
                    Button { viewModel.tempo -= 1 } label: {
                        Image(systemName: "minus").frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.tempo) },
                            set: { viewModel.tempo = Int($0.rounded()) }
                        ),
                        in: 40...220,
                        step: 1
                    )
                    .tint(PiaKeysTheme.gold)
                    Button { viewModel.tempo += 1 } label: {
                        Image(systemName: "plus").frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    viewModel.metronomeRunning.toggle()
                } label: {
                    Label(viewModel.metronomeRunning ? copy.stop : copy.start, systemImage: viewModel.metronomeRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PiaKeysTheme.navy)

                HStack(spacing: 8) {
                    tempoPreset("Largo", 52, range: 40...66)
                    tempoPreset("Adagio", 72, range: 67...82)
                    tempoPreset("Andante", 92, range: 83...108)
                }
            }
        }
    }

    private var timeSignatureCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: copy.timeSignature, symbol: "music.note.list")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(["2/4", "4/4", "3/4", "6/8", "9/8", "12/8"], id: \.self) { signature in
                        Button(signature) { viewModel.timeSignature = signature }
                            .buttonStyle(.bordered)
                            .tint(viewModel.timeSignature == signature ? PiaKeysTheme.gold : .secondary)
                    }
                }
            }
        }
    }

    private var accentCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: copy.accentPattern, symbol: "waveform")
                Toggle(copy.firstBeatAccent, isOn: $viewModel.firstBeatAccent)
                Toggle(copy.visualPulse, isOn: $viewModel.visualPulse)
            }
        }
    }

    private var soundCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: copy.soundProfile, symbol: "speaker.wave.2")
                Picker(copy.soundProfile, selection: $viewModel.soundProfile) {
                    Text("Woodblock").tag("Woodblock")
                    Text("Digital").tag("Digital")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var audioCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(copy.audioFeedback, isOn: $viewModel.audioEnabled)
                VStack(alignment: .leading) {
                    Text(copy.appVolume).font(.subheadline)
                    Slider(value: $viewModel.audioVolume, in: 0...1)
                }
            }
        }
    }

    private func tempoPreset(_ label: String, _ tempo: Int, range: ClosedRange<Int>) -> some View {
        Button(label) { viewModel.tempo = tempo }
            .buttonStyle(.bordered)
            .tint(range.contains(viewModel.tempo) ? PiaKeysTheme.purple : .secondary)
            .frame(maxWidth: .infinity)
    }
}

private struct PendulumView: View {
    let tempo: Int
    let running: Bool
    let beat: Int
    let beatCount: Int
    let visualPulse: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !running)) { timeline in
            let interval = 60 / Double(max(1, tempo))
            let phase = running
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: interval * 2) / (interval * 2)
                : 0.25
            let angle = sin(phase * 2 * .pi) * 22

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.12)
                let length = size.height * 0.34
                let radians = angle * .pi / 180
                let bob = CGPoint(
                    x: center.x + sin(radians) * length,
                    y: center.y + cos(radians) * length
                )
                var line = Path()
                line.move(to: center)
                line.addLine(to: bob)
                context.stroke(line, with: .color(PiaKeysTheme.navy.opacity(0.82)), lineWidth: 4)
                context.fill(Path(ellipseIn: CGRect(x: bob.x - 12, y: bob.y - 12, width: 24, height: 24)), with: .color(PiaKeysTheme.gold))

                let displayedBeatCount = max(1, beatCount)
                for index in 0..<displayedBeatCount {
                    let progress = displayedBeatCount == 1
                        ? 0.5
                        : 0.18 + Double(index) * 0.64 / Double(displayedBeatCount - 1)
                    let x = size.width * progress
                    let active = visualPulse && running && index == beat % displayedBeatCount
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - (active ? 6 : 3), y: size.height * 0.27, width: active ? 12 : 6, height: active ? 12 : 6)),
                        with: .color(active ? PiaKeysTheme.gold : Color.secondary.opacity(0.25))
                    )
                }
            }
            .overlay {
                VStack(spacing: 0) {
                    Text("\(tempo)")
                        .font(.system(size: 64, weight: .medium, design: .rounded))
                        .foregroundStyle(PiaKeysTheme.gold)
                        .monospacedDigit()
                    Text("BPM").font(.caption.weight(.semibold))
                }
                .padding(.top, 70)
            }
            .background(
                RadialGradient(
                    colors: [PiaKeysTheme.gold.opacity(running ? 0.24 : 0.10), PiaKeysTheme.paleBlue.opacity(0.58)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 240
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }
}
