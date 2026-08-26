import XCTest
@testable import Sotto

final class AIAnalysisServiceTests: XCTestCase {

    var service: AIAnalysisService!

    override func setUp() {
        super.setUp()
        service = AIAnalysisService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testInitialState() {
        if case .initial = service.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("State should be initial")
        }
    }

    /// Empty transcripts must fail with a deterministic error before any
    /// model interaction happens (input validation precedes inference).
    func testAnalyzeEmptyTranscript() async {
        await service.analyzeTranscript("   ")
        guard case .error(let appError) = service.state else {
            XCTFail("Should fail with empty transcript")
            return
        }
        guard case .aiAnalysisFailed(let msg) = appError else {
            XCTFail("Wrong error type")
            return
        }
        XCTAssertEqual(msg, "Transcript is empty.")
    }

    // MARK: - String-path JSON parsing

    func testParseInsightJSONPassthrough() throws {
        let json = #"{"summary":"ok","primaryEmotion":"Calm","intensity":3,"energyLevel":4,"valence":0.2,"themes":["work","rest","focus"],"followUpQuestion":"Why?","hiddenObservation":"Tired but hopeful."}"#
        let result = try XCTUnwrap(AIAnalysisService.parseInsightJSON(json))
        XCTAssertEqual(result.summary, "ok")
        XCTAssertEqual(result.themes.count, 3)
    }

    func testParseInsightJSONWithFencesAndProse() throws {
        let noisy = """
        Here's your reflection:
        ```json
        {"summary":"ok","primaryEmotion":"Calm","intensity":3,"energyLevel":4,"valence":0,"themes":["a","b","c"],"followUpQuestion":"q","hiddenObservation":"h"}
        ```
        """
        let result = try XCTUnwrap(AIAnalysisService.parseInsightJSON(noisy))
        XCTAssertEqual(result.primaryEmotion, "Calm")
    }

    func testParseInsightJSONRejectsGarbage() {
        XCTAssertNil(AIAnalysisService.parseInsightJSON("Sorry, I can't help with that."))
    }

    // MARK: - NaturalLanguage fallback

    func testNLFallbackProducesValidResult() {
        let result = NLInsightEngine.analyze(
            transcript: "Today was really hard at work. I felt anxious about the deadlines and kept worrying all afternoon, but a long walk afterwards helped me calm down."
        )
        XCTAssertFalse(result.summary.isEmpty)
        XCTAssertFalse(result.primaryEmotion.isEmpty)
        XCTAssertTrue((1...10).contains(result.intensity))
        XCTAssertTrue((1...10).contains(result.energyLevel))
        XCTAssertTrue((-1.0...1.0).contains(result.valence))
        XCTAssertEqual(result.themes.count, 3)
        XCTAssertFalse(result.followUpQuestion.isEmpty)
        XCTAssertFalse(result.hiddenObservation.isEmpty)
    }

    func testNLFallbackIsDeterministic() {
        let transcript = "Quiet morning. Coffee, journaling, a slow walk by the water."
        let first = NLInsightEngine.analyze(transcript: transcript)
        let second = NLInsightEngine.analyze(transcript: transcript)
        XCTAssertEqual(first, second)
    }

    // MARK: - Light cleanup (NL fallback for dictation cleaning)

    func testLightCleanupRemovesFillersAndDuplicates() {
        let dirty = "um today I I went to the the store , and uh it was closed !"
        let clean = NLInsightEngine.lightCleanup(dirty)

        XCTAssertFalse(clean.lowercased().contains("um"))
        XCTAssertFalse(clean.lowercased().contains("uh "))
        XCTAssertFalse(clean.contains("I I"))
        XCTAssertFalse(clean.contains("the the"))
        XCTAssertFalse(clean.contains(" ,"))
        XCTAssertTrue(clean.hasSuffix("!") || clean.hasSuffix("."))
    }

    func testLightCleanupCapitalizesSentences() {
        let clean = NLInsightEngine.lightCleanup("first thing happened. then another thing went fine")
        XCTAssertTrue(clean.hasPrefix("First"))
        XCTAssertTrue(clean.contains("Then"))
    }

    func testLightCleanupCollapsesBlankLines() {
        let dirty = "line one\n\n\n\n\nline two"
        let clean = NLInsightEngine.lightCleanup(dirty)
        XCTAssertFalse(clean.contains("\n\n\n"))
    }
}
