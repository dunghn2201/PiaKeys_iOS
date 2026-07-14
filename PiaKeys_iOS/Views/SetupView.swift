import SwiftUI

struct SetupView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var scanTapSequence = 0
    @State private var scanTapFeedback = false

    private var copy: LocalizedCopy { .init(language: viewModel.language) }

    var body: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 14) {
                bluetoothCard
                VStack(spacing: 14) {
                    wiredCard
                    preferencesCard
                    diagnosticsCard
                }
            }
        } else {
            VStack(spacing: 14) {
                bluetoothCard
                wiredCard
                preferencesCard
                diagnosticsCard
            }
        }
    }

    private var bluetoothCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(title: copy.bluetoothMIDI, subtitle: viewModel.bleStatus.message, symbol: "antenna.radiowaves.left.and.right")
                    Spacer()
                    StatusCapsule(text: viewModel.bleStatus.label, connected: viewModel.bleStatus.isConnected)
                }

                HStack {
                    Spacer()
                    ScanPianoButton(
                        status: viewModel.bleStatus,
                        tapFeedback: scanTapFeedback
                    ) {
                        scanTapSequence += 1
                        let currentTap = scanTapSequence
                        scanTapFeedback = true
                        Task {
                            try? await Task.sleep(for: .milliseconds(700))
                            guard currentTap == scanTapSequence else { return }
                            scanTapFeedback = false
                        }
                        if viewModel.bleStatus.isScanning {
                            viewModel.stopBLEScan()
                        } else if viewModel.bleStatus.isConnected || viewModel.bleStatus.isBusy {
                            viewModel.disconnectBLE()
                        } else {
                            viewModel.startBLEScan()
                        }
                    }
                    .sensoryFeedback(.impact(weight: .medium), trigger: scanTapSequence)
                    Spacer()
                }

                if viewModel.bleCompatibilityScanActive {
                    Label(
                        "MIDI service was not advertised. Showing named nearby BLE devices for compatibility.",
                        systemImage: "antenna.radiowaves.left.and.right.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PiaKeysTheme.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                Text("Available devices")
                    .font(.headline)
                if viewModel.bleDevices.isEmpty {
                    ContentUnavailableView(
                        "No MIDI pianos",
                        systemImage: "pianokeys.inverse",
                        description: Text("Turn on Bluetooth pairing mode, then tap Scan.")
                    )
                    .frame(minHeight: 120)
                } else {
                    ForEach(viewModel.bleDevices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: signalSymbol(device.signalStrength))
                                .foregroundStyle(PiaKeysTheme.purple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(.subheadline.weight(.semibold))
                                HStack(spacing: 6) {
                                    Text(device.signalStrength == 0 ? "Previously connected" : "\(device.signalStrength) dBm")
                                    Text(device.advertisesMIDIService ? "MIDI" : "Nearby BLE")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PiaKeysTheme.purple.opacity(0.10), in: Capsule())
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Connect") { viewModel.connectBLE(device.id) }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.bleStatus.isConnected || viewModel.bleStatus.isBusy)
                        }
                        .padding(.vertical, 4)
                        if device.id != viewModel.bleDevices.last?.id { Divider() }
                    }
                }

                if viewModel.bleStatus.isConnected {
                    Button(role: .destructive) { viewModel.disconnectBLE() } label: {
                        Label(copy.disconnect, systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var wiredCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: copy.wiredMIDI, subtitle: copy.wiredDescription, symbol: "cable.connector")
                    Spacer()
                    Button(copy.refresh) { viewModel.refreshWiredMIDI() }
                        .buttonStyle(.bordered)
                }

                if viewModel.wiredSources.isEmpty && viewModel.wiredDestinations.isEmpty {
                    Label("No CoreMIDI devices connected", systemImage: "cable.connector.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }

                ForEach(viewModel.wiredSources) { source in
                    MIDIPortRow(name: source.name, direction: "Input", symbol: "arrow.down.circle.fill")
                }
                ForEach(viewModel.wiredDestinations) { destination in
                    MIDIPortRow(name: destination.name, direction: "Output", symbol: "arrow.up.circle.fill")
                }
            }
        }
    }

    private var preferencesCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Preferences", symbol: "slider.horizontal.3")

                Toggle(copy.audioFeedback, isOn: $viewModel.audioEnabled)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(copy.appVolume)
                        Spacer()
                        Text("\(Int(viewModel.audioVolume * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.audioVolume, in: 0...1)
                }
                Button(copy.testC4) { viewModel.injectTestC4() }
                    .buttonStyle(.bordered)

                Label(
                    viewModel.pianoSampleStatus,
                    systemImage: viewModel.pianoSampleCount > 0 ? "waveform.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(viewModel.pianoSampleCount > 0 ? .green : .orange)

                Divider()
                Picker(copy.appearance, selection: $viewModel.appearance) {
                    ForEach(AppAppearance.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)

                Picker(copy.languageTitle, selection: $viewModel.language) {
                    ForEach(PiaKeysLanguage.allCases) { language in Text(language.rawValue).tag(language) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var diagnosticsCard: some View {
        PiaKeysCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.rawPackets.isEmpty {
                        Text("Raw BLE MIDI packets appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.rawPackets.prefix(8)) { packet in
                        HStack {
                            Text(packet.hex)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                            Spacer()
                            Text("\(packet.size) B")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                SectionTitle(title: copy.diagnostics, subtitle: "BLE MIDI packet log", symbol: "waveform.badge.magnifyingglass")
            }
        }
    }

    private func signalSymbol(_ rssi: Int) -> String {
        switch rssi {
        case -55...Int.max: "wifi"
        case -72 ... -56: "wifi"
        default: "wifi.exclamationmark"
        }
    }
}

private struct MIDIPortRow: View {
    let name: String
    let direction: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(PiaKeysTheme.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(direction).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Ready")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
}

private struct ScanPianoButton: View {
    let status: MIDIConnectionStatus
    let tapFeedback: Bool
    let action: () -> Void

    private var animating: Bool { status.isBusy || tapFeedback }

    private var title: String {
        switch status {
        case .preparingBluetooth: "Preparing"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .discoveringServices: "Services"
        case .enablingNotifications: "Subscribing"
        case .connected: "Connected"
        case .failed: "Scan again"
        default: "Scan piano"
        }
    }

    private var symbol: String {
        switch status {
        case .connected: "checkmark.circle.fill"
        case .discoveringServices: "point.3.connected.trianglepath.dotted"
        case .enablingNotifications: "wave.3.right.circle.fill"
        default: "antenna.radiowaves.left.and.right"
        }
    }

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { timeline in
                let phase = animating
                    ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                    : 0
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        let ringPhase = (phase + Double(index) * 0.24).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(
                                PiaKeysTheme.purple.opacity(animating ? max(0.04, 0.40 * (1 - ringPhase)) : 0.12),
                                lineWidth: animating ? 1.5 + 2.2 * (1 - ringPhase) : 1.5
                            )
                            .scaleEffect(0.60 + CGFloat(ringPhase) * 0.40)
                    }
                    Circle()
                        .fill(PiaKeysTheme.purple.opacity(animating ? 0.16 : 0.11))
                        .padding(18)
                    VStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 34, weight: .medium))
                            .rotationEffect(.degrees(animating && status == .scanning ? phase * 8 - 4 : 0))
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if animating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(PiaKeysTheme.purple)
                        }
                    }
                    .foregroundStyle(PiaKeysTheme.purple)
                }
                .frame(width: 174, height: 174)
                .contentShape(Circle())
            }
        }
        .buttonStyle(ScanPianoPressStyle())
        .accessibilityLabel(status.isConnected ? "Disconnect piano" : status.isScanning ? "Stop scan" : "Scan for piano")
        .accessibilityHint("Double tap to change the Bluetooth MIDI scan state")
    }
}

private struct ScanPianoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: configuration.isPressed)
    }
}
