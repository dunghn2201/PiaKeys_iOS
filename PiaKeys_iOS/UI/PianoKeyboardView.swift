import SwiftUI

struct PianoKeyboardView: View, Equatable {
    let activeNotes: Set<Int>
    var firstNote = 21
    var lastNote = 108
    var height: CGFloat = 170
    var fitToWidth = false
    var language: PiaKeysLanguage = .english
    var naturalKeyWidth: CGFloat = 34
    var scrollToNote: Int? = nil
    var scrollRequestID = 0
    var scrollAnimationDuration = 0.12
    var onScrollProgress: ((CGFloat) -> Void)?
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    static func == (lhs: PianoKeyboardView, rhs: PianoKeyboardView) -> Bool {
        lhs.activeNotes == rhs.activeNotes &&
            lhs.firstNote == rhs.firstNote &&
            lhs.lastNote == rhs.lastNote &&
            lhs.height == rhs.height &&
            lhs.fitToWidth == rhs.fitToWidth &&
            lhs.language == rhs.language &&
            lhs.naturalKeyWidth == rhs.naturalKeyWidth &&
            lhs.scrollToNote == rhs.scrollToNote &&
            lhs.scrollRequestID == rhs.scrollRequestID &&
            lhs.scrollAnimationDuration == rhs.scrollAnimationDuration
    }

    private var notes: [Int] { Array(firstNote...lastNote) }
    private var whiteNotes: [Int] { notes.filter { !$0.isBlackPianoKey } }

    var body: some View {
        GeometryReader { proxy in
            let whiteKeyWidth = fitToWidth
                ? max(5, proxy.size.width / CGFloat(max(1, whiteNotes.count)))
                : naturalKeyWidth
            let contentWidth = whiteKeyWidth * CGFloat(whiteNotes.count)
            let showsLabels = whiteKeyWidth >= 16

            ScrollViewReader { scrollProxy in
                let scrollView = ScrollView(.horizontal) {
                    keyboard(width: contentWidth, whiteKeyWidth: whiteKeyWidth, showsLabels: showsLabels)
                        .background {
                            GeometryReader { contentProxy in
                                Color.clear.preference(
                                    key: PianoKeyboardScrollOffsetKey.self,
                                    value: contentProxy.frame(in: .named("PianoKeyboardScroll")).minX
                                )
                            }
                        }
                }
                .coordinateSpace(name: "PianoKeyboardScroll")
                .scrollDisabled(fitToWidth)
                .scrollIndicators(.hidden)
                .onChange(of: scrollRequestID, initial: true) { _, _ in
                    guard let scrollToNote else { return }
                    let requestedNote = min(max(scrollToNote, firstNote), lastNote)
                    if scrollRequestID == 0 {
                        scrollProxy.scrollTo(requestedNote, anchor: .leading)
                    } else {
                        withAnimation(.easeOut(duration: scrollAnimationDuration)) {
                            scrollProxy.scrollTo(requestedNote, anchor: .leading)
                        }
                    }
                }

                if #available(iOS 18.0, *) {
                    scrollView.onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x
                    } action: { _, offset in
                        let maximumOffset = max(0, contentWidth - proxy.size.width)
                        let progress = maximumOffset > 0
                            ? min(max(offset / maximumOffset, 0), 1)
                            : 0
                        onScrollProgress?(progress)
                    }
                } else {
                    scrollView.onPreferenceChange(PianoKeyboardScrollOffsetKey.self) { offset in
                        let maximumOffset = max(0, contentWidth - proxy.size.width)
                        let scrollOffset = max(0, -offset)
                        let progress = maximumOffset > 0
                            ? min(max(scrollOffset / maximumOffset, 0), 1)
                            : 0
                        onScrollProgress?(progress)
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LocalizedCopy(language: language).pianoKeyboard)
    }

    private func keyboard(width: CGFloat, whiteKeyWidth: CGFloat, showsLabels: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(whiteNotes, id: \.self) { note in
                PianoKeyboardNaturalKeyView(
                    note: note,
                    accidentalNote: accidentalNote(after: note),
                    activeNotes: activeNotes,
                    height: height,
                    whiteKeyWidth: whiteKeyWidth,
                    showsLabels: showsLabels,
                    onNoteOn: onNoteOn,
                    onNoteOff: onNoteOff
                )
                .id(note)
                .zIndex(columnStackingOrder(for: note))
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .padding(.horizontal, 1)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    private func accidentalNote(after note: Int) -> Int? {
        let candidate = note + 1
        return candidate <= lastNote && candidate.isBlackPianoKey ? candidate : nil
    }

    private func columnStackingOrder(for note: Int) -> Double {
        switch note.positiveModulo(12) {
        case 0: 5 // C♯ overlays the right edge of D.
        case 2: 4 // D♯ overlays the right edge of E.
        case 5: 3 // F♯ overlays the right edge of G.
        case 7: 2 // G♯ overlays the right edge of A.
        case 9: 1 // A♯ overlays the right edge of B.
        default: 0
        }
    }
}

private struct PianoKeyboardNaturalKeyView: View {
    let note: Int
    let accidentalNote: Int?
    let activeNotes: Set<Int>
    let height: CGFloat
    let whiteKeyWidth: CGFloat
    let showsLabels: Bool
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            PianoKeyTouchView(
                note: note,
                active: activeNotes.contains(note),
                isBlack: false,
                showsLabel: showsLabels,
                onPressed: { onNoteOn(note) },
                onReleased: { onNoteOff(note) }
            )
            .frame(width: whiteKeyWidth - 1, height: height)

            if let accidentalNote {
                PianoKeyTouchView(
                    note: accidentalNote,
                    active: activeNotes.contains(accidentalNote),
                    isBlack: true,
                    showsLabel: showsLabels,
                    onPressed: { onNoteOn(accidentalNote) },
                    onReleased: { onNoteOff(accidentalNote) }
                )
                .frame(width: max(4, whiteKeyWidth * 0.62), height: height * 0.62)
                .offset(x: whiteKeyWidth * 0.69)
                .zIndex(2)
            }
        }
        .frame(width: whiteKeyWidth, height: height, alignment: .leading)
    }
}

private struct PianoKeyboardScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PianoKeyboardOverviewView: View {
    let activeNotes: Set<Int>
    let progress: CGFloat
    let viewportFraction: CGFloat
    let rangeLabel: String
    let language: PiaKeysLanguage
    let onSeek: (CGFloat) -> Void
    let onAdjust: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let selectionWidth = min(proxy.size.width, proxy.size.width * viewportFraction)
            let selectionTravel = max(0, proxy.size.width - selectionWidth)
            let selectionX = selectionTravel * min(max(progress, 0), 1)

            PianoKeyboardOverviewKeys(activeNotes: activeNotes, colorScheme: colorScheme)
                .equatable()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(PiaKeysTheme.purple.opacity(0.12))
                        .frame(width: selectionWidth)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(PiaKeysTheme.purple, lineWidth: 2)
                        }
                        .offset(x: selectionX)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onSeek(progress(at: value.location.x, width: proxy.size.width, selectionWidth: selectionWidth))
                        }
                        .onEnded { value in
                            onSeek(progress(at: value.location.x, width: proxy.size.width, selectionWidth: selectionWidth))
                        }
                )
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityLabel(LocalizedCopy(language: language).fullKeyboardOverview)
        .accessibilityValue(rangeLabel)
        .accessibilityHint(LocalizedCopy(language: language).overviewAdjustmentHint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdjust(1)
            case .decrement: onAdjust(-1)
            @unknown default: break
            }
        }
    }

    private func progress(at x: CGFloat, width: CGFloat, selectionWidth: CGFloat) -> CGFloat {
        let travel = max(0, width - selectionWidth)
        guard travel > 0 else { return 0 }
        return min(max((x - selectionWidth / 2) / travel, 0), 1)
    }
}

private struct PianoKeyboardOverviewKeys: View, Equatable {
    let activeNotes: Set<Int>
    let colorScheme: ColorScheme

    private let notes = Array(21...108)

    private var whiteNotes: [Int] { notes.filter { !$0.isBlackPianoKey } }

    static func == (lhs: PianoKeyboardOverviewKeys, rhs: PianoKeyboardOverviewKeys) -> Bool {
        lhs.activeNotes == rhs.activeNotes && lhs.colorScheme == rhs.colorScheme
    }

    var body: some View {
        Canvas { context, size in
            let whiteWidth = size.width / CGFloat(whiteNotes.count)
            let cornerSize = CGSize(width: min(2, whiteWidth * 0.14), height: 2)
            let whiteBorder = Color.black.opacity(colorScheme == .dark ? 0.18 : 0.12)
            let naturalColor = Color.white
            let accidentalColor = colorScheme == .dark
                ? Color(red: 0.075, green: 0.10, blue: 0.16)
                : Color(red: 0.035, green: 0.055, blue: 0.085)
            let activeNaturalColor = colorScheme == .dark
                ? Color(red: 0.40, green: 0.31, blue: 0.62)
                : PiaKeysTheme.purple.opacity(0.76)

            for (index, note) in whiteNotes.enumerated() {
                let rect = CGRect(
                    x: CGFloat(index) * whiteWidth,
                    y: 0,
                    width: max(1, whiteWidth - 0.5),
                    height: size.height
                )
                let path = Path(roundedRect: rect, cornerSize: cornerSize)
                let fill = activeNotes.contains(note) ? activeNaturalColor : naturalColor
                context.fill(path, with: .color(fill))
                context.stroke(path, with: .color(whiteBorder), lineWidth: 0.5)
            }

            for note in notes where note.isBlackPianoKey {
                let whiteIndex = whiteNotes.count(where: { $0 < note })
                let rect = CGRect(
                    x: CGFloat(whiteIndex) * whiteWidth - whiteWidth * 0.31,
                    y: 0,
                    width: max(1.5, whiteWidth * 0.62),
                    height: size.height * 0.62
                )
                let path = Path(roundedRect: rect, cornerSize: CGSize(width: 1.5, height: 1.5))
                let fill = activeNotes.contains(note) ? PiaKeysTheme.purple : accidentalColor
                context.fill(path, with: .color(fill))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PianoKeyTouchView: View {
    let note: Int
    let active: Bool
    let isBlack: Bool
    let showsLabel: Bool
    let onPressed: () -> Void
    let onReleased: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var pressed = false
    @State private var holdRecognized = false
    @State private var tapGeneration = 0
    @GestureState private var touchActive = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: isBlack ? 5 : 7, style: .continuous)
                .fill(fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: isBlack ? 5 : 7, style: .continuous)
                        .stroke(borderColor, lineWidth: active ? 2.5 : 1)
                }

            if !isBlack && showsLabel {
                Text(note.noteName)
                    .font(.system(size: 10, weight: active ? .bold : .medium, design: .rounded))
                    .foregroundStyle(noteLabelColor)
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
        .gesture(noteGesture)
        .onChange(of: touchActive) { _, active in
            // A parent scroll can cancel a recognized hold without ending it.
            if !active && holdRecognized {
                holdRecognized = false
                finishPress()
            }
        }
        .onDisappear {
            tapGeneration &+= 1
            holdRecognized = false
            finishPress()
        }
        .accessibilityAction { playTap() }
        .accessibilityLabel(note.noteName)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var noteGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.14, maximumDistance: 10)
            .updating($touchActive) { isPressing, state, _ in state = isPressing }
            .onChanged { recognized in
                guard recognized, !pressed else { return }
                holdRecognized = true
                beginPress()
            }
            .onEnded { _ in
                holdRecognized = false
                finishPress()
            }
            .exclusively(before: TapGesture().onEnded { playTap() })
    }

    private func beginPress() {
        guard !pressed else { return }
        pressed = true
        onPressed()
    }

    private func finishPress() {
        guard pressed else { return }
        pressed = false
        onReleased()
    }

    private func playTap() {
        if pressed { finishPress() }
        tapGeneration &+= 1
        let generation = tapGeneration
        beginPress()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(65))
            guard tapGeneration == generation else { return }
            finishPress()
        }
    }

    private var noteLabelColor: Color {
        if active { return colorScheme == .dark ? .white : PiaKeysTheme.purple }
        if isBlack { return .white.opacity(0.78) }
        return PiaKeysTheme.navy
    }

    private var fillColor: Color {
        if active {
            if isBlack { return PiaKeysTheme.purple }
            return colorScheme == .dark
                ? Color(red: 0.40, green: 0.31, blue: 0.62)
                : Color(red: 0.86, green: 0.80, blue: 1.0)
        }
        if pressed {
            if isBlack && colorScheme == .dark {
                return Color(red: 0.33, green: 0.25, blue: 0.14)
            }
            return isBlack ? PiaKeysTheme.gold : Color(red: 1.0, green: 0.91, blue: 0.62)
        }
        if isBlack {
            return colorScheme == .dark
                ? Color(red: 0.075, green: 0.10, blue: 0.16)
                : Color(red: 0.035, green: 0.055, blue: 0.085)
        }
        return .white
    }

    private var borderColor: Color {
        if active { return PiaKeysTheme.purple }
        if isBlack { return Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28) }
        return PiaKeysTheme.navy.opacity(colorScheme == .dark ? 0.24 : 0.46)
    }
}
