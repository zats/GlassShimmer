/// The semi-implicit Euler step and settlement rule used by Shortcuts.
struct SpringAnimator {
    var target: Float {
        didSet { settled = false }
    }
    private(set) var current: Float
    private(set) var velocity: Float = 0
    private(set) var settled = true
    let stiffness: Float
    let damping: Float
    let settlementThreshold: Float

    init(value: Float, stiffness: Float, damping: Float, settlementThreshold: Float) {
        target = value
        current = value
        self.stiffness = stiffness
        self.damping = damping
        self.settlementThreshold = settlementThreshold
    }

    mutating func step(_ deltaTime: Float) {
        guard !settled else { return }
        let force = -damping * velocity - stiffness * (current - target)
        velocity += deltaTime * force
        current += deltaTime * velocity
        if abs(current - target) < settlementThreshold && abs(velocity) < settlementThreshold {
            current = target
            velocity = 0
            settled = true
        }
    }
}
