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

    /// Empty transcripts must fail with a deterministic error regardless of
    /// whether an API key is configured (input validation precedes config).
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

    // MARK: - JSON fence cleaning

    func testCleanedJSONPassthrough() throws {
        let json = #"{"summary":"ok"}"#
        let cleaned = try XCTUnwrap(AIAnalysisService.cleanedJSONData(from: json))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: cleaned))
    }

    func testCleanedJSONWithFences() throws {
        let fenced = """
        ```json
        {"summary": "ok"}
        ```
        """
        let cleaned = try XCTUnwrap(AIAnalysisService.cleanedJSONData(from: fenced))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: cleaned) as? [String: String])
        XCTAssertEqual(object["summary"], "ok")
    }
}
