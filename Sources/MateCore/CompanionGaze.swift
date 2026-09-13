import Foundation

/// Calms normalized face positions without retaining camera frames or identity.
/// Supply monotonic seconds, for example ProcessInfo.processInfo.systemUptime.
public struct CompanionGaze: Sendable {
    public struct Position: Equatable, Sendable {
        public let x: Double
        public let y: Double
    }

    public private(set) var position = Position(x: 0, y: 0)
    private var target = Position(x: 0, y: 0)
    private var updatedAt: TimeInterval?
    private var lastFaceAt: TimeInterval?
    private static let timeConstant = 0.28
    private static let deadband = 0.02
    private static let maximumSpeed = 1.5
    private static let lossHold = 0.6
    // A delayed callback must not turn into a single large jump.
    private static let maximumStepTime = 0.1

    public init() {}

    @discardableResult
    public mutating func update(x: Double?, y: Double?, now: TimeInterval) -> Position {
        guard now.isFinite, updatedAt.map({ now > $0 }) ?? true else { return position }
        let previousTime = updatedAt
        updatedAt = now

        let hasFace: Bool
        if let x, let y, x.isFinite, y.isFinite {
            let candidate = Position(x: max(-1, min(1, x)), y: max(-1, min(1, y)))
            if lastFaceAt == nil || hypot(candidate.x - target.x, candidate.y - target.y) > Self.deadband {
                target = candidate
            }
            lastFaceAt = now
            hasFace = true
        } else {
            hasFace = false
        }

        guard let previousTime else { return position }
        var elapsed = now - previousTime
        let destination: Position
        if hasFace {
            destination = target
        } else {
            guard let lastFaceAt, now - lastFaceAt > Self.lossHold else { return position }
            // Count only time after the hold expires, even when it falls between frames.
            elapsed = now - max(previousTime, lastFaceAt + Self.lossHold)
            destination = Position(x: 0, y: 0)
        }

        let dt = min(Self.maximumStepTime, max(0, elapsed))
        let blend = 1 - exp(-dt / Self.timeConstant)
        let dx = (destination.x - position.x) * blend
        let dy = (destination.y - position.y) * blend
        let distance = hypot(dx, dy)
        let maximumDistance = Self.maximumSpeed * dt
        let scale = distance > maximumDistance && distance > 0 ? maximumDistance / distance : 1
        position = Position(x: position.x + dx * scale, y: position.y + dy * scale)
        return position
    }

    /// Explicit stop clears both visible gaze and tracking history immediately.
    public mutating func reset() {
        position = Position(x: 0, y: 0)
        target = Position(x: 0, y: 0)
        updatedAt = nil
        lastFaceAt = nil
    }
}
