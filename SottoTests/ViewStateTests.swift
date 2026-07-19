import XCTest
@testable import Sotto

final class ViewStateTests: XCTestCase {
    
    func testInitialState() {
        let state: ViewState<Int> = .initial
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.data)
        XCTAssertNil(state.error)
    }
    
    func testLoadingState() {
        let state: ViewState<Int> = .loading
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.data)
        XCTAssertNil(state.error)
    }
    
    func testLoadedState() {
        let state: ViewState<Int> = .loaded(42)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.data, 42)
        XCTAssertNil(state.error)
    }
    
    func testErrorState() {
        let err = AppError.unknown("Test error")
        let state: ViewState<Int> = .error(err)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.data)
        if case .unknown(let msg) = state.error {
            XCTAssertEqual(msg, "Test error")
        } else {
            XCTFail("Wrong error")
        }
    }
}
