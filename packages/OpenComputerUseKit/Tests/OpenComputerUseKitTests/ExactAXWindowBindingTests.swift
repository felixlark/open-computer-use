import XCTest
@testable import OpenComputerUseKit

final class ExactAXWindowBindingTests: XCTestCase {
    private let unavailable: Int32 = -25204

    func testTransientAXWindowsReadCanRecoverOnlyTheRequestedID() throws {
        var reads = 0
        let result: Int = try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: { true }, owner: { .owned }, windows: { timeout in
            XCTAssertGreaterThan(timeout, 0); XCTAssertLessThanOrEqual(timeout, 0.5)
            reads += 1
            return ExactAXRead(value: reads == 1 ? nil : [99, 42], status: reads == 1 ? self.unavailable : 0)
        }, focused: { _ in ExactAXRead(value: 99, status: 0) }, id: { value, _ in ExactAXRead(value: UInt32(value), status: 0) }, pause: {})
        XCTAssertEqual(result, 42)
        XCTAssertEqual(reads, 2)
    }

    func testIDMessagingFailureIsRetriedAsReadWithoutChangingTarget() throws {
        var ids = 0
        let result: Int = try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: { true }, owner: { .owned }, windows: { _ in
            ExactAXRead(value: [42], status: 0)
        }, focused: { _ in ExactAXRead(value: nil, status: -25212) }, id: { value, _ in
            ids += 1
            return ExactAXRead(value: ids == 1 ? nil : UInt32(value), status: ids == 1 ? self.unavailable : 0)
        }, pause: {})
        XCTAssertEqual(result, 42)
        XCTAssertEqual(ids, 2)
    }

    func testUnavailableAXKeepsRawErrorAndDoesNotClaimWindowClosed() {
        var reads = 0
        XCTAssertThrowsError(try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: { true }, owner: { .owned }, windows: { _ -> ExactAXRead<[Int]> in
            reads += 1
            return ExactAXRead(value: nil, status: self.unavailable)
        }, focused: { _ in ExactAXRead(value: nil, status: self.unavailable) }, id: { _, _ in XCTFail("No candidate should be probed"); return ExactAXRead(value: nil, status: 0) }, pause: {})) { error in
            XCTAssertTrue(error.localizedDescription.contains("CG_owner_confirmed"))
            XCTAssertTrue(error.localizedDescription.contains("AXWindows=-25204"))
            XCTAssertFalse(error.localizedDescription.contains("not a current window"))
        }
        XCTAssertEqual(reads, 2)
    }

    func testFocusedSheetMustHaveExactRequestedID() throws {
        let result: Int = try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: { true }, owner: { .owned }, windows: { _ in
            ExactAXRead(value: [99], status: 0)
        }, focused: { _ in ExactAXRead(value: 42, status: 0) }, id: { value, _ in ExactAXRead(value: UInt32(value), status: 0) }, pause: {})
        XCTAssertEqual(result, 42)
    }

    func testWrongFocusedIDCannotSubstituteForKnownCGWindow() {
        XCTAssertThrowsError(try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: { true }, owner: { .owned }, windows: { _ in
            ExactAXRead(value: [99], status: 0)
        }, focused: { _ in ExactAXRead(value: 100, status: 0) }, id: { value, _ in ExactAXRead(value: UInt32(value), status: 0) }, pause: {})) { error in
            XCTAssertTrue(error.localizedDescription.contains("No other window was selected"))
        }
    }

    func testCGOwnerChangingDuringReadRejectsMatchingAXID() {
        var ownershipReads = 0
        XCTAssertThrowsError(try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: { true }, owner: {
            ownershipReads += 1
            return ownershipReads == 1 ? .owned : .other(88)
        }, windows: { _ in ExactAXRead(value: [42], status: 0) }, focused: { _ in ExactAXRead(value: nil, status: 0) }, id: { value, _ in ExactAXRead(value: UInt32(value), status: 0) }, pause: {})) { error in
            XCTAssertTrue(error.localizedDescription.contains("cg_owner_mismatch(88)"))
        }
    }

    func testProcessRestartDuringReadCannotBindReplacement() {
        var identityReads = 0
        XCTAssertThrowsError(try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: {
            identityReads += 1; return identityReads == 1
        }, owner: { .owned }, windows: { _ in ExactAXRead(value: [42], status: 0) }, focused: { _ in ExactAXRead(value: nil, status: 0) }, id: { value, _ in ExactAXRead(value: UInt32(value), status: 0) }, pause: {})) { error in
            XCTAssertTrue(error.localizedDescription.contains("process_changed"))
        }
    }

    func testDeadlinePreventsFurtherAXReadsOrRetry() {
        var time: TimeInterval = 0, reads = 0
        XCTAssertThrowsError(try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: { true }, owner: { .owned }, windows: { _ in
            reads += 1; time = 3
            return ExactAXRead(value: [42], status: 0)
        }, focused: { _ in XCTFail("Budget expired"); return ExactAXRead(value: nil, status: 0) }, id: { _, _ in XCTFail("Budget expired"); return ExactAXRead(value: nil, status: 0) }, now: { time }, pause: { XCTFail("Budget expired") })) { error in
            XCTAssertTrue(error.localizedDescription.contains("ax_budget_exhausted"))
        }
        XCTAssertEqual(reads, 1)
    }

    func testMissingCGOwnerFailsBeforeAnyAXRead() {
        for owner: ExactCGOwner in [.absent, .other(88), .unavailable] {
            XCTAssertThrowsError(try ExactAXWindowBinding.resolve(windowID: 42, sameProcess: { true }, owner: { owner }, windows: { _ -> ExactAXRead<[Int]> in
                XCTFail("CG evidence already rejects target"); return ExactAXRead(value: nil, status: 0)
            }, focused: { _ in XCTFail("Unexpected read"); return ExactAXRead(value: nil, status: 0) }, id: { _, _ in XCTFail("Unexpected read"); return ExactAXRead(value: nil, status: 0) }, pause: {}))
        }
    }
}
