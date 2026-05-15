import SwiftUI



// MARK: - Premium DS Controls

struct DSButton: View {
    let id: Int
    let label: String
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            // Shadow
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.3))
                .blur(radius: 2)
                .offset(x: 0, y: isPressed ? 1 : 3)
            
            // Base Shape (Bevel Look)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.7), Color(white: 0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .padding(1)
                )
            
            // Top Highlights
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .padding(2)

            // Inner Body (Depress effect)
            if isPressed {
                RoundedRectangle(cornerRadius: cornerRadius - 2)
                    .fill(Color(white: 0.45))
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius - 2)
                            .stroke(Color.black.opacity(0.2), lineWidth: 2)
                            .blur(radius: 1)
                            .padding(4)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius - 2)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.6), Color(white: 0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(4)
            }

            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(isPressed ? .white.opacity(0.5) : .white.opacity(0.8))
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            }
        }
        .frame(width: width, height: height)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .rotation3DEffect(
            .degrees(isPressed ? 15 : 0),
            axis: (x: 1.0, y: 0.0, z: 0.0),
            perspective: 0.5
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        DSInput.shared.setButton(id, pressed: true)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    DSInput.shared.setButton(id, pressed: false)
                }
        )
    }
}

struct DSCircularButton: View {
    let size: CGFloat
    let label: String
    var isPressed: Bool
    
    // DS Colors often grey/black or colored. Let's stick to the Premium Grey similar to GBA for consistency,
    // or maybe slightly lighter for DS. Dark Grey is safe and premium.
    var buttonColor: Color = Color(red: 0.35, green: 0.35, blue: 0.4)
    
    var body: some View {
        ZStack {
            // Shadow
            Circle()
                .fill(Color.black.opacity(isPressed ? 0.2 : 0.4))
                .offset(y: isPressed ? 1 : 3)
                .blur(radius: 2)
            
            // Main Body (Glossy Plastic)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            buttonColor.opacity(0.9),
                            buttonColor.opacity(1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Glossy Reflection Top
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .padding(2)
                        .blur(radius: 1)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
            
            Text(label)
                .font(.system(size: size * 0.45, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                .offset(y: isPressed ? 0 : -1)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
    }
}

struct DSActionButtonsPad: View {
    struct ButtonDef {
        let id: Int
        let label: String
        let offset: CGPoint
    }
    
    let buttons: [ButtonDef] = [
        ButtonDef(id: DSInput.ID_Y, label: "Y", offset: CGPoint(x: -45, y: 0)),
        ButtonDef(id: DSInput.ID_A, label: "A", offset: CGPoint(x: 45, y: 0)),
        ButtonDef(id: DSInput.ID_X, label: "X", offset: CGPoint(x: 0, y: -45)),
        ButtonDef(id: DSInput.ID_B, label: "B", offset: CGPoint(x: 0, y: 45))
    ]
    
    @State private var pressedButtons: Set<Int> = []
    
    var body: some View {
        ZStack {
            // Visual Layer
            ForEach(buttons, id: \.id) { btn in
                DSCircularButton(size: 55, label: btn.label, isPressed: pressedButtons.contains(btn.id))
                    .offset(x: btn.offset.x, y: btn.offset.y)
            }
            
            // Touch Handling Layer (UIKit MultiTouch)
            DSMultiTouchPad(buttons: buttons) { newPressed in
                if newPressed != pressedButtons {
                    // Trigger Haptics for new presses
                    let added = newPressed.subtracting(pressedButtons)
                    if !added.isEmpty {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    pressedButtons = newPressed
                }
            }
        }
        .frame(width: 150, height: 150)
    }
}

// Helper: True Multi-Touch Handler using UIKit
struct DSMultiTouchPad: UIViewRepresentable {
    let buttons: [DSActionButtonsPad.ButtonDef]
    var onUpdate: (Set<Int>) -> Void
    
    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.buttons = buttons
        view.onUpdate = onUpdate
        return view
    }
    
    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.buttons = buttons
        uiView.onUpdate = onUpdate
    }
    
    class TouchView: UIView {
        var buttons: [DSActionButtonsPad.ButtonDef] = []
        var onUpdate: ((Set<Int>) -> Void)?
        
        // Track which touch is pressing which button ID
        private var activeTouches: [UITouch: Int] = [:]
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
        }
        
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateTouches(touches, phase: .began)
        }
        
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateTouches(touches, phase: .moved)
        }
        
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateTouches(touches, phase: .ended)
        }
        
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateTouches(touches, phase: .cancelled)
        }
        
        private func updateTouches(_ touches: Set<UITouch>, phase: UITouch.Phase) {
            let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
            
            for touch in touches {
                if phase == .ended || phase == .cancelled {
                    activeTouches.removeValue(forKey: touch)
                } else {
                    let loc = touch.location(in: self)
                    var foundBtn: Int? = nil
                    
                    // Check against all buttons
                    for btn in buttons {
                        let btnCenter = CGPoint(x: center.x + btn.offset.x, y: center.y + btn.offset.y)
                        let dist = hypot(loc.x - btnCenter.x, loc.y - btnCenter.y)
                        if dist < 40 { // 40 radius hit detection
                            foundBtn = btn.id
                            break
                        }
                    }
                    
                    if let btnID = foundBtn {
                        activeTouches[touch] = btnID
                    } else {
                        activeTouches.removeValue(forKey: touch)
                    }
                }
            }
            
            // Calculate final set of pressed buttons
            let allPressed = Set(activeTouches.values)
            
            // Update Core
            DSInput.shared.updateActionButtons(allPressed)
            
            // Callback for UI
            onUpdate?(allPressed)
        }
    }
}

struct DSDPad: View {
    let size: CGFloat = 140
    let thickness: CGFloat = 48
    
    @State private var pressedButtons: Set<Int> = []
    
    var body: some View {
        let isUp = pressedButtons.contains(DSInput.ID_UP)
        let isDown = pressedButtons.contains(DSInput.ID_DOWN)
        let isLeft = pressedButtons.contains(DSInput.ID_LEFT)
        let isRight = pressedButtons.contains(DSInput.ID_RIGHT)
        
        // Tilt Logic (Inverted for correct physics)
        let tiltX: Double = isUp ? 10 : (isDown ? -10 : 0)
        let tiltY: Double = isLeft ? -10 : (isRight ? 10 : 0)
        
        return ZStack {
            // Shadow
            Image(systemName: "dpad.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundColor(.black.opacity(0.4))
                .blur(radius: 4)
                .offset(y: 5)
                .scaleEffect(0.95)
            
            // Unified Cross Body
            ZStack {
                Group {
                    RoundedRectangle(cornerRadius: 6)
                        .frame(width: thickness, height: size)
                    RoundedRectangle(cornerRadius: 6)
                        .frame(width: size, height: thickness)
                }
                .foregroundColor(.clear)
                .background(
                    LinearGradient(
                        colors: [Color(white: 0.25), Color(white: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .mask(
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .frame(width: thickness, height: size)
                            RoundedRectangle(cornerRadius: 6)
                                .frame(width: size, height: thickness)
                        }
                    )
                )
                // Bevel/Stroke (Individual strokes to valid ZStack issue)
                .overlay(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            .frame(width: thickness, height: size)
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            .frame(width: size, height: thickness)
                    }
                    .mask(
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .frame(width: thickness, height: size)
                            RoundedRectangle(cornerRadius: 6)
                                .frame(width: size, height: thickness)
                        }
                    )
                )
                
                // Subtle Directional Arrows
                Group {
                    Image(systemName: "play.fill")
                        .rotationEffect(.degrees(-90))
                        .offset(y: -size/3 + 5)
                        .foregroundColor(isUp ? .white.opacity(0.5) : .black.opacity(0.3))
                    
                    Image(systemName: "play.fill")
                        .rotationEffect(.degrees(90))
                        .offset(y: size/3 - 5)
                        .foregroundColor(isDown ? .white.opacity(0.5) : .black.opacity(0.3))
                        
                    Image(systemName: "play.fill")
                        .rotationEffect(.degrees(180))
                        .offset(x: -size/3 + 5)
                        .foregroundColor(isLeft ? .white.opacity(0.5) : .black.opacity(0.3))
                        
                    Image(systemName: "play.fill")
                        .rotationEffect(.degrees(0))
                        .offset(x: size/3 - 5)
                        .foregroundColor(isRight ? .white.opacity(0.5) : .black.opacity(0.3))
                }
                .font(.system(size: 10, weight: .black))
                .shadow(color: .white.opacity(0.1), radius: 0, x: 0, y: 1)
            }
            .rotation3DEffect(
                .degrees(tiltX),
                axis: (x: 1.0, y: 0.0, z: 0.0),
                perspective: 0.5
            )
            .rotation3DEffect(
                .degrees(tiltY),
                axis: (x: 0.0, y: 1.0, z: 0.0),
                perspective: 0.5
            )
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.6), value: pressedButtons)
            
            // Touch Handling with GeometryReader
            GeometryReader { geo in
                Color.white.opacity(0.001)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                updateDirection(value.location, center: center)
                            }
                            .onEnded { _ in
                                releaseAll()
                            }
                    )
            }
            .frame(width: size * 1.6, height: size * 1.6)
        }
        .frame(width: size, height: size)
    }
    
    private func updateDirection(_ location: CGPoint, center: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        
        if hypot(dx, dy) < 10 {
            releaseAll()
            return
        }
        
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }
        

        
        var newPressed: Set<Int> = []
        
        if angle >= 330 || angle < 30 {
            newPressed.insert(DSInput.ID_RIGHT)
        } else if angle >= 30 && angle < 60 {
            newPressed.insert(DSInput.ID_RIGHT)
            newPressed.insert(DSInput.ID_DOWN)
        } else if angle >= 60 && angle < 120 {
            newPressed.insert(DSInput.ID_DOWN)
        } else if angle >= 120 && angle < 150 {
            newPressed.insert(DSInput.ID_DOWN)
            newPressed.insert(DSInput.ID_LEFT)
        } else if angle >= 150 && angle < 210 {
            newPressed.insert(DSInput.ID_LEFT)
        } else if angle >= 210 && angle < 240 {
            newPressed.insert(DSInput.ID_LEFT)
            newPressed.insert(DSInput.ID_UP)
        } else if angle >= 240 && angle < 300 {
            newPressed.insert(DSInput.ID_UP)
        } else if angle >= 300 && angle < 330 {
            newPressed.insert(DSInput.ID_UP)
            newPressed.insert(DSInput.ID_RIGHT)
        }
        
        updateInputs(newPressed)
    }
    
    private func updateInputs(_ newPressed: Set<Int>) {
        if newPressed != pressedButtons {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            for id in pressedButtons.subtracting(newPressed) {
                DSInput.shared.setButton(id, pressed: false)
            }
            
            for id in newPressed.subtracting(pressedButtons) {
                DSInput.shared.setButton(id, pressed: true)
            }
            
            pressedButtons = newPressed
        }
    }
    
    private func releaseAll() {
        for id in pressedButtons {
            DSInput.shared.setButton(id, pressed: false)
        }
        pressedButtons.removeAll()
    }
}

public struct DSVirtualController: View {
    var isTransparent: Bool = false
    var showInputControls: Bool = true
    
    // Estados de visibilidad
    enum VisibilityMode {
        case visible
        case transparent
        case hidden
        
        var opacity: Double {
            switch self {
            case .visible: return 1.0
            case .transparent: return 0.2 // Muy transparente
            case .hidden: return 0.0
            }
        }
        
        mutating func next() {
            switch self {
            case .visible: self = .transparent
            case .transparent: self = .hidden
            case .hidden: self = .visible
            }
        }
    }
    
    @State private var mode: VisibilityMode = .visible
    @ObservedObject var controlManager = DSControlManager.shared
    @ObservedObject var skinManager = DSSkinManager.shared // New Skin Manager
    @ObservedObject var input = DSInput.shared // Observe controller state
    

    private func draggable(key: WritableKeyPath<DSControlPositions, CGPoint>) -> some ViewModifier {
        DraggableGeneric(manager: controlManager, key: key)
    }
    
    public init(isTransparent: Bool = false, showInputControls: Bool = true) {
        self.isTransparent = isTransparent
        self.showInputControls = showInputControls
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Force Full Screen always
                Color.clear
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)

                // Fondo semi-transparente
                if !isTransparent && mode == .visible {
                    Color(white: 0.7).edgesIgnoringSafeArea(.all)
                }
                
                // Edit mode
                if controlManager.isEditing {

                    VStack {
                        Text("EDIT MODE")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.top, 50)
                        
                        Text("Drag controls to allow custom positioning")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 20) {
                            Button(action: { controlManager.resetConfig() }) {
                                Text("Reset")
                                    .bold()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(Color.red)
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            
                            Button(action: { 
                                controlManager.saveConfig()
                                withAnimation { controlManager.isEditing = false }
                            }) {
                                Text("Save")
                                    .bold()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(Color.green)
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        Spacer()
                    }
                    .zIndex(100)
                }
                
                // Detección de orientación robusta
                let isPortrait = UIScreen.main.bounds.height > UIScreen.main.bounds.width || geo.size.height > geo.size.width
                
                // --- SKIN SUPPORT CHECK ---
                if let representation = skinManager.currentRepresentation(portrait: isPortrait),
                   skinManager.resolveAssetImage(named: representation.backgroundImageName) != nil {
                     // Render Skin Inputs (Invisible Touch Zones)
                     DSSkinInputOverlay(representation: representation, viewSize: geo.size, showInputControls: showInputControls)
                } else if isPortrait {
                    
                    // (Portrait) ---
                    ZStack {
                        
          
                        if showInputControls {
                        Group {
                        
                            VStack {
                                Spacer()
                                DSDPad()
                                    .modifier(draggable(key: isPortrait ? \.dpadPortrait : \.dpadLandscape)) // DRAGGABLE
                                    .padding(.leading, 10)
                                    .padding(.bottom, 110)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                 
                            VStack {
                                Spacer()
                                DSActionButtonsPad()
        .modifier(draggable(key: isPortrait ? \.buttonsPortrait : \.buttonsLandscape)) // DRAGGABLE
        .padding(.trailing, 0)
        .padding(.bottom, 110)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            
                            // 3. Start / Select
                            
                            // 3. Start / Select (Unified Center)
                            VStack {
                                Spacer()
                                HStack(spacing: 40) {
                                    // Select
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(white: 0.35), Color(white: 0.25)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: 45, height: 14)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                                        .padding(1)
                                                )
                                                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                                        }
                                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in 
                                            guard !DSControlManager.shared.isEditing else { return }
                                            DSInput.shared.setButton(DSInput.ID_SELECT, pressed: true)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }.onEnded { _ in 
                                            DSInput.shared.setButton(DSInput.ID_SELECT, pressed: false) 
                                        })
                                        
                                        Text("SELECT").font(.system(size: 9, weight: .bold)).foregroundColor(Color(white: 0.3))
                                    }
                                    .modifier(draggable(key: isPortrait ? \.selectPortrait : \.selectLandscape))

                                    // Start
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(white: 0.35), Color(white: 0.25)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: 45, height: 14)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                                        .padding(1)
                                                )
                                                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                                        }
                                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in 
                                            guard !DSControlManager.shared.isEditing else { return }
                                            DSInput.shared.setButton(DSInput.ID_START, pressed: true)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }.onEnded { _ in 
                                            DSInput.shared.setButton(DSInput.ID_START, pressed: false) 
                                        })
                                        
                                        Text("START").font(.system(size: 9, weight: .bold)).foregroundColor(Color(white: 0.3))
                                    }
                                    .modifier(draggable(key: isPortrait ? \.startPortrait : \.startLandscape))
                                }
                                .padding(.bottom, 25)
                            }
                            
                            VStack {
                                Spacer()
                                HStack {
                                    DSButton(id: DSInput.ID_L, label: "L", width: 100, height: 50, cornerRadius: 15)
                                        .modifier(draggable(key: isPortrait ? \.lPortrait : \.lLandscape)) // DRAGGABLE
                                        .padding(.leading, 20)
                                    Spacer()
                                    DSButton(id: DSInput.ID_R, label: "R", width: 100, height: 50, cornerRadius: 15)
                                        .modifier(draggable(key: isPortrait ? \.rPortrait : \.rLandscape)) // DRAGGABLE
                                        .padding(.trailing, 20)
                                }
                                .padding(.bottom, 310)
                            }
                        }
                        .opacity(mode.opacity)
                        .allowsHitTesting(mode != .hidden || controlManager.isEditing) // Siempre permitir hit en edit mode
                        }
                        
               
                        if showInputControls {
                        VStack(spacing: 0) {
                            Spacer()
                            HStack {
                                Spacer()
                                Menu {
                                    Button(action: {
                                        withAnimation { DSScreenLayoutManager.shared.layoutMode.next() }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }) {
                                        Label("Change Screens", systemImage: "rectangle.split.2x1")
                                    }
                                    
                                    Toggle(isOn: $controlManager.positions.showBezel) {
                                        Label("Show Bezel", systemImage: "rectangle.inset.filled")
                                    }
                                    
                                    // Graphics Section
                                    Menu {
                                        Menu("Resolution (Requires Restart)") {
                                            Button("1x (Native)") { DSCore.internalResolution = 1 }
                                            Button("2x (HD)") { DSCore.internalResolution = 2 }
                                            Button("4x (Ultra)") { DSCore.internalResolution = 4 }
                                        }
                                        Menu("Texture Filter") {
                                            Button("Pixelated (Sharp)") { 
                                                DSRenderer.setFilterOnly(linear: false)
                                                DSRenderer.currentFilterMode = 0 
                                            }
                                            Button("Smooth (Linear)") { 
                                                DSRenderer.setFilterOnly(linear: true)
                                                DSRenderer.currentFilterMode = 0
                                            }
                                            Button("LCD Grid (Retro)") {
                                                DSRenderer.setFilterOnly(linear: true) // Linear helps grid look better
                                                DSRenderer.currentFilterMode = 1
                                            }
                                        }
                                    } label: {
                                        Label("Graphics", systemImage: "display")
                                    }
                                    
                                    Button(action: {
                                        withAnimation { controlManager.isEditing = true }
                                    }) {
                                        Label("Edit Controls", systemImage: "slider.horizontal.3")
                                    }
                                    
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            mode.next()
                                        }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }) {
                                        Label("Change Opacity", systemImage: "sun.min")
                                    }
                                } label: {
                                    Image(systemName: "gamecontroller.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(10)
                                        .background(Circle().fill(Color.black.opacity(0.3)))
                                }
                            }
                            .padding(.bottom, 20)
                            .padding(.trailing, 20)
                        }
                        .opacity(controlManager.isEditing ? 0 : 1)
                        .allowsHitTesting(!controlManager.isEditing)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else {
                    // --- MODO HORIZONTAL (Landscape) ---
                    ZStack {
                        if showInputControls {
                        Group {
                            HStack {
                                // Izquierda
                                VStack {
                                    DSButton(id: DSInput.ID_L, label: "L", width: 100, height: 45, cornerRadius: 15)
                                        .modifier(draggable(key: isPortrait ? \.lPortrait : \.lLandscape))
                                        .padding(.top, 70) 
                                    Spacer().frame(height: 50)
                                    DSDPad()
                                        .modifier(draggable(key: isPortrait ? \.dpadPortrait : \.dpadLandscape))
                                        .padding(.bottom, 20)  
                                    Spacer()

                                }
                                .frame(width: 180).padding(.leading, 60)
                                
                                Spacer() 
                                
                                // Derecha
                                VStack {
                                    DSButton(id: DSInput.ID_R, label: "R", width: 100, height: 45, cornerRadius: 15)
                                        .modifier(draggable(key: isPortrait ? \.rPortrait : \.rLandscape))
                                        .padding(.top, 70) 
                                    Spacer().frame(height: 50)
                                    DSActionButtonsPad()
        .modifier(draggable(key: isPortrait ? \.buttonsPortrait : \.buttonsLandscape))
        .padding(.bottom, 20)  
                                    Spacer()

                                }
                                .frame(width: 180).padding(.trailing, 60) 
                            }
                        }
                        .opacity(mode.opacity)
                        .allowsHitTesting(mode != .hidden || controlManager.isEditing)

                        
                            // 2. Start / Select (Unified Center - Landscape)
                            VStack {
                                Spacer()
                                HStack(spacing: 40) {
                                    // Select
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(white: 0.35), Color(white: 0.25)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: 45, height: 14)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                                        .padding(1)
                                                )
                                                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                                        }
                                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in 
                                            guard !DSControlManager.shared.isEditing else { return }
                                            DSInput.shared.setButton(DSInput.ID_SELECT, pressed: true)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }.onEnded { _ in 
                                            DSInput.shared.setButton(DSInput.ID_SELECT, pressed: false) 
                                        })
                                        
                                        Text("SELECT").font(.system(size: 9, weight: .bold)).foregroundColor(Color(white: 0.3))
                                    }
                                    .modifier(draggable(key: isPortrait ? \.selectPortrait : \.selectLandscape))

                                    // Start
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(white: 0.35), Color(white: 0.25)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: 45, height: 14)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                                        .padding(1)
                                                )
                                                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                                        }
                                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in 
                                            guard !DSControlManager.shared.isEditing else { return }
                                            DSInput.shared.setButton(DSInput.ID_START, pressed: true)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }.onEnded { _ in 
                                            DSInput.shared.setButton(DSInput.ID_START, pressed: false) 
                                        })
                                        
                                        Text("START").font(.system(size: 9, weight: .bold)).foregroundColor(Color(white: 0.3))
                                    }
                                    .modifier(draggable(key: isPortrait ? \.startPortrait : \.startLandscape))
                                }
                                .padding(.bottom, 20)
                            }
                            .opacity(mode.opacity)
                            .allowsHitTesting(mode != .hidden || controlManager.isEditing)
                        }
                        
                        // Botones Centrales (Ahora Bottom Right Overlay)
                        
                        VStack {
                            Spacer()
                            HStack(spacing: 20) {
                                Spacer()
                                Menu {
                                    Button(action: {
                                        withAnimation { DSScreenLayoutManager.shared.layoutMode.next() }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }) {
                                        Label("Change Screens", systemImage: "rectangle.split.2x1")
                                    }

                                    Toggle(isOn: $controlManager.positions.showBezel) {
                                        Label("Show Bezel", systemImage: "rectangle.inset.filled")
                                    }

                                    // Graphics Section
                                    Menu {
                                        Menu("Resolution (Requires Restart)") {
                                            Button("1x (Native)") { DSCore.internalResolution = 1 }
                                            Button("2x (HD)") { DSCore.internalResolution = 2 }
                                            Button("4x (Ultra)") { DSCore.internalResolution = 4 }
                                        }
                                        Menu("Texture Filter") {
                                            Button("Pixelated (Sharp)") { 
                                                DSRenderer.setFilterOnly(linear: false)
                                                DSRenderer.currentFilterMode = 0 
                                            }
                                            Button("Smooth (Linear)") { 
                                                DSRenderer.setFilterOnly(linear: true)
                                                DSRenderer.currentFilterMode = 0
                                            }
                                            Button("LCD Grid (Retro)") {
                                                DSRenderer.setFilterOnly(linear: true) // Linear helps grid look better
                                                DSRenderer.currentFilterMode = 1
                                            }
                                        }
                                    } label: {
                                        Label("Graphics", systemImage: "display")
                                    }

                                    Button(action: {
                                        withAnimation { controlManager.isEditing = true }
                                    }) {
                                        Label("Edit Controls", systemImage: "slider.horizontal.3")
                                    }
                                    
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            mode.next()
                                        }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }) {
                                        Label("Change Opacity", systemImage: "sun.min")
                                    }
                                } label: {
                                    Image(systemName: "gamecontroller.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(10)
                                        .background(Circle().fill(Color.black.opacity(0.3)))
                                }
                            }
                            .padding(.bottom, 20)
                            .padding(.trailing, 20)
                            .allowsHitTesting(!controlManager.isEditing)
                         }
                        
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .edgesIgnoringSafeArea(.all)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// Modifier para Drag
struct DraggableGeneric: ViewModifier {
    @ObservedObject var manager: DSControlManager
    let key: WritableKeyPath<DSControlPositions, CGPoint>
    
    @State private var dragOffset: CGPoint = .zero
    
    func body(content: Content) -> some View {
        let currentPos = manager.positions[keyPath: key]
        // Color de realce en modo edición
        let isEditing = manager.isEditing
        
        return content
            .offset(x: currentPos.x + dragOffset.x, y: currentPos.y + dragOffset.y)
            .overlay(
                // Borde visual en modo edición
                isEditing ? 
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.yellow, lineWidth: 2)
                        .padding(-5)
                    : nil
            )
            .simultaneousGesture(
                isEditing ?
                DragGesture()
                    .onChanged { value in
                        dragOffset = CGPoint(x: value.translation.width, y: value.translation.height)
                    }
                    .onEnded { value in
                        let newPos = CGPoint(x: currentPos.x + value.translation.width, y: currentPos.y + value.translation.height)
                        manager.updatePosition(key, value: newPos)
                        dragOffset = .zero
                    }
                : nil
            )
    }
}
