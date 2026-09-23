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
    var fullKeyboardHint: String { value("Play and navigate across all 88 keys", "Chơi và di chuyển trong 88 phím", "88鍵すべてを演奏・移動") }
    var fullKeyboardOverview: String { value("88-key overview", "Tổng quan 88 phím", "88鍵盤の概要") }
    var overviewAdjustmentHint: String { value("Swipe up or down to move by one octave.", "Vuốt lên hoặc xuống để dịch một quãng tám.", "上下にスワイプして1オクターブ移動します。") }
    var lowerOctave: String { value("Move down one octave", "Lùi một quãng tám", "1オクターブ下へ") }
    var higherOctave: String { value("Move up one octave", "Tiến một quãng tám", "1オクターブ上へ") }
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

    // MARK: Shared UI labels

    var appName: String { "Piano MIDI" }
    var ok: String { value("OK", "OK", "OK") }
    var ready: String { value("Ready", "Sẵn sàng", "準備完了") }
    var input: String { value("Input", "Đầu vào", "入力") }
    var output: String { value("Output", "Đầu ra", "出力") }
    var preferences: String { value("Preferences", "Tùy chọn", "環境設定") }
    var privacyLicenses: String { value("Privacy & licenses", "Quyền riêng tư & giấy phép", "プライバシーとライセンス") }
    var openBluetoothMIDI: String { value("Open iOS Bluetooth MIDI", "Mở Bluetooth MIDI của iOS", "iOS Bluetooth MIDIを開く") }
    var bluetoothHint: String {
        value(
            "Enable Bluetooth from Control Center or Settings, then return here and tap Scan.",
            "Bật Bluetooth trong Trung tâm điều khiển hoặc Cài đặt, sau đó quay lại đây và nhấn Quét.",
            "コントロールセンターまたは設定でBluetoothを有効にしてから、ここに戻って検索をタップしてください。"
        )
    }
    var compatibilityScanMessage: String {
        value(
            "MIDI service was not advertised. Showing named nearby BLE devices for compatibility.",
            "Thiết bị không quảng bá dịch vụ MIDI. Đang hiển thị các thiết bị BLE lân cận có tên để tương thích.",
            "MIDIサービスが広告されていません。互換性のため、名前のある近くのBLEデバイスを表示しています。"
        )
    }
    var availableDevices: String { value("Available devices", "Thiết bị khả dụng", "利用可能なデバイス") }
    var noMIDIPianos: String { value("No MIDI pianos", "Không có đàn MIDI", "MIDIピアノがありません") }
    var bluetoothPairingHint: String {
        value(
            "Turn on Bluetooth pairing mode, then tap Scan.",
            "Bật chế độ ghép nối Bluetooth, sau đó nhấn Quét.",
            "Bluetoothのペアリングモードを有効にしてから、検索をタップしてください。"
        )
    }
    var previouslyConnected: String { value("Previously connected", "Đã kết nối trước đây", "以前接続済み") }
    var nearbyBLE: String { value("Nearby BLE", "BLE lân cận", "近くのBLE") }
    func deviceName(_ name: String) -> String {
        switch name {
        case "Unnamed BLE device": return value(name, "Thiết bị BLE không tên", "名前のないBLEデバイス")
        case "MIDI device": return value(name, "Thiết bị MIDI", "MIDIデバイス")
        default: return name
        }
    }
    var connect: String { value("Connect", "Kết nối", "接続") }
    var noCoreMIDIDevices: String { value("No Core MIDI devices connected", "Chưa kết nối thiết bị Core MIDI", "Core MIDIデバイスが接続されていません") }
    var coreMIDIPacketLog: String { value("Core MIDI packet log", "Nhật ký gói Core MIDI", "Core MIDIパケットログ") }
    var rawMIDIPacketsHint: String { value("Raw MIDI packets appear here.", "Các gói MIDI thô sẽ xuất hiện ở đây.", "生のMIDIパケットがここに表示されます。") }
    func pianoSamplesReady(_ count: Int) -> String {
        value(
            "Upright Piano KW · \(count) FLAC samples ready",
            "Upright Piano KW · đã sẵn sàng \(count) mẫu FLAC",
            "Upright Piano KW · \(count)個のFLACサンプルを使用できます"
        )
    }
    var pianoSamplesUnavailable: String {
        value(
            "Piano samples unavailable — check app resources",
            "Không có mẫu piano — hãy kiểm tra tài nguyên ứng dụng",
            "ピアノサンプルを利用できません。アプリのリソースを確認してください"
        )
    }
    var woodblock: String { value("Woodblock", "Mõ gỗ", "ウッドブロック") }
    var digital: String { value("Digital", "Điện tử", "デジタル") }
    var loadingScore: String { value("Loading score…", "Đang tải bản nhạc…", "楽譜を読み込み中…") }
    var generatedPianoSheetMusic: String { value("Generated piano sheet music", "Bản nhạc piano được tạo", "生成されたピアノ楽譜") }
    var grandStaffPreview: String { value("Grand staff preview", "Xem trước khuông nhạc kép", "大譜表プレビュー") }
    var pianoKeyboard: String { value("Piano keyboard", "Bàn phím piano", "ピアノ鍵盤") }
    var noSheetMusic: String { value("No sheet music", "Không có bản nhạc", "楽譜がありません") }
    var noWiredMIDIOutput: String { value("No wired MIDI output", "Không có đầu ra MIDI có dây", "有線MIDI出力がありません") }
    var bluetoothOutputNotReady: String { value("Bluetooth MIDI output is not ready", "Đầu ra Bluetooth MIDI chưa sẵn sàng", "Bluetooth MIDI出力の準備ができていません") }
    var fullPiano: String { value("88-key piano", "Piano 88 phím", "88鍵ピアノ") }
    var scoreRendererUnavailable: String {
        value("Score renderer is unavailable.", "Bộ hiển thị bản nhạc không khả dụng.", "楽譜レンダラーを利用できません。")
    }
    var unableReadScore: String {
        value("Unable to read this MusicXML score.", "Không thể đọc bản nhạc MusicXML này.", "このMusicXML楽譜を読み込めません。")
    }
    var unableRenderScore: String {
        value("Unable to render this MusicXML score.", "Không thể hiển thị bản nhạc MusicXML này.", "このMusicXML楽譜を表示できません。")
    }

    // MARK: Enum labels kept separate from raw values

    func appearanceName(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: value("System", "Hệ thống", "システム")
        case .light: value("Light", "Sáng", "ライト")
        case .dark: value("Dark", "Tối", "ダーク")
        }
    }

    func outputRouteName(_ route: SongOutputRoute) -> String {
        switch route {
        case .appOnly: value("App only", "Chỉ ứng dụng", "アプリのみ")
        case .wired: value("Wired MIDI", "MIDI có dây", "有線MIDI")
        case .ble: value("Bluetooth MIDI", "Bluetooth MIDI", "Bluetooth MIDI")
        }
    }

    func eventName(_ event: MIDIEventType?) -> String {
        guard let event else { return "—" }
        switch event {
        case .noteOn: return value("NoteOn", "Bật nốt", "ノートオン")
        case .noteOff: return value("NoteOff", "Tắt nốt", "ノートオフ")
        }
    }

    func sourceName(_ source: MIDIInputSource?) -> String {
        guard let source else { return "—" }
        switch source {
        case .ble: return value("BLE", "BLE", "BLE")
        case .wired: return value("MIDI", "MIDI", "MIDI")
        case .preview: return value("Preview", "Xem trước", "プレビュー")
        case .song: return value("Song", "Bài nhạc", "曲")
        }
    }

    func solfegeName(for noteNumber: Int) -> String {
        let names: [String]
        switch language {
        case .english: names = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
        case .vietnamese: names = ["Đô", "Đô♯", "Rê", "Rê♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
        case .japanese: names = ["ド", "ド♯", "レ", "レ♯", "ミ", "ファ", "ファ♯", "ソ", "ソ♯", "ラ", "ラ♯", "シ"]
        }
        return "\(names[noteNumber.positiveModulo(12)])\(noteNumber / 12 - 1)"
    }

    func statusLabel(_ status: MIDIConnectionStatus) -> String {
        switch status {
        case .idle: ready
        case .preparingBluetooth: value("Preparing", "Đang chuẩn bị", "準備中")
        case .scanning: value("Scanning", "Đang quét", "検索中")
        case .connecting: value("Connecting", "Đang kết nối", "接続中")
        case .discoveringServices: value("Discovering", "Đang tìm dịch vụ", "サービスを検出中")
        case .enablingNotifications: value("Subscribing", "Đang đăng ký", "通知を登録中")
        case .connected: value("Live", "Đang hoạt động", "接続中")
        case .unavailable: value("Unavailable", "Không khả dụng", "利用不可")
        case .failed: value("Error", "Lỗi", "エラー")
        }
    }

    func overallConnectionLabel(status: MIDIConnectionStatus, hasExternalMIDI: Bool) -> String {
        if status.isConnected || hasExternalMIDI {
            return value("MIDI Live", "MIDI đang hoạt động", "MIDIライブ")
        }
        return statusLabel(status)
    }

    /// Localizes connection state text while preserving device names and OS error details.
    func statusMessage(_ status: MIDIConnectionStatus) -> String {
        switch status {
        case .idle:
            return value("Ready to search for a Bluetooth MIDI piano.", "Sẵn sàng tìm đàn piano Bluetooth MIDI.", "Bluetooth MIDIピアノを検索する準備ができました。")
        case .preparingBluetooth:
            return value("Waiting for Bluetooth permission and radio readiness…", "Đang chờ quyền Bluetooth và trạng thái sẵn sàng của bộ thu phát…", "Bluetoothの許可と無線の準備を待っています…")
        case .scanning:
            return value("Searching for nearby BLE MIDI pianos…", "Đang tìm đàn piano BLE MIDI ở gần…", "近くのBLE MIDIピアノを検索中…")
        case let .connecting(name):
            return value("Connecting to \(name)…", "Đang kết nối với \(name)…", "\(name)に接続中…")
        case let .discoveringServices(name):
            return value("Connected to \(name). Discovering MIDI services…", "Đã kết nối với \(name). Đang tìm dịch vụ MIDI…", "\(name)に接続しました。MIDIサービスを検出中…")
        case let .enablingNotifications(name):
            return value("Enabling MIDI notifications on \(name)…", "Đang bật thông báo MIDI trên \(name)…", "\(name)のMIDI通知を有効にしています…")
        case let .connected(name, _):
            return value("Receiving MIDI from \(name).", "Đang nhận MIDI từ \(name).", "\(name)からMIDIを受信中です。")
        case let .unavailable(message), let .failed(message):
            return localizedConnectionError(message)
        }
    }

    private func localizedConnectionError(_ message: String) -> String {
        if message.hasPrefix("Allow Bluetooth access") {
            return value(
                "Allow Bluetooth access in Settings → PiaKeys, then scan again.",
                "Cho phép truy cập Bluetooth trong Cài đặt → PiaKeys, sau đó quét lại.",
                "設定 → PiaKeysでBluetoothへのアクセスを許可してから、もう一度検索してください。"
            )
        }
        if message.hasPrefix("Bluetooth Low Energy is not supported") {
            return value("Bluetooth Low Energy is not supported on this device.", "Thiết bị này không hỗ trợ Bluetooth Low Energy.", "このデバイスはBluetooth Low Energyに対応していません。")
        }
        if message.hasPrefix("Turn on Bluetooth") {
            return value("Turn on Bluetooth to scan for MIDI pianos.", "Bật Bluetooth để quét tìm đàn MIDI.", "MIDIピアノを検索するにはBluetoothをオンにしてください。")
        }
        if message.hasPrefix("Bluetooth is restarting") {
            return value("Bluetooth is restarting. Please try again shortly.", "Bluetooth đang khởi động lại. Vui lòng thử lại sau ít phút.", "Bluetoothを再起動しています。しばらくしてからもう一度お試しください。")
        }
        if message == "Bluetooth is not ready yet." {
            return value(message, "Bluetooth chưa sẵn sàng.", "Bluetoothの準備がまだできていません。")
        }
        if message.hasPrefix("The selected piano is no longer available") {
            return value("The selected piano is no longer available. Scan again.", "Đàn piano đã chọn không còn khả dụng. Hãy quét lại.", "選択したピアノは利用できません。もう一度検索してください。")
        }
        if message.hasPrefix("Connection to ") && message.hasSuffix(" timed out.") {
            let name = message.dropFirst("Connection to ".count).dropLast(" timed out.".count)
            return value("Connection to \(name) timed out.", "Kết nối với \(name) đã hết thời gian chờ.", "\(name)への接続がタイムアウトしました。")
        }
        if message.hasPrefix("Disconnected: ") {
            let detail = String(message.dropFirst("Disconnected: ".count))
            return value("Disconnected: \(detail)", "Đã ngắt kết nối: \(detail)", "切断されました: \(detail)")
        }
        if message.hasPrefix("Service discovery failed: ") {
            let detail = String(message.dropFirst("Service discovery failed: ".count))
            return value("Service discovery failed: \(detail)", "Không thể tìm dịch vụ: \(detail)", "サービスの検出に失敗しました: \(detail)")
        }
        if message.hasPrefix("Characteristic discovery failed: ") {
            let detail = String(message.dropFirst("Characteristic discovery failed: ".count))
            return value("Characteristic discovery failed: \(detail)", "Không thể tìm đặc tính MIDI: \(detail)", "特性の検出に失敗しました: \(detail)")
        }
        if message.hasPrefix("iOS could not register this BLE MIDI piano with Core MIDI") {
            return value(
                message,
                "iOS không thể đăng ký đàn piano BLE MIDI này với Core MIDI. Hãy ngắt kết nối đàn khỏi các ứng dụng MIDI khác rồi thử lại.",
                "iOSはこのBLE MIDIピアノをCore MIDIに登録できませんでした。他のMIDIアプリから切断してから、もう一度お試しください。"
            )
        }
        if message == "iOS registered no MIDI output for this piano." {
            return value(message, "iOS không đăng ký được đầu ra MIDI cho đàn piano này.", "iOSはこのピアノのMIDI出力を登録できませんでした。")
        }
        if message == "The BLE MIDI characteristic cannot receive MIDI output." {
            return value(message, "Đặc tính BLE MIDI không thể nhận dữ liệu MIDI đầu ra.", "BLE MIDI特性はMIDI出力を受信できません。")
        }
        if message == "The BLE MIDI characteristic was not found." {
            return value(message, "Không tìm thấy đặc tính BLE MIDI.", "BLE MIDI特性が見つかりません。")
        }
        if message == "The BLE MIDI characteristic cannot receive or send MIDI." {
            return value(message, "Đặc tính BLE MIDI không thể nhận hoặc gửi dữ liệu MIDI.", "BLE MIDI特性はMIDIの受信・送信に対応していません。")
        }
        if message == "This device does not expose the standard BLE MIDI service." {
            return value(message, "Thiết bị này không cung cấp dịch vụ BLE MIDI chuẩn.", "このデバイスは標準BLE MIDIサービスを提供していません。")
        }
        if message == "Could not connect to the MIDI piano." {
            return value(message, "Không thể kết nối với đàn piano MIDI.", "MIDIピアノに接続できません。")
        }
        return value(message, "Lỗi Bluetooth MIDI: \(message)", "Bluetooth MIDIエラー: \(message)")
    }

    // MARK: Import and persistence messages

    var invalidMIDIFile: String {
        value("Choose a Standard MIDI file (.mid or .midi).", "Hãy chọn tệp MIDI chuẩn (.mid hoặc .midi).", "標準MIDIファイル（.midまたは.midi）を選択してください。")
    }

    func songAlreadyInLibrary(_ title: String) -> String {
        value("\(title) is already in the library.", "\(title) đã có trong thư viện.", "\(title)はすでにライブラリにあります。")
    }

    func importedSong(_ title: String) -> String {
        value("Imported \(title).", "Đã nhập \(title).", "\(title)を読み込みました。")
    }

    func scoreAttached(_ title: String) -> String {
        value("MusicXML score attached to \(title).", "Đã gắn bản nhạc MusicXML vào \(title).", "MusicXML楽譜を\(title)に添付しました。")
    }

    func importScoreFailed(_ detail: String) -> String {
        value("Could not import the score: \(detail)", "Không thể nhập bản nhạc: \(detail)", "楽譜を読み込めませんでした: \(detail)")
    }

    func importMIDIFailed(_ detail: String) -> String {
        let localizedDetail: String
        switch detail {
        case "Invalid MIDI header":
            localizedDetail = value(detail, "Tiêu đề MIDI không hợp lệ", "MIDIヘッダーが正しくありません")
        case "Only MIDI format 0 and 1 are supported":
            localizedDetail = value(detail, "Chỉ hỗ trợ định dạng MIDI 0 và 1", "MIDI形式0と1のみ対応しています")
        case "MIDI format 0 must contain exactly one track":
            localizedDetail = value(detail, "MIDI định dạng 0 phải có đúng một track", "MIDI形式0には1つのトラックが必要です")
        case "MIDI time division must be positive":
            localizedDetail = value(detail, "MIDI time division phải lớn hơn 0", "MIDIタイムディビジョンは正の値である必要があります")
        case "MIDI file has no tracks":
            localizedDetail = value(detail, "Tệp MIDI không có track", "MIDIファイルにトラックがありません")
        case "SMPTE time division is not supported":
            localizedDetail = value(detail, "Không hỗ trợ SMPTE time division", "SMPTEタイムディビジョンには対応していません")
        case "No playable piano notes were found":
            localizedDetail = value(detail, "Không tìm thấy nốt piano có thể phát", "再生できるピアノ音符が見つかりません")
        case "Running status appeared before a status byte":
            localizedDetail = value(detail, "Running status xuất hiện trước status byte", "ステータスバイトより前にランニングステータスが現れました")
        case "Invalid tempo event":
            localizedDetail = value(detail, "Sự kiện tempo không hợp lệ", "テンポイベントが正しくありません")
        case "MIDI tempo must be positive":
            localizedDetail = value(detail, "Tempo MIDI phải lớn hơn 0", "MIDIテンポは正の値である必要があります")
        case "Invalid time signature":
            localizedDetail = value(detail, "Time signature không hợp lệ", "拍子記号が正しくありません")
        case "Invalid MIDI data byte":
            localizedDetail = value(detail, "Byte dữ liệu MIDI không hợp lệ", "MIDIデータバイトが正しくありません")
        case "Unexpected end of MIDI file":
            localizedDetail = value(detail, "Tệp MIDI kết thúc bất ngờ", "MIDIファイルが途中で終了しました")
        case "Invalid MIDI variable-length quantity":
            localizedDetail = value(detail, "Giá trị MIDI có độ dài biến đổi không hợp lệ", "MIDI可変長値が正しくありません")
        default:
            if detail.hasPrefix("Unsupported MIDI status ") {
                let code = String(detail.dropFirst("Unsupported MIDI status ".count))
                localizedDetail = value(detail, "Trạng thái MIDI không được hỗ trợ \(code)", "未対応のMIDIステータス \(code)")
            } else if detail.hasPrefix("Expected MIDI chunk ") {
                let chunk = String(detail.dropFirst("Expected MIDI chunk ".count))
                localizedDetail = value(detail, "Thiếu MIDI chunk \(chunk)", "MIDIチャンク \(chunk) が必要です")
            } else {
                localizedDetail = detail
            }
        }
        return value("Could not import MIDI: \(localizedDetail)", "Không thể nhập MIDI: \(localizedDetail)", "MIDIを読み込めませんでした: \(localizedDetail)")
    }

    func restoreLibraryFailed(_ detail: String) -> String {
        value("Could not restore the song library: \(detail)", "Không thể khôi phục thư viện bài nhạc: \(detail)", "曲ライブラリを復元できませんでした: \(detail)")
    }

    func restoreHistoryFailed(_ detail: String) -> String {
        value("Could not restore practice history: \(detail)", "Không thể khôi phục lịch sử luyện tập: \(detail)", "練習履歴を復元できませんでした: \(detail)")
    }

    func removeSongFailed(_ detail: String) -> String {
        value("Could not remove the song: \(detail)", "Không thể xóa bài nhạc: \(detail)", "曲を削除できませんでした: \(detail)")
    }

    func clearHistoryFailed(_ detail: String) -> String {
        value("Could not clear practice history: \(detail)", "Không thể xóa lịch sử luyện tập: \(detail)", "練習履歴を消去できませんでした: \(detail)")
    }

    func saveHistoryFailed(_ detail: String) -> String {
        value("Could not save practice history: \(detail)", "Không thể lưu lịch sử luyện tập: \(detail)", "練習履歴を保存できませんでした: \(detail)")
    }

    var feedbackSubject: String { value("PiaKeys iOS Feedback", "Phản hồi PiaKeys iOS", "PiaKeys iOSへのフィードバック") }
    var feedbackBodyAppVersion: String { value("App version", "Phiên bản ứng dụng", "アプリバージョン") }

    // MARK: Legal and attribution

    var legalPrivacyDescription: String {
        value(
            "PiaKeys processes MIDI input, audio playback, imported songs, and MusicXML scores on this device. The current build has no account, advertising, analytics, or developer-hosted upload.",
            "PiaKeys xử lý dữ liệu MIDI, phát âm thanh, bài nhạc đã nhập và bản nhạc MusicXML trên thiết bị này. Bản dựng hiện tại không có tài khoản, quảng cáo, phân tích dữ liệu hoặc tải dữ liệu lên máy chủ của nhà phát triển.",
            "PiaKeysはこのデバイス上でMIDI入力、オーディオ再生、読み込んだ曲、MusicXML楽譜を処理します。現在のビルドにはアカウント、広告、分析、開発者サーバーへのアップロードはありません。"
        )
    }
    var piaKeysLinks: String { value("PiaKeys links", "Liên kết PiaKeys", "PiaKeysリンク") }
    var privacyPolicy: String { value("Privacy Policy", "Chính sách quyền riêng tư", "プライバシーポリシー") }
    var support: String { value("Support", "Hỗ trợ", "サポート") }
    var licensesSources: String { value("Licenses & sources", "Giấy phép & nguồn", "ライセンスとソース") }
    var bundledSources: String { value("Bundled third-party sources", "Nguồn bên thứ ba đi kèm", "同梱されたサードパーティソース") }
    var uprightPianoSamples: String { "Upright Piano KW samples" }
    var freePatsLicense: String { "FreePats · CC0 1.0" }
    var verovioRenderer: String { value("Verovio score renderer", "Bộ hiển thị bản nhạc Verovio", "Verovio楽譜レンダラー") }
    var verovioLicense: String { value("LGPL · see upstream COPYING and COPYING.LESSER", "LGPL · xem COPYING và COPYING.LESSER của dự án gốc", "LGPL · 上流のCOPYINGとCOPYING.LESSERを参照") }
    var awesomeSheetMusic: String { "awesome-sheet-music" }
    var awesomeSheetMusicDescription: String {
        value("Curated directory; not a blanket license for linked scores", "Thư mục tuyển chọn; không phải giấy phép chung cho các bản nhạc được liên kết", "厳選ディレクトリ。リンク先の楽譜に包括的なライセンスを付与するものではありません")
    }
    var midiFiles: String { value("MIDI files", "Tệp MIDI", "MIDIファイル") }
    var midiFilesDescription: String {
        value(
            "The built-in PiaKeys Waltz Study is generated in-app. PiaKeys does not bundle a third-party MIDI catalog. When importing a .mid or .midi file, use only material you are allowed to use and share.",
            "Bài PiaKeys Waltz Study tích hợp được tạo ngay trong ứng dụng. PiaKeys không đi kèm kho MIDI của bên thứ ba. Khi nhập tệp .mid hoặc .midi, chỉ sử dụng nội dung mà bạn được phép sử dụng và chia sẻ.",
            "内蔵のPiaKeys Waltz Studyはアプリ内で生成されます。PiaKeysはサードパーティのMIDIカタログを同梱していません。.midまたは.midiファイルを読み込む際は、使用と共有が許可された素材だけを使用してください。"
        )
    }
}
