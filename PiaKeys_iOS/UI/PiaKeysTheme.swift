import SwiftUI

enum PiaKeysTheme {
    static let gold = Color(red: 0.96, green: 0.69, blue: 0.08)
    static let purple = Color(red: 0.52, green: 0.32, blue: 1.0)
    static let navy = Color(red: 0.04, green: 0.11, blue: 0.20)
    static let paleBlue = Color(red: 0.91, green: 0.94, blue: 0.98)
    static let darkInsetSurface = Color(red: 0.10, green: 0.14, blue: 0.25)
}

/// Displays the user-provided light or dark musical background for the app.
///
/// The asset catalog contains luminosity variants under one image name, so
/// SwiftUI selects the matching artwork for `.system`, `.light`, and `.dark`
/// appearance settings without duplicating theme logic in each screen.
struct PiaKeysBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image("PiaKeysBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
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
            // An opaque dynamic color keeps the card appearance while
            // avoiding a live blur pass for every card during scrolling.
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .background(Color(uiColor: .systemBackground), in: Capsule())
        .overlay { Capsule().stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 0.8) }
        .accessibilityElement(children: .combine)
    }
}

struct MetricPill: View {
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            colorScheme == .dark
                ? PiaKeysTheme.darkInsetSurface
                : PiaKeysTheme.paleBlue.opacity(0.52),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 0.8)
        }
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
