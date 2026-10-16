import SwiftUI

/// Geometry bookkeeping is deliberately not observable: scrolling must not
/// invalidate the conversation view for every pixel of movement.
final class TimelineViewport {
    var frames: [String: CGRect] = [:]
    var height: CGFloat = 0
    var pendingAnchor: ReadingAnchor?

    struct ReadingAnchor {
        let id: String
        let point: UnitPoint
    }
    func readingAnchor() -> ReadingAnchor? {
        guard height > 1,
              let row = frames.filter({ $0.value.maxY > 0 && $0.value.minY < height })
                .min(by: { $0.value.minY < $1.value.minY }) else { return nil }
        // Each row owns a one-point start target. Its height stays fixed even
        // when a message is taller than, or exactly as tall as, the viewport.
        return ReadingAnchor(id: Self.anchorID(row.key), point: UnitPoint(x: 0, y: row.value.minY / (height - 1)))
    }
    static func anchorID(_ rowID: String) -> String { "message-start-" + rowID }
}
