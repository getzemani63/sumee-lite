import SwiftUI

struct DSSkinInputOverlay: View {
    let representation: SkinRepresentation
    let viewSize: CGSize
    let showInputControls: Bool
    
    // Helper to map string keys to DSInput IDs
    private func mapInput(_ key: String) -> Int? {
        switch key.lowercased() {
        case "a": return DSInput.ID_A
        case "b": return DSInput.ID_B
        case "x": return DSInput.ID_X
        case "y": return DSInput.ID_Y
        case "l": return DSInput.ID_L
        case "r": return DSInput.ID_R
        case "start": return DSInput.ID_START
        case "select": return DSInput.ID_SELECT
        case "up": return DSInput.ID_UP
        case "down": return DSInput.ID_DOWN
        case "left": return DSInput.ID_LEFT
        case "right": return DSInput.ID_RIGHT
        case "menu": return 999
        case "quicksave": return 998
        case "quickload": return 997
        case "fastforward": return 996
        case "togglefastforward": return 995
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            if showInputControls {
                // Use container size from parent layout to keep mapping identical to rendered skin.
                let screenW = max(1, viewSize.width)
                let screenH = max(1, viewSize.height)
                let mapSize = representation.mappingSize ?? SkinSize(width: screenW, height: screenH)
                
                // Aspect Fit Logic (Consistent with DSScreensLayout)
                let widthRatio = screenW / mapSize.width
                let heightRatio = screenH / mapSize.height
                let isPDF = representation.backgroundImageName.lowercased().contains(".pdf")
                let useAspectFit = isPDF
                
                let scaleX = useAspectFit ? min(widthRatio, heightRatio) : widthRatio
                let scaleY = useAspectFit ? min(widthRatio, heightRatio) : heightRatio
                
                let offsetX = (screenW - mapSize.width * scaleX) / 2
                
                // Align Bottom for Portrait if aspect fitting
                let isPortrait = screenH > screenW
                let offsetY = (useAspectFit && isPortrait) ? 
                    (screenH - (mapSize.height * scaleY)) : 
                    ((screenH - mapSize.height * scaleY) / 2)
                
                let zones = calculateZones(representation: representation, scaleX: scaleX, scaleY: scaleY, offsetX: offsetX, offsetY: offsetY)
                DSSkinMultiTouchOverlay(zones: zones)
            }
        }
        .ignoresSafeArea()
    }
    
    private func calculateZones(representation: SkinRepresentation, scaleX: CGFloat, scaleY: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> [DSTouchZone] {
        var zones: [DSTouchZone] = []
        
        for item in representation.items {
            let frame = item.frame
            var rect = CGRect(
                x: offsetX + frame.x * scaleX,
                y: offsetY + frame.y * scaleY,
                width: frame.width * scaleX,
                height: frame.height * scaleY
            )
            
            // Apply Extended Edges
            if let extended = item.extendedEdges {
                let top = (extended.top ?? 0) * scaleY
                let bottom = (extended.bottom ?? 0) * scaleY
                let left = (extended.left ?? 0) * scaleX
                let right = (extended.right ?? 0) * scaleX
                rect = CGRect(x: rect.minX - left, y: rect.minY - top, width: rect.width + left + right, height: rect.height + top + bottom)
            }
            
            if let inputs = item.inputs {
                switch inputs {
                case .distinct(let keys):
                    if let key = keys.first {
                        if key == "menu" {
                            zones.append(DSTouchZone(rect: rect, type: .menu))
                        } else if let id = mapInput(key) {
                            if id == 996 { zones.append(DSTouchZone(rect: rect, type: .fastForward)) }
                            else if id == 995 { zones.append(DSTouchZone(rect: rect, type: .toggleFastForward)) }
                            else { zones.append(DSTouchZone(rect: rect, type: .button(id))) }
                        }
                    }
                case .directional(let dict):
                    if dict.values.contains("touchScreenX") {
                        zones.append(DSTouchZone(rect: rect, type: .touchScreen))
                    } else {
                        // INFLATED HITBOX: Increase D-Pad active area by 50pts
                        let dpadRect = rect.insetBy(dx: -50, dy: -50)
                        zones.append(DSTouchZone(rect: dpadRect, type: .dpad))
                    }
                }
            }
        }
        return zones
    }
}

// --- Multi-Touch Logic ---

struct DSTouchZone {
    enum ZoneType {
        case button(Int)
        case dpad
        case touchScreen
        case menu
        case fastForward
        case toggleFastForward
    }
    let rect: CGRect
    let type: ZoneType
}

struct DSSkinMultiTouchOverlay: UIViewRepresentable {
    let zones: [DSTouchZone]
    
    func makeUIView(context: Context) -> DSSkinMultiTouchView {
        let view = DSSkinMultiTouchView()
        view.zones = zones
        view.isMultipleTouchEnabled = true
        return view
    }
    
    func updateUIView(_ uiView: DSSkinMultiTouchView, context: Context) {
        uiView.zones = zones
    }
}

class DSSkinMultiTouchView: UIView {
    var zones: [DSTouchZone] = []
    
    // Track active inputs
    private var activeButtons: Set<Int> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
    }

    // Critical: do not swallow touches outside interactive skin zones.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        zones.contains(where: { $0.rect.contains(point) })
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { updateInputs(touches: event?.allTouches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { updateInputs(touches: event?.allTouches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { updateInputs(touches: event?.allTouches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { updateInputs(touches: event?.allTouches) }
    
    private func updateInputs(touches: Set<UITouch>?) {
        guard let touches = touches else { return }
        
        var nextButtons: Set<Int> = []
        var dpadPressed = false
        var dpadAngle: CGFloat = -1
        var touchScreenActive = false
        var ffHeld = false
        
        for touch in touches {
            let loc = touch.location(in: self)
            if touch.phase == .ended || touch.phase == .cancelled { continue }
            
            // Priority: Physical Controls > Touch Screen
            var capturedByPhysical = false
            
            // Pass 1: Check Physical Controls
            for zone in zones {
                if case .touchScreen = zone.type { continue } // Skip Screen
                
                if zone.rect.contains(loc) {
                    capturedByPhysical = true
                    switch zone.type {
                    case .button(let id):
                         nextButtons.insert(id)
                    case .menu:
                        if touch.phase == .began {
                            DSSkinManager.shared.nextSkin()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    case .fastForward:
                        ffHeld = true
                        if touch.phase == .began { DSCore.fastForward = true }
                    case .toggleFastForward:
                        if touch.phase == .began { DSCore.fastForward.toggle() }
                    case .dpad:
                        dpadPressed = true
                        let center = CGPoint(x: zone.rect.midX, y: zone.rect.midY)
                        let dx = loc.x - center.x
                        let dy = loc.y - center.y
                        if hypot(dx, dy) >= 5 {
                            var angle = atan2(dy, dx) * 180 / .pi
                            if angle < 0 { angle += 360 }
                            dpadAngle = angle
                        }
                    default: break
                    }
                }
            }
            
            // Pass 2: Check Touch Screen (Only if not captured)
            if !capturedByPhysical {
                for zone in zones {
                    if case .touchScreen = zone.type, zone.rect.contains(loc) {
                        touchScreenActive = true
                        let localX = loc.x - zone.rect.minX
                        let localY = loc.y - zone.rect.minY
                        let clampedX = max(0, min(localX, zone.rect.width))
                        let clampedY = max(0, min(localY, zone.rect.height))
                        let dsX = Int16(min(max((clampedX / zone.rect.width) * 255.0, 0), 255))
                        let dsY = Int16(min(max((clampedY / zone.rect.height) * 191.0, 0), 191))
                        DSInput.shared.setTouch(x: dsX, y: dsY, pressed: true, source: "SkinOverlay-touchScreen")
                    }
                }
            }
        }
        
        // Handle DPad
        if dpadPressed && dpadAngle >= 0 {
             if dpadAngle >= 337.5 || dpadAngle < 22.5 { nextButtons.insert(DSInput.ID_RIGHT) }
             else if dpadAngle >= 22.5 && dpadAngle < 67.5 { nextButtons.insert(DSInput.ID_RIGHT); nextButtons.insert(DSInput.ID_DOWN) }
             else if dpadAngle >= 67.5 && dpadAngle < 112.5 { nextButtons.insert(DSInput.ID_DOWN) }
             else if dpadAngle >= 112.5 && dpadAngle < 157.5 { nextButtons.insert(DSInput.ID_DOWN); nextButtons.insert(DSInput.ID_LEFT) }
             else if dpadAngle >= 157.5 && dpadAngle < 202.5 { nextButtons.insert(DSInput.ID_LEFT) }
             else if dpadAngle >= 202.5 && dpadAngle < 247.5 { nextButtons.insert(DSInput.ID_LEFT); nextButtons.insert(DSInput.ID_UP) }
             else if dpadAngle >= 247.5 && dpadAngle < 292.5 { nextButtons.insert(DSInput.ID_UP) }
             else if dpadAngle >= 292.5 && dpadAngle < 337.5 { nextButtons.insert(DSInput.ID_UP); nextButtons.insert(DSInput.ID_RIGHT) }
        }
        
        // Reset Touch Screen if no finger is on it
        if !touchScreenActive {
            DSInput.shared.setTouch(x: 0, y: 0, pressed: false, source: "SkinOverlay-touchScreen-end")
        }
        

        if !ffHeld && !zones.isEmpty { // Only if zones exist (to avoid reset on deinit)
             // Check if we have a FF button at all
             if zones.contains(where: { if case .fastForward = $0.type { return true }; return false }) {
                 DSCore.fastForward = false
             }
        }
        
        // 1. Release buttons
        for id in activeButtons.subtracting(nextButtons) {
            DSInput.shared.setButton(id, pressed: false)
        }
        
        // 2. Press new buttons
        for id in nextButtons.subtracting(activeButtons) {
            DSInput.shared.setButton(id, pressed: true)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        
        activeButtons = nextButtons
    }
}
