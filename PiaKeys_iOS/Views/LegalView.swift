import SwiftUI

/// Public legal and attribution links shown inside PiaKeys.
///
/// Keeping these links in the app gives App Review and users a direct path to
/// the policy and third-party notices without requiring them to discover the
/// website independently.
struct LegalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("PiaKeys processes MIDI input, audio playback, imported songs, and MusicXML scores on this device. The current build has no account, advertising, analytics, or developer-hosted upload.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("PiaKeys links") {
                    Link(destination: PiaKeysLegal.privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: PiaKeysLegal.supportURL) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    Link(destination: PiaKeysLegal.licensesURL) {
                        Label("Licenses & sources", systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section("Bundled third-party sources") {
                    Link(destination: PiaKeysLegal.pianoSamplesURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Upright Piano KW samples")
                            Text("FreePats · CC0 1.0").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: PiaKeysLegal.verovioURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Verovio score renderer")
                            Text("LGPL · see upstream COPYING and COPYING.LESSER").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: PiaKeysLegal.awesomeSheetMusicURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("awesome-sheet-music")
                            Text("Curated directory; not a blanket license for linked scores").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("MIDI files") {
                    Text("The built-in PiaKeys Waltz Study is generated in-app. PiaKeys does not bundle a third-party MIDI catalog. When importing a .mid or .midi file, use only material you are allowed to use and share.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Legal & sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Stable URLs for the public PiaKeys legal and attribution site.
enum PiaKeysLegal {
    private static let baseURL = URL(string: "https://piakeys-piano-midi.dunghn292024.chatgpt.site")!

    static let privacyURL = baseURL.appendingPathComponent("privacy.html")
    static let supportURL = baseURL.appendingPathComponent("support.html")
    static let licensesURL = baseURL.appendingPathComponent("licenses.html")
    static let pianoSamplesURL = URL(string: "https://github.com/freepats/upright-piano-KW")!
    static let verovioURL = URL(string: "https://github.com/rism-digital/verovio")!
    static let awesomeSheetMusicURL = URL(string: "https://github.com/ad-si/awesome-sheet-music")!
}
