import UIKit
import QuartzCore

/// A local reconstruction of Shortcuts' glass component.
/// The host supplies geometry and color through the original configuration fields.
@MainActor
final class GenerativeGlassView: UIView {
    var configuration = GlassConfiguration() {
        didSet { applyConfiguration() }
    }

    private let renderer = CausticRenderer()
    private var layers: GlassLayers!
    private var displayLink: CADisplayLink?
    private var glow = SpringAnimator(value: 0, stiffness: 120, damping: 18, settlementThreshold: 0.01)
    private var radius = SpringAnimator(value: 65, stiffness: 180, damping: 20, settlementThreshold: 0.5)
    private var dark: Bool { traitCollection.userInterfaceStyle == .dark }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        layers = GlassLayers(root: layer, causticLayer: renderer.layer)
        applyConfiguration()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: GenerativeGlassView, _) in
            self.applyConfiguration()
        }
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(frame:).")
    }

    func setCausticEnabled(_ enabled: Bool) {
        glow.target = enabled ? 1 : 0
        startRendering()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopRendering()
        } else {
            startRendering()
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cornerRadius = CGFloat(radius.current)
        layers.layout(in: bounds, configuration: configuration, radius: cornerRadius, dark: dark)
        renderer.resize(to: bounds, scale: traitCollection.displayScale)
        renderer.layer.cornerRadius = cornerRadius
        CATransaction.commit()
    }

    private func applyConfiguration() {
        // Assigning the configuration snaps radius and color, as in the original setter.
        radius = SpringAnimator(value: Float(configuration.cornerRadius), stiffness: 180, damping: 20, settlementThreshold: 0.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers.apply(configuration, dark: dark)
        layers.shadowRing.opacity = configuration.shadowOpacity + glow.current * (dark ? 0.01 : 0.1)
        CATransaction.commit()
        setNeedsLayout()
    }

    private func startRendering() {
        guard window != nil, displayLink == nil else { return }
        let target = DisplayLinkTarget(owner: self)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func render(_ link: CADisplayLink) {
        let deltaTime = link.targetTimestamp > link.timestamp ? Float(link.targetTimestamp - link.timestamp) : 1 / 60
        radius.step(deltaTime)
        glow.step(deltaTime)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers.updateRadius(CGFloat(radius.current), dark: dark)
        layers.shadowRing.opacity = configuration.shadowOpacity + glow.current * (dark ? 0.01 : 0.1)
        renderer.layer.cornerRadius = CGFloat(radius.current)
        renderer.layer.opacity = glow.current
        CATransaction.commit()

        renderer.render(cornerRadius: CGFloat(radius.current), edgeMask: configuration.causticEdgeMask, intensity: glow.current, dark: dark)
        if glow.settled && glow.current < 0.01 && radius.settled {
            stopRendering()
        }
    }
}

/// CADisplayLink retains its target. This proxy lets the view leave the hierarchy.
@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var owner: GenerativeGlassView?

    init(owner: GenerativeGlassView) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else {
            link.invalidate()
            return
        }
        owner.render(link)
    }
}
