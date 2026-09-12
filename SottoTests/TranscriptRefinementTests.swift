import XCTest
@testable import Sotto

/// Regression cover for the refinement pass that replaced real entries with
/// "[SIGHING] [BLANK_AUDIO]".
///
/// Two independent faults produced that: the recorded samples were handed to
/// Whisper at the wrong sample rate (so the model heard a stretched drone and
/// reported non-speech), and the result was accepted without stripping the
/// non-speech annotations it answered with.
final class TranscriptRefinementTests: XCTestCase {

    // MARK: - Annotation stripping

    func testStripsBlankAudioAnnotationEntirely() {
        XCTAssertEqual(
            SpeechService.strippingNonSpeechAnnotations("[SIGHING] [BLANK_AUDIO]"),
            ""
        )
    }

    func testStripsAssortedNonSpeechMarkup() {
        let cases = [
            "[MUSIC]", "[ Silence ]", "(sighs)", "*laughs*", "<|startoftranscript|>",
        ]
        for markup in cases {
            XCTAssertEqual(
                SpeechService.strippingNonSpeechAnnotations(markup), "",
                "\(markup) should reduce to nothing"
            )
        }
    }

    func testStripsControlAndTimestampTokensAroundRealSpeech() {
        let raw = "<|startoftranscript|><|en|><|0.00|> I felt calm today. <|4.20|>"
        XCTAssertEqual(
            SpeechService.strippingNonSpeechAnnotations(raw),
            "I felt calm today."
        )
    }

    func testKeepsSpeechWhenAnnotationsAreInterleaved() {
        let raw = "[BLANK_AUDIO] I was thinking about work. (sighs) Then I let it go."
        XCTAssertEqual(
            SpeechService.strippingNonSpeechAnnotations(raw),
            "I was thinking about work. Then I let it go."
        )
    }

    func testLeavesOrdinaryTranscriptUntouched() {
        let raw = "Today went better than I expected, honestly."
        XCTAssertEqual(SpeechService.strippingNonSpeechAnnotations(raw), raw)
    }

    // MARK: - Sample rate

    /// The bug: 48 kHz samples were written under a 16 kHz header, which
    /// relabels rather than converts — a 2 s entry became 6 s of audio pitched
    /// an octave and a half down.
    func testResampleFromHardwareRateProducesWhisperDuration() {
        let seconds = 2.0
        let hardwareRate = 48_000.0
        let samples = [Float](repeating: 0.25, count: Int(hardwareRate * seconds))

        let converted = SpeechService.resample(
            samples,
            from: hardwareRate,
            to: SpeechService.whisperSampleRate
        )

        // Duration must survive the conversion.
        let duration = Double(converted.count) / SpeechService.whisperSampleRate
        XCTAssertEqual(duration, seconds, accuracy: 0.01)
        XCTAssertEqual(converted.count, 32_000)
    }

    func testWhisperSampleRateMatchesWavWritten() throws {
        let samples = SpeechService.resample(
            [Float](repeating: 0.1, count: 4_800),
            from: 48_000,
            to: SpeechService.whisperSampleRate
        )
        let url = try XCTUnwrap(
            SpeechService.writeTemporaryWav(samples: samples, sampleRate: SpeechService.whisperSampleRate)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        // Sample rate lives at byte offset 24 of a canonical PCM header.
        let declared = data.subdata(in: 24..<28).withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }
        XCTAssertEqual(declared, UInt32(SpeechService.whisperSampleRate))
        // ...and the payload must actually be that many samples per second.
        let payloadSamples = (data.count - 44) / 2
        XCTAssertEqual(payloadSamples, 1_600)
    }
}
