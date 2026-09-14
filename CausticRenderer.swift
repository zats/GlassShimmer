import Metal
import QuartzCore

@MainActor
final class CausticRenderer {
    let layer = CAMetalLayer()
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let startTime = CACurrentMediaTime()

    init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal is required to render the glass.")
        }
        self.queue = queue
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = true
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
        layer.compositingFilter = "plusL"
        layer.opacity = 0

        let descriptor = MTLRenderPipelineDescriptor()
        do {
            let library = try device.makeDefaultLibrary(bundle: .main)
            descriptor.vertexFunction = library.makeFunction(name: "causticVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "causticFragment")
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = layer.pixelFormat
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Cannot compile the caustic shader: \(error)")
        }
    }

    func resize(to bounds: CGRect, scale: CGFloat) {
        layer.frame = bounds
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    func render(cornerRadius: CGFloat, edgeMask: Float, intensity: Float, dark: Bool) {
        guard intensity > 0.01, layer.bounds.width > 0, layer.bounds.height > 0,
              let drawable = layer.nextDrawable(), let commandBuffer = queue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let scale = Float(layer.contentsScale)
        var resolution = SIMD2<Float>(Float(layer.bounds.width) * scale, Float(layer.bounds.height) * scale)
        var shape = SIMD4<Float>(resolution.x, resolution.y, Float(cornerRadius) * scale, edgeMask)
        var time = Float(CACurrentMediaTime() - startTime)
        // The original render loop uses these values, despite causticOpacity in its configuration.
        var opacity: Float = (dark ? 0.14 : 0.3) * intensity

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&resolution, length: MemoryLayout.size(ofValue: resolution), index: 0)
        encoder.setFragmentBytes(&shape, length: MemoryLayout.size(ofValue: shape), index: 1)
        encoder.setFragmentBytes(&time, length: MemoryLayout.size(ofValue: time), index: 2)
        encoder.setFragmentBytes(&opacity, length: MemoryLayout.size(ofValue: opacity), index: 3)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
