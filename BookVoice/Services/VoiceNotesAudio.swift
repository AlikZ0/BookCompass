import Foundation
import AVFoundation
import Combine

/// Separate, actionable errors for microphone capture. Do not use the generic
/// `invalidAudio` error for failures that occur before a file is even created.
enum VoiceRecordingError: LocalizedError {
    case preparationFailed
    case startFailed
    case notRecording
    case cancelled
    case interrupted
    case fileMissing
    case fileEmpty
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .preparationFailed:
            return "Не удалось подготовить микрофон к записи. Проверь доступ к микрофону и попробуй ещё раз."
        case .startFailed:
            return "iPhone не начал запись звука. Отключи другие приложения, использующие микрофон, и попробуй снова."
        case .notRecording:
            return "Запись ещё не запущена. Нажми «Начать запись»."
        case .cancelled:
            return "Запись отменена."
        case .interrupted:
            return "Запись была прервана. Попробуй создать новую голосовую заметку."
        case .fileMissing:
            return "Запись остановлена, но аудиофайл не был создан. Попробуй снова."
        case .fileEmpty:
            return "Запись получилась слишком короткой или пустой. Запиши хотя бы одну секунду."
        case .invalidFile:
            return "Аудиофайл создан, но iPhone не может прочитать его как M4A. Попробуй записать заметку ещё раз."
        }
    }
}

@MainActor
final class VoiceNoteRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var seconds: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var recordingID: UUID?
    private var ticker: Timer?
    private var startGeneration = 0

    func start(in directory: URL, beforeStart: () -> Void) async throws {
        guard !isRecording else { return }
        startGeneration &+= 1
        let token = startGeneration

        let permission = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard token == startGeneration else { throw VoiceRecordingError.cancelled }
        guard permission else { throw CompassError.microphoneDenied }
        beforeStart()  // Stop TTS only after permission was actually granted.

        let session = AVAudioSession.sharedInstance()
        // AVSpeechSynthesizer is stopped by BookSpeechPlayer before we get here;
        // recording and TTS must not compete for this shared audio session.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let id = UUID()
        let url = directory.appendingPathComponent("\(id.uuidString).m4a")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard newRecorder.prepareToRecord() else {
                throw VoiceRecordingError.preparationFailed
            }
            guard newRecorder.record() else {
                throw VoiceRecordingError.startFailed
            }

            recorder = newRecorder
            fileURL = url
            recordingID = id
            isRecording = true
            seconds = 0
            ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let recorder = self.recorder else { return }
                    self.seconds = recorder.currentTime
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func finish(annotationID: UUID) throws -> VoiceBookmark {
        guard let recorder, let url = fileURL, let id = recordingID, isRecording else {
            throw VoiceRecordingError.notRecording
        }
        let duration = recorder.currentTime
        let wasCapturing = recorder.isRecording
        // AVAudioRecorder.stop() finalizes and closes the M4A container.
        recorder.stop()

        do {
            guard wasCapturing else { throw VoiceRecordingError.interrupted }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw VoiceRecordingError.fileMissing
            }
            let info = try FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (info[.size] as? NSNumber)?.intValue ?? 0
            guard duration >= 0.5 && bytes > 128 else {
                throw VoiceRecordingError.fileEmpty
            }
            // Validate the actual encoded file, not just the presence of its name.
            guard let probe = try? AVAudioPlayer(contentsOf: url), probe.duration > 0 else {
                throw VoiceRecordingError.invalidFile
            }
            let bookmark = VoiceBookmark(id: id, annotationID: annotationID,
                                         audioFileName: url.lastPathComponent,
                                         duration: probe.duration)
            cleanup(keepFile: true)
            return bookmark
        } catch {
            cleanup(keepFile: false)
            throw error
        }
    }

    func discard() {
        startGeneration &+= 1 // Invalidate any outstanding microphone-permission request.
        recorder?.stop()
        cleanup(keepFile: false)
    }

    private func cleanup(keepFile: Bool) {
        ticker?.invalidate()
        ticker = nil
        let oldFile = fileURL
        fileURL = nil
        recordingID = nil
        recorder = nil
        seconds = 0
        isRecording = false
        if !keepFile, let oldFile {
            try? FileManager.default.removeItem(at: oldFile)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private final class VoiceAudioDelegate: NSObject, AVAudioPlayerDelegate {
    var didFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        didFinish?()
    }
}

@MainActor
final class VoiceNotePlayback: ObservableObject {
    @Published private(set) var playingID: UUID?
    private var playback: AVAudioPlayer?
    private let delegate = VoiceAudioDelegate()

    init() {
        delegate.didFinish = { [weak self] in
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    func toggle(_ note: VoiceBookmark, fileURL: URL) throws {
        if playingID == note.id { stop(); return }
        stop()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw CompassError.invalidAudio }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
        try session.setActive(true)
        try? session.overrideOutputAudioPort(.speaker)
        let newPlayer = try AVAudioPlayer(contentsOf: fileURL)
        newPlayer.delegate = delegate
        newPlayer.volume = 1.0
        newPlayer.prepareToPlay()
        guard newPlayer.play() else { throw CompassError.invalidAudio }
        playback = newPlayer
        playingID = note.id
    }

    func stop() {
        playback?.stop()
        playback = nil
        playingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class QuotePlayback: ObservableObject {
    @Published private(set) var speaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private let proxy = SpeechDelegateProxy()

    init() {
        proxy.onFinish = { [weak self] _ in
            Task { @MainActor [weak self] in self?.speaking = false }
        }
        synthesizer.delegate = proxy
    }

    func toggle(text: String, preferredVoiceID: String, rate: Float) {
        if speaking { stop(); return }
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        if preferredVoiceID != "automatic" {
            utterance.voice = AVSpeechSynthesisVoice.speechVoices().first { $0.identifier == preferredVoiceID }
        }
        if utterance.voice == nil {
            let hasArmenian = text.unicodeScalars.contains { (0x0530...0x058F).contains($0.value) }
            let hasCyrillic = text.unicodeScalars.contains { (0x0400...0x052F).contains($0.value) }
            utterance.voice = AVSpeechSynthesisVoice(language: hasArmenian ? "hy-AM" : (hasCyrillic ? "ru-RU" : "en-US"))
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* TTS may continue using the current audio session. */ }
        speaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speaking = false
    }
}
