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

/// Shows MIDI notes descending toward a compact keyboard at the playback line.
///
/// The vertical position is derived directly from musical milliseconds, so a
/// note reaches the keyboard exactly at its scheduled start time and its bar
/// length remains proportional to the note duration. A single Canvas keeps the
/// view lightweight when a song contains many simultaneous notes.
struct PianoRollView: View {
    let notes: [SongNote]
    let positionMilliseconds: Int64
    let activeNotes: Set<Int>
    let tempo: Int
    let timeSignature: String
    let language: PiaKeysLanguage
    var height: CGFloat = 350

    @Environment(\.colorScheme) private var colorScheme

    private let lookAheadMilliseconds: Int64 = 4_000
    private let lookBehindMilliseconds: Int64 = 180
    private let activeTimingToleranceMilliseconds: Int64 = 40

    private var noteRange: ClosedRange<Int> {
        guard let minimum = notes.map(\.noteNumber).min(),
              let maximum = notes.map(\.noteNumber).max() else {
            return 36...84
        }

        // Keep the visible keyboard readable for ordinary songs while falling
        // back to the full piano when an imported song spans widely. The
        // padding is intentionally measured in semitones so the roll stays
        // compact instead of adding unused octaves around the melody.
        let lower = max(21, minimum - 4)
        let upper = min(108, maximum + 4)
        if upper - lower > 60 { return 21...108 }
        return lower...min(108, max(lower + 24, upper))
    }

    private var beatsPerBar: Int {
        let numerator = timeSignature.split(separator: "/").first.flatMap { Int($0) } ?? 4
        return max(1, numerator)
    }

    private var visibleNotes: [SongNote] {
        let lowerBound = max(0, positionMilliseconds - lookBehindMilliseconds)
        let upperBound = positionMilliseconds + lookAheadMilliseconds
        return notes.filter { note in
            let end = note.startMilliseconds + max(1, note.durationMilliseconds)
            return end >= lowerBound && note.startMilliseconds <= upperBound
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let keyboardHeight = min(88, max(72, proxy.size.height * 0.24))
            let rollHeight = max(1, proxy.size.height - keyboardHeight)
            let range = noteRange

            VStack(spacing: 0) {
                Canvas { context, size in
                    drawRoll(
                        context: &context,
                        size: size,
                        range: range,
                        notes: visibleNotes,
                        positionMilliseconds: positionMilliseconds
                    )
                }
                .frame(height: rollHeight)

                PianoKeyboardView(
                    activeNotes: activeNotes,
                    firstNote: range.lowerBound,
                    lastNote: range.upperBound,
                    height: keyboardHeight,
                    fitToWidth: true,
                    language: language,
                    onNoteOn: { _ in },
                    onNoteOff: { _ in }
                )
                .frame(height: keyboardHeight)
            }
        }
        .frame(height: height)
        .background(PiaKeysTheme.navy)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.20), lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LocalizedCopy(language: language).fallingNotes)
        .accessibilityValue(accessibilityPosition)
    }

    private var accessibilityPosition: String {
        let seconds = max(0, positionMilliseconds) / 1_000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func drawRoll(
        context: inout GraphicsContext,
        size: CGSize,
        range: ClosedRange<Int>,
        notes: [SongNote],
        positionMilliseconds: Int64
    ) {
        let bounds = CGRect(origin: .zero, size: size)
        let whiteNotes = Array(range).filter { !$0.isBlackPianoKey }
        let whiteWidth = size.width / CGFloat(max(1, whiteNotes.count))
        let hitLineY = size.height - 2
        let pixelsPerMillisecond = max(0.001, (size.height - 14) / CGFloat(lookAheadMilliseconds))

        context.fill(Path(bounds), with: .color(PiaKeysTheme.navy))
        drawGrid(
            context: &context,
            size: size,
            whiteNotes: whiteNotes,
            whiteWidth: whiteWidth,
            hitLineY: hitLineY,
            pixelsPerMillisecond: pixelsPerMillisecond,
            positionMilliseconds: positionMilliseconds
        )

        for note in notes {
            guard let noteRect = noteRect(
                for: note,
                range: range,
                whiteNotes: whiteNotes,
                whiteWidth: whiteWidth,
                hitLineY: hitLineY,
                pixelsPerMillisecond: pixelsPerMillisecond,
                positionMilliseconds: positionMilliseconds,
                size: size
            ) else { continue }
            drawNote(
                context: &context,
                note: note,
                rect: noteRect,
                active: isActive(note: note, at: positionMilliseconds)
            )
        }

        var hitPath = Path()
        hitPath.move(to: CGPoint(x: 0, y: hitLineY))
        hitPath.addLine(to: CGPoint(x: size.width, y: hitLineY))
        context.stroke(hitPath, with: .color(Color.white.opacity(0.70)), lineWidth: 1.4)
    }

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize,
        whiteNotes: [Int],
        whiteWidth: CGFloat,
        hitLineY: CGFloat,
        pixelsPerMillisecond: CGFloat,
        positionMilliseconds: Int64
    ) {
        for index in 0...whiteNotes.count {
            let x = CGFloat(index) * whiteWidth
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(
                path,
                with: .color(Color.white.opacity(index % 7 == 0 ? 0.16 : 0.07)),
                lineWidth: index % 7 == 0 ? 1 : 0.6
            )
        }

        let beatMilliseconds = Int64(max(1, 60_000 / max(1, tempo)))
        let firstBeat = max(0, positionMilliseconds - lookBehindMilliseconds) / beatMilliseconds
        let lastBeat = (positionMilliseconds + lookAheadMilliseconds) / beatMilliseconds + 1
        for beatIndex in firstBeat...lastBeat {
            let beatTime = beatIndex * beatMilliseconds
            let y = hitLineY - CGFloat(beatTime - positionMilliseconds) * pixelsPerMillisecond
            guard y >= 0, y <= size.height else { continue }

            let isBar = beatIndex % Int64(beatsPerBar) == 0
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                path,
                with: .color(Color.white.opacity(isBar ? 0.14 : 0.055)),
                lineWidth: isBar ? 1 : 0.6
            )
            if isBar {
                context.draw(
                    Text("\(beatIndex / Int64(beatsPerBar) + 1)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.52)),
                    at: CGPoint(x: 14, y: max(10, y - 8))
                )
            }
        }
    }

    private func noteRect(
        for note: SongNote,
        range: ClosedRange<Int>,
        whiteNotes: [Int],
        whiteWidth: CGFloat,
        hitLineY: CGFloat,
        pixelsPerMillisecond: CGFloat,
        positionMilliseconds: Int64,
        size: CGSize
    ) -> CGRect? {
        guard let keyRect = keyRect(
            for: note.noteNumber,
            range: range,
            whiteNotes: whiteNotes,
            whiteWidth: whiteWidth
        ) else { return nil }

        let endMilliseconds = note.startMilliseconds + max(1, note.durationMilliseconds)
        let top = hitLineY - CGFloat(endMilliseconds - positionMilliseconds) * pixelsPerMillisecond
        let bottom = hitLineY - CGFloat(note.startMilliseconds - positionMilliseconds) * pixelsPerMillisecond
        guard bottom > 0, top < size.height else { return nil }

        let clippedTop = max(1, top)
        let clippedBottom = min(hitLineY - 1, bottom)
        guard clippedBottom > clippedTop else { return nil }
        return CGRect(
            x: keyRect.minX,
            y: clippedTop,
            width: keyRect.width,
            height: max(4, clippedBottom - clippedTop)
        )
    }

    /// Highlights only the note currently crossing or sounding at the
    /// playhead. Matching by pitch alone would also brighten future repeated
    /// notes that share the same MIDI note number.
    private func isActive(note: SongNote, at positionMilliseconds: Int64) -> Bool {
        guard activeNotes.contains(note.noteNumber) else { return false }

        let startMilliseconds = note.startMilliseconds
        let endMilliseconds = note.startMilliseconds + max(1, note.durationMilliseconds)
        let tolerance = activeTimingToleranceMilliseconds
        return startMilliseconds <= positionMilliseconds + tolerance
            && endMilliseconds >= positionMilliseconds - tolerance
    }

    private func keyRect(
        for note: Int,
        range: ClosedRange<Int>,
        whiteNotes: [Int],
        whiteWidth: CGFloat
    ) -> CGRect? {
        guard range.contains(note), !whiteNotes.isEmpty else { return nil }

        if note.isBlackPianoKey {
            guard let precedingNote = whiteNotes.last(where: { $0 < note }),
                  let index = whiteNotes.firstIndex(of: precedingNote) else { return nil }
            return CGRect(
                x: CGFloat(index + 1) * whiteWidth - whiteWidth * 0.32,
                y: 0,
                width: max(5, whiteWidth * 0.64),
                height: 1
            )
        }

        guard let index = whiteNotes.firstIndex(of: note) else { return nil }
        return CGRect(
            x: CGFloat(index) * whiteWidth + whiteWidth * 0.10,
            y: 0,
            width: max(5, whiteWidth * 0.80),
            height: 1
        )
    }

    private func drawNote(
        context: inout GraphicsContext,
        note: SongNote,
        rect: CGRect,
        active: Bool
    ) {
        let color = note.hand == .left
            ? Color(red: 0.18, green: 0.58, blue: 1.0)
            : PiaKeysTheme.purple
        let radius = min(7, rect.width * 0.28)
        let glowRect = rect.insetBy(dx: -2.5, dy: -1.5)
        let glowPath = Path(roundedRect: glowRect, cornerRadius: radius + 2)
        context.fill(glowPath, with: .color(color.opacity(active ? 0.36 : 0.15)))

        let notePath = Path(roundedRect: rect, cornerRadius: radius)
        context.fill(notePath, with: .color(color.opacity(active ? 0.98 : 0.76)))
        context.stroke(
            notePath,
            with: .color(Color.white.opacity(active ? 0.92 : 0.62)),
            lineWidth: active ? 1.4 : 0.9
        )
    }
}
