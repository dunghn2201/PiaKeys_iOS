import Foundation

@main
struct AudioSchedulingRegression {
    static func main() {
        let queue = DispatchQueue(label: "PiaKeysTests.audio", qos: .userInteractive)
        let scheduler = SongAudioScheduler(queue: queue)
        let notes: [SongNote] = (0..<4).map {
            SongNote(startMilliseconds: Int64($0 * 60), durationMilliseconds: 500,
                     noteNumber: 60 + $0, velocity: 90, hand: .right)
        }
        var attacks: [(Int, Double)] = []
        let origin = DispatchTime.now().uptimeNanoseconds
        queue.sync {
            scheduler.start(notes: notes, positionMilliseconds: 0, speed: 1, loop: nil,
                            startedAtNanoseconds: origin, onNote: { note, _ in
                attacks.append((note.noteNumber, Double(DispatchTime.now().uptimeNanoseconds - origin) / 1_000_000))
            }, onLoop: {})
        }
        // Deliberately stall the main thread longer than the entire note sequence.
        // The real audio scheduler must still dispatch every attack on time.
        Thread.sleep(forTimeInterval: 0.35)
        queue.sync {
            precondition(attacks.map(\.0) == [60, 61, 62, 63], "UI stall must not drop notes")
            let worstLateness = attacks.enumerated().map { $0.element.1 - Double($0.offset * 60) }.max()!
            precondition(worstLateness < 50, "Audio scheduling must not wait for the blocked main thread")
            print(String(format: "PASS: main thread blocked 350 ms; worst audio scheduling lateness %.2f ms", worstLateness))
            scheduler.stop()
        }

        // Restart cancels the prior timer; stop must prevent all future attacks.
        queue.sync {
            attacks.removeAll()
            let later = [SongNote(startMilliseconds: 100, durationMilliseconds: 100,
                                  noteNumber: 72, velocity: 90, hand: .right)]
            scheduler.start(notes: later, positionMilliseconds: 0, speed: 1, loop: nil,
                            startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds,
                            onNote: { note, _ in attacks.append((note.noteNumber, 0)) }, onLoop: {})
            scheduler.stop()
        }
        Thread.sleep(forTimeInterval: 0.15)
        queue.sync { precondition(attacks.isEmpty, "Stop cancels pending notes") }

        var durations: [Int64] = []
        queue.sync {
            let now = DispatchTime.now().uptimeNanoseconds
            let resumeNotes = [
                SongNote(startMilliseconds: 0, durationMilliseconds: 500, noteNumber: 48, velocity: 90, hand: .left),
                SongNote(startMilliseconds: 10, durationMilliseconds: 20, noteNumber: 60, velocity: 90, hand: .right)
            ]
            scheduler.start(notes: resumeNotes, positionMilliseconds: 100, speed: 2, loop: nil,
                            startedAtNanoseconds: now - 50_000_000, onNote: { note, duration in
                attacks.append((note.noteNumber, 0))
                durations.append(duration)
            }, onLoop: {})
        }
        Thread.sleep(forTimeInterval: 0.06)
        queue.sync {
            precondition(attacks.map(\.0) == [48], "Resume skips expired notes behind sustained bass")
            precondition((150...200).contains(durations[0]), "Speed scales remaining note duration")
            scheduler.stop()
        }

        var loops = 0
        queue.sync {
            attacks.removeAll()
            scheduler.start(notes: notes, positionMilliseconds: 0, speed: 1, loop: 0...100,
                            startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds,
                            onNote: { note, _ in attacks.append((note.noteNumber, 0)) },
                            onLoop: { loops += 1 })
        }
        Thread.sleep(forTimeInterval: 0.26)
        queue.sync {
            scheduler.stop()
            precondition(loops >= 2, "Loop runs independently of UI")
            precondition(attacks.allSatisfy { $0.0 < 62 }, "Loop excludes notes beyond B")
        }
        print("PASS: audio scheduler cancellation, resume, speed and loop")
    }
}
