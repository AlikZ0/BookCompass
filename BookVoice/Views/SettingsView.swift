import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var player: BookSpeechPlayer
    @Environment(\.dismiss) private var dismiss

    private var selectedVoiceDescription: String {
        guard player.chosenVoiceID != "automatic" else {
            return "Лучший доступный по языку книги"
        }
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: {
            $0.identifier == player.chosenVoiceID
        }) else { return "Голос недоступен — выбери другой" }
        return "\(voice.name) · \(voice.language)"
    }

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                readingSection
                offlineSection
                Section {
                    Text("BookVoice 1.3 · Offline PDF Reader")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Голос и чтение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var voiceSection: some View {
        Section {
            NavigationLink {
                VoicePickerView()
                    .environmentObject(player)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Выбрать голос").font(.subheadline.weight(.semibold))
                        Text(selectedVoiceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Голос диктора")
        } footer: {
            Text("Голоса Premium и Enhanced звучат качественнее обычных, но их наличие зависит от iOS и установленных голосовых пакетов. Все доступные голоса можно прослушать перед выбором.")
        }
    }

    private var readingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Быстрые настройки", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    presetButton("Обычно", rate: 0.50, pitch: 1.00, pause: 0.12)
                    presetButton("Книга", rate: 0.47, pitch: 1.02, pause: 0.24)
                    presetButton("Перед сном", rate: 0.40, pitch: 0.96, pause: 0.38)
                }
            }
            .padding(.vertical, 4)

            sliderRow(title: "Скорость", value: Double(player.rate),
                      range: 0.35...0.65, step: 0.025,
                      formatted: String(format: "%.2f", player.rate)) {
                player.setRate(Float($0))
            }
            sliderRow(title: "Высота голоса", value: Double(player.pitch),
                      range: 0.8...1.2, step: 0.025,
                      formatted: String(format: "%.2f", player.pitch)) {
                player.setPitch(Float($0))
            }
            sliderRow(title: "Пауза между абзацами", value: player.paragraphPause,
                      range: 0...0.7, step: 0.05,
                      formatted: String(format: "%.2f с", player.paragraphPause)) {
                player.setParagraphPause($0)
            }
        } header: {
            Text("Манера чтения")
        } footer: {
            Text("Приложение сохраняет границы предложений и делает небольшие паузы между абзацами. Это помогает ритму, но не заменяет живую актёрскую интонацию. Изменения применяются со следующего фрагмента.")
        }
    }

    private func presetButton(_ title: String, rate: Float, pitch: Float,
                              pause: Double) -> some View {
        Button {
            player.setRate(rate)
            player.setPitch(pitch)
            player.setParagraphPause(pause)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }

    private func sliderRow(title: String, value: Double,
                           range: ClosedRange<Double>, step: Double,
                           formatted: String,
                           onChange: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(formatted)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: onChange), in: range, step: step)
                .tint(.blue)
        }
        .padding(.vertical, 3)
    }

    private var offlineSection: some View {
        Section("Конфиденциальность") {
            Label("Книги и озвучивание остаются на iPhone", systemImage: "iphone")
            Label("Текст PDF и OCR не отправляются на сервер", systemImage: "lock.shield")
        }
        .font(.subheadline)
    }
}
