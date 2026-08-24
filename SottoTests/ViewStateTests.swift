import XCTest
@testable import Sotto

final class ViewStateTests: XCTestCase {

    func testInitialState() {
        let state: ViewState<Int> = .initial
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.value)
    }

    func testLoadingState() {
        let state: ViewState<Int> = .loading
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.value)
    }

    func testLoadedState() {
        let state: ViewState<Int> = .loaded(42)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.value, 42)
    }

    func testEmptyState() {
        let state: ViewState<Int> = .empty
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.value)
    }

    func testErrorState() {
        let err = AppError.unknown("Test error")
        let state: ViewState<Int> = .error(err)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.value)
        if case .error(.unknown(let msg)) = state {
            XCTAssertEqual(msg, "Test error")
        } else {
            XCTFail("Wrong error case")
        }
    }
}
