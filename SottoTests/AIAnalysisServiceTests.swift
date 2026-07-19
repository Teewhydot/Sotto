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
    
    func testAnalyzeEmptyTranscript() async {
        await service.analyzeTranscript("   ")
        if case .error(let appError) = service.state {
            if case .aiAnalysisFailed(let msg) = appError {
                XCTAssertEqual(msg, "Transcript is empty.")
            } else {
                XCTFail("Wrong error type")
            }
        } else {
            XCTFail("Should fail with empty transcript")
        }
    }
}
