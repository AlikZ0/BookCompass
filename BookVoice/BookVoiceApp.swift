import SwiftUI

@main
struct BookVoiceApp: App {
    @StateObject private var library = BookLibrary()
    @StateObject private var player = BookSpeechPlayer()
    @StateObject private var annotations = AnnotationStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(annotations)
                .preferredColorScheme(nil)
        }
    }
}
