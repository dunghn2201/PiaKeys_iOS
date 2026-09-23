import CoreAudioKit
import SwiftUI

struct SetupView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @State private var scanTapSequence = 0
    @State private var scanTapFeedback = false
    @State private var showBluetoothMIDIPicker = false
    @State private var showLegal = false
    @State private var showFeedbackUnavailable = false

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
                    SectionTitle(
                        title: copy.bluetoothMIDI,
                        subtitle: copy.statusMessage(viewModel.bleStatus),
                        symbol: "antenna.radiowaves.left.and.right"
                    )
                    Spacer()
                    StatusCapsule(text: copy.statusLabel(viewModel.bleStatus), connected: viewModel.bleStatus.isConnected)
                }

                HStack {
                    Spacer()
                    ScanPianoButton(
                        status: viewModel.bleStatus,
                        tapFeedback: scanTapFeedback,
                        copy: copy
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

                Button {
                    showBluetoothMIDIPicker = true
                } label: {
                    Label(copy.openBluetoothMIDI, systemImage: "pianokeys")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if viewModel.bleStatus.isUnavailable {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.statusMessage(viewModel.bleStatus))
                                .font(.subheadline.weight(.semibold))
                            Text(copy.bluetoothHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bluetooth.slash")
                            .foregroundStyle(PiaKeysTheme.purple)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PiaKeysTheme.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                if viewModel.bleCompatibilityScanActive {
                    Label(
                        copy.compatibilityScanMessage,
                        systemImage: "antenna.radiowaves.left.and.right.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PiaKeysTheme.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                Text(copy.availableDevices)
                    .font(.headline)
                if viewModel.bleDevices.isEmpty {
                    ContentUnavailableView(
                        copy.noMIDIPianos,
                        systemImage: "pianokeys.inverse",
                        description: Text(copy.bluetoothPairingHint)
                    )
                    .frame(minHeight: 120)
                } else {
                    ForEach(viewModel.bleDevices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: signalSymbol(device.signalStrength))
                                .foregroundStyle(PiaKeysTheme.purple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(copy.deviceName(device.name)).font(.subheadline.weight(.semibold))
                                HStack(spacing: 6) {
                                    Text(device.signalStrength == 0 ? copy.previouslyConnected : "\(device.signalStrength) dBm")
                                    Text(device.advertisesMIDIService ? copy.midiReady : copy.nearbyBLE)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PiaKeysTheme.purple.opacity(0.10), in: Capsule())
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(copy.connect) { viewModel.connectBLE(device.id) }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.bleStatus.isConnected || viewModel.bleStatus.isConnectionInProgress)
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
        .sheet(isPresented: $showBluetoothMIDIPicker, onDismiss: viewModel.refreshWiredMIDI) {
            BluetoothMIDIPickerView()
        }
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

                if viewModel.visibleWiredSources.isEmpty && viewModel.visibleWiredDestinations.isEmpty {
                    Label(copy.noCoreMIDIDevices, systemImage: "cable.connector.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }

                ForEach(viewModel.visibleWiredSources) { source in
                    MIDIPortRow(name: copy.deviceName(source.name), direction: copy.input, status: copy.ready, symbol: "arrow.down.circle.fill")
                }
                ForEach(viewModel.visibleWiredDestinations) { destination in
                    MIDIPortRow(name: copy.deviceName(destination.name), direction: copy.output, status: copy.ready, symbol: "arrow.up.circle.fill")
                }
            }
        }
    }

    private var preferencesCard: some View {
        PiaKeysCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: copy.preferences, symbol: "slider.horizontal.3")

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
                    viewModel.pianoSampleCount > 0
                        ? copy.pianoSamplesReady(viewModel.pianoSampleCount)
                        : copy.pianoSamplesUnavailable,
                    systemImage: viewModel.pianoSampleCount > 0 ? "waveform.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(viewModel.pianoSampleCount > 0 ? .green : .orange)

                Divider()
                Picker(copy.appearance, selection: $viewModel.appearance) {
                    ForEach(AppAppearance.allCases) { mode in Text(copy.appearanceName(mode)).tag(mode) }
                }
                .pickerStyle(.segmented)

                Picker(copy.languageTitle, selection: $viewModel.language) {
                    ForEach(PiaKeysLanguage.allCases) { language in Text(language.rawValue).tag(language) }
                }
                .pickerStyle(.menu)

                Divider()
                Button {
                    showLegal = true
                } label: {
                    Label(copy.privacyLicenses, systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button(action: openFeedback) {
                    Label(copy.feedback, systemImage: "envelope")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Text("\(copy.appVersion): \(appVersion)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .sheet(isPresented: $showLegal) {
            LegalView(language: viewModel.language)
        }
        .alert(copy.feedbackUnavailable, isPresented: $showFeedbackUnavailable) {
            Button(copy.ok, role: .cancel) {}
        } message: {
            Text(copy.feedbackUnavailableMessage)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func openFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "dunghn2201@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: copy.feedbackSubject),
            URLQueryItem(name: "body", value: "\n\n\(copy.feedbackBodyAppVersion): \(appVersion)")
        ]

        guard let url = components.url else {
            showFeedbackUnavailable = true
            return
        }
        openURL(url) { accepted in
            if !accepted { showFeedbackUnavailable = true }
        }
    }

    private var diagnosticsCard: some View {
        PiaKeysCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.rawPackets.isEmpty {
                        Text(copy.rawMIDIPacketsHint)
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
                SectionTitle(title: copy.diagnostics, subtitle: copy.coreMIDIPacketLog, symbol: "waveform.badge.magnifyingglass")
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

private struct BluetoothMIDIPickerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ uiViewController: CABTMIDICentralViewController, context: Context) {}
}

private struct MIDIPortRow: View {
    let name: String
    let direction: String
    let status: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(PiaKeysTheme.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(direction).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
}

private struct ScanPianoButton: View {
    let status: MIDIConnectionStatus
    let tapFeedback: Bool
    let copy: LocalizedCopy
    let action: () -> Void

    private var animating: Bool { status.isBusy || tapFeedback }

    private var title: String {
        switch status {
        case .preparingBluetooth: copy.statusLabel(status)
        case .scanning: copy.statusLabel(status)
        case .connecting: copy.statusLabel(status)
        case .discoveringServices: copy.statusLabel(status)
        case .enablingNotifications: copy.statusLabel(status)
        case .connected: value("Connected", "Đã kết nối", "接続済み")
        case .failed: value("Scan again", "Quét lại", "再検索")
        default: copy.scanPiano
        }
    }

    private func value(_ english: String, _ vietnamese: String, _ japanese: String) -> String {
        switch copy.language {
        case .english: english
        case .vietnamese: vietnamese
        case .japanese: japanese
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
        .accessibilityLabel(status.isConnected ? copy.disconnect : status.isScanning ? copy.stopScan : copy.scanPiano)
        .accessibilityHint(value("Double tap to change the Bluetooth MIDI scan state", "Chạm hai lần để đổi trạng thái quét Bluetooth MIDI", "ダブルタップしてBluetooth MIDIの検索状態を変更します"))
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
