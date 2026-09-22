import SwiftUI

/// Renders a generated MIDI song with the same notation engine used for
/// imported MusicXML scores.
struct GeneratedSongScoreView: View {
    let song: PracticeSong
    let positionMilliseconds: Int64
    let height: CGFloat
    let showsAllPages: Bool
    let page: Int
    let onPageCount: ((Int) -> Void)?
    let onPageChange: ((Int) -> Void)?

    @State private var contentHeight: CGFloat
    @State private var generatedScoreData: Data?

    init(
        song: PracticeSong,
        positionMilliseconds: Int64,
        height: CGFloat = 190,
        showsAllPages: Bool = false,
        page: Int = 1,
        onPageCount: ((Int) -> Void)? = nil,
        onPageChange: ((Int) -> Void)? = nil
    ) {
        self.song = song
        self.positionMilliseconds = positionMilliseconds
        self.height = height
        self.showsAllPages = showsAllPages
        self.page = max(1, page)
        self.onPageCount = onPageCount
        self.onPageChange = onPageChange
        _contentHeight = State(initialValue: max(120, height))
        _generatedScoreData = State(initialValue: nil)
    }

    var body: some View {
        Group {
            if let generatedScoreData {
                MusicXMLScoreView(
                    data: generatedScoreData,
                    positionMilliseconds: positionMilliseconds,
                    contentHeight: $contentHeight,
                    heightRange: showsAllPages ? 360...60_000 : 120...420,
                    showsAllPages: showsAllPages,
                    page: page,
                    onPageCount: onPageCount,
                    onPageChange: onPageChange
                )
                .allowsHitTesting(false)
            } else {
                ProgressView("Loading score…")
                    .frame(maxWidth: .infinity, minHeight: height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: showsAllPages ? max(360, contentHeight) : height)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: contentHeight)
        .accessibilityLabel("Generated piano sheet music")
        .task(id: song.id) {
            let snapshot = song
            let data = await Task.detached(priority: .userInitiated) {
                GeneratedMusicXMLBuilder.data(for: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            generatedScoreData = data
        }
    }
}
