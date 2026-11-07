import SwiftUI

struct SleepTimerSheet: View {
    @EnvironmentObject private var player: BookSpeechPlayer
    @Environment(\.dismiss) private var dismiss

    private let choices: [Int] = [5, 10, 15, 20, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.indigo)
                        .frame(width: 74, height: 74)
                        .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))

                    if player.sleepDeadline != nil {
                        Text("Осталось \(timeDescription)")
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("Когда время закончится, озвучивание остановится.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Засыпай под книгу")
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text("Выбери время до автоматической остановки чтения.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(choices, id: \.self) { minutes in
                            Button {
                                player.startSleepTimer(minutes: minutes)
                                dismiss()
                            } label: {
                                Text(label(for: minutes))
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if player.sleepDeadline != nil {
                        Button(role: .destructive) {
                            player.cancelSleepTimer()
                            dismiss()
                        } label: {
                            Label("Отменить таймер", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                }
                .padding(22)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Таймер сна")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func label(for minutes: Int) -> String {
        minutes < 60 ? "\(minutes) мин" : "\(minutes / 60) ч \(minutes % 60 == 0 ? "" : "\(minutes % 60) мин")"
    }

    private var timeDescription: String {
        let value = player.sleepRemainingSeconds
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
