import UIKit

/// The inputs and defaults of Shortcuts' GenerativeGlassView.
struct GlassConfiguration {
    var cornerRadius: CGFloat = 65
    var edgeGlowOpacity: Float = 1
    // Present in the original interface; its render loop uses 0.3 / 0.14 instead.
    var causticOpacity: Float = 0.2
    var causticEdgeMask: Float = 0.85
    var shadowOpacity: Float = 0.15
    var shadowColor: CGColor = UIColor.black.cgColor
    var shadowOffset = CGSize(width: 0, height: 80)
    var shadowRadius: CGFloat = 40
}
