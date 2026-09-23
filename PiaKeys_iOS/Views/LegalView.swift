import SwiftUI

/// Public legal and attribution links shown inside PiaKeys.
///
/// Keeping these links in the app gives App Review and users a direct path to
/// the policy and third-party notices without requiring them to discover the
/// website independently.
struct LegalView: View {
    let language: PiaKeysLanguage
    @Environment(\.dismiss) private var dismiss

    init(language: PiaKeysLanguage = .english) {
        self.language = language
    }

    private var copy: LocalizedCopy { .init(language: language) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(copy.legalPrivacyDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(copy.piaKeysLinks) {
                    Link(destination: PiaKeysLegal.privacyURL) {
                        Label(copy.privacyPolicy, systemImage: "hand.raised")
                    }
                    Link(destination: PiaKeysLegal.supportURL) {
                        Label(copy.support, systemImage: "questionmark.circle")
                    }
                    Link(destination: PiaKeysLegal.licensesURL) {
                        Label(copy.licensesSources, systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section(copy.bundledSources) {
                    Link(destination: PiaKeysLegal.pianoSamplesURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(copy.uprightPianoSamples)
                            Text(copy.freePatsLicense).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: PiaKeysLegal.verovioURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(copy.verovioRenderer)
                            Text(copy.verovioLicense).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: PiaKeysLegal.awesomeSheetMusicURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(copy.awesomeSheetMusic)
                            Text(copy.awesomeSheetMusicDescription).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(copy.midiFiles) {
                    Text(copy.midiFilesDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { PiaKeysBackground() }
            .navigationTitle(copy.licensesSources)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.close) { dismiss() }
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
