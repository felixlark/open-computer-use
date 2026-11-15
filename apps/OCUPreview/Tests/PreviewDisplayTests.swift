import CoreGraphics
import XCTest
@testable import OCUPreview

final class PreviewDisplayTests: XCTestCase {
    func testDiscoveryNeverAcceptsPhysicalMainOrMirroredDisplay() {
        XCTAssertTrue(PreviewDisplay.accepts(vendor: 3244, model: 3244, serial: 1, isMain: false, isMirrored: false))
        XCTAssertFalse(PreviewDisplay.accepts(vendor: 1552, model: 3244, serial: 1, isMain: false, isMirrored: false))
        XCTAssertFalse(PreviewDisplay.accepts(vendor: 3244, model: 1, serial: 1, isMain: false, isMirrored: false))
        XCTAssertFalse(PreviewDisplay.accepts(vendor: 3244, model: 3244, serial: 0, isMain: false, isMirrored: false))
        XCTAssertFalse(PreviewDisplay.accepts(vendor: 3244, model: 3244, serial: 1, isMain: true, isMirrored: false))
        XCTAssertFalse(PreviewDisplay.accepts(vendor: 3244, model: 3244, serial: 1, isMain: false, isMirrored: true))
    }

    func testDisconnectedSelectionDoesNotFallBackToAnotherOwnerOrReusedID() {
        let selected = PreviewDisplay(id: 10, serial: 123)
        let reusedID = PreviewDisplay(id: 10, serial: 456)
        let reconnect = PreviewDisplay(id: 20, serial: 123)
        XCTAssertNil(PreviewDisplay.selected(in: [], serial: nil))
        XCTAssertEqual(PreviewDisplay.selected(in: [selected], serial: nil), selected)
        XCTAssertNil(PreviewDisplay.selected(in: [reusedID], serial: selected.serial))
        XCTAssertEqual(PreviewDisplay.selected(in: [reusedID, reconnect], serial: selected.serial), reconnect)
    }

    func testFrameHandoffKeepsOnlyNewestAndClearsOnClose() throws {
        func image(width: Int) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: 2,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let frames = PreviewLatestFrame()
        frames.put(try image(width: 2)); frames.put(try image(width: 4))
        XCTAssertEqual(frames.take()?.width, 4)
        XCTAssertNil(frames.take())
        frames.put(try image(width: 8)); frames.clear()
        XCTAssertNil(frames.take())
    }
}
