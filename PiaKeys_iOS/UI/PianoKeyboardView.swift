import SwiftUI

struct PianoKeyboardView: View {
    let activeNotes: Set<Int>
    var firstNote = 21
    var lastNote = 108
    var height: CGFloat = 170
    var fitToWidth = false
    let onNotePlayed: (Int, Int64) -> Void

    private var notes: [Int] { Array(firstNote...lastNote) }
    private var whiteNotes: [Int] { notes.filter { !$0.isBlackPianoKey } }

    var body: some View {
        GeometryReader { proxy in
            let naturalKeyWidth: CGFloat = 34
            let whiteKeyWidth = fitToWidth
                ? max(5, proxy.size.width / CGFloat(max(1, whiteNotes.count)))
                : naturalKeyWidth
            let contentWidth = whiteKeyWidth * CGFloat(whiteNotes.count)
            let showsLabels = whiteKeyWidth >= 16

            ScrollView(.horizontal) {
                keyboard(width: contentWidth, whiteKeyWidth: whiteKeyWidth, showsLabels: showsLabels)
            }
            .scrollDisabled(fitToWidth)
            .scrollIndicators(.hidden)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Piano keyboard")
    }

    private func keyboard(width: CGFloat, whiteKeyWidth: CGFloat, showsLabels: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(whiteNotes.enumerated()), id: \.element) { index, note in
                PianoKeyTouchView(
                    note: note,
                    active: activeNotes.contains(note),
                    isBlack: false,
                    showsLabel: showsLabels
                ) { duration in
                    onNotePlayed(note, duration)
                }
                .frame(width: whiteKeyWidth - 1, height: height)
                .offset(x: CGFloat(index) * whiteKeyWidth)
            }

            ForEach(notes.filter(\.isBlackPianoKey), id: \.self) { note in
                let precedingWhiteCount = notes.filter { $0 < note && !$0.isBlackPianoKey }.count
                PianoKeyTouchView(
                    note: note,
                    active: activeNotes.contains(note),
                    isBlack: true,
                    showsLabel: showsLabels
                ) { duration in
                    onNotePlayed(note, duration)
                }
                .frame(width: max(4, whiteKeyWidth * 0.62), height: height * 0.62)
                .offset(x: CGFloat(precedingWhiteCount) * whiteKeyWidth - whiteKeyWidth * 0.31)
                .zIndex(2)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .padding(.horizontal, 1)
    }
}

private struct PianoKeyTouchView: View {
    let note: Int
    let active: Bool
    let isBlack: Bool
    let showsLabel: Bool
    let onReleased: (Int64) -> Void

    @State private var pressed = false
    @State private var startedAt: ContinuousClock.Instant?

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: isBlack ? 5 : 7, style: .continuous)
                .fill(fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: isBlack ? 5 : 7, style: .continuous)
                        .stroke(borderColor, lineWidth: active ? 2.5 : 1)
                }
                .shadow(color: .black.opacity(isBlack ? 0.24 : 0.06), radius: 1, y: 1)

            if !isBlack && showsLabel {
                Text(note.noteName)
                    .font(.system(size: 10, weight: active ? .bold : .medium, design: .rounded))
                    .foregroundStyle(active ? PiaKeysTheme.purple : PiaKeysTheme.navy)
                    .padding(.vertical, 6)
                    .minimumScaleFactor(0.35)
            } else if isBlack && !active && showsLabel {
                Text(note.noteName.replacingOccurrences(of: String(note.noteName.last!), with: ""))
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.bottom, 5)
                    .minimumScaleFactor(0.25)
            }
        }
        .scaleEffect(y: pressed ? 0.97 : 1, anchor: .top)
        .animation(.snappy(duration: 0.12), value: pressed)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    startedAt = ContinuousClock().now
                }
                .onEnded { _ in
                    let duration: Int64 = startedAt.map {
                        let components = $0.duration(to: ContinuousClock().now).components
                        return Int64(components.seconds * 1_000) +
                            Int64(components.attoseconds / 1_000_000_000_000_000)
                    } ?? 180
                    pressed = false
                    startedAt = nil
                    onReleased(max(80, duration))
                }
        )
        .accessibilityLabel(note.noteName)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var fillColor: Color {
        if active { return isBlack ? PiaKeysTheme.purple : Color(red: 0.86, green: 0.80, blue: 1.0) }
        if pressed { return isBlack ? PiaKeysTheme.gold : Color(red: 1.0, green: 0.91, blue: 0.62) }
        return isBlack
            ? Color(red: 0.035, green: 0.055, blue: 0.085)
            : Color(red: 0.985, green: 0.98, blue: 0.965)
    }

    private var borderColor: Color {
        active ? PiaKeysTheme.purple : (isBlack ? Color.white.opacity(0.28) : PiaKeysTheme.navy.opacity(0.46))
    }
}
