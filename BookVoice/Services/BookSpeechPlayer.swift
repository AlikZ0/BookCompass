import Foundation
import PDFKit
import AVFoundation
import Combine
import NaturalLanguage
import MediaPlayer
import UIKit

@MainActor
final class BookSpeechPlayer: NSObject, ObservableObject {
    enum State: Equatable { case stopped, loading, speaking, paused }

    @Published private(set) var state: State = .stopped
    @Published private(set) var currentPage = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var pageProgress: Double = 0
    @Published private(set) var notice: String?
    @Published private(set) var recognizedPage = false
    @Published private(set) var spokenSentence = ""
    @Published private(set) var sleepRemainingSeconds = 0
    @Published private(set) var sleepDeadline: Date?

    @Published var rate: Float = 0.5
    @Published var chosenVoiceID = "automatic"
    @Published private(set) var pitch: Float = 1.0
    @Published private(set) var paragraphPause: Double = 0.20

    private let synthesizer = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegateProxy()
    private let remote = LockScreenPlayer()
    private var document: PDFDocument?
    private var activeBookID: UUID?
    private var activeBookTitle = "BookVoice"
    private var artwork: MPMediaItemArtwork?
    private var task: Task<Void, Never>?
    private struct SpeechChunk {
        let text: String
        let endsParagraph: Bool
    }

    private var chunks: [SpeechChunk] = []
    private var chunkIndex = 0
    private var currentUtterance: AVSpeechUtterance?
    private var sentenceRanges: [NSRange] = []
    private var currentSentenceIndex = -1
    private var generation: UInt = 0
    private var sleepTimer: Timer?

    var didChangePage: ((UUID, Int) -> Void)?

    override init() {
        super.init()
        // Keep the synthesizer's Obj-C delegate separate from this MainActor model.
        speechDelegate.onStart = { [weak self] utterance in
            Task { @MainActor [weak self] in self?.handleStarted(utterance) }
        }
        speechDelegate.onWord = { [weak self] utterance, range in
            Task { @MainActor [weak self] in self?.handleWord(utterance, range: range) }
        }
        speechDelegate.onFinish = { [weak self] utterance in
            Task { @MainActor [weak self] in self?.handleFinished(utterance) }
        }
        synthesizer.delegate = speechDelegate

        let stored = UserDefaults.standard.float(forKey: "speechRate")
        rate = stored == 0 ? 0.5 : stored
        chosenVoiceID = UserDefaults.standard.string(forKey: "voiceID") ?? "automatic"
        if UserDefaults.standard.object(forKey: "speechPitch") != nil {
            pitch = min(1.2, max(0.8, UserDefaults.standard.float(forKey: "speechPitch")))
        }
        if UserDefaults.standard.object(forKey: "speechParagraphPause") != nil {
            paragraphPause = min(0.7, max(0, UserDefaults.standard.double(forKey: "speechParagraphPause")))
        }

        remote.install(
            play: { [weak self] in self?.remotePlay() },
            pause: { [weak self] in self?.remotePause() },
            toggle: { [weak self] in self?.playOrPause() },
            next: { [weak self] in self?.nextPage() },
            previous: { [weak self] in self?.previousPage() }
        )
    }

    func open(book: Book, at url: URL) {
        if activeBookID == book.id { return }
        stop()
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
            notice = "Не удалось открыть книгу"
            return
        }
        activeBookID = book.id
        activeBookTitle = book.title
        document = pdf
        pageCount = pdf.pageCount
        currentPage = min(max(book.lastPage, 0), pdf.pageCount - 1)
        pageProgress = 0
        spokenSentence = ""
        notice = nil

        // Generated completely offline from the PDF's first page.
        if let cover = pdf.page(at: 0)?.thumbnail(of: CGSize(width: 420, height: 600), for: .mediaBox) {
            artwork = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
        } else {
            artwork = nil
        }
        remote.setEnabled(true)
    }

    func isCurrentBook(_ id: UUID) -> Bool { activeBookID == id }

    func close() {
        stop()
        document = nil
        activeBookID = nil
        pageCount = 0
        currentPage = 0
        pageProgress = 0
        artwork = nil
        remote.clear()
    }

    func setRate(_ value: Float) {
        rate = value
        UserDefaults.standard.set(value, forKey: "speechRate")
    }

    func setPitch(_ value: Float) {
        pitch = min(1.2, max(0.8, value))
        UserDefaults.standard.set(pitch, forKey: "speechPitch")
    }

    func setParagraphPause(_ seconds: Double) {
        paragraphPause = min(0.7, max(0, seconds))
        UserDefaults.standard.set(paragraphPause, forKey: "speechParagraphPause")
    }

    func setVoice(_ id: String) {
        chosenVoiceID = id
        UserDefaults.standard.set(id, forKey: "voiceID")
    }

    func playOrPause() {
        switch state {
        case .speaking: remotePause()
        case .paused: remotePlay()
        case .stopped: startCurrentPage()
        case .loading: break
        }
    }

    /// Pause the book before recording a personal voice note, preserving the page.
    /// Do not clear the reading position or sleep timer.
    func pauseForRecording() {
        switch state {
        case .speaking: remotePause()
        case .loading: stopAudio()
        case .stopped, .paused: break
        }
    }

    private func remotePlay() {
        switch state {
        case .paused:
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                try session.setActive(true)
            } catch {
                notice = "Не удалось восстановить звук: \(error.localizedDescription)"
            }
            if synthesizer.continueSpeaking() {
                state = .speaking
                publishNowPlaying()
            } else {
                startCurrentPage()
            }
        case .stopped: startCurrentPage()
        case .speaking, .loading: break
        }
    }

    private func remotePause() {
        guard state == .speaking else { return }
        if synthesizer.pauseSpeaking(at: .immediate) {
            state = .paused
            publishNowPlaying()
        }
    }

    func stop() {
        stopAudio()
        cancelSleepTimer()
    }

    private func stopAudio() {
        generation &+= 1
        task?.cancel()
        task = nil
        currentUtterance = nil
        chunks.removeAll()
        sentenceRanges.removeAll()
        currentSentenceIndex = -1
        chunkIndex = 0
        synthesizer.stopSpeaking(at: .immediate)
        state = .stopped
        recognizedPage = false
        spokenSentence = ""
        publishNowPlaying()
    }

    func nextPage() { go(to: currentPage + 1) }
    func previousPage() { go(to: currentPage - 1) }

    func go(to page: Int) {
        guard document != nil, pageCount > 0 else { return }
        let target = min(max(page, 0), pageCount - 1)
        guard target != currentPage else { return }
        let wasPlaying = state == .speaking || state == .loading
        stopAudio() // Keep sleep timer running across page transitions.
        currentPage = target
        pageProgress = 0
        notifyPosition()
        if wasPlaying { startCurrentPage() }
        else { publishNowPlaying() }
    }

    private func notifyPosition() {
        if let id = activeBookID { didChangePage?(id, currentPage) }
    }

    // MARK: - Sleep timer

    func startSleepTimer(minutes: Int) {
        guard minutes > 0 else { cancelSleepTimer(); return }
        sleepTimer?.invalidate()
        sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
        refreshSleepTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshSleepTimer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepDeadline = nil
        sleepRemainingSeconds = 0
    }

    private func refreshSleepTimer() {
        guard let deadline = sleepDeadline else { return }
        let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        sleepRemainingSeconds = remaining
        if remaining == 0 {
            stopAudio()
            cancelSleepTimer()
            notice = "Таймер сна завершён. Чтение остановлено."
        }
    }

    // MARK: - Reading

    private func startCurrentPage() {
        guard let pdf = document,
              let id = activeBookID,
              let page = pdf.page(at: currentPage) else { return }

        generation &+= 1
        let token = generation
        task?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        chunks = []
        chunkIndex = 0
        sentenceRanges = []
        currentSentenceIndex = -1
        pageProgress = 0
        spokenSentence = ""
        notice = nil
        recognizedPage = false
        state = .loading
        publishNowPlaying()

        let index = currentPage
        task = Task { [weak self] in
            let directText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let result = await PDFTextExtractor.text(on: page, bookID: id, pageIndex: index)
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.recognizedPage = directText.isEmpty
            guard !result.isEmpty else {
                self.state = .stopped
                self.notice = "На странице \(index + 1) не найден текст. Попробуй следующую страницу."
                self.publishNowPlaying()
                return
            }
            self.chunks = Self.splitIntoChunks(result)
            self.chunkIndex = 0
            self.speakChunk()
        }
    }

    private func speakChunk() {
        guard chunkIndex < chunks.count else { finishPage(); return }
        let chunk = chunks[chunkIndex]
        let text = chunk.text
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.voice = resolveVoice(for: text)
        utterance.postUtteranceDelay = chunk.endsParagraph ? paragraphPause : 0.03
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            notice = "Не удалось настроить звук: \(error.localizedDescription)"
        }
        currentUtterance = utterance
        sentenceRanges = Self.sentenceRanges(in: text)
        currentSentenceIndex = -1
        state = .speaking
        synthesizer.speak(utterance)
        publishNowPlaying()
    }

    private func finishPage() {
        currentUtterance = nil
        spokenSentence = ""
        if currentPage + 1 < pageCount {
            currentPage += 1
            pageProgress = 0
            notifyPosition()
            startCurrentPage()
        } else {
            pageProgress = 1
            state = .stopped
            cancelSleepTimer()
            notice = "Книга закончилась"
            publishNowPlaying()
        }
    }

    // MARK: - Voice + sentence tracking

    private func handleStarted(_ utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        updateCurrentSentence(in: utterance, at: 0)
    }

    private func handleWord(_ utterance: AVSpeechUtterance, range: NSRange) {
        guard currentUtterance === utterance else { return }
        updateCurrentSentence(in: utterance, at: range.location)
        let length = max(1, (utterance.speechString as NSString).length)
        let fraction = Double(min(length, range.location)) / Double(length)
        let progress = (Double(chunkIndex) + fraction) / Double(max(1, chunks.count))
        if progress - pageProgress >= 0.015 { pageProgress = progress }
    }

    private func handleFinished(_ utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        chunkIndex += 1
        pageProgress = Double(chunkIndex) / Double(max(1, chunks.count))
        speakChunk()
    }

    private func updateCurrentSentence(in utterance: AVSpeechUtterance, at offset: Int) {
        guard let index = sentenceRanges.firstIndex(where: {
            $0.location <= offset && offset < NSMaxRange($0)
        }) ?? sentenceRanges.indices.last else { return }
        guard currentSentenceIndex != index else { return }
        currentSentenceIndex = index
        let nsText = utterance.speechString as NSString
        let range = sentenceRanges[index]
        guard NSMaxRange(range) <= nsText.length, range.length > 0 else { return }
        spokenSentence = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sentenceRanges(in text: String) -> [NSRange] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let span = NSRange(range, in: text)
            if span.length > 0 { result.append(span) }
            return true
        }
        if result.isEmpty { result = [NSRange(location: 0, length: (text as NSString).length)] }
        return result
    }

    // Highest-quality *installed* voice for the detected language. Premium and
    // enhanced voices cannot be downloaded directly by a third-party app.
    private func resolveVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if chosenVoiceID != "automatic",
           let selected = voices.first(where: { $0.identifier == chosenVoiceID }) {
            return selected
        }
        let language = Self.detectLanguage(text)
        let baseCode = language.split(separator: "-").first.map(String.init) ?? language
        let candidates = voices.filter {
            $0.language.split(separator: "-").first.map(String.init) == baseCode
        }
        let best = candidates.sorted { first, second in
            if first.quality.rawValue != second.quality.rawValue {
                return first.quality.rawValue > second.quality.rawValue
            }
            let firstLocale = first.language == language ? 1 : 0
            let secondLocale = second.language == language ? 1 : 0
            if firstLocale != secondLocale { return firstLocale > secondLocale }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }.first
        return best ?? AVSpeechSynthesisVoice(language: language)
    }

    private static func detectLanguage(_ text: String) -> String {
        var armenian = 0, cyrillic = 0
        for scalar in text.unicodeScalars.prefix(1500) {
            if (0x0530...0x058F).contains(scalar.value) { armenian += 1 }
            if (0x0400...0x052F).contains(scalar.value) { cyrillic += 1 }
        }
        if armenian > cyrillic && armenian > 0 { return "hy-AM" }
        if cyrillic > 0 { return "ru-RU" }
        return "en-US"
    }

    // Preserve sentence boundaries and real paragraph breaks, rather than
    // chopping at arbitrary words. It improves phrasing without cloud APIs.
    private static func splitIntoChunks(_ source: String, maximum: Int = 720) -> [SpeechChunk] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let separated = normalized.replacingOccurrences(
            of: #"\n[ \t]*\n+"#, with: "\u{E000}", options: .regularExpression
        )
        var output: [SpeechChunk] = []

        for rawParagraph in separated.components(separatedBy: "\u{E000}") {
            let paragraph = rawParagraph.replacingOccurrences(
                of: #"\s+"#, with: " ", options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.isEmpty else { continue }

            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = paragraph
            var sentences: [String] = []
            tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
                let sentence = String(paragraph[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                return true
            }
            if sentences.isEmpty { sentences = [paragraph] }

            var buffer = ""
            for sentence in sentences {
                // Very long unpunctuated sentences are split only at word edges.
                for part in splitLongSentence(sentence, maximum: maximum) {
                    if !buffer.isEmpty && buffer.count + 1 + part.count > maximum {
                        output.append(SpeechChunk(text: buffer, endsParagraph: false))
                        buffer = ""
                    }
                    buffer += buffer.isEmpty ? part : " " + part
                }
            }
            if !buffer.isEmpty {
                output.append(SpeechChunk(text: buffer, endsParagraph: true))
            } else if let last = output.indices.last {
                let lastChunk = output[last]
                output[last] = SpeechChunk(text: lastChunk.text, endsParagraph: true)
            }
        }
        return output
    }

    private static func splitLongSentence(_ sentence: String, maximum: Int) -> [String] {
        guard sentence.count > maximum else { return [sentence] }
        var result: [String] = []
        var buffer = ""
        for piece in sentence.split(separator: " ") {
            let word = String(piece)
            if !buffer.isEmpty && buffer.count + word.count + 1 > maximum {
                result.append(buffer)
                buffer = ""
            }
            // Extremely long tokens are uncommon in books; never discard text.
            if word.count > maximum {
                if !buffer.isEmpty { result.append(buffer); buffer = "" }
                var remaining = word[...]
                while !remaining.isEmpty {
                    let end = remaining.index(remaining.startIndex, offsetBy: maximum, limitedBy: remaining.endIndex) ?? remaining.endIndex
                    result.append(String(remaining[..<end]))
                    remaining = remaining[end...]
                }
            } else {
                buffer += buffer.isEmpty ? word : " " + word
            }
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result
    }

    private func publishNowPlaying() {
        guard activeBookID != nil else { return }
        remote.publish(title: activeBookTitle, page: currentPage, total: pageCount,
                       isPlaying: state == .speaking, artwork: artwork)
    }
}
