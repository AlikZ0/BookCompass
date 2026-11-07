import AVFoundation
import Foundation

/// Separate NSObject-based delegate avoids @MainActor / Obj-C protocol isolation issues
/// encountered by BookVoice on the Xcode 16.4 GitHub Actions runner.
final class SpeechDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
    var onStart: ((AVSpeechUtterance) -> Void)?
    var onFinish: ((AVSpeechUtterance) -> Void)?
    var onWord: ((AVSpeechUtterance, NSRange) -> Void)?

    @objc(speechSynthesizer:didStartSpeechUtterance:)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStart?(utterance)
    }

    @objc(speechSynthesizer:willSpeakRangeOfSpeechString:utterance:)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        onWord?(utterance, characterRange)
    }

    @objc(speechSynthesizer:didFinishSpeechUtterance:)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?(utterance)
    }
}
