import SwiftUI

struct StaffPreview: View {
    let notes: [MIDINoteEvent]
    let activeNote: Int?

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 40
            let gap: CGFloat = 10
            let trebleBottom = size.height * 0.45
            let bassBottom = size.height * 0.82

            drawStaff(context: &context, from: inset, to: size.width - 10, bottom: trebleBottom, gap: gap)
            drawStaff(context: &context, from: inset, to: size.width - 10, bottom: bassBottom, gap: gap)
            context.draw(Text("𝄞").font(.system(size: 42)).foregroundStyle(.secondary), at: CGPoint(x: 20, y: trebleBottom - 20))
            context.draw(Text("𝄢").font(.system(size: 34)).foregroundStyle(.secondary), at: CGPoint(x: 20, y: bassBottom - 18))

            let displayNotes = Array(notes.filter { $0.type == .noteOn }.prefix(5).reversed())
            for (index, event) in displayNotes.enumerated() {
                let x = inset + 50 + CGFloat(index) * max(35, (size.width - inset - 75) / 5)
                drawNote(
                    context: &context,
                    note: event.noteNumber,
                    x: x,
                    trebleBottom: trebleBottom,
                    bassBottom: bassBottom,
                    gap: gap,
                    active: event.noteNumber == activeNote
                )
            }
        }
        .frame(height: 190)
        .background(PiaKeysTheme.paleBlue.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Grand staff preview")
    }

    private func drawStaff(
        context: inout GraphicsContext,
        from startX: CGFloat,
        to endX: CGFloat,
        bottom: CGFloat,
        gap: CGFloat
    ) {
        for line in 0..<5 {
            let y = bottom - CGFloat(line) * gap
            var path = Path()
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
            context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
        }
    }

    private func drawNote(
        context: inout GraphicsContext,
        note: Int,
        x: CGFloat,
        trebleBottom: CGFloat,
        bassBottom: CGFloat,
        gap: CGFloat,
        active: Bool
    ) {
        let usesTreble = note >= 60
        let referenceNote = usesTreble ? 64 : 43
        let referenceY = usesTreble ? trebleBottom : bassBottom
        let step = diatonicStep(note) - diatonicStep(referenceNote)
        let y = referenceY - CGFloat(step) * gap / 2
        let color = active ? PiaKeysTheme.gold : PiaKeysTheme.purple
        let ellipse = Path(ellipseIn: CGRect(x: x - 8, y: y - 5, width: 16, height: 10))
        context.fill(ellipse, with: .color(color))
        var stem = Path()
        stem.move(to: CGPoint(x: x + 7, y: y))
        stem.addLine(to: CGPoint(x: x + 7, y: y - 31))
        context.stroke(stem, with: .color(color), lineWidth: 2)

        if note.isBlackPianoKey {
            context.draw(Text("♯").font(.caption).foregroundStyle(color), at: CGPoint(x: x - 13, y: y))
        }
    }

    private func diatonicStep(_ note: Int) -> Int {
        let octave = note / 12 - 1
        let stepInOctave: Int
        switch note.positiveModulo(12) {
        case 0, 1: stepInOctave = 0
        case 2, 3: stepInOctave = 1
        case 4: stepInOctave = 2
        case 5, 6: stepInOctave = 3
        case 7, 8: stepInOctave = 4
        case 9, 10: stepInOctave = 5
        default: stepInOctave = 6
        }
        return octave * 7 + stepInOctave
    }
}

struct SongStaffPreview: View {
    let song: PracticeSong?
    let positionMilliseconds: Int64
    let activeNotes: Set<Int>

    var visibleEvents: [MIDINoteEvent] {
        guard let song else { return [] }
        return song.notes
            .filter { abs($0.startMilliseconds - positionMilliseconds) < 2_500 }
            .prefix(8)
            .map {
                MIDINoteEvent(
                    noteNumber: $0.noteNumber,
                    velocity: $0.velocity,
                    type: .noteOn,
                    source: .preview
                )
            }
    }

    var body: some View {
        StaffPreview(notes: visibleEvents, activeNote: activeNotes.sorted().last)
    }
}
