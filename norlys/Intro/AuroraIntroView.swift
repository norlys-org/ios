import MetalKit
import UIKit

/// Mirrors `IntroUniforms` in AuroraIntro.metal
private struct IntroUniforms {
    var canvas: SIMD4<Float>
    var liquify: SIMD4<Float>
    var bands: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var bandAngles: SIMD4<Float>
    var bandOpacity: SIMD4<Float>
}

/**
 * The website's opening aurora, drawn with Metal (see AuroraIntro.metal for the passes).
 *
 * The scene's layout and its `appear` states are reproduced from norlys-animation.json: sizes are
 * in points, as the site's canvas measures them in CSS pixels, and every pass runs at the
 * resolution the scene gives it, relative to the site's mobile `dpi` of 0.75.
 */
final class AuroraIntroView: MTKView {
    private struct Band {
        /// Fractions of the canvas
        let left: Float
        let top: Float
        /// Points
        let width: Float
        let height: (Double) -> Float
        /// Turns
        let rotation: Float
    }

    /// The site's mobile scene resolution
    private static let dpi: CGFloat = 0.75

    private static let bands: [Band] = [
        Band(left: -0.07708333333333334, top: 0.4725801564815699, width: 1616.9,
             height: { Float(appear(from: 125.7, to: 200, at: $0, delay: -600)) }, rotation: 0.4995),
        Band(left: -0.06016454670850599, top: 0.519951690821256, width: 1616.9,
             height: { Float(appear(from: 0, to: 45.4, at: $0, delay: 500)) }, rotation: 0.5535),
        Band(left: -0.01597222222222222, top: 0.4688888888888889, width: 1616.9,
             height: { Float(appear(from: 0, to: 11.8, at: $0, delay: 250)) }, rotation: 0.4995),
        Band(left: -0.01579114004953941, top: 0.45666585405396065, width: 1616.9,
             height: { Float(appear(from: 0, to: 24, at: $0, delay: 250, ease: easeInOutExpo)) }, rotation: 0.5)
    ]

    private struct Pipelines {
        let liquify: MTLRenderPipelineState
        let noiseBlur: MTLRenderPipelineState
        let brightAreas: MTLRenderPipelineState
        let rays: MTLRenderPipelineState
        let composite: MTLRenderPipelineState
    }

    private let commandQueue: MTLCommandQueue
    /// Compiled off the main thread, which is busy starting the web view; nothing draws until then
    private var pipelines: Pipelines?

    /// Called once, on the main thread, when the first frame is on screen
    var onFirstFrame: (() -> Void)?

    private var targets: (liquify: MTLTexture, blurFirst: MTLTexture, blurSecond: MTLTexture,
                          bright: MTLTexture, rays: MTLTexture)?

    private var startTime: CFTimeInterval?
    /// Where the liquify clock starts, picked at random as the site does on every load
    private let timeSeed = Float.random(in: 0..<500)
    /// Brightness of the whole scene: halved at night on the reader's clock, like the site
    private let brightness: Float = {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 || hour < 7 ? 0.5 : 1
    }()

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device,
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }

        self.commandQueue = commandQueue
        let colorFormat = MTLPixelFormat.bgra8Unorm
        super.init(frame: .zero, device: device)
        colorPixelFormat = colorFormat
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        backgroundColor = .black
        isOpaque = true
        preferredFramesPerSecond = 60
        // Everything is blurred to the softness of the site's own canvas, so full resolution would
        // only cost the GPU while the web view is trying to start
        contentScaleFactor = min(UIScreen.main.scale, 2)
        isUserInteractionEnabled = false
        delegate = self

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let pipelines = Self.makePipelines(device: device, library: library, colorFormat: colorFormat)
            DispatchQueue.main.async { self?.pipelines = pipelines }
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makePipelines(
        device: MTLDevice,
        library: MTLLibrary,
        colorFormat: MTLPixelFormat
    ) -> Pipelines? {
        let targetFormat = MTLPixelFormat.rgba16Float
        func pipeline(_ fragment: String, format: MTLPixelFormat) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "introVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = format
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                print("❌ Aurora intro: \(fragment) did not build:", error)
                return nil
            }
        }

        guard let liquify = pipeline("introLiquify", format: targetFormat),
              let noiseBlur = pipeline("introNoiseBlur", format: targetFormat),
              let brightAreas = pipeline("introBrightAreas", format: targetFormat),
              let rays = pipeline("introRays", format: targetFormat),
              let composite = pipeline("introComposite", format: colorFormat) else { return nil }

        return Pipelines(
            liquify: liquify,
            noiseBlur: noiseBlur,
            brightAreas: brightAreas,
            rays: rays,
            composite: composite
        )
    }

    // MARK: - Timing

    /// The value an `appear` state holds `time` milliseconds in, as the Unicorn runtime eases it
    private static func appear(
        from: Double,
        to: Double,
        at time: Double,
        delay: Double,
        duration: Double = 2000,
        ease: (Double) -> Double = easeInOutCubic
    ) -> Double {
        let progress = max(0, min(1, (time - delay) / duration))
        return from + (to - from) * ease(progress)
    }

    private static func easeInOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func easeInOutExpo(_ t: Double) -> Double {
        if t == 0 || t == 1 { return t }
        return t < 0.5 ? pow(2, 20 * t - 10) / 2 : (2 - pow(2, -20 * t + 10)) / 2
    }

    private func uniforms(at elapsed: Double) -> IntroUniforms {
        let size = bounds.size
        let width = Float(size.width)
        let height = Float(size.height)

        // The runtime advances the clock by `speed` each frame at 60 fps
        let liquifySpeed: Float = 0.11
        let time = timeSeed + Float(elapsed / 1000) * liquifySpeed * 60
        let progress = Self.appear(from: 0, to: 1, at: elapsed, delay: -600)

        let geometry = Self.bands.map { band -> SIMD4<Float> in
            SIMD4(band.left * width, band.top * height, band.width, band.height(elapsed))
        }

        return IntroUniforms(
            canvas: SIMD4(width, height, time, brightness),
            liquify: SIMD4(
                Float(0.25 + (0.7 - 0.25) * progress),
                Float(0.3 + (0.45 - 0.3) * progress),
                Float(-0.5 + progress),
                // The runtime hands a position to GL with its y turned over
                Float(1 - (-0.5 + progress))
            ),
            bands: (geometry[0], geometry[1], geometry[2], geometry[3]),
            bandAngles: SIMD4(Self.bands.map { $0.rotation * 2 * .pi }),
            bandOpacity: SIMD4(Float(0.5 + 0.5 * progress), 0, 0, 0)
        )
    }

    // MARK: - Targets

    private func makeTargets() {
        guard let device, bounds.width > 0, bounds.height > 0 else { return }

        func texture(_ scale: CGFloat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: max(1, Int(bounds.width * Self.dpi * scale)),
                height: max(1, Int(bounds.height * Self.dpi * scale)),
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)
        }

        // Each pass at the scale the scene's `downSample` gives it
        guard let liquify = texture(1),
              let blurFirst = texture(0.25),
              let blurSecond = texture(0.5),
              let bright = texture(1),
              let rays = texture(0.5) else { return }
        targets = (liquify, blurFirst, blurSecond, bright, rays)
    }
}

extension AuroraIntroView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        makeTargets()
    }

    func draw(in view: MTKView) {
        guard let pipelines else { return }
        if targets == nil { makeTargets() }
        guard let targets,
              let drawable = currentDrawable,
              let finalPass = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // The scene's clock starts with its first frame, not with the view
        let now = CACurrentMediaTime()
        let start = startTime ?? now
        let isFirstFrame = startTime == nil
        startTime = start
        var uniforms = uniforms(at: (now - start) * 1000)

        func pass(
            _ pipeline: MTLRenderPipelineState,
            into target: MTLTexture?,
            reading sources: [MTLTexture]
        ) {
            let descriptor: MTLRenderPassDescriptor
            if let target {
                descriptor = MTLRenderPassDescriptor()
                descriptor.colorAttachments[0].texture = target
                descriptor.colorAttachments[0].loadAction = .dontCare
                descriptor.colorAttachments[0].storeAction = .store
            } else {
                descriptor = finalPass
            }
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<IntroUniforms>.stride, index: 0)
            for (index, source) in sources.enumerated() {
                encoder.setFragmentTexture(source, index: index)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        pass(pipelines.liquify, into: targets.liquify, reading: [])
        pass(pipelines.noiseBlur, into: targets.blurFirst, reading: [targets.liquify])
        pass(pipelines.noiseBlur, into: targets.blurSecond, reading: [targets.blurFirst])
        pass(pipelines.brightAreas, into: targets.bright, reading: [targets.blurSecond])
        pass(pipelines.rays, into: targets.rays, reading: [targets.bright])
        pass(pipelines.composite, into: nil, reading: [targets.rays, targets.blurSecond])

        commandBuffer.present(drawable)
        if isFirstFrame {
            commandBuffer.addCompletedHandler { [weak self] _ in
                DispatchQueue.main.async {
                    self?.onFirstFrame?()
                    self?.onFirstFrame = nil
                }
            }
        }
        commandBuffer.commit()
    }
}
