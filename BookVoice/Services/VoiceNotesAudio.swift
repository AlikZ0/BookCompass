import Foundation
import AVFoundation
import Combine

@MainActor
final class VoiceNoteRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var seconds: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var ticker: Timer?

    func start(in directory: URL) async throws {
        guard !isRecording else { return }
        let permission = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard permission else { throw CompassError.microphoneDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ]
        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.prepareToRecord()
        guard newRecorder.record() else { throw CompassError.invalidAudio }
        recorder = newRecorder
        fileURL = url
        isRecording = true
        seconds = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.seconds = self?.recorder?.currentTime ?? 0 }
        }
    }

    func finish(annotationID: UUID) throws -> VoiceBookmark {
        guard let recorder, let url = fileURL, isRecording else { throw CompassError.invalidAudio }
        let duration = max(0, recorder.currentTime)
        recorder.stop()
        cleanup(keepFile: true)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CompassError.invalidAudio }
        let name = url.deletingPathExtension().lastPathComponent
        guard let id = UUID(uuidString: name) else { throw CompassError.invalidAudio }
        return VoiceBookmark(id: id, annotationID: annotationID, audioFileName: url.lastPathComponent, duration: duration)
    }

    func discard() {
        recorder?.stop()
        cleanup(keepFile: false)
    }

    private func cleanup(keepFile: Bool) {
        ticker?.invalidate()
        ticker = nil
        let oldFile = fileURL
        fileURL = nil
        recorder = nil
        seconds = 0
        isRecording = false
        if !keepFile, let oldFile { try? FileManager.default.removeItem(at: oldFile) }
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
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        let newPlayer = try AVAudioPlayer(contentsOf: fileURL)
        newPlayer.delegate = delegate
        guard newPlayer.play() else { throw CompassError.invalidAudio }
        playback = newPlayer
        playingID = note.id
    }

    func stop() {
        playback?.stop()
        playback = nil
        playingID = nil
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
