import Foundation
import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class VirtualDisplayPersistenceTests: XCTestCase {
    func testRestorationUsesDisplayRelativeCoordinatesAndKeepsFallbackAccessible() {
        let original = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let moved = CGRect(x: 1920, y: -548, width: 1920, height: 1080)
        XCTAssertEqual(agentDisplayRestoredPosition(original: CGPoint(x: 1552, y: 40), originalDisplay: original,
                       targetDisplay: moved, windowSize: CGSize(width: 800, height: 600)), CGPoint(x: 1960, y: -508))
        XCTAssertEqual(agentDisplayRestoredPosition(original: CGPoint(x: 3000, y: 1000), originalDisplay: original,
                       targetDisplay: CGRect(x: 0, y: 0, width: 800, height: 600), windowSize: CGSize(width: 1100, height: 800)), .zero)
    }

    func testToolDispatchCannotOvertakeAnInProgressWindowCleanup() {
        final class Holder: @unchecked Sendable {
            let dispatcher = ComputerUseToolDispatcher()
        }
        let holder = Holder()
        let cleanupEntered = DispatchSemaphore(value: 0), releaseCleanup = DispatchSemaphore(value: 0)
        let requestAttempted = DispatchSemaphore(value: 0), requestFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            BackgroundWindowStateTransaction.perform {
                cleanupEntered.signal()
                _ = releaseCleanup.wait(timeout: .now() + 5)
            }
        }
        defer { releaseCleanup.signal() }
        XCTAssertEqual(cleanupEntered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            requestAttempted.signal()
            // Unknown tool performs no GUI work, but uses the real dispatcher.
            _ = try? holder.dispatcher.callTool(name: "missing-test-tool", arguments: [:])
            requestFinished.signal()
        }
        XCTAssertEqual(requestAttempted.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(requestFinished.wait(timeout: .now() + 0.05), .timedOut)
        releaseCleanup.signal()
        XCTAssertEqual(requestFinished.wait(timeout: .now() + 2), .success)
    }

    func testRetentionIsOptInAndIndependentOfEnabledOverride() {
        let document: [String: Any] = ["virtualDisplay": ["enabled": true, "restoreOnSessionEnd": false]]
        XCTAssertTrue(VirtualDisplayConfig.resolve(document: [:], environment: [:]).restoreOnSessionEnd)
        let file = VirtualDisplayConfig.resolve(document: document, environment: [:])
        XCTAssertTrue(file.enabled)
        XCTAssertFalse(file.restoreOnSessionEnd)
        let enabledOverride = VirtualDisplayConfig.resolve(document: document, environment: [VirtualDisplayConfig.environmentKey: "true"])
        XCTAssertFalse(enabledOverride.restoreOnSessionEnd, "enabled override must not discard the retention setting")
        XCTAssertTrue(VirtualDisplayConfig.resolve(document: document, environment: [VirtualDisplayConfig.restoreEnvironmentKey: "true"]).restoreOnSessionEnd)
        XCTAssertFalse(VirtualDisplayConfig.resolve(document: [:], environment: [VirtualDisplayConfig.restoreEnvironmentKey: "false"]).restoreOnSessionEnd)
        for value in ["1", "yes", "", "FALSE"] {
            XCTAssertTrue(VirtualDisplayConfig.resolve(document: document, environment: [VirtualDisplayConfig.restoreEnvironmentKey: value]).restoreOnSessionEnd)
        }
        for value in [0, "false", NSNull(), [], [:]] as [Any] {
            XCTAssertTrue(VirtualDisplayConfig.resolve(document: ["virtualDisplay": ["restoreOnSessionEnd": value]], environment: [:]).restoreOnSessionEnd)
        }
        XCTAssertTrue(OCUConfiguration.environmentKeys.contains(VirtualDisplayConfig.restoreEnvironmentKey))
    }

    func testStopNotificationsShareSocketIdentityWithoutReachingLegacyListeners() {
        func name(_ namespace: String?) -> Notification.Name {
            openComputerUseTurnEndedNotification(forSocketFileName: openComputerUseAppAgentSocketFileName(namespace: namespace))
        }
        XCTAssertEqual(name(nil), openComputerUseTurnEndedNotificationName)
        XCTAssertEqual(name("  "), name(nil))
        XCTAssertNotEqual(name("persistent-display"), name(nil))
        XCTAssertNotEqual(name("persistent-display"), name("orange"))
        XCTAssertEqual(name(" persistent-display "), name("persistent-display"))
    }

    func testDisplayIdentityPreservesLegacyAndSeparatesStableNamespaces() {
        XCTAssertEqual(agentDisplaySerialNumber(namespace: nil), 1)
        XCTAssertEqual(agentDisplaySerialNumber(namespace: " "), 1)
        XCTAssertNotEqual(agentDisplaySerialNumber(namespace: "persistent-display"), 1)
        XCTAssertNotEqual(agentDisplaySerialNumber(namespace: "persistent-display"), agentDisplaySerialNumber(namespace: "orange"))
        XCTAssertEqual(agentDisplaySerialNumber(namespace: " persistent-display "), agentDisplaySerialNumber(namespace: "persistent-display"))
    }

    func testRetainedPinsSurviveSessionCleanupAndStaleIDsAreForgotten() {
        final class FakeSPI: WindowOcclusionControlling {
            let occlusionCapability = SkyLightSPICapability(missingSymbols: [], feature: "occlusion")
            var states: [CGWindowID: Bool] = [:]
            var calls: [CGWindowID] = []
            func setWindowOcclusionNotificationsEnabled(_ enabled: Bool, windowID: CGWindowID) throws -> Bool {
                calls.append(windowID)
                let before = states[windowID] ?? true
                states[windowID] = enabled
                return before
            }
        }
        let pins = WindowOcclusionKeepAlive(), spi = FakeSPI()
        let bounds = CGRect(x: -20000, y: -20000, width: 10, height: 10)
        XCTAssertTrue(pins.keepVisible(windowID: 101, bounds: bounds, spi: spi))
        XCTAssertTrue(pins.keepVisible(windowID: 102, bounds: bounds, spi: spi))
        pins.releaseAll(excluding: [101], spi: spi)
        XCTAssertTrue(pins.isPinned(windowID: 101))
        XCTAssertFalse(pins.isPinned(windowID: 102))
        XCTAssertEqual(spi.states[101], false)
        XCTAssertEqual(spi.states[102], true)
        let before = spi.calls
        pins.forget(windowIDs: [101])
        pins.releaseAll(spi: spi)
        XCTAssertEqual(spi.calls, before, "do not restore stale state onto a replacement window")
        XCTAssertFalse(pins.isPinned(windowID: 101))
    }
}
