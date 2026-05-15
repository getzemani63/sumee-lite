import SwiftUI
import Combine

// Gestor de Estado de Layout (Singleton) - Compartido entre vistas
public class DSScreenLayoutManager: ObservableObject {
    public static let shared = DSScreenLayoutManager()
    
    public enum LayoutMode: String, Codable {
        case standard   // Lado a lado (50/50)
        case hybrid     // Izquierda Grande, Derecha Pequeña
        case singleTop  // Solo Pantalla Superior
        case singleBottom // Solo Pantalla Inferior
        
        mutating func next() {
            switch self {
            case .standard: self = .hybrid
            case .hybrid: self = .singleTop
            case .singleTop: self = .singleBottom
            case .singleBottom: self = .standard
            }
        }
    }
    
    @Published public var layoutMode: LayoutMode = .standard {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: "DSLayoutMode")
        }
    }
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "DSLayoutMode"),
           let mode = LayoutMode(rawValue: saved) {
            self.layoutMode = mode
        }
    }
}

public struct DSScreensLayout: View {
    @ObservedObject var core: DSCore
    @ObservedObject var layoutManager = DSScreenLayoutManager.shared
    @ObservedObject var skinManager = DSSkinManager.shared // New Skin Manager
    @ObservedObject var input = DSInput.shared // Observe controller state
    @ObservedObject var controlManager = DSControlManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    // [NEW] Gesture State for Edit Mode
    @State private var gestureStartOffset: CGPoint?
    @State private var gestureStartScale: CGFloat?
    
    // Animation States
    @State private var isLedOn = false
    @State private var isLogoOn = false
    @State private var isScreenOn = false
    
    // Computed Glow Color (User Requested Red)
    private var glowColor: Color {
        return .red
    }
    
    // Console Name for Light Mode
    private var consoleDisplayName: String {
        return "NINTENDO DS"
    }
    
    // Helper to load image
    private func getLogoImage() -> Image? {
        if let path = Bundle.main.path(forResource: "NDS_Full_Logo", ofType: "png") {
             if let uiImage = UIImage(contentsOfFile: path) {
                 return Image(uiImage: uiImage)
             }
        }
        return nil
    }
    
    // Helper to load icon
    private func getIconImage() -> Image? {
        if let path = Bundle.main.path(forResource: "NDS_Icon", ofType: "png") {
             if let uiImage = UIImage(contentsOfFile: path) {
                 return Image(uiImage: uiImage)
             }
        }
        return nil
    }
    
    // Reusable Power LED Component
    private var powerLED: some View {
        let activeColor: Color = (colorScheme == .dark) ? .red : .red
        let labelColor = (colorScheme == .dark) ? Color.gray.opacity(0.8) : Color.black.opacity(0.6)
        
        return VStack(spacing: 4) {
            Text("POWER")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(labelColor)
            
            Circle()
                .fill(isLedOn ? activeColor : Color.black.opacity(0.3))
                .frame(width: 8, height: 8)
                .shadow(color: activeColor.opacity(isLedOn ? 1.0 : 0.0), radius: isLedOn ? 5 : 0)
                .shadow(color: activeColor.opacity(isLedOn ? 0.8 : 0.0), radius: isLedOn ? 10 : 0)
                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
        }
    }
    
    // Dynamic Theme Background (Matches ResumePromptView)
    var themeBg: Color {
        colorScheme == .dark 
            ? Color(red: 28/255, green: 28/255, blue: 30/255) // Dark Grey Mesh
            : Color(red: 235/255, green: 235/255, blue: 240/255) // Light Grey Mesh
    }
    
    public init(core: DSCore) {
        self.core = core
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Unified Background with Grid
                ZStack {
                    themeBg.ignoresSafeArea()
                    PromptGridBackground(isDark: colorScheme == .dark)
                        .ignoresSafeArea()
                }
                
                // Detectar orientación basado en dimensiones
                let isPortrait = geo.size.height > geo.size.width
                
                // --- SKIN SUPPORT CHECK ---
                if let representation = skinManager.currentRepresentation(portrait: isPortrait),
                       let bgImage = skinManager.resolveAssetImage(named: representation.backgroundImageName) {
                        
                        GeometryReader { _ in
                            let screenW = geo.size.width
                            let screenH = geo.size.height
                            let mapSize = representation.mappingSize ?? SkinSize(width: screenW, height: screenH)
                            
                            // Aspect Fit Logic
                            let widthRatio = screenW / mapSize.width
                            let heightRatio = screenH / mapSize.height
                            
                            // Check if skin is PDF based on name
                            let isPDF = representation.backgroundImageName.lowercased().contains(".pdf")
                            
                            // Only apply Aspect Fit for PDFs (Strict: No distortion allowed)
                            let useAspectFit = isPDF
                            
                            let scaleX = useAspectFit ? min(widthRatio, heightRatio) : widthRatio
                            let scaleY = useAspectFit ? min(widthRatio, heightRatio) : heightRatio
                            
                            let offsetX = (screenW - mapSize.width * scaleX) / 2
                            
                            // Align Bottom for Portrait if aspect fitting
                            let offsetY = (useAspectFit && isPortrait) ? 
                                (screenH - (mapSize.height * scaleY)) : 
                                ((screenH - mapSize.height * scaleY) / 2)
                            
                            ZStack(alignment: .topLeading) {
                                // 1. Screens (Rendered BEHIND skin)
                                let screens = representation.effectiveScreens
                                if !screens.isEmpty {
                                    ForEach(0..<screens.count, id: \.self) { i in
                                        let screenDef = screens[i]
                                        let isTop = screenDef.isTouchScreen == false
                                        let renderer = isTop ? core.topRenderer : core.bottomRenderer
                                        let mode: DSScreenMode = isTop ? .topOnly : .bottomOnly
                                        
                                        let frame = screenDef.outputFrame
                                        
                                        DSRenderView(renderer: renderer, screenMode: mode)
                                            .frame(width: frame.width * scaleX, height: frame.height * scaleY)
                                            .position(
                                                x: offsetX + (frame.x + frame.width/2) * scaleX,
                                                y: offsetY + (frame.y + frame.height/2) * scaleY
                                            )
                                    }
                                } else {
                                    // Fallback: No screens defined
                                    // Assuming DS standard layout (Top/Bottom split) if missing
                                    if isPortrait {
                                        let gameAreaHeight = max(offsetY, 0)
                                        // Render Top/Bottom split in available space
                                        VStack(spacing: 0) {
                                            DSRenderView(renderer: core.topRenderer, screenMode: .topOnly)
                                                .frame(width: screenW, height: gameAreaHeight / 2)
                                            DSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly)
                                                .frame(width: screenW, height: gameAreaHeight / 2)
                                        }
                                        .frame(width: screenW, height: gameAreaHeight)
                                        .position(x: screenW/2, y: gameAreaHeight/2)
                                    } else {
                                        // Landscape Fallback
                                        HStack(spacing: 0) {
                                            DSRenderView(renderer: core.topRenderer, screenMode: .topOnly)
                                                .frame(width: screenW / 2, height: screenH)
                                            DSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly)
                                                .frame(width: screenW / 2, height: screenH)
                                        }
                                        .position(x: screenW/2, y: screenH/2)
                                    }
                                }
                                
                                // 2. Background Image (Rendered ON TOP of screens)
                                Image(uiImage: bgImage)
                                    .resizable()
                                    .frame(width: mapSize.width * scaleX, height: mapSize.height * scaleY)
                                    .position(x: offsetX + (mapSize.width * scaleX) / 2, y: offsetY + (mapSize.height * scaleY) / 2)
                            }
                        }
                        .ignoresSafeArea()
                        
                } else if isPortrait {
                        // --- FALLBACK: EXISTING PORTRAIT LAYOUT ---
                    ZStack {
                        let scale = isPortrait ? controlManager.positions.screenScalePortrait : controlManager.positions.screenScaleLandscape
                        let offset = isPortrait ? controlManager.positions.screenPositionPortrait : controlManager.positions.screenPositionLandscape
                        
                        VStack(spacing: 0) {
                            switch layoutManager.layoutMode {
                            case .standard:
                                // 1. STANDARD (Small & High) - 68% Width
                                if controlManager.positions.showBezel {
                                    // BEZEL MODE: Unified "Clamshell" Style
                                    Spacer().frame(height: 60)
                                    
                                    VStack(spacing: 0) {
                                        // Top Screen
                                        GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn, showGlow: false)
                                            .aspectRatio(4.0/3.0, contentMode: .fit)
                                        
                                        // Hinge/Gap
                                        Color.black.opacity(0.2)
                                            .frame(height: 30)
                                            .overlay(
                                                HStack {
                                                    // Hinge details
                                                    Capsule().fill(Color.white.opacity(0.1)).frame(width: 40, height: 4)
                                                    Spacer()
                                                    Capsule().fill(Color.white.opacity(0.1)).frame(width: 40, height: 4)
                                                }.padding(.horizontal, 20)
                                            )
                                        
                                        // Bottom Screen
                                        GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn, showGlow: false)
                                            .aspectRatio(4.0/3.0, contentMode: .fit)
                                        
                                        // Footer Text & LED
                                        HStack(alignment: .center) {
                                             Text("NINTENDO DS")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .italic()
                                                .foregroundColor(Color.white.opacity(0.5))
                                             Spacer()
                                             powerLED
                                                .padding(.bottom, 2)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.black.opacity(0.85))
                                    }
                                    .padding(12)
                                    .background(Color.black.opacity(0.85))
                                    .cornerRadius(16)
                                    .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                                    .frame(width: geo.size.width * 0.72)
                                    
                                    Spacer()
                                } else {
                                    // NO BEZEL MODE (Original with Glow Optimization)
                                    Spacer().frame(height: 60)
                                    GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn, showGlow: true)
                                        .aspectRatio(4.0/3.0, contentMode: .fit)
                                        .frame(width: geo.size.width * 0.68)
                                    Spacer().frame(height: 40)
                                    GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn, showGlow: true)
                                        .aspectRatio(4.0/3.0, contentMode: .fit)
                                        .frame(width: geo.size.width * 0.68)
                                    // [Cleaned] Logo/LED removed when bezel is off
                                    Spacer()
                                }
                                
                            case .hybrid:
                                // 2. LARGE (Full Width) - The "Buttons on screen" mode
                                if controlManager.positions.showBezel {
                                    Spacer().frame(height: 40)
                                    VStack(spacing: 0) {
                                        GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn, showGlow: false)
                                            .aspectRatio(4.0/3.0, contentMode: .fit)
                                            .frame(maxWidth: .infinity)
                                        
                                        // Small hinge divider for hybrid
                                        Color.black.opacity(0.3).frame(height: 10)
                                        
                                        GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn, showGlow: false)
                                            .aspectRatio(4.0/3.0, contentMode: .fit)
                                            .frame(maxWidth: .infinity)
                                            
                                        // Minimal Footer
                                        HStack(alignment: .center) {
                                             Text("NINTENDO DS")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .italic()
                                                .foregroundColor(Color.white.opacity(0.5))
                                             Spacer()
                                             powerLED.padding(.bottom, 2)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.black.opacity(0.85))
                                    }
                                    .background(Color.black.opacity(0.85))
                                    .cornerRadius(16)
                                    .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                                    .padding(.horizontal, 10)
                                    
                                    Spacer()
                                } else {
                                    Spacer().frame(height: 40)
                                    GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn, showGlow: true)
                                        .aspectRatio(4.0/3.0, contentMode: .fit)
                                        .frame(maxWidth: .infinity) // Full width
                                    Spacer().frame(height: 10)
                                    GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn, showGlow: true)
                                        .aspectRatio(4.0/3.0, contentMode: .fit)
                                        .frame(maxWidth: .infinity) // Full width
                                    Spacer()
                                }
                                
                            case .singleTop:
                                // 3. SINGLE TOP - Aligned to Top
                                if controlManager.positions.showBezel {
                                    Spacer().frame(height: 60)
                                    VStack(spacing: 0) {
                                        GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn, showGlow: false)
                                            .aspectRatio(4.0/3.0, contentMode: .fit)
                                            .frame(maxWidth: .infinity)
                                            
                                        // Footer
                                        HStack(alignment: .center) {
                                             Text("NINTENDO DS")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .italic()
                                                .foregroundColor(Color.white.opacity(0.5))
                                             Spacer()
                                             powerLED.padding(.bottom, 2)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.black.opacity(0.85))
                                    }
                                    .background(Color.black.opacity(0.85))
                                    .cornerRadius(16)
                                    .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                                    .padding(.horizontal, 16)
                                    
                                    Spacer()
                                } else {
                                    Spacer().frame(height: 60)
                                    GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn, showGlow: true)
                                        .aspectRatio(4.0/3.0, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                    // [Cleaned] Logo/LED removed when bezel is off
                                    Spacer()
                                }
                                
                            case .singleBottom:
                                // 4. SINGLE BOTTOM - Aligned to Top
                                if controlManager.positions.showBezel {
                                    Spacer().frame(height: 60)
                                    VStack(spacing: 0) {
                                        GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn, showGlow: false)
                                            .aspectRatio(4.0/3.0, contentMode: .fit)
                                            .frame(maxWidth: .infinity)
                                            
                                        // Footer
                                        HStack(alignment: .center) {
                                             Text("NINTENDO DS")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .italic()
                                                .foregroundColor(Color.white.opacity(0.5))
                                             Spacer()
                                             powerLED.padding(.bottom, 2)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.black.opacity(0.85))
                                    }
                                    .background(Color.black.opacity(0.85))
                                    .cornerRadius(16)
                                    .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                                    .padding(.horizontal, 16)
                                    
                                    Spacer()
                                } else {
                                    Spacer().frame(height: 60)
                                    GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn, showGlow: true)
                                        .aspectRatio(4.0/3.0, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                    // [Cleaned] Logo/LED removed when bezel is off
                                    Spacer()
                                }
                            }
                        }
                        .scaleEffect(scale)
                        .offset(x: offset.x, y: offset.y)
                        .overlay(
                            Group {
                                if controlManager.isEditing {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 2)
                                        Color.white.opacity(0.001)
                                            .gesture(
                                                SimultaneousGesture(
                                                    DragGesture(coordinateSpace: .named("DSScreen"))
                                                        .onChanged { value in
                                                            let current = isPortrait ? controlManager.positions.screenPositionPortrait : controlManager.positions.screenPositionLandscape
                                                            if gestureStartOffset == nil { gestureStartOffset = current }
                                                            if let start = gestureStartOffset {
                                                                controlManager.updateScreenPosition(isPortrait: isPortrait, position: CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
                                                            }
                                                        }
                                                        .onEnded { _ in gestureStartOffset = nil },
                                                    MagnificationGesture()
                                                        .onChanged { value in
                                                            let current = isPortrait ? controlManager.positions.screenScalePortrait : controlManager.positions.screenScaleLandscape
                                                            if gestureStartScale == nil { gestureStartScale = current }
                                                            if let start = gestureStartScale {
                                                                controlManager.updateScreenScale(isPortrait: isPortrait, scale: max(0.5, min(3.0, start * value)))
                                                            }
                                                        }
                                                        .onEnded { _ in gestureStartScale = nil }
                                                )
                                            )
                                    }
                                    .scaleEffect(scale)
                                    .offset(x: offset.x, y: offset.y)
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()
                    }
                    
                } else {
                    // --- MODO HORIZONTAL (Landscape) ---
                    ZStack {
                        HStack(spacing: 20) {
                            
                            // Lógica de Modos
                            switch layoutManager.layoutMode {
                            case .standard:
                                // 1. Lado a lado (50/50)
                                GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn)
                                    .aspectRatio(4.0/3.0, contentMode: .fit)
                                
                                GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn)
                                    .aspectRatio(4.0/3.0, contentMode: .fit)
                                    
                            case .hybrid:
                                // 2. Izquierda Grande (Principal), Derecha Pequeña
                                GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn)
                                    .aspectRatio(4.0/3.0, contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                                VStack {
                                    Spacer()
                                    GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn)
                                        .aspectRatio(4.0/3.0, contentMode: .fit)
                                        .frame(width: geo.size.width * 0.25)
                                    Spacer()
                                }
                                
                            case .singleTop:
                                // 3. Solo Pantalla Superior (Top Screen)
                                Spacer()
                                GlowingDSRenderView(renderer: core.topRenderer, screenMode: .topOnly, isScreenOn: isScreenOn)
                                    .aspectRatio(4.0/3.0, contentMode: .fit)
                                Spacer()
                                
                            case .singleBottom:
                                // 4. Solo Pantalla Inferior (Bottom Screen)
                                Spacer()
                                GlowingDSRenderView(renderer: core.bottomRenderer, screenMode: .bottomOnly, isScreenOn: isScreenOn)
                                    .aspectRatio(4.0/3.0, contentMode: .fit)
                                Spacer()
                            }
                        }
                        .padding()
                        .scaleEffect(isPortrait ? controlManager.positions.screenScalePortrait : controlManager.positions.screenScaleLandscape)
                        .offset(
                            x: (isPortrait ? controlManager.positions.screenPositionPortrait.x : controlManager.positions.screenPositionLandscape.x),
                            y: (isPortrait ? controlManager.positions.screenPositionPortrait.y : controlManager.positions.screenPositionLandscape.y)
                        )
                        .overlay(
                            Group {
                                if controlManager.isEditing {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 2)
                                        Color.white.opacity(0.001)
                                            .gesture(
                                                SimultaneousGesture(
                                                    DragGesture(coordinateSpace: .named("DSScreen"))
                                                        .onChanged { value in
                                                            let current = isPortrait ? controlManager.positions.screenPositionPortrait : controlManager.positions.screenPositionLandscape
                                                            if gestureStartOffset == nil { gestureStartOffset = current }
                                                            if let start = gestureStartOffset {
                                                                controlManager.updateScreenPosition(isPortrait: isPortrait, position: CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
                                                            }
                                                        }
                                                        .onEnded { _ in gestureStartOffset = nil },
                                                    MagnificationGesture()
                                                        .onChanged { value in
                                                            let current = isPortrait ? controlManager.positions.screenScalePortrait : controlManager.positions.screenScaleLandscape
                                                            if gestureStartScale == nil { gestureStartScale = current }
                                                            if let start = gestureStartScale {
                                                                controlManager.updateScreenScale(isPortrait: isPortrait, scale: max(0.5, min(3.0, start * value)))
                                                            }
                                                        }
                                                        .onEnded { _ in gestureStartScale = nil }
                                                )
                                            )
                                    }
                                    .scaleEffect(isPortrait ? controlManager.positions.screenScalePortrait : controlManager.positions.screenScaleLandscape)
                                    .offset(
                                        x: (isPortrait ? controlManager.positions.screenPositionPortrait.x : controlManager.positions.screenPositionLandscape.x),
                                        y: (isPortrait ? controlManager.positions.screenPositionPortrait.y : controlManager.positions.screenPositionLandscape.y)
                                    )
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Bottom Right: Power LED (Only show if bezel is active)
                        if controlManager.positions.showBezel {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    powerLED
                                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 10))
                                        .padding(.trailing, max(geo.safeAreaInsets.trailing, 40))
                                }
                            }
                            
                            // Bottom Left: NDS Icon with Red Glow
                            if let icon = getIconImage() {
                                VStack {
                                    Spacer()
                                    HStack {
                                        icon
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 40, height: 40)
                                            .shadow(color: glowColor.opacity(0.8), radius: 10, x: 0, y: 0)
                                            .opacity(isLogoOn ? 1.0 : 0.0)
                                            .padding(.bottom, max(geo.safeAreaInsets.bottom, 10))
                                            .padding(.leading, max(geo.safeAreaInsets.leading, 40))
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .coordinateSpace(name: "DSScreen")
        .onAppear {
            // Attempt to load default skin
            skinManager.loadDefaultSkin()
            
            // Instant On (No Flicker/Delay)
            isLedOn = true
            isLogoOn = true
            isScreenOn = true
        }
    }
}

// Wrapper para añadir efecto Glow del color del contenido
struct GlowingDSRenderView: View {
    let renderer: DSRenderer
    let screenMode: DSScreenMode
    var isScreenOn: Bool
    var showGlow: Bool = true // [NEW] Optimization flag

    private func pushTouch(_ point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        switch screenMode {
        case .topOnly:
            DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "SwiftUIOverlay-topOnly")

        case .bottomOnly:
            let u = max(0, min(1, point.x / size.width))
            let v = max(0, min(1, point.y / size.height))
            let x = Int16(min(max(u * 255, 0), 255))
            let y = Int16(min(max(v * 191, 0), 191))
            DSInput.shared.setTouch(x: x, y: y, pressed: true, source: "SwiftUIOverlay-bottomOnly")

        case .both:
            // Only bottom half is touchable in combined layout.
            let u = point.x / size.width
            let v = point.y / size.height
            if u >= 0 && u <= 1 && v >= 0.5 && v <= 1.0 {
                let touchV = (v - 0.5) * 2.0
                let x = Int16(min(max(u * 255, 0), 255))
                let y = Int16(min(max(touchV * 191, 0), 191))
                DSInput.shared.setTouch(x: x, y: y, pressed: true, source: "SwiftUIOverlay-both")
            } else {
                DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "SwiftUIOverlay-both-outside")
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Capa de Glow (Fondo desenfocado) - Only render if showGlow is true
            if isScreenOn && showGlow {
                DSRenderView(renderer: renderer, screenMode: screenMode, acceptsNativeTouch: false)
                    .cornerRadius(10)
                    .blur(radius: 15)
                    .opacity(0.8)
                    .scaleEffect(1.08)
                    .allowsHitTesting(false)
            }
            
            // Capa Principal (Nítida)
            DSRenderView(renderer: renderer, screenMode: screenMode, acceptsNativeTouch: false)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 5)
                .opacity(isScreenOn ? 1.0 : 0.0)
                .overlay(
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .allowsHitTesting(screenMode != .topOnly)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        pushTouch(value.location, in: geo.size)
                                    }
                                    .onEnded { _ in
                                        DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "SwiftUIOverlay-end")
                                    }
                            )
                    }
                )
        }
    }
}

// Background Component (Local Copy)
private struct PromptGridBackground: View {
    var isDark: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let width = geo.size.width
                let height = geo.size.height
                let spacing: CGFloat = 30
                for x in stride(from: 0, through: width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: height))
                }
                for y in stride(from: 0, through: height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(
                isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03), 
                lineWidth: 1
            )
        }
    }
}
