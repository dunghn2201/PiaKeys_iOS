import Foundation

struct LocalizedCopy {
    let language: PiaKeysLanguage

    private func value(_ english: String, _ vietnamese: String, _ japanese: String) -> String {
        switch language {
        case .english: english
        case .vietnamese: vietnamese
        case .japanese: japanese
        }
    }

    var practice: String { value("Practice", "Luyện tập", "練習") }
    var midiMonitor: String { value("MIDI Monitor", "MIDI Monitor", "MIDIモニター") }
    var metronome: String { value("Metronome", "Máy đếm nhịp", "メトロノーム") }
    var setup: String { value("Setup", "Thiết lập", "設定") }
    var songs: String { value("Songs", "Bài nhạc", "曲") }
    var learnNotes: String { value("Learn notes live", "Học nốt trực tiếp", "音符をリアルタイム学習") }
    var inputSubtitle: String { value("Bluetooth and wired MIDI input", "MIDI Bluetooth và có dây", "Bluetooth・有線MIDI入力") }
    var liveMonitorSubtitle: String { value("MIDI input and song playback", "MIDI và phát bài nhạc", "MIDI入力と曲の再生") }
    var liveMonitor: String { value("Live note monitor", "Theo dõi nốt trực tiếp", "ライブ音符モニター") }
    var recentNotes: String { value("Recent notes", "Các nốt gần đây", "最近の音符") }
    var source: String { value("Source", "Nguồn", "入力") }
    var velocity: String { value("Velocity", "Lực nhấn", "ベロシティ") }
    var event: String { value("Event", "Sự kiện", "イベント") }
    var tempo: String { value("Tempo", "Nhịp độ", "テンポ") }
    var playing: String { value("Playing", "Đang phát", "再生中") }
    var midiReady: String { value("MIDI", "MIDI", "MIDI") }
    var sheetPreview: String { value("Sheet preview", "Xem trước bản nhạc", "楽譜プレビュー") }
    var sheetMusic: String { value("Sheet music", "Bản nhạc", "楽譜") }
    var previousPage: String { value("Previous page", "Trang trước", "前のページ") }
    var nextPage: String { value("Next page", "Trang sau", "次のページ") }
    var openSheet: String { value("Open sheet music", "Mở bản nhạc", "楽譜を開く") }
    var close: String { value("Done", "Xong", "完了") }
    var keyboard: String { value("Keyboard", "Bàn phím", "鍵盤") }
    var noNotes: String { value("Play a key to begin.", "Hãy chơi một phím để bắt đầu.", "鍵盤を弾いて始めましょう。") }
    var chord: String { value("Chord", "Hợp âm", "コード") }
    var noChord: String { value("Play a major or minor triad", "Chơi hợp âm trưởng hoặc thứ", "長三和音・短三和音を弾く") }
    var songStudio: String { value("Song studio", "Phòng tập bài nhạc", "ソングスタジオ") }
    var importMIDI: String { value("Import MIDI", "Nhập MIDI", "MIDIを読み込む") }
    var importScore: String { value("Import MusicXML", "Nhập MusicXML", "MusicXMLを読み込む") }
    var play: String { value("Play", "Phát", "再生") }
    var pause: String { value("Pause", "Tạm dừng", "一時停止") }
    var reset: String { value("Reset", "Đặt lại", "リセット") }
    var outputRoute: String { value("Output route", "Đường xuất", "出力先") }
    var library: String { value("Library", "Thư viện", "ライブラリ") }
    var fullKeyboard: String { value("Full 88-key keyboard", "Đủ 88 phím", "88鍵盤") }
    var fullKeyboardHint: String { value("Fit all keys on screen", "Hiển thị tất cả phím", "全鍵盤を画面に表示") }
    var pianoSetup: String { value("Connect your piano", "Kết nối đàn piano", "ピアノを接続") }
    var bluetoothMIDI: String { value("Bluetooth MIDI", "MIDI Bluetooth", "Bluetooth MIDI") }
    var scanPiano: String { value("Scan for piano", "Quét tìm đàn", "ピアノを検索") }
    var stopScan: String { value("Stop scan", "Dừng quét", "検索を停止") }
    var disconnect: String { value("Disconnect", "Ngắt kết nối", "接続解除") }
    var wiredMIDI: String { value("Wired MIDI", "MIDI có dây", "有線MIDI") }
    var wiredDescription: String { value("USB, Lightning or network MIDI devices discovered by CoreMIDI.", "Thiết bị USB, Lightning hoặc MIDI mạng do CoreMIDI nhận diện.", "CoreMIDIが検出したUSB・Lightning・ネットワークMIDI機器。") }
    var refresh: String { value("Refresh", "Làm mới", "更新") }
    var appearance: String { value("Appearance", "Giao diện", "外観") }
    var languageTitle: String { value("Language", "Ngôn ngữ", "言語") }
    var diagnostics: String { value("Diagnostics", "Chẩn đoán", "診断") }
    var audioFeedback: String { value("Audio feedback", "Phản hồi âm thanh", "オーディオフィードバック") }
    var appVolume: String { value("App volume", "Âm lượng ứng dụng", "アプリ音量") }
    var testC4: String { value("Play test C4", "Phát thử C4", "C4をテスト") }
    var feedback: String { value("Send feedback", "Gửi phản hồi", "フィードバックを送る") }
    var appVersion: String { value("App version", "Phiên bản ứng dụng", "アプリバージョン") }
    var feedbackUnavailable: String { value("Mail unavailable", "Không có ứng dụng mail", "メールアプリを利用できません") }
    var feedbackUnavailableMessage: String {
        value(
            "Set up a mail app on this iPhone to send feedback.",
            "Hãy thiết lập ứng dụng mail trên iPhone để gửi phản hồi.",
            "フィードバックを送るにはiPhoneにメールアプリを設定してください。"
        )
    }
    var practiceTiming: String { value("Practice timing", "Luyện nhịp", "テンポ練習") }
    var bpm: String { value("beats per minute", "nhịp mỗi phút", "BPM") }
    var start: String { value("Start", "Bắt đầu", "開始") }
    var stop: String { value("Stop", "Dừng", "停止") }
    var timeSignature: String { value("Time signature", "Số chỉ nhịp", "拍子記号") }
    var accentPattern: String { value("Accent pattern", "Mẫu nhấn", "アクセント") }
    var firstBeatAccent: String { value("Accent first beat", "Nhấn phách đầu", "1拍目を強調") }
    var visualPulse: String { value("Visual pulse", "Nhịp trực quan", "視覚パルス") }
    var soundProfile: String { value("Sound profile", "Kiểu âm", "サウンド") }
    var speed: String { value("Speed", "Tốc độ", "速度") }
    var loop: String { value("Loop A–B", "Lặp A–B", "A–Bループ") }
    var loopStart: String { value("Set A", "Đặt A", "Aを設定") }
    var loopEnd: String { value("Set B", "Đặt B", "Bを設定") }
    var countIn: String { value("Count in", "Đếm trước", "カウントイン") }
    var countInBars: String { value("Bars", "Số ô nhịp", "小節数") }
    var hands: String { value("Hands", "Tay chơi", "手") }
    var bothHands: String { value("Both hands", "Hai tay", "両手") }
    var leftHand: String { value("Left hand", "Tay trái", "左手") }
    var rightHand: String { value("Right hand", "Tay phải", "右手") }
    var practiceMode: String { value("Practice mode", "Chế độ luyện", "練習モード") }
    var playAlong: String { value("Listen / play along", "Nghe / chơi cùng", "聴く・合わせて弾く") }
    var waitForNote: String { value("Wait for my note", "Chờ nốt của tôi", "自分の音を待つ") }
    var playWithTiming: String { value("Play with timing", "Chơi theo nhịp", "テンポに合わせて弾く") }
    var startPractice: String { value("Start practice", "Bắt đầu luyện", "練習を開始") }
    var stopPractice: String { value("Stop practice", "Dừng luyện", "練習を停止") }
    var target: String { value("Target", "Mục tiêu", "目標") }
    var waitingForNote: String { value("Play the highlighted note", "Chơi nốt đang chờ", "ハイライトされた音符を弾く") }
    var countInBeat: String { value("Count-in %d", "Đếm trước %d", "カウントイン %d") }
    var history: String { value("Practice history", "Lịch sử luyện tập", "練習履歴") }
    var accuracy: String { value("Accuracy", "Độ chính xác", "正確度") }
    var hits: String { value("Hits", "Đúng", "正解") }
    var missed: String { value("Missed", "Bỏ lỡ", "ミス") }
    var wrong: String { value("Wrong", "Sai nốt", "音程違い") }
    var early: String { value("Early", "Sớm", "早い") }
    var late: String { value("Late", "Trễ", "遅い") }
    var clearHistory: String { value("Clear history", "Xóa lịch sử", "履歴を消去") }
    var deleteSong: String { value("Delete song", "Xóa bài", "曲を削除") }
    var timing: String { value("Timing", "Độ lệch", "タイミング") }
    var hit: String { value("✓ Hit", "✓ Đúng", "✓ 正解") }
    var earlyBy: String { value("Early by %d ms", "Sớm %d ms", "%d ms 早い") }
    var lateBy: String { value("Late by %d ms", "Trễ %d ms", "%d ms 遅い") }
    var wrongNote: String { value("Wrong note", "Sai nốt", "音程違い") }
    var extraNote: String { value("Extra note", "Nốt thừa", "余分な音") }
    var missedNote: String { value("Missed note", "Bỏ lỡ nốt", "ミスした音") }
}
