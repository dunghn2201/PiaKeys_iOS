import SwiftUI

/// Renders a generated MIDI song with the same notation engine used for
/// imported MusicXML scores.
struct GeneratedSongScoreView: View {
    let song: PracticeSong
    let positionMilliseconds: Int64
    let height: CGFloat
    let showsAllPages: Bool

    @State private var contentHeight: CGFloat

    init(
        song: PracticeSong,
        positionMilliseconds: Int64,
        height: CGFloat = 190,
        showsAllPages: Bool = false
    ) {
        self.song = song
        self.positionMilliseconds = positionMilliseconds
        self.height = height
        self.showsAllPages = showsAllPages
        _contentHeight = State(initialValue: max(120, height))
    }

    var body: some View {
        MusicXMLScoreView(
            data: GeneratedMusicXMLBuilder.data(for: song),
            positionMilliseconds: positionMilliseconds,
            contentHeight: $contentHeight,
            heightRange: showsAllPages ? 360...60_000 : 120...420,
            showsAllPages: showsAllPages
        )
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity)
        .frame(height: showsAllPages ? max(360, contentHeight) : height)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: contentHeight)
        .accessibilityLabel("Generated piano sheet music")
    }
}
