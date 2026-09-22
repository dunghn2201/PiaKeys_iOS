import Foundation

/// Converts the app's MIDI-timed song model into a two-staff MusicXML score.
///
/// The generated score is intentionally rendered by the same Verovio pipeline
/// as imported MusicXML. This keeps clefs, rests, accidentals, durations,
/// chords, ties, bar layout, and playback highlighting consistent instead of
/// maintaining a second hand-drawn notation engine.
nonisolated enum GeneratedMusicXMLBuilder {
    private static let divisions = 480
    private static let minimumGrid = divisions / 8

    private struct Meter {
        let beats: Int
        let beatType: Int

        var measureTicks: Int { beats * divisions * 4 / beatType }
    }

    private struct DurationSpec {
        let ticks: Int
        let type: String
        let dots: Int
    }

    private struct NoteFragment {
        let note: SongNote
        let start: Int
        let duration: Int
        let continuesFromPrevious: Bool
        let continuesIntoNext: Bool
    }

    private struct VoiceLane {
        var fragments: [NoteFragment]
        var end: Int
    }

    /// Returns a UTF-8 MusicXML document for a generated practice song.
    static func data(for song: PracticeSong) -> Data {
        Data(xml(for: song).utf8)
    }

    /// Builds a piano score with treble and bass staves from millisecond MIDI
    /// timings. Timings are quantized to 32nd-note units so the result can be
    /// represented by standard MusicXML durations and rests.
    static func xml(for song: PracticeSong) -> String {
        let meter = parseMeter(song.timeSignature)
        let notes = song.notes.filter { (21...108).contains($0.noteNumber) }
        let maximumEnd = notes.map { quantizedTick(forMilliseconds: $0.startMilliseconds + $0.durationMilliseconds, tempo: song.tempo) }.max() ?? 0
        let measureCount = max(1, (maximumEnd + meter.measureTicks - 1) / meter.measureTicks)
        let tempo = max(1, song.tempo)

        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<score-partwise version=\"3.1\">",
            "  <work><work-title>\(escape(song.title))</work-title></work>",
            "  <identification><creator type=\"composer\">\(escape(song.composer))</creator></identification>",
            "  <part-list>",
            "    <score-part id=\"P1\"><part-name>Piano</part-name></score-part>",
            "  </part-list>",
            "  <part id=\"P1\">"
        ]

        for measureIndex in 0..<measureCount {
            lines.append(contentsOf: renderMeasure(
                index: measureIndex,
                meter: meter,
                tempo: tempo,
                notes: notes,
                isLastMeasure: measureIndex == measureCount - 1
            ))
        }

        lines += [
            "  </part>",
            "</score-partwise>"
        ]
        return lines.joined(separator: "\n")
    }

    private static func renderMeasure(
        index: Int,
        meter: Meter,
        tempo: Int,
        notes: [SongNote],
        isLastMeasure: Bool
    ) -> [String] {
        let measureStart = index * meter.measureTicks
        let measureEnd = measureStart + meter.measureTicks
        var lines = ["    <measure number=\"\(index + 1)\">"]

        if index == 0 {
            lines += [
                "      <attributes>",
                "        <divisions>\(divisions)</divisions>",
                "        <key><fifths>0</fifths><mode>major</mode></key>",
                "        <time><beats>\(meter.beats)</beats><beat-type>\(meter.beatType)</beat-type></time>",
                "        <staves>2</staves>",
                "        <clef number=\"1\"><sign>G</sign><line>2</line></clef>",
                "        <clef number=\"2\"><sign>F</sign><line>4</line></clef>",
                "      </attributes>",
                "      <direction placement=\"above\">",
                "        <direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>\(tempo)</per-minute></metronome></direction-type>",
                "        <sound tempo=\"\(tempo)\"/>",
                "      </direction>"
            ]
        }

        let rightHand = notes.filter { $0.hand == .right }
        let leftHand = notes.filter { $0.hand == .left }
        lines += renderStaff(
            notes: rightHand,
            staff: 1,
            measureStart: measureStart,
            measureEnd: measureEnd,
            meter: meter,
            tempo: tempo
        )
        lines += [
            "      <backup><duration>\(meter.measureTicks)</duration></backup>"
        ]
        lines += renderStaff(
            notes: leftHand,
            staff: 2,
            measureStart: measureStart,
            measureEnd: measureEnd,
            meter: meter,
            tempo: tempo
        )

        if index == 0 {
            lines.append("      <barline location=\"left\"><bar-style>regular</bar-style></barline>")
        }
        if isLastMeasure {
            lines.append("      <barline location=\"right\"><bar-style>light-heavy</bar-style></barline>")
        }
        lines.append("    </measure>")
        return lines
    }

    private static func renderStaff(
        notes: [SongNote],
        staff: Int,
        measureStart: Int,
        measureEnd: Int,
        meter: Meter,
        tempo: Int
    ) -> [String] {
        let fragments = makeFragments(
            notes: notes,
            measureStart: measureStart,
            measureEnd: measureEnd,
            tempo: tempo
        )
        let grouped = Dictionary(grouping: fragments, by: \.start)
        var lanes: [VoiceLane] = []

        // A single MusicXML voice is sequential. MIDI piano data often has a
        // sustained melody note overlapping a later note in the same hand;
        // placing both in voice 1 makes the later note appear after the
        // sustained duration and shifts the rest of the measure. Allocate
        // overlapping onset groups to additional voices while keeping notes
        // sharing an onset together as a chord.
        for start in grouped.keys.sorted() {
            let group = (grouped[start] ?? []).sorted {
                ($0.note.noteNumber, $0.note.id.uuidString) < ($1.note.noteNumber, $1.note.id.uuidString)
            }
            let groupEnd = group.map { $0.start + $0.duration }.max() ?? start
            if let laneIndex = lanes.firstIndex(where: { $0.end <= start }) {
                lanes[laneIndex].fragments.append(contentsOf: group)
                lanes[laneIndex].end = groupEnd
            } else {
                lanes.append(VoiceLane(fragments: group, end: groupEnd))
            }
        }

        guard !lanes.isEmpty else {
            return renderRests(duration: meter.measureTicks, staff: staff, voice: 1)
        }

        var lines: [String] = []

        for (laneIndex, lane) in lanes.enumerated() {
            let voice = laneIndex + 1
            if laneIndex > 0 {
                lines.append("      <backup><duration>\(meter.measureTicks)</duration></backup>")
            }
            let laneGroups = Dictionary(grouping: lane.fragments, by: \.start)
            var cursor = 0
            for start in laneGroups.keys.sorted() {
                if start > cursor {
                    lines += renderRests(duration: start - cursor, staff: staff, voice: voice)
                }
                let group = (laneGroups[start] ?? []).sorted { $0.note.noteNumber < $1.note.noteNumber }
                for (index, fragment) in group.enumerated() {
                    lines += renderNote(
                        fragment,
                        staff: staff,
                        voice: voice,
                        chord: index > 0,
                        stem: staff == 1 ? "up" : "down"
                    )
                }
                cursor = max(cursor, group.map { $0.start + $0.duration }.max() ?? cursor)
            }

            if cursor < meter.measureTicks {
                lines += renderRests(duration: meter.measureTicks - cursor, staff: staff, voice: voice)
            }
        }
        return lines
    }

    private static func makeFragments(
        notes: [SongNote],
        measureStart: Int,
        measureEnd: Int,
        tempo: Int
    ) -> [NoteFragment] {
        notes.compactMap { note in
            let start = quantizedTick(forMilliseconds: note.startMilliseconds, tempo: tempo)
            let rawEnd = note.startMilliseconds + note.durationMilliseconds
            let end = max(start + minimumGrid, quantizedTick(forMilliseconds: rawEnd, tempo: tempo))
            let fragmentStart = max(start, measureStart)
            let fragmentEnd = min(end, measureEnd)
            guard fragmentEnd > fragmentStart else { return nil }
            return NoteFragment(
                note: note,
                start: fragmentStart - measureStart,
                duration: fragmentEnd - fragmentStart,
                continuesFromPrevious: start < measureStart,
                continuesIntoNext: end > measureEnd
            )
        }
    }

    private static func renderRests(duration: Int, staff: Int, voice: Int) -> [String] {
        splitDuration(duration).map { spec in
            var lines = [
                "      <note>",
                "        <rest/>",
                "        <duration>\(spec.ticks)</duration>",
                "        <voice>\(voice)</voice>",
                "        <type>\(spec.type)</type>"
            ]
            lines += Array(repeating: "        <dot/>", count: spec.dots)
            lines += [
                "        <staff>\(staff)</staff>",
                "      </note>"
            ]
            return lines
        }.flatMap { $0 }
    }

    private static func renderNote(
        _ fragment: NoteFragment,
        staff: Int,
        voice: Int,
        chord: Bool,
        stem: String
    ) -> [String] {
        let specs = splitDuration(fragment.duration)
        return specs.enumerated().flatMap { index, spec in
            let isFirst = index == 0
            let isLast = index == specs.count - 1
            let tieStart = fragment.continuesIntoNext || !isLast
            let tieStop = fragment.continuesFromPrevious || !isFirst
            let noteID = "note-\(fragment.note.id.uuidString.replacingOccurrences(of: "-", with: ""))-\(fragment.start)-\(index)"
            let pitch = pitchParts(for: fragment.note.noteNumber)
            var lines = ["      <note xml:id=\"\(noteID)\">"]
            if chord && isFirst { lines.append("        <chord/>") }
            lines += [
                "        <pitch>",
                "          <step>\(pitch.step)</step>"
            ]
            if pitch.alter != 0 { lines.append("          <alter>\(pitch.alter)</alter>") }
            lines += [
                "          <octave>\(pitch.octave)</octave>",
                "        </pitch>",
                "        <duration>\(spec.ticks)</duration>",
                "        <voice>\(voice)</voice>",
                "        <type>\(spec.type)</type>"
            ]
            lines += Array(repeating: "        <dot/>", count: spec.dots)
            if pitch.alter != 0 { lines.append("        <accidental>sharp</accidental>") }
            lines += [
                "        <stem>\(stem)</stem>",
                "        <staff>\(staff)</staff>"
            ]
            if tieStart { lines.append("        <tie type=\"start\"/>") }
            if tieStop { lines.append("        <tie type=\"stop\"/>") }
            if tieStart || tieStop {
                lines.append("        <notations>")
                if tieStart { lines.append("          <tied type=\"start\"/>") }
                if tieStop { lines.append("          <tied type=\"stop\"/>") }
                lines.append("        </notations>")
            }
            lines.append("      </note>")
            return lines
        }
    }

    private static func splitDuration(_ ticks: Int) -> [DurationSpec] {
        let candidates = [
            DurationSpec(ticks: divisions * 6, type: "whole", dots: 1),
            DurationSpec(ticks: divisions * 4, type: "whole", dots: 0),
            DurationSpec(ticks: divisions * 3, type: "half", dots: 1),
            DurationSpec(ticks: divisions * 2, type: "half", dots: 0),
            DurationSpec(ticks: divisions * 3 / 2, type: "quarter", dots: 1),
            DurationSpec(ticks: divisions, type: "quarter", dots: 0),
            DurationSpec(ticks: divisions * 3 / 4, type: "eighth", dots: 1),
            DurationSpec(ticks: divisions / 2, type: "eighth", dots: 0),
            DurationSpec(ticks: divisions * 3 / 8, type: "16th", dots: 1),
            DurationSpec(ticks: divisions / 4, type: "16th", dots: 0),
            DurationSpec(ticks: divisions * 3 / 16, type: "32nd", dots: 1),
            DurationSpec(ticks: divisions / 8, type: "32nd", dots: 0)
        ]
        var remaining = max(minimumGrid, ticks)
        var result: [DurationSpec] = []
        while remaining > 0 {
            guard let candidate = candidates.first(where: { $0.ticks <= remaining }) else {
                result.append(candidates.last!)
                remaining -= candidates.last!.ticks
                continue
            }
            result.append(candidate)
            remaining -= candidate.ticks
        }
        return result
    }

    private static func parseMeter(_ value: String) -> Meter {
        let parts = value.split(separator: "/").compactMap { Int($0) }
        let beats = parts.first?.clamped(to: 1...32) ?? 4
        let requestedBeatType = parts.count > 1 ? parts[1] : 4
        let beatType = [1, 2, 4, 8, 16, 32].contains(requestedBeatType) ? requestedBeatType : 4
        return Meter(beats: beats, beatType: beatType)
    }

    private static func quantizedTick(forMilliseconds milliseconds: Int64, tempo: Int) -> Int {
        let quarterMilliseconds = 60_000.0 / Double(max(1, tempo))
        let raw = Double(max(0, milliseconds)) / quarterMilliseconds * Double(divisions)
        let tick = Int(raw.rounded())
        return max(0, (tick / minimumGrid) * minimumGrid + (tick % minimumGrid >= minimumGrid / 2 ? minimumGrid : 0))
    }

    private static func pitchParts(for midiNote: Int) -> (step: String, alter: Int, octave: Int) {
        let names: [(String, Int)] = [
            ("C", 0), ("C", 1), ("D", 0), ("D", 1),
            ("E", 0), ("F", 0), ("F", 1), ("G", 0),
            ("G", 1), ("A", 0), ("A", 1), ("B", 0)
        ]
        let pitch = names[midiNote.positiveModulo(12)]
        return (pitch.0, pitch.1, midiNote / 12 - 1)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
