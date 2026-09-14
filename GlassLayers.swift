import UIKit
import QuartzCore

/// The Core Animation layer graph used by Shortcuts, built without WorkflowEditor.
@MainActor
final class GlassLayers {
    let sdfSource = CALayer()
    let sdfElement = GlassLayers.makeLayer("CASDFElementLayer")
    let shadowRing = CALayer()
    let backdrop = GlassLayers.makeLayer("CABackdropLayer")
    let sdfOutput = GlassLayers.makeLayer("CASDFLayer")
    let sdfOutputPortal = GlassLayers.makeLayer("CAPortalLayer")
    let edgeContainer = CALayer()
    let edgeGroup = CALayer()
    let sdfGradient = GlassLayers.makeLayer("CASDFLayer")
    let edgePortal = GlassLayers.makeLayer("CAPortalLayer")
    let borderGradient = CAGradientLayer()
    let borderMask = CALayer()

    init(root: CALayer, causticLayer: CAMetalLayer) {
        sdfElement.setValue("bounds", forKey: "mode")
        sdfElement.setValue("union", forKey: "operation")
        sdfSource.addSublayer(sdfElement)

        backdrop.masksToBounds = true
        backdrop.filters = [
            Self.makeFilter("glassBackground", name: "glassFilter", values: [
                "inputSourceSublayerName": "sdf output",
                "inputInnerRefractionHeight": 117,
                "inputInnerRefractionAmount": 0,
                "inputOuterRefractionHeight": 25,
                "inputOuterRefractionAmount": -6,
                "inputRefractionDistance0": 10,
                "inputRefractionDistance1": 10,
                "inputRefractionOpacity": 0,
                "inputBlurRadius": 0,
                "inputBleedAmount": 0,
                "inputBleedSaturation": 1.2,
                "inputShadowOpacity": 0,
                "inputBleedOpacity": 0
            ]),
            Self.makeFilter("colorBrightness", name: "brightnessFilter", values: ["inputAmount": 0.04])
        ]
        sdfOutput.name = "sdf output"
        sdfOutput.setValue(Self.makeObject("CASDFOutputEffect"), forKey: "effect")
        sdfOutput.setValue(100, forKey: "smoothness")
        connectPortal(sdfOutputPortal, to: sdfOutput)
        backdrop.addSublayer(sdfOutput)

        edgeContainer.allowsGroupOpacity = false
        edgeGroup.allowsGroupOpacity = false
        edgeGroup.compositingFilter = "plusL"
        edgeGroup.filters = [Self.makeFilter("colorSaturate", values: ["inputAmount": 0.5])]
        sdfGradient.setValue(100, forKey: "smoothness")
        sdfGradient.setValue("high", forKey: "preferredDynamicRange")
        connectPortal(edgePortal, to: sdfGradient)
        edgeGroup.addSublayer(sdfGradient)
        edgeContainer.addSublayer(edgeGroup)

        let bright = UIColor(white: 1.2, alpha: 1).cgColor
        let clear = UIColor(white: 1.2, alpha: 0).cgColor
        borderGradient.colors = [bright, clear, clear, clear, bright]
        borderGradient.locations = [0, 0.2, 0.5, 0.8, 1]
        borderGradient.startPoint = CGPoint(x: 0.5, y: 0)
        borderGradient.endPoint = CGPoint(x: 0.5, y: 1)
        borderGradient.opacity = 0.8
        borderMask.backgroundColor = UIColor.clear.cgColor
        borderMask.borderColor = UIColor.black.cgColor
        borderMask.borderWidth = 1
        borderGradient.mask = borderMask

        for layer in [sdfSource, shadowRing, backdrop, edgeContainer, borderGradient, causticLayer] {
            root.addSublayer(layer)
        }
        for layer in [sdfElement, shadowRing, backdrop, borderMask] {
            layer.cornerCurve = .continuous
        }
    }

    func apply(_ configuration: GlassConfiguration, dark: Bool) {
        edgeContainer.opacity = configuration.edgeGlowOpacity
        shadowRing.borderWidth = configuration.shadowRadius * 2
        shadowRing.filters = [Self.makeFilter("gaussianBlur", values: ["inputRadius": configuration.shadowRadius])]
        updateColor(configuration.shadowColor, dark: dark)
    }

    func updateColor(_ color: CGColor, dark: Bool) {
        shadowRing.backgroundColor = dark ? color : color.copy(alpha: color.alpha * 0.2)
        shadowRing.borderColor = dark ? UIColor.clear.cgColor : color

        let gradient = Self.makeObject("CASDFGradientEffect")
        gradient.setValue([
            UIColor(white: 1.05, alpha: 0).cgColor,
            color.copy(alpha: color.alpha * 0.2)!,
            color.copy(alpha: color.alpha * 0.3)!
        ], forKey: "colors")
        gradient.setValue([-20, 0, 1], forKey: "distances")
        gradient.setValue([
            CAMediaTimingFunction(controlPoints: 0.42, 0, 0.94062, 0.44027),
            CAMediaTimingFunction(controlPoints: 0, 0, 0.10841, 1.0022)
        ], forKey: "interpolations")
        gradient.setValue(false, forKey: "premultiplied")
        sdfGradient.setValue(gradient, forKey: "effect")
    }

    func layout(in bounds: CGRect, configuration: GlassConfiguration, radius: CGFloat, dark: Bool) {
        // The source layer stays at zero size. Its portals position the SDF element.
        for layer in [sdfElement, backdrop, sdfOutput, sdfOutputPortal, edgeContainer, edgeGroup, sdfGradient, edgePortal, borderGradient, borderMask] {
            layer.frame = bounds
        }
        shadowRing.bounds = bounds
        shadowRing.position = CGPoint(x: bounds.midX + configuration.shadowOffset.width, y: bounds.midY + configuration.shadowOffset.height * (dark ? 0.7 : 1))
        shadowRing.transform = CATransform3DMakeScale(dark ? 0.65 : 0.95, dark ? 0.9 : 1.1, 1)
        updateRadius(radius, dark: dark)
    }

    func updateRadius(_ radius: CGFloat, dark: Bool) {
        for layer in [sdfElement, backdrop, borderMask] {
            layer.cornerRadius = radius
        }
        shadowRing.cornerRadius = radius * (dark ? 1.9 : 1)
    }

    private func connectPortal(_ portal: CALayer, to destination: CALayer) {
        portal.setValue(sdfSource, forKey: "sourceLayer")
        portal.setValue(true, forKey: "hidesSourceLayer")
        portal.setValue(true, forKey: "matchesPosition")
        portal.setValue(true, forKey: "matchesTransform")
        destination.addSublayer(portal)
    }

    // These QuartzCore classes have no public Swift declarations.
    private static func makeLayer(_ name: String) -> CALayer {
        guard let type = NSClassFromString(name) as? CALayer.Type else {
            fatalError("Missing Core Animation class: \(name)")
        }
        return type.init()
    }

    private static func makeObject(_ name: String) -> NSObject {
        guard let type = NSClassFromString(name) as? NSObject.Type else {
            fatalError("Missing Core Animation class: \(name)")
        }
        return type.init()
    }

    private static func makeFilter(_ type: String, name: String? = nil, values: [String: Any]) -> NSObject {
        let factory = NSClassFromString("CAFilter") as! NSObject.Type
        let filter = factory.perform(NSSelectorFromString("filterWithType:"), with: type)!.takeUnretainedValue() as! NSObject
        if let name { filter.setValue(name, forKey: "name") }
        for (key, value) in values { filter.setValue(value, forKey: key) }
        return filter
    }
}
