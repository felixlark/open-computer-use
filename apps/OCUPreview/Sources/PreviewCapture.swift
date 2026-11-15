import CoreImage
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// Does not contain any input or display-placement capability.
final class PreviewCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let frames = PreviewLatestFrame()
    private let queue = DispatchQueue(label: "ocu.preview.frames", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let failure: @Sendable (String) -> Void

    init(failure: @escaping @Sendable (String) -> Void) { self.failure = failure }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixels = buffer.imageBuffer else { return }
        let source = CIImage(cvPixelBuffer: pixels)
        if let image = context.createCGImage(source, from: source.extent) { frames.put(image) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failure(error.localizedDescription)
    }

    func makeStream(display: SCDisplay, excluding windows: [SCWindow]) throws -> SCStream {
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        // Preview pacing, not an automation limit; the latest frame replaces old ones.
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = false
        config.showsCursor = true
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: windows),
                              configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        return stream
    }
}
