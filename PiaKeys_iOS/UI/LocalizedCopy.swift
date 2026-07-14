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
    var metronome: String { value("Metronome", "Máy đếm nhịp", "メトロノーム") }
    var setup: String { value("Setup", "Thiết lập", "設定") }
    var songs: String { value("Songs", "Bài nhạc", "曲") }
    var learnNotes: String { value("Learn notes live", "Học nốt trực tiếp", "音符をリアルタイム学習") }
    var inputSubtitle: String { value("Bluetooth and wired MIDI input", "MIDI Bluetooth và có dây", "Bluetooth・有線MIDI入力") }
    var liveMonitor: String { value("Live note monitor", "Theo dõi nốt trực tiếp", "ライブ音符モニター") }
    var recentNotes: String { value("Recent notes", "Các nốt gần đây", "最近の音符") }
    var source: String { value("Source", "Nguồn", "入力") }
    var velocity: String { value("Velocity", "Lực nhấn", "ベロシティ") }
    var event: String { value("Event", "Sự kiện", "イベント") }
    var sheetPreview: String { value("Sheet preview", "Xem trước bản nhạc", "楽譜プレビュー") }
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
    var practiceTiming: String { value("Practice timing", "Luyện nhịp", "テンポ練習") }
    var bpm: String { value("beats per minute", "nhịp mỗi phút", "BPM") }
    var start: String { value("Start", "Bắt đầu", "開始") }
    var stop: String { value("Stop", "Dừng", "停止") }
    var timeSignature: String { value("Time signature", "Số chỉ nhịp", "拍子記号") }
    var accentPattern: String { value("Accent pattern", "Mẫu nhấn", "アクセント") }
    var firstBeatAccent: String { value("Accent first beat", "Nhấn phách đầu", "1拍目を強調") }
    var visualPulse: String { value("Visual pulse", "Nhịp trực quan", "視覚パルス") }
    var soundProfile: String { value("Sound profile", "Kiểu âm", "サウンド") }
}
