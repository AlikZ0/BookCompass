import SwiftUI
import PDFKit

struct ReaderView: View {
    let bookID: UUID
    var initialPage: Int? = nil
    var initialHighlight: String? = nil

    @EnvironmentObject private var annotations: AnnotationStore
    @EnvironmentObject private var library: BookLibrary
    @EnvironmentObject private var player: BookSpeechPlayer

    @State private var document: PDFDocument?
    @State private var showSettings = false
    @State private var showPageJump = false
    @State private var showSleepTimer = false
    @State private var pageInput = "1"
    @State private var showAnnotationEditor = false
    @State private var showVoiceNote = false
    @State private var showOCRQuote = false
    @State private var selectedText = ""
    @State private var quoteDraft = ""
    @State private var annotationNotice: String?

    private var book: Book? { library.books.first(where: { $0.id == bookID }) }
    private var page: Int { player.currentPage }

    private var currentQuoteCandidate: String {
        let direct = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        return player.spokenSentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasCurrentQuote: Bool { !currentQuoteCandidate.isEmpty }

    private var hasSavedCurrentQuote: Bool {
        guard hasCurrentQuote else { return false }
        return annotations.annotations(for: bookID).contains {
            $0.pageIndex == page && ($0.quoteText ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == currentQuoteCandidate
        }
    }

    var body: some View {
        readerContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if document != nil { playerPanel }
            }
            .navigationTitle(book?.title ?? "Книга")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { settingsToolbar }
            .sheet(isPresented: $showSettings) { settingsSheet }
            .sheet(isPresented: $showPageJump) { pageJumpSheet }
            .sheet(isPresented: $showSleepTimer) { sleepTimerSheet }
            .sheet(isPresented: $showAnnotationEditor) {
                AnnotationEditorView(bookID: bookID, pageIndex: page, selectedText: quoteDraft)
            }
            .sheet(isPresented: $showVoiceNote) {
                VoiceNoteSheet(bookID: bookID, pageIndex: page, quote: currentQuoteCandidate, annotationID: nil)
            }
            .sheet(isPresented: $showOCRQuote) {
                if let document {
                    OCRQuotePickerView(document: document, bookID: bookID, pageIndex: page) { quote in
                        saveBookmark(quote)
                    }
                }
            }
            .onAppear(perform: openBook)
    }

    @ViewBuilder
    private var readerContent: some View {
        if let document = document {
            documentContent(document)
        } else {
            ContentUnavailableViewFallback()
        }
    }

    private func documentContent(_ document: PDFDocument) -> some View {
        VStack(spacing: 10) {
            pageHeader
            pageProgressView
            PDFPageViewer(document: document, pageIndex: page,
                          sentence: player.spokenSentence.isEmpty ? (initialHighlight ?? "") : player.spokenSentence,
                          selectedText: $selectedText)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.055))
                }
                .padding(.horizontal, 14)
        }
        .padding(.top, 14)
    }

    private var safePageCount: Int { max(player.pageCount, 1) }

    private var completionPercent: Int {
        Int(Double(page + 1) / Double(safePageCount) * 100)
    }

    private var pageHeader: some View {
        HStack {
            Button {
                pageInput = String(page + 1)
                showPageJump = true
            } label: {
                Label("Страница \(page + 1) из \(safePageCount)", systemImage: "book.closed")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("\(completionPercent)%")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
    }

    private var pageProgressView: some View {
        ProgressView(value: Double(page) + player.pageProgress, total: Double(safePageCount))
            .tint(.blue)
            .padding(.horizontal, 20)
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            NavigationLink { AnnotationsListView(bookID: bookID) } label: {
                Image(systemName: "bookmark")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
    }

    private var settingsSheet: some View {
        SettingsView()
            .environmentObject(player)
            .presentationDragIndicator(.visible)
    }

    private var sleepTimerSheet: some View {
        SleepTimerSheet()
            .environmentObject(player)
            .presentationDragIndicator(.visible)
    }

    private var targetPageIndex: Int? {
        guard let number = Int(pageInput), (1...safePageCount).contains(number) else {
            return nil
        }
        return number - 1
    }

    private var pageJumpSheet: some View {
        NavigationStack {
            pageJumpForm
                .navigationTitle("Перейти к странице")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Закрыть") { showPageJump = false }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    private var pageJumpForm: some View {
        Form {
            Section("Номер страницы") {
                TextField("От 1 до \(player.pageCount)", text: $pageInput)
                    .keyboardType(.numberPad)
            }
            Section {
                Button("Перейти") {
                    guard let target = targetPageIndex else { return }
                    player.go(to: target)
                    showPageJump = false
                }
                .disabled(targetPageIndex == nil)
            }
        }
    }

    private func openBook() {
        guard let book = book else { return }
        let bookURL = library.url(for: book)
        document = PDFDocument(url: bookURL)
        player.didChangePage = { [weak library] id, currentPage in
            library?.updatePosition(bookID: id, page: currentPage)
        }
        player.open(book: book, at: bookURL)
        if let initialPage { player.go(to: initialPage) }
    }

    private var playerPanel: some View {
        VStack(spacing: 14) {
            playerStatus
            if !player.spokenSentence.isEmpty { spokenSentencePanel }
            knowledgeControls
            playbackControls
            secondaryControls
            if let annotationNotice { noticeBanner(annotationNotice) }
            if let notice = player.notice { noticeBanner(notice, tint: .orange) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)
        }
    }

    private var playerStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.blue)
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text("\(Int(player.pageProgress * 100))% страницы")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var spokenSentencePanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Сейчас звучит", systemImage: "text.quote")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(player.spokenSentence)
                .font(.system(size: 13, weight: .medium))
                .lineSpacing(3)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Текущее предложение: \(player.spokenSentence)")
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var knowledgeControls: some View {
        HStack(spacing: 10) {
            saveActionButton
            quoteActionButton
            voiceActionButton
        }
    }

    private var saveActionButton: some View {
        Button {
            saveBookmark(currentQuoteCandidate)
        } label: {
            quickActionLabel(
                title: hasSavedCurrentQuote ? "Сохранено" : "Запомнить",
                systemImage: hasSavedCurrentQuote ? "checkmark.circle.fill" : "bookmark",
                tint: hasSavedCurrentQuote ? .green : .blue,
                emphasized: hasSavedCurrentQuote
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasCurrentQuote)
    }

    private var quoteActionButton: some View {
        Button {
            quoteDraft = currentQuoteCandidate
            if quoteDraft.isEmpty, let document, document.page(at: page)?.string?.isEmpty != false {
                showOCRQuote = true
            } else {
                showAnnotationEditor = true
            }
        } label: {
            quickActionLabel(title: "Цитата", systemImage: "text.quote", tint: .blue)
        }
        .buttonStyle(.plain)
    }

    private var voiceActionButton: some View {
        Button {
            showVoiceNote = true
        } label: {
            quickActionLabel(title: "Голос", systemImage: "mic", tint: .blue)
        }
        .buttonStyle(.plain)
    }

    private func saveBookmark(_ rawText: String) {
        let quote = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else {
            annotationNotice = "Сначала выбери текст или запусти чтение."
            return
        }
        if hasSavedCurrentQuote {
            annotationNotice = "Эта цитата уже сохранена"
            return
        }
        let item = BookAnnotation(bookID: bookID, pageIndex: page,
            quoteText: quote, comment: "", tags: [], isFavorite: false,
            locator: TextLocator(pageIndex: page, selectedText: quote, contextBefore: nil, contextAfter: nil))
        do {
            try annotations.save(item)
            annotationNotice = "Цитата сохранена"
        } catch {
            annotationNotice = "Ошибка: \(error.localizedDescription)"
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 22) {
            Button { player.previousPage() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 48)
            }
            .disabled(page <= 0)
            .accessibilityLabel("Предыдущая страница")

            Button { player.playOrPause() } label: {
                playPauseSymbol
            }
            .disabled(player.state == .loading)
            .accessibilityLabel(player.state == .speaking ? "Пауза" : "Слушать")

            Button { player.nextPage() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 48)
            }
            .disabled(page >= player.pageCount - 1)
            .accessibilityLabel("Следующая страница")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var playPauseSymbol: some View {
        ZStack {
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 66, height: 66)
                .shadow(color: .blue.opacity(0.22), radius: 12, y: 5)
            if player.state == .loading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: player.state == .speaking ? "pause.fill" : "play.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: player.state == .speaking ? 0 : 2)
            }
        }
    }

    private var secondaryControls: some View {
        HStack {
            Button { player.stop() } label: {
                Label("Стоп", systemImage: "stop.fill")
            }
            .disabled(player.state == .stopped)

            Spacer()

            Button { showSleepTimer = true } label: {
                Label(sleepLabel, systemImage: "moon.stars")
            }
            .accessibilityLabel("Таймер сна")

            Spacer()

            Button { showSettings = true } label: {
                Label("Голос и скорость", systemImage: "waveform.circle")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func noticeBanner(_ text: String, tint: Color = .green) -> some View {
        HStack(spacing: 10) {
            Image(systemName: text == "Цитата сохранена" || text == "Эта цитата уже сохранена" ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.14))
        }
    }

    private func quickActionLabel(title: String, systemImage: String, tint: Color, emphasized: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(emphasized ? tint.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(emphasized ? tint.opacity(0.18) : Color.primary.opacity(0.06))
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sleepLabel: String {
        let remaining = player.sleepRemainingSeconds
        guard remaining > 0 else { return "Сон" }
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    private var statusText: String {
        switch player.state {
        case .stopped: return "Готов к чтению"
        case .loading: return "Готовим озвучивание"
        case .speaking: return "Читаем распознанный текст"
        case .paused: return "Пауза"
        }
    }
}

private struct PDFPageViewer: UIViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int
    let sentence: String
    @Binding var selectedText: String

    final class Coordinator {
        var current: PDFPageViewer
        var observer: NSObjectProtocol?
        init(current: PDFPageViewer) { self.current = current }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator(current: self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.backgroundColor = .secondarySystemGroupedBackground
        view.document = document
        let coordinator = context.coordinator
        coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewSelectionChanged, object: view, queue: .main
        ) { notification in
            guard let pdfView = notification.object as? PDFView else { return }
            let text = pdfView.currentSelection?.string ?? ""
            DispatchQueue.main.async { coordinator.current.selectedText = text }
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.current = self
        if view.document !== document { view.document = document }
        if let desiredPage = document.page(at: pageIndex), view.currentPage !== desiredPage {
            view.clearSelection()
            view.go(to: desiredPage)
        }
        updateHighlight(in: view)
    }

    private func updateHighlight(in view: PDFView) {
        guard let page = document.page(at: pageIndex),
              let pageText = page.string,
              !pageText.isEmpty,
              !sentence.isEmpty else {
            view.highlightedSelections = nil
            return
        }

        // PDFKit's character ranges are UTF-16 positions in the original page text.
        // OCR-only images have no such positions; the sentence panel still works.
        let words = sentence.split(whereSeparator: { $0.isWhitespace })
        let source = pageText as NSString
        var found = NSRange(location: NSNotFound, length: 0)
        let minimum = min(words.count, 3)
        let lengths = [words.count] + Array(stride(from: min(8, words.count), through: minimum, by: -1))
        for length in lengths where length > 0 {
            let prefix = words.prefix(length).map(String.init)
            // Allow line breaks between words in PDF's original text layer.
            let pattern = prefix.map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "\\s+")
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            if let match = expression.firstMatch(in: pageText, range: NSRange(location: 0, length: source.length)) {
                found = match.range
                break
            }
        }
        guard found.location != NSNotFound, found.length > 0,
              NSMaxRange(found) <= source.length,
              let selection = page.selection(for: found) else {
            view.highlightedSelections = nil
            return
        }
        selection.color = UIColor.systemYellow.withAlphaComponent(0.4)
        view.highlightedSelections = [selection]
    }
}

private struct ContentUnavailableViewFallback: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("Книга не открылась")
                .font(.headline)
            Text("Проверь, что PDF по-прежнему существует в локальной библиотеке.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
