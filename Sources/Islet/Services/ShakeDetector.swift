import CoreGraphics
import Foundation

/// Recognises the back-and-forth wiggle of a shaken drag from a stream of cursor x positions.
///
/// It tracks how far the cursor got in its current direction and counts a turn each time it comes
/// back by `minSwing`. Enough turns in a short window is a shake, so a slow drag or a single
/// change of direction never triggers it.
struct ShakeDetector {
    private let minSwing: CGFloat = 36
    private let window: TimeInterval = 0.9
    private let turnsNeeded = 3

    private var started = false
    private var direction: CGFloat = 0
    private var pivot: CGFloat = 0
    private var turns: [TimeInterval] = []

    mutating func reset() {
        started = false
        direction = 0
        turns.removeAll()
    }

    /// Feed each new cursor position; returns true on the move that completes a shake.
    mutating func feed(x: CGFloat, at time: TimeInterval) -> Bool {
        guard started else {
            started = true
            pivot = x
            return false
        }
        if direction == 0 {
            if abs(x - pivot) > 12 {
                direction = x > pivot ? 1 : -1
                pivot = x
            }
            return false
        }
        let progress = (x - pivot) * direction
        if progress > 0 {
            pivot = x
            return false
        }
        guard -progress > minSwing else { return false }
        direction = -direction
        pivot = x
        turns.append(time)
        turns.removeAll { time - $0 > window }
        if turns.count >= turnsNeeded {
            reset()
            return true
        }
        return false
    }
}
