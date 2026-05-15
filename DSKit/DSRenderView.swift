import SwiftUI
import MetalKit

public enum DSScreenMode {
    case topOnly
    case bottomOnly
    case both
}

public struct DSRenderView: UIViewRepresentable {
    public let renderer: DSRenderer
    public var screenMode: DSScreenMode = .both
    public var acceptsNativeTouch: Bool = true
    
    public init(renderer: DSRenderer, screenMode: DSScreenMode = .both, acceptsNativeTouch: Bool = true) {
        self.renderer = renderer
        self.screenMode = screenMode
        self.acceptsNativeTouch = acceptsNativeTouch
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = DSTouchMTKView(screenMode: screenMode, acceptsNativeTouch: acceptsNativeTouch)
        mtkView.device = renderer.device
        mtkView.delegate = renderer
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = true 
        mtkView.isPaused = true 
        
        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.contentMode = .scaleToFill
        mtkView.isUserInteractionEnabled = acceptsNativeTouch
        mtkView.isMultipleTouchEnabled = true
        
        // Registrar vista en el renderer
        renderer.registerMTKView(mtkView)
        // renderer.screenMode = screenMode // [FIX] Don't overwrite global state!
        
        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
    }
}

public class DSRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState?
    var texture: MTLTexture?
    weak var mtkView: MTKView?
    var screenMode: DSScreenMode = .both
    
    // Array de vistas para renderizar a múltiples pantallas
    private var mtkViews: NSHashTable<MTKView> = NSHashTable.weakObjects()
    
    // Para renderizar a múltiples vistas
    static var sharedTexture: MTLTexture? = nil
    static var sharedDevice: MTLDevice? = nil 
    
    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("[DSRenderer] Metal no soportado en este dispositivo")
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        mtkView = nil 
        super.init()
        
        buildPipeline()
        DSRenderer.initSamplers(device: device)
    }
    
    // Samplers
    static var nearestSampler: MTLSamplerState?
    static var linearSampler: MTLSamplerState?
    static var currentSamplerState: MTLSamplerState?
    
    // Filter Modes: 0 = None, 1 = LCD Grid
    static var currentFilterMode: UInt32 = 0
    
    static func initSamplers(device: MTLDevice) {
        let nearestDesc = MTLSamplerDescriptor()
        nearestDesc.minFilter = .nearest
        nearestDesc.magFilter = .nearest
        nearestSampler = device.makeSamplerState(descriptor: nearestDesc)
        
        let linearDesc = MTLSamplerDescriptor()
        linearDesc.minFilter = .linear
        linearDesc.magFilter = .linear
        linearSampler = device.makeSamplerState(descriptor: linearDesc)
        
        currentSamplerState = nearestSampler // Default
    }
    
    static func setFilterOnly(linear: Bool) {
        currentSamplerState = linear ? linearSampler : nearestSampler
    }
    
    // Registrar una vista para renderizar
    func registerMTKView(_ view: MTKView) {
        mtkView = view
        mtkViews.add(view)
    }
    
    func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else { 
            print("❌ [DSRenderer] Failed to load Default Metal Library")
            return 
        }
        
        guard let vertexFunc = library.makeFunction(name: "ds_vertex"),
              let fragmentFunc = library.makeFunction(name: "ds_fragment") else {
            print("❌ [DSRenderer] Shaders 'ds_vertex' or 'ds_fragment' not found in library")
            return
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            print("✅ [DSRenderer] Pipeline State Created Successfully")
        } catch {
            print("[DSRenderer] Error compilando pipeline: \(error)")
        }
    }
    
    var currentPixelFormat: MTLPixelFormat = .b5g6r5Unorm // Default start
    
    func updateTexture(width: Int, height: Int, pitch: Int, data: UnsafeRawPointer) {
        let pixelFormat = self.currentPixelFormat
        
        // Crear o actualizar textura propia (no compartida)
        if texture == nil || texture?.width != width || texture?.height != height || texture?.pixelFormat != pixelFormat {
            print("[DSRenderer] METAL: Creada nueva textura de \(width)x\(height) fmt=\(pixelFormat.rawValue)")
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            texture = device.makeTexture(descriptor: desc)
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture?.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: pitch)
        
        DispatchQueue.main.async {
            // Actualizar todas las vistas registradas
            for view in self.mtkViews.allObjects {
                view.setNeedsDisplay()
            }
            // También intentar actualizar la vista principal si existe
            self.mtkView?.setNeedsDisplay()
        }
    }
    
    public func draw(in view: MTKView) {
        guard let pipelineState = pipelineState else { return }
        guard let drawable = view.currentDrawable else { return }
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        encoder.setRenderPipelineState(pipelineState)
        encoder.setCullMode(.none) 
        
        if let texture = texture {
            encoder.setFragmentTexture(texture, index: 0)
            
            // Determine Screen Mode based on View context
            var activeMode: DSScreenMode = self.screenMode // Default fallback
            if let touchView = view as? DSTouchMTKView {
                activeMode = touchView.screenMode
            }
            
            // Send screen mode to shader
            var mode: UInt32 = activeMode == .topOnly ? 0 : (activeMode == .bottomOnly ? 1 : 2)
            encoder.setFragmentBytes(&mode, length: MemoryLayout<UInt32>.size, index: 0)
            
            // Send filter mode
            var fMode: UInt32 = DSRenderer.currentFilterMode
            encoder.setFragmentBytes(&fMode, length: MemoryLayout<UInt32>.size, index: 1)
            
            // Set Sampler
            encoder.setFragmentSamplerState(DSRenderer.currentSamplerState ?? DSRenderer.nearestSampler, index: 0)
            
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

class DSTouchMTKView: MTKView {
    var screenMode: DSScreenMode = .both
    var acceptsNativeTouch: Bool = true
    private var lastTouchCaptureLogAt: TimeInterval = 0
    
    init(screenMode: DSScreenMode = .both, acceptsNativeTouch: Bool = true) {
        super.init(frame: .zero, device: nil)
        self.screenMode = screenMode
        self.acceptsNativeTouch = acceptsNativeTouch
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.screenMode = .both
        self.acceptsNativeTouch = true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouch(touches)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouch(touches)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "MTKTouchEnded")
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "MTKTouchCancelled")
    }
    
    private func handleTouch(_ touches: Set<UITouch>) {
        guard acceptsNativeTouch else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if DSInput.debugTouchLogsEnabled {
            let now = Date.timeIntervalSinceReferenceDate
            if now - lastTouchCaptureLogAt > 0.08 {
                print("📲 [MTKTouch] mode=\(screenMode) loc=(\(Int(location.x)),\(Int(location.y))) size=(\(Int(bounds.width)),\(Int(bounds.height)))")
                lastTouchCaptureLogAt = now
            }
        }

        updateInput(at: location)
    }
    
    private func updateInput(at point: CGPoint) {
        guard acceptsNativeTouch else { return }
        let viewSize = bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        
        // Handle based on screen mode
        if screenMode == .bottomOnly {
            // [MODIFIED] Stretched Layout: Touch maps directly to view bounds
            // This ensures alignment even if the view is non-uniform or stretched (e.g. by Skin)
            let u = point.x / viewSize.width
            let v = point.y / viewSize.height
            
            if u >= 0 && u <= 1 && v >= 0 && v <= 1 {
                // Map to DS bottom screen coordinates (0-255 for X, 0-191 for Y)
                let finalX = Int16(min(max(u * 255, 0), 255))
                let finalY = Int16(min(max(v * 191, 0), 191))
                DSInput.shared.setTouch(x: finalX, y: finalY, pressed: true, source: "MTK-bottomOnly")
            } else {
                DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "MTK-bottomOnly-outside")
            }
        } else if screenMode == .topOnly {
            // Top screen - no touch support
            DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "MTK-topOnly")
        } else {
            // .both - Original vertical layout
            let viewRatio = viewSize.width / viewSize.height
            let gameRatio: CGFloat = 256.0 / 384.0
            
            var gameRect = CGRect.zero
            
            if viewRatio > gameRatio {
                let w = viewSize.height * gameRatio
                let h = viewSize.height
                let x = (viewSize.width - w) / 2.0
                gameRect = CGRect(x: x, y: 0, width: w, height: h)
            } else {
                let w = viewSize.width
                let h = w / gameRatio
                let y = (viewSize.height - h) / 2.0
                gameRect = CGRect(x: 0, y: y, width: w, height: h)
            }
            
            let px = point.x - gameRect.minX
            let py = point.y - gameRect.minY
            
            let u = px / gameRect.width
            let v = py / gameRect.height
            
            if u >= 0 && u <= 1 && v >= 0 && v <= 1 {
                // Bottom screen is v [0.5, 1.0]
                if v >= 0.5 {
                    let touchV = (v - 0.5) * 2.0
                    let finalX = Int16(min(max(u * 255, 0), 255))
                    let finalY = Int16(min(max(touchV * 191, 0), 191))
                    DSInput.shared.setTouch(x: finalX, y: finalY, pressed: true, source: "MTK-both")
                } else {
                    DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "MTK-both-top")
                }
            } else {
                DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "MTK-both-outside")
            }
        }
    }
}
