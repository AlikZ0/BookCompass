import SwiftUI
import AVFoundation

/// Every listed voice is reported by AVSpeechSynthesisVoice.speechVoices() on
/// this iPhone. The app cannot install arbitrary voice packs by itself.
struct VoicePickerView: View {
    @EnvironmentObject private var player: BookSpeechPlayer
    @StateObject private var samples = VoiceSamplePlayer()
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var language = "ru"
    @State private var searchText = ""

    private var filteredVoices: [AVSpeechSynthesisVoice] {
        voices.filter { voice in
            let languageMatch = language == "all" ||
                voice.language.lowercased().hasPrefix(language + "-") ||
                voice.language.lowercased() == language
            let searchMatch = searchText.isEmpty ||
                voice.name.localizedCaseInsensitiveContains(searchText) ||
                voice.language.localizedCaseInsensitiveContains(searchText)
            return languageMatch && searchMatch
        }
        .sorted { left, right in
            if left.quality.rawValue != right.quality.rawValue {
                return left.quality.rawValue > right.quality.rawValue
            }
            if left.language != right.language { return left.language < right.language }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Язык", selection: $language) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                    Text("Հայերեն").tag("hy")
                    Text("Все").tag("all")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Язык книги")
            }

            Section {
                Button {
                    player.setVoice("automatic")
                    samples.stop()
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Лучший доступный")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Подбирается по языку и качеству")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if player.chosenVoiceID == "automatic" {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Автовыбор отдаёт предпочтение Premium, затем Enhanced, затем стандартному голосу нужного языка.")
            }

            Section {
                if filteredVoices.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Для выбранного языка голосов не найдено")
                            .font(.subheadline.weight(.medium))
                        Text("Добавь голос в настройках iPhone, затем вернись сюда и обнови список. Для армянского доступность зависит от версии iOS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Показать все языки") { language = "all" }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 10)
                } else {
                    ForEach(filteredVoices, id: \.identifier) { voice in
                        voiceRow(voice)
                    }
                }
            } header: {
                Text("Доступные голоса · \(filteredVoices.count)")
            } footer: {
                Text("Нажми ▶ для прослушивания примера. Если книга уже читается, её воспроизведение будет поставлено на паузу.")
            }

            Section {
                Text("Дополнительные голоса можно скачать в Настройки iPhone → Универсальный доступ → Чтение и произношение (или «Устный контент») → Голоса. Названия разделов зависят от версии iOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Как добавить голоса")
            }
        }
        .searchable(text: $searchText, prompt: "Имя или язык голоса")
        .navigationTitle("Голоса")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    voices = AVSpeechSynthesisVoice.speechVoices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Обновить список голосов")
            }
        }
        .onAppear { voices = AVSpeechSynthesisVoice.speechVoices() }
        .onDisappear { samples.stop() }
    }

    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        HStack(spacing: 10) {
            Button {
                player.setVoice(voice.identifier)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(voice.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if player.chosenVoiceID == voice.identifier {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(voice.language)
                            Text("·")
                            Text(qualityText(voice))
                                .foregroundStyle(voice.quality == .default ? Color.secondary : Color.blue)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if player.state == .speaking { player.playOrPause() }
                samples.toggle(voice: voice, rate: player.rate, pitch: player.pitch)
            } label: {
                Image(systemName: samples.playingVoiceID == voice.identifier ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.blue.opacity(0.10), in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Прослушать голос \(voice.name)")
        }
        .padding(.vertical, 3)
    }

    private func qualityText(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Стандартный"
        }
    }
}

@MainActor
final class VoiceSamplePlayer: NSObject, ObservableObject {
    @Published private(set) var playingVoiceID: String?
    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechDelegateProxy()
    private var activeUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        delegate.onFinish = { [weak self] utterance in
            Task { @MainActor [weak self] in
                guard let self, self.activeUtterance === utterance else { return }
                self.playingVoiceID = nil
                self.activeUtterance = nil
            }
        }
        synthesizer.delegate = delegate
    }

    func toggle(voice: AVSpeechSynthesisVoice, rate: Float, pitch: Float) {
        if playingVoiceID == voice.identifier {
            stop()
            return
        }
        stop()
        let utterance = AVSpeechUtterance(string: sampleText(for: voice.language))
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        activeUtterance = utterance
        playingVoiceID = voice.identifier
        synthesizer.speak(utterance)
    }

    func stop() {
        activeUtterance = nil
        playingVoiceID = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func sampleText(for language: String) -> String {
        if language.hasPrefix("ru") {
            return "Вечер был тихим. За окном шелестели деревья, а книга оживала с каждой страницей."
        }
        if language.hasPrefix("hy") {
            return "Բարի երեկո։ Այս գիրքը կարող ես լսել հանգիստ և հաճույքով։"
        }
        if language.hasPrefix("en") {
            return "It was a quiet evening. The pages turned softly, and the story began to unfold."
        }
        return "Welcome. This is a short voice preview."
    }
}
