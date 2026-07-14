import SwiftUI

enum PiaKeysTheme {
    static let gold = Color(red: 0.96, green: 0.69, blue: 0.08)
    static let purple = Color(red: 0.52, green: 0.32, blue: 1.0)
    static let navy = Color(red: 0.04, green: 0.11, blue: 0.20)
    static let paleBlue = Color(red: 0.91, green: 0.94, blue: 0.98)
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct PiaKeysCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 0.8)
            }
    }
}

struct StatusCapsule: View {
    let text: String
    let connected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(connected ? Color.green : PiaKeysTheme.purple)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(connected ? .green : PiaKeysTheme.purple)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 0.8) }
        .accessibilityElement(children: .combine)
    }
}

struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PiaKeysTheme.paleBlue.opacity(0.52), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PiaKeysTheme.purple)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
